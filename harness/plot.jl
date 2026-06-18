"""
plot.jl — Pure-Julia SVG figure generation for PHD (Slice 4)

    julia plot.jl <project_root>

Generates publication-usable SVG figures from the ledger + run artifacts into
`<project_root>/paper/figures/`, plus a `figures.md` index. Three figures:

    convergence-<hid>.svg  — score vs epoch, K seeds overlaid (per latest group)
    trajectory.svg         — best mean score across KEPT hypotheses, with ± std error bars
    seed-spread-<hid>.svg  — per-seed scores + mean ± std band (the rigor plot)

No third-party dependency: the SVG is emitted by a small built-in writer, so the
harness stays stdlib-only and drops into any project. A project that wants prettier
figures can replace this file with its own Makie/Plots recipe exposing the same
`generate_figures(project_root)` entry point.
"""

const PLOT_DIR = @__DIR__
include(joinpath(PLOT_DIR, "jobctl.jl"))   # _jc_read_json, ledger_path, scan/group helpers

# ---------------------------------------------------------------------------
# Minimal SVG writer
# ---------------------------------------------------------------------------

const W, H = 720, 440
const ML, MR, MT, MB = 70, 30, 40, 55   # plot-area margins
const PW, PH = W - ML - MR, H - MT - MB  # plot area size
const PALETTE = ["#2563eb", "#dc2626", "#059669", "#d97706", "#7c3aed", "#0891b2"]

_esc(s) = replace(string(s), "&"=>"&amp;", "<"=>"&lt;", ">"=>"&gt;")
_fmt(x) = abs(x) >= 1e4 || (x != 0 && abs(x) < 1e-3) ? string(round(x, sigdigits=3)) :
          string(round(x, digits=4))

# Map data (x,y) → pixel, given data ranges.
_px(x, xmin, xmax) = ML + (xmax > xmin ? (x - xmin) / (xmax - xmin) * PW : PW/2)
_py(y, ymin, ymax) = MT + PH - (ymax > ymin ? (y - ymin) / (ymax - ymin) * PH : PH/2)

function _frame(title, xlabel, ylabel, xmin, xmax, ymin, ymax)
    io = IOBuffer()
    print(io, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $W $H" font-family="sans-serif">""")
    print(io, """<rect width="$W" height="$H" fill="white"/>""")
    print(io, """<text x="$(W/2)" y="22" text-anchor="middle" font-size="16" font-weight="bold">$(_esc(title))</text>""")
    # axes
    print(io, """<line x1="$ML" y1="$(MT+PH)" x2="$(ML+PW)" y2="$(MT+PH)" stroke="#334155" stroke-width="1.5"/>""")
    print(io, """<line x1="$ML" y1="$MT" x2="$ML" y2="$(MT+PH)" stroke="#334155" stroke-width="1.5"/>""")
    # gridlines + tick labels (5 each)
    for i in 0:4
        gx = ML + PW * i / 4; xv = xmin + (xmax - xmin) * i / 4
        gy = MT + PH * i / 4; yv = ymax - (ymax - ymin) * i / 4
        print(io, """<line x1="$gx" y1="$MT" x2="$gx" y2="$(MT+PH)" stroke="#e2e8f0" stroke-width="1"/>""")
        print(io, """<line x1="$ML" y1="$gy" x2="$(ML+PW)" y2="$gy" stroke="#e2e8f0" stroke-width="1"/>""")
        print(io, """<text x="$gx" y="$(MT+PH+18)" text-anchor="middle" font-size="11" fill="#475569">$(_esc(_fmt(xv)))</text>""")
        print(io, """<text x="$(ML-8)" y="$(gy+4)" text-anchor="end" font-size="11" fill="#475569">$(_esc(_fmt(yv)))</text>""")
    end
    print(io, """<text x="$(ML+PW/2)" y="$(H-12)" text-anchor="middle" font-size="13">$(_esc(xlabel))</text>""")
    print(io, """<text x="18" y="$(MT+PH/2)" text-anchor="middle" font-size="13" transform="rotate(-90 18 $(MT+PH/2))">$(_esc(ylabel))</text>""")
    return io
end

_finish(io) = (print(io, "</svg>"); String(take!(io)))

# ---------------------------------------------------------------------------
# Data readers
# ---------------------------------------------------------------------------

"""Read (epochs, scores) from a single job dir's epoch/NNNN.json files, sorted by epoch."""
function _epoch_series(jobdir::AbstractString)
    ed = joinpath(jobdir, "epoch")
    isdir(ed) || return (Int[], Float64[])
    pts = Tuple{Int,Float64}[]
    for f in readdir(ed)
        endswith(f, ".json") || continue
        try
            d = _jc_read_json(joinpath(ed, f))
            e = Int(get(d, "epoch", 0)); s = Float64(get(d, "score", NaN))
            (isnan(s) || isinf(s)) || push!(pts, (e, s))
        catch; end
    end
    sort!(pts; by = first)
    return (first.(pts), last.(pts))
end

"""Parse KEPT rows below the marker: returns Vector of (hid, mean, std)."""
function _ledger_kept(project_root::AbstractString)
    p = ledger_path(project_root)
    isfile(p) || return Tuple{String,Float64,Float64}[]
    txt = read(p, String)
    marker = "Experiment rows are appended below this line"
    body = occursin(marker, txt) ? split(txt, marker; limit=2)[2] : txt
    rows = Tuple{String,Float64,Float64}[]
    hid = ""; status = ""
    for line in split(body, '\n')
        h = match(r"^## (H-\d+) · [\d-]+ · (\w+)", line)
        if h !== nothing; hid = h.captures[1]; status = h.captures[2]; continue; end
        m = match(r"^metric:.*?→\s*([-\d.eE]+)(?:\s*±\s*([-\d.eE]+))?", line)
        if m !== nothing && status == "KEPT"
            mean = tryparse(Float64, m.captures[1])
            std  = m.captures[2] === nothing ? 0.0 : something(tryparse(Float64, m.captures[2]), 0.0)
            mean !== nothing && push!(rows, (hid, mean, std))
        end
    end
    return rows
end

# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------

"""Score-vs-epoch, one line per seed-child of a group dir."""
function fig_convergence(groupdir::AbstractString)::Union{String,Nothing}
    children = group_children(groupdir)
    isempty(children) && return nothing
    series = [(basename(c), _epoch_series(c)...) for c in children]
    series = [s for s in series if !isempty(s[2])]
    isempty(series) && return nothing
    xmax = maximum(maximum(s[2]) for s in series)
    allys = vcat([s[3] for s in series]...)
    ymin, ymax = minimum(allys), maximum(allys); ymin == ymax && (ymax = ymin + 1)
    io = _frame("Convergence — $(basename(groupdir))", "epoch", "score (lower better)", 0, xmax, ymin, ymax)
    for (i, (lbl, xs, ys)) in enumerate(series)
        col = PALETTE[(i-1) % length(PALETTE) + 1]
        pts = join(["$(_px(x,0,xmax)),$(_py(y,ymin,ymax))" for (x,y) in zip(xs,ys)], " ")
        print(io, """<polyline points="$pts" fill="none" stroke="$col" stroke-width="1.8"/>""")
        print(io, """<text x="$(ML+PW-4)" y="$(MT+14*i)" text-anchor="end" font-size="11" fill="$col">$(_esc(lbl))</text>""")
    end
    return _finish(io)
end

"""Best-so-far mean across KEPT hypotheses, with ± std error bars."""
function fig_trajectory(project_root::AbstractString)::Union{String,Nothing}
    kept = _ledger_kept(project_root)
    isempty(kept) && return nothing
    n = length(kept)
    means = [r[2] for r in kept]; stds = [r[3] for r in kept]
    ymin = minimum(means .- stds); ymax = maximum(means .+ stds); ymin == ymax && (ymax = ymin + 1)
    xmax = max(n, 1)
    io = _frame("Best-score trajectory (KEPT hypotheses)", "kept hypothesis #", "mean score ± std", 1, xmax, ymin, ymax)
    px(i) = _px(i, 1, xmax); py(y) = _py(y, ymin, ymax)
    line = join(["$(px(i)),$(py(means[i]))" for i in 1:n], " ")
    print(io, """<polyline points="$line" fill="none" stroke="$(PALETTE[1])" stroke-width="2"/>""")
    for i in 1:n
        x = px(i)
        if stds[i] > 0
            print(io, """<line x1="$x" y1="$(py(means[i]-stds[i]))" x2="$x" y2="$(py(means[i]+stds[i]))" stroke="$(PALETTE[1])" stroke-width="1.2"/>""")
        end
        print(io, """<circle cx="$x" cy="$(py(means[i]))" r="3.5" fill="$(PALETTE[1])"/>""")
        print(io, """<text x="$x" y="$(MT+PH+34)" text-anchor="middle" font-size="9" fill="#475569">$(_esc(kept[i][1]))</text>""")
    end
    return _finish(io)
end

"""Per-seed scores for a group as dots, with a mean line and ± std band.

Reads the K child result.json/job.json directly (rather than the group meta's
seed_scores array, which the minimal JSON reader doesn't parse back)."""
function fig_seed_spread(groupdir::AbstractString)::Union{String,Nothing}
    scores = Float64[]; labels = String[]
    for c in group_children(groupdir)
        rp = joinpath(c, "result.json")
        isfile(rp) || continue
        s = Float64(get(_jc_read_json(rp), "score", Inf))
        (isnan(s) || isinf(s)) && continue
        jp = joinpath(c, "job.json")
        lbl = isfile(jp) ? string(get(_jc_read_json(jp), "seed", basename(c))) : basename(c)
        push!(scores, s); push!(labels, lbl)
    end
    length(scores) < 1 && return nothing
    μ = sum(scores)/length(scores)
    σ = length(scores) > 1 ? sqrt(sum((scores .- μ).^2)/(length(scores)-1)) : 0.0
    ymin = min(minimum(scores), μ-σ); ymax = max(maximum(scores), μ+σ); ymin == ymax && (ymax = ymin+1)
    n = length(scores); xmax = n + 1
    io = _frame("Seed spread — $(basename(groupdir))  (μ=$(_fmt(μ)) ± $(_fmt(σ)), n=$n)",
                "seed", "score", 0, xmax, ymin, ymax)
    # ± std band + mean line
    yb1 = _py(μ+σ, ymin, ymax); yb2 = _py(μ-σ, ymin, ymax); ym = _py(μ, ymin, ymax)
    σ > 0 && print(io, """<rect x="$ML" y="$yb1" width="$PW" height="$(yb2-yb1)" fill="$(PALETTE[1])" opacity="0.10"/>""")
    print(io, """<line x1="$ML" y1="$ym" x2="$(ML+PW)" y2="$ym" stroke="$(PALETTE[1])" stroke-width="1.5" stroke-dasharray="5 3"/>""")
    for i in 1:n
        x = _px(i, 0, xmax)
        print(io, """<circle cx="$x" cy="$(_py(scores[i],ymin,ymax))" r="4.5" fill="$(PALETTE[2])"/>""")
        print(io, """<text x="$x" y="$(MT+PH+18)" text-anchor="middle" font-size="10" fill="#475569">$(_esc(labels[i]))</text>""")
    end
    return _finish(io)
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

"""
    generate_figures(project_root) -> Vector{String}

Write all available figures into paper/figures/ and a figures.md index.
Returns the list of figure file paths written.
"""
function generate_figures(project_root::AbstractString)::Vector{String}
    project_root = abspath(project_root)
    figdir = joinpath(project_root, "paper", "figures")
    mkpath(figdir)
    written = String[]

    function _save(name, svg)
        svg === nothing && return
        path = joinpath(figdir, name)
        write(path, svg)
        push!(written, path)
    end

    # Trajectory across all KEPT hypotheses.
    _save("trajectory.svg", fig_trajectory(project_root))

    # Per-group figures for groups that have been reaped (have result.json).
    runs = joinpath(project_root, "runs")
    if isdir(runs)
        for e in sort(readdir(runs))
            gdir = joinpath(runs, e)
            (isdir(gdir) && match(r"^h\d+$", e) !== nothing) || continue
            isfile(joinpath(gdir, "group.json")) || continue
            _save("convergence-$(e).svg", fig_convergence(gdir))
            _save("seed-spread-$(e).svg", fig_seed_spread(gdir))
        end
    end

    # Index
    idx = IOBuffer()
    println(idx, "# Figures\n")
    if isempty(written)
        println(idx, "_No figures yet — run experiments (`/phd:run` or `/phd:daemon`) first._")
    else
        for p in written
            b = basename(p)
            println(idx, "## $(b)\n\n![$(b)](figures/$(b))\n")
        end
    end
    write(joinpath(project_root, "paper", "figures.md"), String(take!(idx)))

    return written
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && (println("usage: julia plot.jl <project_root>"); exit(0))
    figs = generate_figures(ARGS[1])
    if isempty(figs)
        println("No figures generated (no reaped groups / KEPT rows yet).")
    else
        println("Generated $(length(figs)) figure(s):")
        for f in figs; println("  ", f); end
    end
end
