---
description: Generate publication figures from the ledger and run artifacts. Runs the Julia SVG plotter over runs/ + LEDGER.md to produce paper/figures/*.svg (best-score trajectory with error bars, per-group convergence curves, per-group seed-spread plots) and a paper/figures.md index. Pure-Julia SVG — no plotting dependency. Read-only over the ledger; writes only under paper/.
argument-hint: [--hid hNNN to focus one group]
---

# /phd:analyze — Generate figures from the experiment record

You turn the accumulated experiment record into **paper-ready figures**. Multi-seed results are
only honest if their variance is *shown*, so the figures lead with error bars and seed spread.

---

## What to do

1. **Resolve the project root** (the directory with `runs/`, `LEDGER.md`) — the same resolution
   rule as `/phd:run`: the open workspace, else `project_root:` in `CONTEXT.md`, else ask.

2. **Run the plotter:**
   ```
   julia harness/plot.jl <project_root>
   ```
   It reads `LEDGER.md` (KEPT rows) and `runs/hNNN/` artifacts and writes, into `paper/figures/`:
   - `trajectory.svg` — best mean score across KEPT hypotheses, **with ± std error bars** (the research arc).
   - `convergence-hNNN.svg` — score vs epoch, the K seeds of a group overlaid.
   - `seed-spread-hNNN.svg` — per-seed scores with the mean line and ± std band (the rigor plot).
   It also writes `paper/figures.md` indexing every figure.

   If the harness isn't present or Julia isn't on PATH, say so plainly and stop (suggest copying the
   harness per `harness/SETUP.md`). If there are no reaped groups / KEPT rows yet, report that
   nothing could be plotted and point to `/phd:run` or `/phd:daemon start`.

3. **Report** which figures were written, and call out what the rigor plots reveal — e.g. "the
   seed-spread for H-003 shows one diverging seed driving the ± std; the mean improvement is within
   seed noise." Honest reading of variance is the point; don't oversell a noisy win.

---

## Notes

- The plotter is **pure-Julia SVG** (stdlib only) so it runs anywhere the harness does. A project
  that wants Makie/Plots figures can replace `harness/plot.jl` with its own recipe exposing the same
  `generate_figures(project_root)` entry point — `/phd:analyze` and `/phd:defend` will pick it up
  unchanged.
- Figures feed `/phd:write` (results prose references them) and `/phd:defend` (the compiler numbers
  and embeds them). Regenerate with `/phd:analyze` whenever new results land.

## Hard rules

1. **Never modify `LEDGER.md`.** Analysis reads the ledger; it writes only under `paper/`.
2. **Plot only real results.** Figures come from reaped groups / KEPT rows — never fabricated points.
3. **Show variance.** Always include the ± std / seed-spread; a mean without its spread is misleading.
