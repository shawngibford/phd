"""
report.jl — Ledger audit + live status (PHD harness)

    julia report.jl audit  <project_root>    # integrity + lifetime stats  (/phd:stats)
    julia report.jl status <project_root>    # live, group-aware operational view (/phd:daemon status)

Deterministic, stdlib-only; reuses jobctl helpers. Reads per-child result.json /
job.json (avoids the minimal JSON reader's lack of array parsing).
"""

const REPORT_DIR = @__DIR__
include(joinpath(REPORT_DIR, "jobctl.jl"))   # _jc_read_json, ledger_path, scan_job_dirs, group_*, read_best

# ---------------------------------------------------------------------------
# Ledger parsing (rows below the marker only)
# ---------------------------------------------------------------------------

struct LedgerRow
    hid    :: String
    status :: String
    mean   :: Float64
    std    :: Float64
    n      :: Int
    seeds  :: Vector{Int}
end

function _parse_ledger(project_root::AbstractString)::Vector{LedgerRow}
    p = ledger_path(project_root)
    isfile(p) || return LedgerRow[]
    txt = read(p, String)
    marker = "Experiment rows are appended below this line"
    body = occursin(marker, txt) ? split(txt, marker; limit = 2)[2] : txt
    rows = LedgerRow[]
    hid = ""; status = ""; metric = ""
    function flush!()
        isempty(hid) && return
        m  = match(r"→\s*([-\d.eEnafN]+)(?:\s*±\s*([-\d.eE]+))?", metric)
        mean = m === nothing ? NaN : something(tryparse(Float64, m.captures[1]), NaN)
        std  = (m === nothing || m.captures[2] === nothing) ? 0.0 :
               something(tryparse(Float64, m.captures[2]), 0.0)
        nm = match(r"n=(\d+)", metric); n = nm === nothing ? 1 : parse(Int, nm.captures[1])
        sm = match(r"seeds?:\s*([0-9,\s]+)", metric)
        seeds = sm === nothing ? Int[] :
                [parse(Int, strip(s)) for s in split(sm.captures[1], ",") if !isempty(strip(s))]
        push!(rows, LedgerRow(hid, status, mean, std, n, seeds))
    end
    for line in split(body, '\n')
        h = match(r"^## (H-\d+) · [\d-]+ · (\w+)", line)
        if h !== nothing
            flush!(); hid = h.captures[1]; status = h.captures[2]; metric = ""; continue
        end
        mm = match(r"^metric:\s*(.*)$", line)
        mm !== nothing && (metric = mm.captures[1])
    end
    flush!()
    return rows
end

_ledger_to_dir(hid::AbstractString) = "h" * lpad(match(r"\d+", hid).match, 3, '0')  # H-007 → h007

# ---------------------------------------------------------------------------
# AUDIT — integrity + lifetime stats
# ---------------------------------------------------------------------------

function audit(project_root::AbstractString)::Nothing
    project_root = abspath(project_root)
    rows = _parse_ledger(project_root)
    kept = [r for r in rows if r.status == "KEPT"]
    disc = [r for r in rows if r.status == "DISCARDED"]
    total = length(kept) + length(disc)
    findings = String[]

    # KEPT rows must have an artifact dir + result.json.
    for r in kept
        d = joinpath(project_root, "runs", _ledger_to_dir(r.hid))
        if !isdir(d)
            push!(findings, "$(r.hid): KEPT but artifact dir runs/$(basename(d))/ is missing")
        elseif !isfile(joinpath(d, "result.json"))
            push!(findings, "$(r.hid): KEPT but no result.json in runs/$(basename(d))/")
        end
    end
    # Leakage: held-out seed 1337 must never appear as a run seed.
    for r in rows
        1337 in r.seeds && push!(findings, "$(r.hid): run seeds include 1337 (held-out eval seed — leakage)")
    end
    # Lost seeds: row n < the group's requested n_seeds.
    for r in rows
        gp = joinpath(project_root, "runs", _ledger_to_dir(r.hid), "group.json")
        if isfile(gp)
            req = Int(get(_jc_read_json(gp), "n_seeds", r.n))
            r.n < req && push!(findings, "$(r.hid): only $(r.n)/$(req) seeds produced a valid score (lost seeds)")
        end
    end
    # Malformed metric (NaN mean).
    for r in rows
        isnan(r.mean) && push!(findings, "$(r.hid): metric mean is unparseable/NaN")
    end
    # Non-monotone best: each successive KEPT should strictly improve (lower) the mean.
    prev = Inf
    for r in kept
        !isnan(r.mean) && r.mean >= prev &&
            push!(findings, "$(r.hid): KEPT but mean $(r.mean) did not improve on prior KEPT $(prev)")
        !isnan(r.mean) && (prev = min(prev, r.mean))
    end

    best = read_best(project_root)
    println("PHD Ledger Audit — ", project_root)
    println("-"^56)
    println("Experiments (groups):  $total   KEPT $(length(kept))   DISCARDED $(length(disc))")
    if total > 0
        println("Keep rate:             $(round(100*length(kept)/total, digits=1))%")
    end
    bm = get(best, "score", Inf)
    if !(bm isa Number && isinf(Float64(bm)))
        bstd = get(best, "std", 0.0); bn = get(best, "n", 1)
        println("Best so far:           $(get(best,"hid","?"))  mean=$(round(Float64(bm),sigdigits=5)) ± $(round(Float64(bstd),sigdigits=2))  (n=$(bn))")
    else
        println("Best so far:           none yet")
    end
    println()
    if isempty(findings)
        println("Integrity: ✓ no issues found.")
    else
        println("Integrity: ⚠ $(length(findings)) finding(s):")
        for f in findings; println("  - ", f); end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# STATUS — live, group-aware operational view
# ---------------------------------------------------------------------------

function _job_status(jobdir::AbstractString)::String
    sp = joinpath(jobdir, "status")
    isfile(sp) ? strip(read(sp, String)) : "PENDING"
end

function _avg_epoch_wall(jobdir::AbstractString)::Float64
    ed = joinpath(jobdir, "epoch")
    isdir(ed) || return NaN
    walls = Float64[]
    for f in readdir(ed)
        endswith(f, ".json") || continue
        try; push!(walls, Float64(get(_jc_read_json(joinpath(ed, f)), "wall_s", NaN))); catch; end
    end
    walls = filter(!isnan, walls)
    isempty(walls) ? NaN : sum(walls)/length(walls)
end

function _running_progress(jobdir::AbstractString)::String
    hb = joinpath(jobdir, "heartbeat")
    isfile(hb) || return "starting…"
    ep = try Int(get(_jc_read_json(hb), "epoch", 0)) catch; 0 end
    jp = joinpath(jobdir, "job.json")
    maxep = isfile(jp) ? Int(get(_jc_read_json(jp), "max_epochs", 0)) : 0
    avg = _avg_epoch_wall(jobdir)
    eta = (maxep > ep && !isnan(avg)) ? "  ETA ~$(round((maxep-ep)*avg, digits=1))s" : ""
    maxep > 0 ? "epoch $(ep)/$(maxep)$(eta)" : "epoch $(ep)$(eta)"
end

function status(project_root::AbstractString)::Nothing
    project_root = abspath(project_root)
    jobdirs = scan_job_dirs(project_root)
    counts = Dict("RUNNING"=>0, "PENDING"=>0, "DONE"=>0, "FAILED"=>0)
    running = Tuple{String,String}[]
    for jd in jobdirs
        st = _job_status(jd)
        counts[st] = get(counts, st, 0) + 1
        st == "RUNNING" && push!(running, (relpath(jd, project_root), _running_progress(jd)))
    end

    # Group rollup
    groups = Dict{String,Vector{String}}()
    for jd in jobdirs
        is_group_child(jd) && (g = basename(group_dir_of(jd)); push!(get!(groups, g, String[]), jd))
    end

    rows = _parse_ledger(project_root)
    kept = count(r -> r.status == "KEPT", rows)
    total = kept + count(r -> r.status == "DISCARDED", rows)
    best = read_best(project_root)

    println("PHD Status — ", project_root)
    println("-"^56)
    println("Jobs:  RUNNING $(counts["RUNNING"])   PENDING $(counts["PENDING"])   DONE $(counts["DONE"])   FAILED $(counts["FAILED"])")
    for (jd, prog) in running; println("    ▸ $(jd):  $(prog)"); end
    if !isempty(groups)
        println("Groups in flight:")
        for (g, kids) in sort(collect(groups); by=first)
            term = count(k -> _job_status(k) in ("DONE","FAILED"), kids)
            println("    $(g):  $(term)/$(length(kids)) seeds terminal")
        end
    end
    bm = get(best, "score", Inf)
    if !(bm isa Number && isinf(Float64(bm)))
        println("Best so far:  $(get(best,"hid","?"))  mean=$(round(Float64(bm),sigdigits=5)) ± $(round(Float64(get(best,"std",0.0)),sigdigits=2))  (n=$(get(best,"n",1)))")
    else
        println("Best so far:  none yet")
    end
    total > 0 && println("Reaped groups: $total   keep rate $(round(100*kept/total, digits=1))%")
    if !isempty(rows)
        println("Recent ledger:")
        for r in rows[max(1,end-2):end]
            println("    $(r.hid) · $(r.status)  mean=$(isnan(r.mean) ? "?" : string(round(r.mean,sigdigits=4)))  (n=$(r.n))")
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

function _main(args::Vector{String})
    if length(args) < 2 || !(args[1] in ("audit", "status"))
        println("usage: julia report.jl audit|status <project_root>")
        return
    end
    args[1] == "audit" ? audit(args[2]) : status(args[2])
end

if abspath(PROGRAM_FILE) == @__FILE__
    _main(ARGS)
end
