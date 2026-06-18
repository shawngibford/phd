# PHD Context

> Loaded at session start alongside STATE.md. Keep this accurate — it is the
> agent's long-term memory of *why* this project exists and what the rules are.

---

## Project

project: <!-- short name, e.g. fermentation-surrogate -->
research_question: <!-- one-sentence falsifiable question -->

## Compute budget

time_budget_s: <!-- wall-clock seconds per experiment, e.g. 300 -->
parallel_workers: <!-- K concurrent experiments, e.g. 2 -->

## Background

<!-- One paragraph: what system are you modelling, why does it matter,
     what prior work already exists. Be precise — the agent cites this. -->

## Constraints

<!-- Hard rules the experiment loop must respect. Examples:
     - Must beat a fairly-tuned classical Neural-ODE baseline to claim quantum advantage
     - No data leakage: held-out trajectory is fixed at seed 1337, never touched during search
     - Max model size: fits in 8 GB RAM on M1 Pro
     - Reproducibility: every result must be recoverable from runs/<id>/epoch/NNNN.ckpt + job.json -->

## Prior decisions

<!-- Decisions already made and locked, with rationale. Prevents the loop from
     re-litigating settled questions. Examples:
     - 2026-06-17: CPU-only for v1; Metal.jl Yao paths immature (see ARCHITECTURE.md §5.1)
     - 2026-06-17: Fixed held-out seed = 1337 across all experiments for comparability -->
