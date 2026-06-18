# Experiment Instructions

> **This file is the human-edited "research org" that drives the autonomous loop.**
> The experiment-runner agent reads it before proposing each new experiment.
> Edit this file to steer the search: change what to vary, tighten constraints,
> shift the focus when a line of inquiry is exhausted.
>
> Adapted from the autoresearch `program.md` pattern, generalized for SciML / Yao.jl.

---

## Project

project: <!-- fill in during /phd:init -->
research_question: <!-- fill in during /phd:init -->

---

## What you are optimizing

**Primary metric:** `rel_L2` — relative L2 error on the held-out trajectory.
Lower is better. Formula: `|û − u|₂ / |u|₂` where `û` is the model prediction
and `u` is the ground-truth trajectory at fixed seed 1337.

**For quantum experiments:** report `cost_quantum / cost_classical_baseline`.
A ratio < 1 means quantum advantage. The classical baseline must be a
fairly-tuned Neural-ODE or equivalent; an untrained baseline does not count.
Record the baseline score in the ledger `baseline:` field every time.

**Keep rule:** keep the new model if its score is strictly better than the
current best. Ties go to discard (simpler is preferred). A quantum result
that does not beat the classical baseline is discarded with reason
"no advantage demonstrated" — the score may still be recorded for context.

**Discard rule:** discard if score ≥ current best, or if the job fails or
exceeds the time budget without producing a valid `result.json`.

---

## What to vary (search axes)

The agent should propose changes along one axis per experiment. Suggested axes
in rough priority order — reorder or cross out as you learn:

1. **Architecture** — circuit depth, number of qubits, layer type (qGAN / qLNN / qAAN),
   entanglement topology, number of classical layers wrapping the quantum core.

2. **Quantum kernel / encoding** — amplitude encoding vs angle encoding vs IQP;
   feature maps; data re-uploading strategies.

3. **Optimizer** — Adam vs BFGS vs LBFGS vs SPSA; learning rate schedule;
   gradient clipping threshold.

4. **Hyperparameters** — hidden dimension, dropout, weight decay, batch size,
   ODE solver tolerance (for SciML surrogate problems).

5. **Loss function** — pure rel_L2 vs energy-invariant penalty vs combined;
   trajectory weighting (later time-steps weighted more).

6. **Classical component** — vary the neural wrapper around the quantum circuit;
   residual connections; normalization.

---

## Constraints (hard — the agent must respect these)

- One diff per experiment. The change must be reviewable by a human in under
  two minutes. No "refactor everything" diffs.
- Experiment must complete within the configured time budget T (see CONTEXT.md).
  If it cannot, reduce the model or training steps, not the held-out set.
- Held-out trajectory seed is fixed at 1337. It must never be used during
  training or validation search. This is a hard leakage guard.
- All experiments use the same dataset split and preprocessing pipeline.
  Any change to preprocessing counts as a new experiment axis and must be
  noted explicitly in the `change:` ledger field.
- Classical baseline must be present in every quantum experiment's `meta` dict
  before a result can be marked KEPT-with-advantage.

---

## Framing for the agent

When proposing the next experiment, the agent should:

1. Read the current LEDGER.md and identify the best KEPT score and the most
   recent DISCARDED hypotheses (to avoid re-trying dead ends).
2. Identify the most promising unexplored axis based on the ledger history.
3. Propose exactly one change: a short description and a concrete diff or
   parameter delta. The proposal goes in `job.json` before the job launches.
4. State the expected direction of impact ("I expect this to lower rel_L2
   because...") — this gets recorded in the ledger `note:` field.
5. After the result arrives, honestly assess whether the hypothesis was
   confirmed, refuted, or inconclusive.

The agent should be candid about negative results. A well-documented
discard is as valuable as a keep — it maps the failure modes of the space.

---

## Domain notes (SciML / Yao.jl)

**SciML surrogate problems** (e.g., Lotka–Volterra, fermentation ODE):
- Use `NeuralODE` from DiffEqFlux.jl as the classical baseline.
- Solver: `Tsit5()` with `abstol=1e-6, reltol=1e-6` unless the experiment
  specifically varies solver tolerance.
- Training data: 80% of trajectory time-points; held-out: last 20% (fixed split).

**Quantum models** (Yao.jl / YaoML.jl):
- Use `Yao.jl` for exact statevector simulation and `AD` for gradients.
- The classical baseline runs in the same process (no separate benchmark needed).
- Report qubit count and circuit depth in `meta` for every quantum experiment.
- `CuYao` and Metal.jl paths are not active in v1; CPU statevector only.

---

## Notes for the researcher (free form)

<!-- Add your own observations, hunches, and directions here.
     The agent reads this section too and treats it as guidance,
     not hard constraint. -->
