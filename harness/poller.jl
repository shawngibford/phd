"""
poller.jl — One-pass supervisor tick (PHD harness)

Usage
-----
    julia poller.jl <project_root>

Performs exactly ONE pass of the experiment supervisor loop, then exits.
Designed to be called by a scheduler (cron / scheduled-tasks) every N minutes,
or by /phd:run --tick.

Supervisor loop (one pass = one "tick"):
    1. Scan runs/*/status.
    2. DONE → read result.json → compare to current best → KEEP or DISCARD
       → append LEDGER.md row → write .reaped marker → propose + launch next.
    3. FAILED, or RUNNING with stale heartbeat → mark FAILED → resume from
       latest checkpoint (up to RETRY_CAP retries); after cap, DISCARD +
       "unrecoverable" note.
    4. RUNNING fresh → leave it.
    5. PENDING with no launcher → launch it (handles manual job.json drops).

Idempotency guarantees
----------------------
  • A .reaped file in a job directory means the job has been processed.
    The poller skips it in every subsequent tick.  The .reaped file is written
    AFTER the ledger row is appended and the next job is launched, so a crash
    between those steps just re-runs the same reap (idempotent: ledger gets a
    duplicate row in that edge case, which is visible and acceptable).
  • Retries are tracked in a retry.json file in the job directory.
  • launch_detached() checks status before spawning (never double-launches).

Stale-heartbeat detection
--------------------------
  Staleness threshold = max(STALE_FLOOR_S, 2 × median_epoch_time).
  median_epoch_time is derived from epoch/NNNN.json files in the same job dir.
  If no epoch metrics exist yet (job started but no epoch completed), we use
  STALE_FLOOR_S as the threshold.

  STALE_FLOOR_S = 120.0  (2 minutes — sane floor so brand-new jobs aren't reaped)
"""

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

const POLLER_DIR = @__DIR__
include(joinpath(POLLER_DIR, "jobctl.jl"))

# Include guard for poller itself (supervisor.jl includes poller.jl; protect
# against duplicate definitions if someone includes poller.jl twice).
@isdefined(_POLLER_LOADED) && return
const _POLLER_LOADED = true

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const RETRY_CAP     = 3      # max resume attempts before declaring unrecoverable
const STALE_FLOOR_S = 120.0  # minimum heartbeat age to count as stale (seconds)
const PENDING_GRACE_S = 30.0 # seconds before a PENDING job without a launcher is auto-launched

# ---------------------------------------------------------------------------
# Retry tracking
# ---------------------------------------------------------------------------

"""
    read_retry_count(jobdir) -> Int
"""
function read_retry_count(jobdir::AbstractString)::Int
    p = joinpath(jobdir, "retry.json")
    isfile(p) || return 0
    d = _jc_read_json(p)
    return Int(get(d, "count", 0))
end

"""
    write_retry_count(jobdir, n) -> Nothing
"""
function write_retry_count(jobdir::AbstractString, n::Int)::Nothing
    _jc_write_json_atomic(joinpath(jobdir, "retry.json"),
                          Dict{String,Any}("count" => n))
    return nothing
end

# ---------------------------------------------------------------------------
# Heartbeat staleness check
# ---------------------------------------------------------------------------

"""
    median_epoch_time(jobdir) -> Float64   (seconds, or NaN if no data)

Computes the median wall-clock time per epoch from epoch/NNNN.json files.
Used to set a data-driven staleness threshold.
"""
function median_epoch_time(jobdir::AbstractString)::Float64
    epoch_dir = joinpath(jobdir, "epoch")
    isdir(epoch_dir) || return NaN
    jsons = filter(f -> endswith(f, ".json"), readdir(epoch_dir))
    isempty(jsons) && return NaN
    walls = Float64[]
    for f in jsons
        try
            d = _jc_read_json(joinpath(epoch_dir, f))
            haskey(d, "wall_s") && push!(walls, Float64(d["wall_s"]))
        catch
        end
    end
    isempty(walls) && return NaN
    sort!(walls)
    n = length(walls)
    return n % 2 == 0 ? (walls[n÷2] + walls[n÷2+1]) / 2.0 : walls[(n+1)÷2]
end

"""
    is_heartbeat_stale(jobdir) -> Bool

Returns true if the heartbeat is missing or older than
  max(STALE_FLOOR_S, 2 × median_epoch_time).
"""
function is_heartbeat_stale(jobdir::AbstractString)::Bool
    hb_path = joinpath(jobdir, "heartbeat")
    isfile(hb_path) || return true   # no heartbeat at all = stale

    ts = try
        d = _jc_read_json(hb_path)
        Float64(get(d, "ts", 0.0))
    catch
        return true
    end

    age = time() - ts
    med = median_epoch_time(jobdir)
    threshold = isnan(med) ? STALE_FLOOR_S : max(STALE_FLOOR_S, 2.0 * med)
    return age > threshold
end

# ---------------------------------------------------------------------------
# Next-experiment proposal (Slice 1: deterministic seed/hyperparam sweep)
# ---------------------------------------------------------------------------

"""
    propose_next_job(project_root, best) -> Dict{String,Any}

For Slice 1: simple deterministic sweep over seeds and a small set of
hyperparameters drawn from experiment.md's "What to vary" axes.

The sweep cycles through:
    seed:          [42, 1337, 7, 2024, 314]
    budget_s:      read from experiment.md or default 300.0
    max_epochs:    [50, 100, 200]
    learning_rate: [0.01, 0.05, 0.1, 0.005]

We count how many past jobs exist and use that index to determine the next
combination (mod-based wraparound = infinite supply of experiments).

Returns a job.json dict ready to be written to the new job directory.
"""
function propose_next_job(
    project_root :: AbstractString,
    best         :: Dict{String,Any},
)::Dict{String,Any}
    # Sweep axes (Slice 1 — fully deterministic)
    seeds          = [42, 1337, 7, 2024, 314, 99, 8675309, 2718]
    max_epochs_set = [50, 100, 200, 150]
    lr_set         = [0.01, 0.05, 0.1, 0.005, 0.001]

    # Count total historical jobs (across all status) to advance the sweep index
    past = scan_job_dirs(project_root)
    idx  = length(past)   # 0-based

    seed       = seeds[      (idx % length(seeds))           + 1]
    max_ep     = max_epochs_set[(idx % length(max_epochs_set)) + 1]
    lr         = lr_set[    (idx % length(lr_set))           + 1]

    # Read budget from experiment.md if present
    budget_s = _read_budget_from_experiment(project_root)

    hid = _next_hid(project_root)

    # Assemble job spec
    job = Dict{String,Any}(
        "hid"           => hid,
        "seed"          => seed,
        "budget_s"      => budget_s,
        "max_epochs"    => max_ep,
        "backend"       => "cpu",
        "learning_rate" => lr,
        "sweep_index"   => idx,
        "proposed_by"   => "poller_sweep_v1",
        # hypothesis/change fields for the ledger — filled from experiment.md framing
        "hypothesis"    => _sweep_hypothesis(idx, seed, lr, max_ep),
        "change"        => _sweep_change(idx, seed, lr, max_ep),
    )

    return job
end

"""
    _read_budget_from_experiment(project_root) -> Float64

Try to read `budget_s` from CONTEXT.md or experiment.md.  Falls back to 300.0.
"""
function _read_budget_from_experiment(project_root::AbstractString)::Float64
    # Look for a line like "budget: 300s" or "budget_s: 300" in experiment.md or CONTEXT.md
    for fname in ["CONTEXT.md", "experiment.md"]
        p = joinpath(project_root, fname)
        isfile(p) || continue
        for line in eachline(p)
            m = match(r"budget[_s]*\s*[:=]\s*(\d+(?:\.\d+)?)\s*s?", line)
            m !== nothing && return parse(Float64, m.captures[1])
        end
    end
    return 300.0
end

"""Compose a hypothesis string for the sweep entry."""
function _sweep_hypothesis(idx::Int, seed::Int, lr::Float64, max_ep::Int)::String
    axes = [
        "varying seed for reproducibility check",
        "learning rate adjustment",
        "max-epochs budget increase",
        "combined seed+lr sweep",
    ]
    axis = axes[(idx % length(axes)) + 1]
    return "Sweep experiment $idx: $axis (seed=$seed, lr=$lr, max_epochs=$max_ep)"
end

"""Compose a change string for the sweep entry."""
function _sweep_change(idx::Int, seed::Int, lr::Float64, max_ep::Int)::String
    return "seed=$(seed), learning_rate=$(lr), max_epochs=$(max_ep) (sweep index $idx)"
end

# ---------------------------------------------------------------------------
# Score comparison (lower is better)
# ---------------------------------------------------------------------------

"""
    is_improvement(new_score, best_score) -> Bool

Returns true if `new_score` strictly improves on `best_score`.
Ties go to discard (simpler is preferred, per experiment.md).
"""
function is_improvement(new_score::Float64, best_score::Float64)::Bool
    isnan(new_score)  && return false
    isinf(new_score)  && return false
    isnan(best_score) && return true   # first result is always an improvement on NaN
    return new_score < best_score
end

# ---------------------------------------------------------------------------
# Ledger row builder
# ---------------------------------------------------------------------------

"""
    build_ledger_row(status, hid, job, result, best, project_root; note="") -> String

Build the exact LEDGER.md row format (hard contract from templates/LEDGER.md):

    ## H-NNN · YYYY-MM-DD · STATUS
    hypothesis: <text>
    change: <text>
    metric: <name>  <before> → <after>   (best so far | no improvement)   budget: <T>s   seed: <seed>
    baseline: <classical> → <quantum> <BEATS classical ✓ | does NOT beat classical ✗ | no baseline recorded>
    artifacts: runs/<id>/  commit: <sha or "uncommitted">
    note: <text>
"""
function build_ledger_row(
    status       :: AbstractString,
    hid          :: AbstractString,
    job          :: Dict,
    result       :: Dict,
    best_before  :: Float64,
    project_root :: AbstractString;
    note         :: AbstractString = "",
)::String
    date       = _today_str()
    ledger_hid = _hid_to_ledger(hid)
    sha        = _git_sha(project_root)

    hypothesis = get(job, "hypothesis", "")
    # Accept either "change" (run.md / sweep specs) or "diff" (ARCHITECTURE §5.2 /
    # job.example.json) so both documented job-spec vocabularies populate the ledger.
    change     = get(job, "change", get(job, "diff", ""))
    seed       = get(job, "seed",       "?")
    budget_s   = get(job, "budget_s",   "?")
    metric_name = get(job, "metric_name", "score")

    new_score  = Float64(get(result, "score", Inf))
    before_str = isinf(best_before) ? "none" : string(round(best_before, sigdigits=4))
    after_str  = isnan(new_score) ? "NaN" :
                 isinf(new_score) ? "Inf" :
                 string(round(new_score, sigdigits=4))
    improvement_tag = status == "KEPT" ? "(best so far)" : "(no improvement)"
    budget_str = isa(budget_s, Number) ? string(round(Float64(budget_s), digits=0)) : string(budget_s)

    # Baseline / quantum info from meta
    meta       = get(result, "meta", Dict())
    meta       = isa(meta, Dict) ? meta : Dict()
    no_baseline = get(meta, "no_baseline", true)
    adv_ratio   = get(meta, "quantum_advantage_ratio", nothing)

    if no_baseline
        baseline_line = "no baseline recorded"
    else
        cost_c = get(meta, "cost_classical_baseline", "?")
        cost_q = get(meta, "cost_q",                  "?")
        if isa(adv_ratio, Number) && !isnan(adv_ratio) && adv_ratio < 1.0
            verdict = "BEATS classical ✓"
        elseif isa(adv_ratio, Number) && !isnan(adv_ratio)
            verdict = "does NOT beat classical ✗"
        else
            verdict = "no baseline recorded"
        end
        cost_c_str = isa(cost_c, Number) ? string(round(Float64(cost_c), sigdigits=4)) : string(cost_c)
        cost_q_str = isa(cost_q, Number) ? string(round(Float64(cost_q), sigdigits=4)) : string(cost_q)
        baseline_line = "$(cost_c_str) → $(cost_q_str) $(verdict)"
    end

    row = """## $(ledger_hid) · $(date) · $(status)
hypothesis: $(hypothesis)
change: $(change)
metric: $(metric_name)  $(before_str) → $(after_str)   $(improvement_tag)   budget: $(budget_str)s   seed: $(seed)
baseline: $(baseline_line)
artifacts: runs/$(hid)/  commit: $(sha)
note: $(note)"""

    return row
end

# ---------------------------------------------------------------------------
# Process a single DONE job
# ---------------------------------------------------------------------------

"""
    reap_done(jobdir, project_root) -> Nothing

Called when a job's status file reads DONE.  Steps:
  1. Read result.json.
  2. Compare score to best.json.
  3. Append ledger row (KEPT or DISCARDED).
  4. Update best.json if improved.
  5. Write .reaped marker.
  6. Propose and launch the next experiment.
"""
function reap_done(jobdir::AbstractString, project_root::AbstractString)::Nothing
    hid = basename(jobdir)

    result_path = joinpath(jobdir, "result.json")
    if !isfile(result_path)
        @warn "reap_done: $hid has no result.json; marking FAILED"
        _jc_write_atomic(joinpath(jobdir, "status"), "FAILED")
        return nothing
    end

    result    = _jc_read_json(result_path)
    new_score = Float64(get(result, "score", Inf))
    job_path  = joinpath(jobdir, "job.json")
    job       = isfile(job_path) ? _jc_read_json(job_path) : Dict{String,Any}()

    best       = read_best(project_root)
    best_score = Float64(best["score"])

    if is_improvement(new_score, best_score)
        status = "KEPT"
        note   = get(job, "proposed_note", "")
        write_best(project_root, Dict{String,Any}(
            "hid"    => hid,
            "score"  => new_score,
            "jobdir" => jobdir,
        ))
        @info "reap_done: $hid KEPT  score=$(round(new_score, sigdigits=5))  (was $(round(best_score, sigdigits=5)))"
    else
        status = "DISCARDED"
        note   = "score $(round(new_score, sigdigits=4)) did not improve on best $(round(best_score, sigdigits=4))"
        @info "reap_done: $hid DISCARDED  score=$(round(new_score, sigdigits=5))  best=$(round(best_score, sigdigits=5))"
    end

    row = build_ledger_row(status, hid, job, result, best_score, project_root; note=note)
    append_ledger_row(project_root, row)

    # Mark reaped AFTER ledger write (crash here = duplicate ledger row, acceptable)
    _jc_write_atomic(joinpath(jobdir, ".reaped"), "reaped")

    # Propose + launch the next experiment
    _propose_and_launch(project_root, best)
    return nothing
end

# ---------------------------------------------------------------------------
# Process a stale / failed job
# ---------------------------------------------------------------------------

"""
    reap_failed_or_stale(jobdir, project_root; force_failed=false) -> Nothing

Handle a job that is FAILED or RUNNING-with-stale-heartbeat.
  - Increment retry counter.
  - If retries < RETRY_CAP: resume from latest checkpoint.
  - If retries >= RETRY_CAP: write DISCARDED ledger row with "unrecoverable" note.
"""
function reap_failed_or_stale(
    jobdir       :: AbstractString,
    project_root :: AbstractString;
    force_failed :: Bool = false,
)::Nothing
    hid     = basename(jobdir)
    retries = read_retry_count(jobdir)

    if retries < RETRY_CAP
        new_count = retries + 1
        write_retry_count(jobdir, new_count)
        @info "reap_failed_or_stale: $hid — retry $new_count/$RETRY_CAP (--resume)"
        # Mark FAILED before resuming so the status is honest during the gap
        _jc_write_atomic(joinpath(jobdir, "status"), "FAILED")
        launch_detached(jobdir; resume=true)
    else
        # Unrecoverable: discard
        @warn "reap_failed_or_stale: $hid — retry cap ($RETRY_CAP) reached; DISCARDED as unrecoverable"
        _jc_write_atomic(joinpath(jobdir, "status"), "FAILED")

        job_path = joinpath(jobdir, "job.json")
        job      = isfile(job_path) ? _jc_read_json(job_path) : Dict{String,Any}()
        best     = read_best(project_root)

        # Build a sentinel result for the ledger
        result = Dict{String,Any}("hid" => hid, "score" => Inf, "wall_s" => 0.0,
                                  "backend" => "cpu", "meta" => Dict{String,Any}())
        row = build_ledger_row("DISCARDED", hid, job, result, Float64(best["score"]),
                               project_root;
                               note="unrecoverable after $RETRY_CAP retries")
        append_ledger_row(project_root, row)
        _jc_write_atomic(joinpath(jobdir, ".reaped"), "reaped")

        # Still launch next — the run must never stall
        _propose_and_launch(project_root, best)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Propose + launch the next experiment
# ---------------------------------------------------------------------------

"""
    _propose_and_launch(project_root, current_best) -> Nothing

Generate the next job, write its directory + job.json, and launch detached.
"""
function _propose_and_launch(
    project_root  :: AbstractString,
    current_best  :: Dict{String,Any},
)::Nothing
    job   = propose_next_job(project_root, current_best)
    hid   = job["hid"]
    newdir = joinpath(project_root, "runs", hid)
    mkpath(newdir)

    # Write job.json
    _jc_write_json_atomic(joinpath(newdir, "job.json"), job)

    # Write PENDING status
    _jc_write_atomic(joinpath(newdir, "status"), "PENDING")

    @info "_propose_and_launch: created $newdir"
    launch_detached(newdir)
    return nothing
end

# ---------------------------------------------------------------------------
# Main tick
# ---------------------------------------------------------------------------

"""
    tick(project_root) -> Nothing

One full pass of the supervisor loop.  Call this once per scheduled interval.
"""
function tick(project_root::AbstractString)::Nothing
    project_root = abspath(project_root)
    @info "poller tick: project_root=$project_root  time=$(Dates.now())"

    dirs = scan_job_dirs(project_root)

    if isempty(dirs)
        # No jobs at all — bootstrap the very first experiment
        @info "poller tick: no jobs found; bootstrapping first experiment"
        best = read_best(project_root)
        _propose_and_launch(project_root, best)
        return nothing
    end

    for jobdir in dirs
        hid        = basename(jobdir)
        reaped_p   = joinpath(jobdir, ".reaped")
        status_p   = joinpath(jobdir, "status")

        # Skip already-reaped jobs (idempotency guarantee)
        isfile(reaped_p) && continue

        status = isfile(status_p) ? strip(read(status_p, String)) : "PENDING"

        if status == "DONE"
            @info "poller: $hid DONE → reaping"
            reap_done(jobdir, project_root)

        elseif status == "FAILED"
            @info "poller: $hid FAILED → retry/discard"
            reap_failed_or_stale(jobdir, project_root; force_failed=true)

        elseif status == "RUNNING"
            if is_heartbeat_stale(jobdir)
                @info "poller: $hid RUNNING but stale heartbeat → treat as FAILED"
                reap_failed_or_stale(jobdir, project_root)
            else
                @info "poller: $hid RUNNING fresh → leaving"
            end

        elseif status == "PENDING"
            # Check how old the PENDING status is
            mtime_p = mtime(status_p)
            age     = time() - mtime_p
            if age > PENDING_GRACE_S
                @info "poller: $hid PENDING for $(round(age))s → launching"
                launch_detached(jobdir)
            else
                @info "poller: $hid PENDING ($(round(age))s old) → waiting for launcher"
            end

        else
            @warn "poller: $hid has unknown status '$status' → skipping"
        end
    end

    @info "poller tick: done"
    return nothing
end

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

function _main(args::Vector{String})
    if isempty(args) || args[1] in ("--help", "-h")
        println("""
        PHD poller — one supervisor tick

        Usage:
            julia poller.jl <project_root>

        <project_root>: directory containing runs/, LEDGER.md, experiment.md.
                        Usually the root of your research project.

        One pass of the supervisor loop: reap DONE jobs (keep/discard), handle
        failures/stale jobs (retry → resume, or discard as unrecoverable),
        propose and launch the next experiment.  Exits when done.  Safe to call
        repeatedly (idempotent via .reaped markers).
        """)
        return
    end

    tick(args[1])
end

if abspath(PROGRAM_FILE) == @__FILE__
    _main(ARGS)
end
