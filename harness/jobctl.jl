"""
jobctl.jl — Shared job-control utilities (PHD harness)

Included by both poller.jl and supervisor.jl.  Do NOT run directly.

Provides
--------
    launch_detached(jobdir; resume=false)  -> Int (pid)
    count_running(project_root)            -> Int
    scan_job_dirs(project_root)            -> Vector{String}
    best_json_path(project_root)           -> String
    read_best(project_root)                -> Dict{String,Any}
    write_best(project_root, d)            -> Nothing
    ledger_path(project_root)              -> String
    append_ledger_row(project_root, row)   -> Nothing

JSON helpers (shared with runner.jl but inlined here to keep zero exotic deps)
are re-exported so poller/supervisor can use them without re-including runner.jl.
"""

# Include guard: if supervisor.jl includes jobctl.jl and then poller.jl also
# includes jobctl.jl, the second include is a no-op.  In Julia, a bare `return`
# inside an included file exits the include() call immediately.
@isdefined(_JOBCTL_LOADED) && return
const _JOBCTL_LOADED = true

# ---------------------------------------------------------------------------
# Bootstrap: locate the harness directory relative to THIS file
# ---------------------------------------------------------------------------

const JOBCTL_HARNESS_DIR = @__DIR__

# ---------------------------------------------------------------------------
# Minimal JSON write (matches runner.jl exactly — same hand-rolled serialiser)
# ---------------------------------------------------------------------------

function _jc_json_escape(s::AbstractString)::String
    replace(s,
        '\\' => "\\\\",
        '"'  => "\\\"",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
    )
end

function _jc_json_write(io::IO, d::Dict)
    print(io, "{")
    pairs_vec = collect(d)
    for (i, (k, v)) in enumerate(pairs_vec)
        _jc_json_write(io, string(k))
        print(io, ":")
        _jc_json_write(io, v)
        i < length(pairs_vec) && print(io, ",")
    end
    print(io, "}")
end
_jc_json_write(io::IO, s::AbstractString) = print(io, "\"", _jc_json_escape(s), "\"")
_jc_json_write(io::IO, n::Real)           = isnan(n) ? print(io, "null") : print(io, n)
_jc_json_write(io::IO, b::Bool)           = print(io, b ? "true" : "false")
_jc_json_write(io::IO, ::Nothing)         = print(io, "null")
function _jc_json_write(io::IO, v::Vector)
    print(io, "[")
    for (i, x) in enumerate(v)
        _jc_json_write(io, x)
        i < length(v) && print(io, ",")
    end
    print(io, "]")
end
_jc_json_write(io::IO, x) = print(io, "\"", string(x), "\"")

function _jc_write_json(path::AbstractString, d::Dict)::Nothing
    open(path, "w") do io
        _jc_json_write(io, d)
        println(io)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Minimal JSON read (matches runner.jl exactly)
# ---------------------------------------------------------------------------

function _jc_json_split(s::AbstractString)::Vector{SubString{String}}
    parts = SubString{String}[]
    depth = 0; in_str = false; esc = false; start = firstindex(s)
    for (i, c) in pairs(s)
        if esc;  esc = false; continue; end
        if c == '\\' && in_str; esc = true; continue; end
        if c == '"'; in_str = !in_str; continue; end
        if !in_str
            if c in ('{', '[');   depth += 1
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

function _jc_json_colon_pos(s::AbstractString)::Int
    in_str = false; esc = false
    for (i, c) in pairs(s)
        if esc; esc = false; continue; end
        if c == '\\' && in_str; esc = true; continue; end
        if c == '"'; in_str = !in_str; continue; end
        if c == ':' && !in_str; return i; end
    end
    return 0
end

function _jc_json_unquote(s::AbstractString)::String
    s = strip(s)
    startswith(s, "\"") && endswith(s, "\"") && return String(s[2:end-1])
    return String(s)
end

function _jc_json_parse_value(s::AbstractString)::Any
    s = strip(s)
    s == "null"  && return nothing
    s == "true"  && return true
    s == "false" && return false
    if startswith(s, "\"") && endswith(s, "\"")
        return unescape_string(String(s[2:end-1]))
    end
    # BUG 1 FIX: handle nested object — parse recursively into a Dict
    if startswith(s, "{") && endswith(s, "}")
        inner  = s[2:end-1]
        tokens = _jc_json_split(inner)
        nested = Dict{String,Any}()
        for tok in tokens
            tok = strip(tok)
            isempty(tok) && continue
            ci = _jc_json_colon_pos(tok)
            ci == 0 && continue
            k = _jc_json_unquote(strip(tok[1:ci-1]))
            v = _jc_json_parse_value(strip(tok[ci+1:end]))
            nested[k] = v
        end
        return nested
    end
    iv = tryparse(Int, s); iv !== nothing && return iv
    fv = tryparse(Float64, s); fv !== nothing && return fv
    return String(s)
end

function _jc_read_json(path::AbstractString)::Dict{String,Any}
    raw = read(path, String)
    d   = Dict{String,Any}()
    s   = strip(raw)
    startswith(s, "{") && endswith(s, "}") || error("Not a JSON object: $path")
    inner  = s[2:end-1]
    tokens = _jc_json_split(inner)
    for tok in tokens
        tok = strip(tok)
        isempty(tok) && continue
        ci = _jc_json_colon_pos(tok)
        ci == 0 && continue
        key = _jc_json_unquote(strip(tok[1:ci-1]))
        val = _jc_json_parse_value(strip(tok[ci+1:end]))
        d[key] = val
    end
    return d
end

# ---------------------------------------------------------------------------
# Atomic file write (matches runner.jl)
# ---------------------------------------------------------------------------

function _jc_write_atomic(path::AbstractString, content::AbstractString)::Nothing
    dir = dirname(path)
    tmp = joinpath(dir, ".tmp_$(basename(path))_$(getpid())")
    write(tmp, content)
    mv(tmp, path; force=true)
    return nothing
end

function _jc_write_json_atomic(path::AbstractString, d::Dict)::Nothing
    dir = dirname(path)
    tmp = joinpath(dir, ".tmp_$(basename(path))_$(getpid())")
    _jc_write_json(tmp, d)
    mv(tmp, path; force=true)
    return nothing
end

# ---------------------------------------------------------------------------
# Detached launch
# ---------------------------------------------------------------------------

"""
    launch_detached(jobdir; resume::Bool = false) -> Int

Spawn `julia runner.jl <jobdir> [--resume]` as a detached OS process.
stdout and stderr are redirected to `<jobdir>/stdout.log` and `<jobdir>/stderr.log`.
Returns the PID of the spawned process.  Returns immediately; does not block.

Idempotency guard: if `<jobdir>/status` is already RUNNING or DONE, returns 0
without launching anything.
"""
function launch_detached(jobdir::AbstractString; resume::Bool = false)::Int
    jobdir = abspath(jobdir)
    status_path = joinpath(jobdir, "status")
    if isfile(status_path)
        st = strip(read(status_path, String))
        if st in ("RUNNING", "DONE")
            @info "launch_detached: $jobdir already $st — skipping"
            return 0
        end
    end

    runner = joinpath(JOBCTL_HARNESS_DIR, "runner.jl")
    isfile(runner) || error("runner.jl not found at $runner")

    stdout_log = joinpath(jobdir, "stdout.log")
    stderr_log = joinpath(jobdir, "stderr.log")

    cmd_args = String[Base.julia_cmd()..., runner, jobdir]
    resume && push!(cmd_args, "--resume")

    # Leave status as-is (PENDING) and let the runner write RUNNING itself at
    # startup. The runner's own guard ("RUNNING && !resume → abort") already makes
    # a duplicate launch safe: the second runner no-ops cleanly. (Do NOT pre-write
    # RUNNING here — that would trip the launched runner's own guard and make it
    # no-op, and a heartbeat-less RUNNING job looks stale to the poller.)
    #
    # `detach` is only a valid keyword on the Cmd(::Cmd; ...) constructor, not on
    # Cmd(::Vector); build the command first, then wrap it to set detach.
    stdout_io = open(stdout_log, "a")
    stderr_io = open(stderr_log, "a")
    local proc
    try
        proc = run(pipeline(Cmd(Cmd(cmd_args); detach=true), stdout=stdout_io, stderr=stderr_io);
                   wait=false)
    catch e
        # Spawn itself failed — mark FAILED so the poller doesn't wait on a job
        # that never started.
        _jc_write_atomic(status_path, "FAILED")
        close(stdout_io); close(stderr_io)
        rethrow(e)
    end
    # The file handles are owned by the OS process; we close our references
    close(stdout_io)
    close(stderr_io)

    pid = getpid(proc)   # Base.Process exposes no `.pid` field; getpid(::Process) is the API
    @info "launch_detached: spawned $(jobdir) pid=$pid" * (resume ? " (--resume)" : "")
    return pid
end

# ---------------------------------------------------------------------------
# Job directory scanning
# ---------------------------------------------------------------------------

"""
    scan_job_dirs(project_root) -> Vector{String}

Return absolute paths of all `runs/<hid>/` directories that contain a `job.json`.
Sorted lexicographically (i.e., h001 before h002).
"""
function scan_job_dirs(project_root::AbstractString)::Vector{String}
    runs_dir = joinpath(project_root, "runs")
    isdir(runs_dir) || return String[]
    dirs = String[]
    for entry in sort(readdir(runs_dir))
        d = joinpath(runs_dir, entry)
        isdir(d) || continue
        if isfile(joinpath(d, "job.json"))
            push!(dirs, d)                       # flat job dir (legacy / manual / K=1)
        elseif isfile(joinpath(d, "group.json"))
            # seed group: descend one level for child seed-job dirs
            for sub in sort(readdir(d))
                cd = joinpath(d, sub)
                isdir(cd) && isfile(joinpath(cd, "job.json")) && push!(dirs, cd)
            end
        end
    end
    return dirs
end

# ---------------------------------------------------------------------------
# Seed-group helpers (Slice 4 — a hypothesis = K sibling seed jobs under runs/hNNN/)
# ---------------------------------------------------------------------------

"""A job dir is a seed-group child iff its parent dir holds a `group.json`."""
is_group_child(jobdir::AbstractString)::Bool =
    isfile(joinpath(dirname(jobdir), "group.json"))

"""The group dir owning a child job dir (the parent)."""
group_dir_of(jobdir::AbstractString)::String = dirname(jobdir)

"""Child seed-job dirs of a group, sorted (s1, s2, …)."""
function group_children(groupdir::AbstractString)::Vector{String}
    isdir(groupdir) || return String[]
    return [joinpath(groupdir, s) for s in sort(readdir(groupdir))
            if isdir(joinpath(groupdir, s)) && isfile(joinpath(groupdir, s, "job.json"))]
end

"""
    count_running(project_root) -> Int

Count how many job dirs currently have status RUNNING.
"""
function count_running(project_root::AbstractString)::Int
    n = 0
    for jd in scan_job_dirs(project_root)
        sp = joinpath(jd, "status")
        if isfile(sp) && strip(read(sp, String)) == "RUNNING"
            n += 1
        end
    end
    return n
end

# ---------------------------------------------------------------------------
# Best-score tracking (best.json)
# ---------------------------------------------------------------------------

"""
    best_json_path(project_root) -> String
"""
function best_json_path(project_root::AbstractString)::String
    joinpath(project_root, "runs", "best.json")
end

"""
    read_best(project_root) -> Dict{String,Any}

Read the current best-score record.  Returns a Dict with keys:
    "hid"    => String
    "score"  => Float64  (Inf if no best yet)
    "jobdir" => String

Returns a sentinel dict with score=Inf if no best.json exists yet.
"""
function read_best(project_root::AbstractString)::Dict{String,Any}
    p = best_json_path(project_root)
    isfile(p) || return Dict{String,Any}("hid" => "", "score" => Inf, "jobdir" => "")
    d = _jc_read_json(p)
    # Ensure score is Float64
    if haskey(d, "score")
        d["score"] = Float64(d["score"])
    else
        d["score"] = Inf
    end
    return d
end

"""
    write_best(project_root, d) -> Nothing

Atomically write the best-score record.
Also mirrors `best_score:` into STATE.md (BUG 4 FIX) so the session-start hook
sees the current best without parsing LEDGER.md.  STATE.md is authoritative for
display only; best.json is the authoritative numeric source.
"""
function write_best(project_root::AbstractString, d::Dict)::Nothing
    p    = best_json_path(project_root)
    runs = dirname(p)
    mkpath(runs)
    _jc_write_json_atomic(p, d)

    # Mirror into STATE.md if it exists
    state_path = joinpath(project_root, "STATE.md")
    if isfile(state_path)
        try
            content = read(state_path, String)
            score   = get(d, "score", nothing)
            hid     = get(d, "hid",   "?")
            date    = _today_str()
            score_str = if score === nothing || (isa(score, Float64) && isinf(score))
                "none yet"
            else
                "$(round(Float64(score), sigdigits=5)) ($(hid), $(date))"
            end
            # Replace the best_score: line (keep everything else intact)
            new_content = replace(content,
                r"(?m)^best_score:.*$" => "best_score: $(score_str)")
            if new_content != content
                _jc_write_atomic(state_path, new_content)
            end
        catch e
            @warn "write_best: could not update STATE.md" exception=e
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------

"""
    ledger_path(project_root) -> String
"""
function ledger_path(project_root::AbstractString)::String
    joinpath(project_root, "LEDGER.md")
end

"""
    append_ledger_row(project_root, row::AbstractString) -> Nothing

Append a ledger row to LEDGER.md.  The file is opened in append mode with an
exclusive advisory lock (via a .lock sentinel) so concurrent processes don't
interleave rows.  If LEDGER.md doesn't exist it is created with the canonical
header (from templates/LEDGER.md if available, else a minimal header).
"""
function append_ledger_row(project_root::AbstractString, row::AbstractString)::Nothing
    ledger = ledger_path(project_root)
    lock_dir = ledger * ".lock"

    # Atomic exclusive lock via mkdir: on POSIX `mkdir` is a single atomic
    # test-and-set — it throws if the directory already exists, so exactly one
    # process can hold the lock at a time. (An earlier version used
    # `Base.open(...; create=true)`, which has no O_EXCL and silently succeeds on
    # an existing file — i.e. it was a no-op lock and provided no mutual exclusion.)
    acquired = false
    for _ in 1:100
        try
            mkdir(lock_dir)            # throws IOError(EEXIST) if held by another process
            acquired = true
            break
        catch
            # Lock held elsewhere — back off and retry.
        end
        sleep(0.1)
    end
    acquired || @warn "append_ledger_row: could not acquire lock; proceeding anyway"

    try
        # Create LEDGER.md with header if missing
        if !isfile(ledger)
            template = joinpath(JOBCTL_HARNESS_DIR, "..", "templates", "LEDGER.md")
            if isfile(template)
                cp(template, ledger)
            else
                open(ledger, "w") do io
                    println(io, "# Hypothesis Ledger\n")
                    println(io, "<!-- Experiment rows appended below. -->")
                end
            end
        end

        open(ledger, "a") do io
            println(io, "\n", row)
        end
    finally
        acquired && isdir(lock_dir) && rm(lock_dir; force=true, recursive=true)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Date helper
# ---------------------------------------------------------------------------

import Dates

"""
    _today_str() -> String   (YYYY-MM-DD)
"""
function _today_str()::String
    d = Dates.today()
    return Dates.format(d, "yyyy-mm-dd")
end

# ---------------------------------------------------------------------------
# Git SHA helper
# ---------------------------------------------------------------------------

"""
    _git_sha(project_root) -> String
"""
function _git_sha(project_root::AbstractString)::String
    try
        out = read(Cmd(`git rev-parse --short HEAD`; dir=project_root), String)
        return strip(out)
    catch
        return "uncommitted"
    end
end

# ---------------------------------------------------------------------------
# Hypothesis ID helpers
# ---------------------------------------------------------------------------

"""
    _next_hid(project_root) -> String   e.g. "h042"

Scan runs/ for existing hNNN dirs, return the next in sequence.
Uses three-digit zero-padded integers internally; the human-readable LEDGER
format uses H-NNN (upper case).
"""
function _next_hid(project_root::AbstractString)::String
    runs_dir = joinpath(project_root, "runs")
    isdir(runs_dir) || return "h001"
    existing = [
        entry for entry in readdir(runs_dir)
        if isdir(joinpath(runs_dir, entry)) && match(r"^h\d+$", entry) !== nothing
    ]
    isempty(existing) && return "h001"
    nums = [parse(Int, m.match) for e in existing for m in [match(r"\d+$", e)] if m !== nothing]
    isempty(nums) && return "h001"
    next = maximum(nums) + 1
    return "h" * lpad(next, 3, '0')
end

"""
    _hid_to_ledger(hid) -> String   "h007" → "H-007"
"""
function _hid_to_ledger(hid::AbstractString)::String
    m = match(r"^h(\d+)$", lowercase(hid))
    m === nothing && return uppercase(hid)
    return "H-" * lpad(m.captures[1], 3, '0')
end

# (end of jobctl.jl)
