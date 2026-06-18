"""
runner.jl — Detached experiment driver (PHD harness)

Usage
-----
    julia runner.jl <jobdir>
    julia runner.jl <jobdir> --resume

<jobdir> must contain job.json.  All output files are written inside <jobdir>.

Job directory layout (§5.2 contract)
-------------------------------------
    job.json          # spec: hid, diff, budget_s, backend, seed, max_epochs, parallel_k
    status            # ONE token: PENDING|RUNNING|DONE|FAILED  (atomic rename)
    heartbeat         # {"epoch":Int,"ts":Float64}  rewritten every epoch
    epoch/NNNN.ckpt   # serialized {model_state, opt_state, rng_state, epoch}
    epoch/NNNN.json   # {"epoch","loss","score","wall_s"}
    result.json       # {"hid","score","wall_s","backend","meta":{...}}
    stdout.log / stderr.log  (written by the OS caller; not by runner.jl itself)

Crash-safety guarantee
-----------------------
At the end of EVERY epoch, runner.jl writes epoch/NNNN.ckpt AND epoch/NNNN.json
AND updates heartbeat, flushing each file to disk (close = flush on Julia's IO)
BEFORE the loop continues.  A crash loses at most the in-flight epoch; the last
good checkpoint is always recoverable.  status and result.json use temp-file +
atomic rename so they are never partially written.

Project hook interface
-----------------------
Projects that include runner.jl (or run it with RUNNER_PROJECT_FILE set) must
define the following functions:

    # Return a fresh model (or reload from a checkpoint state dict).
    # `seed` is an Int for reproducibility; `job` is the parsed job.json Dict.
    make_model(job::Dict) -> model

    # One training step.  Mutates model in-place (or returns updated model).
    # Returns a scalar loss (Float64).
    #
    # Arguments:
    #   model   — the current model object
    #   data    — whatever make_data() returned
    #   epoch   — 1-based epoch index
    #   job     — the full job Dict (contains seed, hid, etc.)
    #
    train_step(model, data, epoch::Int, job::Dict) -> (model, loss::Float64)

    # Score the model on held-out / validation data.
    # Returns an ExperimentResult (from metric.jl).
    # budget_s is the remaining wall-clock budget (informational; scorer may ignore it).
    score(model, data, budget_s::Float64) -> ExperimentResult

    # Build or load the dataset.  Called once before the epoch loop.
    # Must be deterministic under the job seed.
    make_data(job::Dict) -> data

    # (Optional) Serialise model state for checkpointing.
    # Defaults to identity (model itself is serialized).
    model_state(model) -> state
    load_model_state!(model, state) -> model

If these functions are not defined, runner.jl falls back to the built-in toy
quadratic optimisation (see DEFAULT HOOKS section below), which makes runner.jl
fully self-testable without a real project.

The project file is loaded via:
    RUNNER_PROJECT_FILE=/path/to/project.jl julia runner.jl <jobdir>
Or set `project_file` in job.json ("project_file": "/abs/path/to/project.jl").
"""

# ---------------------------------------------------------------------------
# Bootstrap: load harness siblings relative to this file's location
# ---------------------------------------------------------------------------

const HARNESS_DIR = @__DIR__

include(joinpath(HARNESS_DIR, "device.jl"))
include(joinpath(HARNESS_DIR, "metric.jl"))

using .DeviceLayer
using .MetricContract
using Serialization: serialize, deserialize
using Printf: @sprintf

# ---------------------------------------------------------------------------
# Minimal JSON helpers (no exotic deps — we only need to write simple objects)
# ---------------------------------------------------------------------------

"""
Write a Dict{String,Any} as a JSON object to a file path.
We use a hand-rolled serialiser for the handful of types we actually emit so
that runner.jl has zero non-stdlib mandatory dependencies.  (If the project
loads JSON.jl or JSON3.jl, they take precedence via the project hook interface.)
"""
function _write_json(path::AbstractString, d::Dict)::Nothing
    open(path, "w") do io
        _json_write(io, d)
        println(io)
    end
    return nothing
end

function _json_write(io::IO, d::Dict)
    print(io, "{")
    pairs_vec = collect(d)
    for (i, (k, v)) in enumerate(pairs_vec)
        _json_write(io, string(k))
        print(io, ":")
        _json_write(io, v)
        i < length(pairs_vec) && print(io, ",")
    end
    print(io, "}")
end
_json_write(io::IO, s::AbstractString) = print(io, "\"", _json_escape(s), "\"")
_json_write(io::IO, n::Real)           = isnan(n) ? print(io, "null") : print(io, n)
_json_write(io::IO, b::Bool)           = print(io, b ? "true" : "false")
_json_write(io::IO, ::Nothing)         = print(io, "null")
function _json_write(io::IO, v::Vector)
    print(io, "[")
    for (i, x) in enumerate(v)
        _json_write(io, x)
        i < length(v) && print(io, ",")
    end
    print(io, "]")
end
_json_write(io::IO, x) = print(io, "\"", string(x), "\"")

function _json_escape(s::AbstractString)::String
    # Escape the handful of characters that break JSON strings.
    replace(s,
        '\\' => "\\\\",
        '"'  => "\\\"",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
    )
end

"""
Minimal JSON parser: reads a flat key:value object (no nesting beyond one level).
Sufficient for reading job.json which is a flat struct.
"""
function _read_json(path::AbstractString)::Dict{String,Any}
    raw = read(path, String)
    # Strip outer braces and split on commas that are not inside strings.
    # For the flat job.json spec this is sufficient; a project needing deep
    # parsing should use JSON.jl in their project file.
    d = Dict{String,Any}()
    # Remove outer braces
    s = strip(raw)
    startswith(s, "{") && endswith(s, "}") || error("Not a JSON object: $path")
    inner = s[2:end-1]
    # Split on commas while respecting quoted strings
    tokens = _json_split(inner)
    for tok in tokens
        tok = strip(tok)
        isempty(tok) && continue
        # Find the colon separating key from value
        ci = _json_colon_pos(tok)
        ci == 0 && continue
        key_raw = strip(tok[1:ci-1])
        val_raw = strip(tok[ci+1:end])
        key = _json_unquote(key_raw)
        d[key] = _json_parse_value(val_raw)
    end
    return d
end

function _json_split(s::AbstractString)::Vector{SubString{String}}
    # Split on commas that are outside quoted strings.
    parts = SubString{String}[]
    depth = 0; in_str = false; esc = false; start = firstindex(s)
    for (i, c) in pairs(s)
        if esc
            esc = false; continue
        end
        if c == '\\' && in_str; esc = true; continue; end
        if c == '"'; in_str = !in_str; continue; end
        if !in_str
            if c in ('{', '['); depth += 1
            elseif c in ('}', ']'); depth -= 1
            elseif c == ',' && depth == 0
                push!(parts, SubString(s, start, prevind(s, i)))
                start = nextind(s, i)
            end
        end
    end
    push!(parts, SubString(s, start))
    return parts
end

function _json_colon_pos(s::AbstractString)::Int
    in_str = false; esc = false
    for (i, c) in pairs(s)
        if esc; esc = false; continue; end
        if c == '\\' && in_str; esc = true; continue; end
        if c == '"'; in_str = !in_str; continue; end
        if c == ':' && !in_str; return i; end
    end
    return 0
end

function _json_unquote(s::AbstractString)::String
    s = strip(s)
    startswith(s, "\"") && endswith(s, "\"") && return String(s[2:end-1])
    return String(s)
end

function _json_parse_value(s::AbstractString)::Any
    s = strip(s)
    s == "null"  && return nothing
    s == "true"  && return true
    s == "false" && return false
    if startswith(s, "\"") && endswith(s, "\"")
        return unescape_string(String(s[2:end-1]))
    end
    # Try Int, then Float64
    iv = tryparse(Int, s)
    iv !== nothing && return iv
    fv = tryparse(Float64, s)
    fv !== nothing && return fv
    return String(s)  # fallback: raw string
end

# ---------------------------------------------------------------------------
# Atomic file utilities
# ---------------------------------------------------------------------------

"""
    write_atomic(path, content::AbstractString)

Write `content` to `path` via a temp file + rename so the file is never
partially written from the perspective of an external reader.
"""
function write_atomic(path::AbstractString, content::AbstractString)::Nothing
    dir = dirname(path)
    tmp = joinpath(dir, ".tmp_$(basename(path))_$(getpid())")
    write(tmp, content)
    mv(tmp, path; force=true)
    return nothing
end

"""
    write_json_atomic(path, d::Dict)

Write a JSON object atomically (temp + rename).
"""
function write_json_atomic(path::AbstractString, d::Dict)::Nothing
    dir = dirname(path)
    tmp = joinpath(dir, ".tmp_$(basename(path))_$(getpid())")
    _write_json(tmp, d)
    mv(tmp, path; force=true)
    return nothing
end

# ---------------------------------------------------------------------------
# Status helpers
# ---------------------------------------------------------------------------

const VALID_STATUSES = ("PENDING", "RUNNING", "DONE", "FAILED")

"""
    read_status(jobdir) -> String
"""
function read_status(jobdir::AbstractString)::String
    p = joinpath(jobdir, "status")
    isfile(p) || return "PENDING"
    return strip(read(p, String))
end

"""
    write_status(jobdir, status)

Atomically overwrite the status file.  `status` must be one of
PENDING | RUNNING | DONE | FAILED.
"""
function write_status(jobdir::AbstractString, status::AbstractString)::Nothing
    status ∈ VALID_STATUSES || error("Invalid status: $status")
    write_atomic(joinpath(jobdir, "status"), status)
    return nothing
end

# ---------------------------------------------------------------------------
# Heartbeat
# ---------------------------------------------------------------------------

"""
    write_heartbeat(jobdir, epoch)

Overwrite heartbeat file with current epoch index and Unix timestamp.
Called at the END of every epoch, after checkpoints are flushed.
"""
function write_heartbeat(jobdir::AbstractString, epoch::Int)::Nothing
    d = Dict{String,Any}("epoch" => epoch, "ts" => time())
    write_json_atomic(joinpath(jobdir, "heartbeat"), d)
    return nothing
end

# ---------------------------------------------------------------------------
# Checkpoint I/O
# ---------------------------------------------------------------------------

"""
    ckpt_path(jobdir, epoch) -> String
    metrics_path(jobdir, epoch) -> String
"""
function ckpt_path(jobdir::AbstractString, epoch::Int)::String
    joinpath(jobdir, "epoch", @sprintf("%04d.ckpt", epoch))
end
function metrics_path(jobdir::AbstractString, epoch::Int)::String
    joinpath(jobdir, "epoch", @sprintf("%04d.json", epoch))
end

"""
    save_checkpoint(jobdir, epoch, model_st, opt_st, rng_st)

Serialise the checkpoint to epoch/NNNN.ckpt and flush to disk.
The checkpoint Dict contains:
    "model_state" => model_st
    "opt_state"   => opt_st
    "rng_state"   => rng_st
    "epoch"       => epoch
"""
function save_checkpoint(
    jobdir    :: AbstractString,
    epoch     :: Int,
    model_st,
    opt_st,
    rng_st,
)::Nothing
    mkpath(joinpath(jobdir, "epoch"))
    p = ckpt_path(jobdir, epoch)
    open(p, "w") do io
        serialize(io, Dict(
            "model_state" => model_st,
            "opt_state"   => opt_st,
            "rng_state"   => rng_st,
            "epoch"       => epoch,
        ))
    end
    # file is closed here (flush is implicit on close in Julia)
    return nothing
end

"""
    load_latest_checkpoint(jobdir) -> Dict or nothing

Scan epoch/ for the highest-numbered .ckpt file and deserialise it.
Returns nothing if no checkpoints exist.
"""
function load_latest_checkpoint(jobdir::AbstractString)
    epoch_dir = joinpath(jobdir, "epoch")
    isdir(epoch_dir) || return nothing
    ckpts = filter(f -> endswith(f, ".ckpt"), readdir(epoch_dir))
    isempty(ckpts) && return nothing
    # Sort by epoch number, not lexically: names are %04d-padded, so past epoch
    # 9999 the widths differ and a lexical sort puts "9999.ckpt" after "10000.ckpt".
    sort!(ckpts; by = f -> parse(Int, first(split(f, '.'))))
    latest = ckpts[end]
    p = joinpath(epoch_dir, latest)
    return open(deserialize, p)
end

"""
    save_epoch_metrics(jobdir, epoch, loss, score, wall_s)

Write epoch/NNNN.json with the per-epoch metric snapshot.
File is closed (flushed) before returning.
"""
function save_epoch_metrics(
    jobdir :: AbstractString,
    epoch  :: Int,
    loss   :: Float64,
    score  :: Float64,
    wall_s :: Float64,
)::Nothing
    mkpath(joinpath(jobdir, "epoch"))
    d = Dict{String,Any}(
        "epoch"  => epoch,
        "loss"   => loss,
        "score"  => score,
        "wall_s" => wall_s,
    )
    _write_json(metrics_path(jobdir, epoch), d)
    return nothing
end

# ---------------------------------------------------------------------------
# DEFAULT PROJECT HOOKS (self-test / fallback)
# ---------------------------------------------------------------------------
#
# A real project overrides these by defining the same functions BEFORE this
# file is included, or by setting RUNNER_PROJECT_FILE= (see top-level runner
# entry point below).
#
# The default is a toy 2D quadratic minimisation: model holds a parameter
# vector θ, train_step does one gradient-descent step, score returns ‖θ‖₂.

"""
Default model: a mutable struct holding a Float64 parameter vector θ.
"""
mutable struct _ToyModel
    θ :: Vector{Float64}
end

"""
Default make_model: initialise θ randomly under the job seed.
"""
function make_model(job::Dict)
    seed = get(job, "seed", 42)
    rng  = _make_rng(seed)
    dim  = 8  # toy quadratic in R^8
    θ    = randn(rng, dim)
    return _ToyModel(θ)
end

"""
Default make_data: synthetic quadratic data (target θ* = zeros(8)).
"""
function make_data(job::Dict)
    seed = get(job, "seed", 42)
    rng  = _make_rng(seed + 1)
    # held-out "data" for scoring: the zero vector (optimal solution)
    return (x = ones(8), y = zeros(8))
end

"""
Default train_step: gradient descent on ‖θ‖².  Loss = ‖θ‖².
"""
function train_step(model::_ToyModel, data, epoch::Int, job::Dict)
    lr   = 0.05
    loss = sum(model.θ .^ 2)
    # Gradient: 2θ
    model.θ .-= lr .* (2 .* model.θ)
    return (model, loss)
end

"""
Default score: rel_l2(θ, 0) = ‖θ‖₂ / ‖y‖₂.  y = zeros so we use ‖θ‖₂ directly.
"""
function score(model::_ToyModel, data, budget_s::Float64)::ExperimentResult
    t0  = time()
    val = sqrt(sum(model.θ .^ 2))
    meta = Dict{String,Any}(
        "scorer"   => "toy_quadratic_l2",
        "note"     => "self-test default; replace with your project scorer",
    )
    return ExperimentResult(val, time() - t0, meta)
end

"""
Default model_state: return a copy of the parameter vector.
"""
function model_state(model::_ToyModel)
    return copy(model.θ)
end

"""
Default load_model_state!: restore θ from saved state.
"""
function load_model_state!(model::_ToyModel, state)
    model.θ = copy(state)
    return model
end

# ---------------------------------------------------------------------------
# RNG helpers
# ---------------------------------------------------------------------------

"""
    _make_rng(seed::Integer) -> AbstractRNG

Returns a seeded MersenneTwister.  Swap for Xoshiro(seed) on Julia >= 1.7.
"""
function _make_rng(seed::Integer)
    return VERSION >= v"1.7" ? Random.Xoshiro(seed) : Random.MersenneTwister(seed)
end

import Random

"""
    _capture_rng_state(rng) -> state

Capture the full RNG state for serialisation.
Works for both MersenneTwister and Xoshiro by copying the struct.
"""
_capture_rng_state(rng) = deepcopy(rng)

"""
    _restore_rng!(rng, state)

Restore the RNG state from a previously captured state.
"""
function _restore_rng!(rng, state)
    # For stdlib RNGs, the easiest safe path is to copy fields.
    # This works for MersenneTwister and Xoshiro (both are mutable structs).
    for f in fieldnames(typeof(state))
        setfield!(rng, f, deepcopy(getfield(state, f)))
    end
    return rng
end

# ---------------------------------------------------------------------------
# Core training loop
# ---------------------------------------------------------------------------

"""
    run_job(jobdir; resume::Bool = false) -> Nothing

The main experiment loop:
  1. Read job.json.
  2. Flip status PENDING → RUNNING (atomic).
  3. Load or create the model / data.
  4. For each epoch up to max_epochs within budget_s:
       a. train_step
       b. score
       c. Write epoch/NNNN.ckpt  (serialised checkpoint)
       d. Write epoch/NNNN.json  (per-epoch metrics)
       e. Update heartbeat
       f. Check wall-clock budget; break if exceeded.
  5. Write result.json (atomic), flip status → DONE.
  6. On any exception: flip status → FAILED; re-throw so the OS logs it.

Crash-safety: every disk write is flushed (via file close) BEFORE the loop
continues.  The status file is written last; an observer always sees a
consistent epoch/ directory.
"""
function run_job(jobdir::AbstractString; resume::Bool = false)::Nothing
    jobdir = abspath(jobdir)
    isdir(jobdir) || error("Job directory does not exist: $jobdir")

    # -----------------------------------------------------------------------
    # 1. Read job spec
    # -----------------------------------------------------------------------
    job = _read_json(joinpath(jobdir, "job.json"))
    hid        = get(job, "hid",        "unknown")
    budget_s   = Float64(get(job, "budget_s",   300.0))
    seed       = Int(get(job, "seed",       42))
    max_epochs = Int(get(job, "max_epochs", 100))
    backend    = get(job, "backend",    "cpu")

    # Load optional project file (from env or job.json)
    _maybe_load_project(jobdir, job)

    # -----------------------------------------------------------------------
    # 2. Configure device
    # -----------------------------------------------------------------------
    configure_threads!()
    dev = describe_device()

    # -----------------------------------------------------------------------
    # 3. Check / set status
    # -----------------------------------------------------------------------
    current_status = read_status(jobdir)
    if !resume && current_status == "RUNNING"
        @warn "Job $hid already RUNNING; use --resume to continue"
        return nothing
    end
    if current_status == "DONE"
        @info "Job $hid already DONE"
        return nothing
    end

    write_status(jobdir, "RUNNING")
    @info "PHD runner: job $hid RUNNING (budget=$(budget_s)s, max_epochs=$max_epochs)"

    start_wall = time()
    start_epoch = 1

    # -----------------------------------------------------------------------
    # 4. Build model / data; optionally resume from checkpoint
    # -----------------------------------------------------------------------
    rng   = _make_rng(seed)
    # invokelatest: project hooks are include()d at runtime (see _maybe_load_project);
    # without it, world-age hides them and dispatch silently falls back to the toy hooks.
    model = Base.invokelatest(make_model, job)
    data  = Base.invokelatest(make_data, job)
    opt_st = nothing  # placeholder; projects with optimiser state populate this

    if resume
        ckpt = load_latest_checkpoint(jobdir)
        if ckpt !== nothing
            start_epoch = Int(ckpt["epoch"]) + 1
            model = Base.invokelatest(load_model_state!, model, ckpt["model_state"])
            opt_st = ckpt["opt_state"]
            if ckpt["rng_state"] !== nothing
                rng_st = ckpt["rng_state"]
                try
                    _restore_rng!(rng, rng_st)
                catch
                    @warn "Could not restore RNG state; continuing with fresh RNG"
                end
            end
            @info "Resumed from epoch $(start_epoch - 1)"
        else
            @warn "--resume requested but no checkpoint found; starting from epoch 1"
        end
    end

    # -----------------------------------------------------------------------
    # 5. Epoch loop
    # -----------------------------------------------------------------------
    best_result = nothing
    elapsed = time() - start_wall

    try
        for epoch in start_epoch:max_epochs
            elapsed = time() - start_wall
            remaining_budget = budget_s - elapsed
            remaining_budget <= 0.0 && (@info "Budget exhausted at epoch $epoch"; break)

            epoch_start = time()

            # 5a. Training step  (invokelatest — see note at model/data construction)
            (model, loss) = Base.invokelatest(train_step, model, data, epoch, job)

            # 5b. Score
            result = Base.invokelatest(score, model, data, max(0.0, remaining_budget - (time() - epoch_start)))

            # Contract check: a project's score() must return an ExperimentResult.
            # Fail loudly with a useful message instead of writing garbage result.json.
            result isa ExperimentResult || error(
                "score() must return an ExperimentResult (score::Float64, wall_s::Float64, " *
                "meta::Dict); got $(typeof(result)) at epoch $epoch. Fix your project's score() hook.")
            isfinite(result.score) || @warn "score() returned non-finite score=$(result.score) at epoch $epoch"

            epoch_wall = time() - epoch_start

            # 5c. Write checkpoint — MUST flush before continuing
            rng_st = _capture_rng_state(rng)
            save_checkpoint(jobdir, epoch, Base.invokelatest(model_state, model), opt_st, rng_st)

            # 5d. Write per-epoch metrics — MUST flush before continuing
            save_epoch_metrics(jobdir, epoch, Float64(loss), result.score, epoch_wall)

            # 5e. Update heartbeat — MUST flush before continuing
            write_heartbeat(jobdir, epoch)

            # Track best
            if best_result === nothing || result.score < best_result.score
                best_result = result
            end

            @info "  epoch=$epoch  loss=$(round(loss, sigdigits=4))" *
                  "  score=$(round(result.score, sigdigits=4))" *
                  "  wall=$(round(epoch_wall, sigdigits=3))s"
        end

        # -------------------------------------------------------------------
        # 6. Write result.json and flip DONE
        # -------------------------------------------------------------------
        final_wall = time() - start_wall
        if best_result === nothing
            best_result = ExperimentResult(Inf, final_wall, Dict{String,Any}())
        end

        result_d = Dict{String,Any}(
            "hid"     => hid,
            "score"   => best_result.score,
            "wall_s"  => final_wall,
            "backend" => backend,
            "meta"    => merge(best_result.meta, dev),
        )
        write_json_atomic(joinpath(jobdir, "result.json"), result_d)
        write_status(jobdir, "DONE")
        @info "Job $hid DONE  score=$(round(best_result.score, sigdigits=5))  wall=$(round(final_wall, sigdigits=3))s"

    catch e
        # -------------------------------------------------------------------
        # On any exception: flip FAILED, leave checkpoints intact
        # -------------------------------------------------------------------
        try
            write_status(jobdir, "FAILED")
        catch
        end
        @error "Job $hid FAILED" exception=(e, catch_backtrace())
        rethrow(e)
    end

    return nothing
end

# ---------------------------------------------------------------------------
# Project file loader
# ---------------------------------------------------------------------------

"""
    _maybe_load_project(jobdir, job)

Load a project-specific Julia file that overrides the default hooks.
Priority:
  1. RUNNER_PROJECT_FILE environment variable
  2. "project_file" key in job.json
  3. project.jl in the job directory itself

If none found, the default toy quadratic hooks are used.
"""
function _maybe_load_project(jobdir::AbstractString, job::Dict)::Nothing
    candidates = [
        get(ENV, "RUNNER_PROJECT_FILE", ""),
        get(job, "project_file", ""),
        joinpath(jobdir, "project.jl"),
    ]
    for path in candidates
        if !isempty(path) && isfile(path)
            @info "Loading project file: $path"
            include(path)
            return nothing
        end
    end
    @info "No project file found; using built-in toy quadratic (self-test mode)"
    return nothing
end

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

"""
Command-line entry point.

    julia runner.jl <jobdir> [--resume]
"""
function _main(args::Vector{String})
    if isempty(args) || args[1] == "--help" || args[1] == "-h"
        println("""
        PHD experiment runner

        Usage:
            julia runner.jl <jobdir>          run job from PENDING
            julia runner.jl <jobdir> --resume  resume from latest checkpoint

        <jobdir>: directory containing job.json
                  (see §5.2 of ARCHITECTURE.md for the full layout)
        """)
        return
    end

    jobdir = args[1]
    resume = "--resume" in args
    run_job(jobdir; resume = resume)
end

# Run when invoked as a script (not when included as a library)
if abspath(PROGRAM_FILE) == @__FILE__
    _main(ARGS)
end
