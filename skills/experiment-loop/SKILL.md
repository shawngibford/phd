---
name: experiment-loop
description: The autonomous experiment-loop protocol for PHD research projects, generalized for SciML and Yao.jl. Auto-applies whenever Claude is about to edit experiment.md, propose or launch an experiment, or reason about keep/discard decisions and the metric contract. Keeps the loop's invariants — edit → run ≤T → measure → keep/discard, fixed-seed reproducibility, the held-out leakage guard, and the quantum-advantage candor rule — visible at every step. Adapted from autoresearch (MIT).
---

# experiment-loop — the loop protocol & its invariants

This is the discipline behind PHD's autonomous loop. It fires whenever you touch the experiment
machinery so the rules that make results *trustworthy* stay in front of you. It does not run
experiments — it governs how they're proposed, scored, and kept. The `experiment-runner` agent
proposes under these rules; `runner.jl`/`poller.jl` execute them; `/phd:verify` enforces them.

Adapted from [autoresearch](https://github.com/karpathy/autoresearch) (MIT), generalized from a
single GPU/`val_bpb` budget to a SciML + Yao.jl metric **contract**.

---

## The loop (one turn)

1. **Read** `experiment.md` (the human-edited research org) for the active search axes + constraints.
2. **Propose** exactly one change, on one axis, reviewable by a human in under two minutes.
3. **Run** under a fixed wall-clock budget `T` (from `CONTEXT.md`), as a detached job — never inside
   the session.
4. **Measure** with `evaluate()` / `score()` → an `ExperimentResult` (lower is better).
5. **Keep** if strictly better than the current best (commit + KEPT ledger row); else **discard**
   (DISCARDED row + reason). Ties go to discard — simpler wins.
6. **Append** an immutable ledger row either way. Negative results are data; they stop dead-end
   re-tries across sessions.

In `daemon` mode this repeats unattended (~`K · 3600/T` experiments/hour). Each turn is one diff,
one score, one row.

---

## The metric contract (what a project must expose)

`score(model, data, budget_s) -> ExperimentResult` where the score is:
- **Lower is better.**
- **Scale-independent** (e.g. relative L2 `|û−u|₂/|u|₂`, not raw L2).
- **Reproducible under a fixed seed** — same seed + same split + same budget ⇒ same score.

For SciML surrogates: relative L2 on the held-out trajectory; energy/invariant drift for
conservative systems; NLL/CRPS for probabilistic time-series. Put auxiliary diagnostics in `meta`,
not in the score.

## The non-negotiable guards

1. **Leakage guard.** The held-out trajectory (fixed seed **1337**) is never used during training or
   search. Any change that could touch it is forbidden. Suggest any seed *except* 1337 for runs.
2. **One concern per change.** Don't fold a refactor into an experiment diff — the ledger must
   attribute a score change to a single cause. (This is the `code-minimalism` governor applied to
   the loop.)
3. **No p-hacking across seeds.** Don't run the same change under many seeds and keep only the best.
   If you report a seed-sensitive result, report the distribution, not the max.
4. **Quantum-advantage candor.** A quantum result may claim advantage **only** if a fairly-tuned
   classical baseline is present in `meta` and was beaten (`cost_quantum / cost_classical < 1`). No
   baseline ⇒ logged "speculative, no advantage demonstrated." This is enforced by `/phd:verify` and
   `/phd:write`, not just advised.

---

## Keep / discard, precisely

- **Keep:** `new_score < best_score` (strictly). Commit the change; append a KEPT row; update best.
- **Discard:** `new_score >= best_score`, OR the job failed / exceeded budget without a valid
  `result.json`, OR (quantum) it did not beat the classical baseline. Append a DISCARDED row with
  the reason — a well-documented discard maps the failure space and is as valuable as a keep.

---

## Hard rules

1. **One change, one axis, per experiment.** Reviewable in under two minutes.
2. **Never touch the held-out set or seed 1337.** Leakage is unrecoverable.
3. **The ledger is append-only.** Every run — kept or discarded — gets a row; never edit prior rows.
4. **No quantum-advantage claim without a beaten, fairly-tuned classical baseline.**
5. **Detached runs only.** Experiments are external processes; the session can close mid-run.
