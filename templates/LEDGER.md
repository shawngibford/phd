# Hypothesis Ledger

> The daemon's long-term memory. Every experiment appends an immutable row — kept
> *and* discarded. Negative results are data; they protect against re-testing dead
> ends across sessions. `/phd:write` reads KEPT rows to build the results section.
> `/phd:verify` must reproduce a KEPT row before it can appear in the paper.
>
> **Format is a hard contract.** The Julia supervisor and poller write rows in this
> exact format. Do not reorder fields or rename keys.

---

## Format reference

```
## H-NNN · YYYY-MM-DD · STATUS
hypothesis: <one-sentence falsifiable claim>
change: <what was modified and approximate scale, e.g. "replaced fixed τ with learned per-neuron τ (12 LOC)">
metric: <metric_name>  <before> → <mean> ± <std>   (best so far | no improvement, n=<K>)   budget: <T>s   seeds: <s1,s2,…>
baseline: <classical baseline score> → <quantum result> <BEATS classical ✓ | does NOT beat classical ✗ | no baseline recorded>
artifacts: runs/<id>/  commit: <git-sha or "uncommitted">
note: <optional free text — observations, follow-up hypotheses, pruning candidates>
```

A hypothesis is run over **K seeds** (`seeds_per_hypothesis` in CONTEXT.md, default 3) and kept on
the **mean**; `± <std>` is the spread across seeds and `n=<K>` the count that produced a valid score.
Single-seed rows (K=1, or legacy/manual) omit `± <std>` and use `seed: <seed>`. The held-out eval
seed **1337 is never a run seed** (leakage guard, §5).

STATUS values: `PENDING` | `RUNNING` | `KEPT` | `DISCARDED` | `FAILED`

---

## Example

> Illustrative only — fenced so tools never parse it as a real result. Real rows
> are appended (unfenced) below the marker at the bottom of this file.

```
## H-007 · 2026-06-17 · KEPT
hypothesis: QLNN with adaptive τ-gating lowers rel-L2 on the fermentation ODE vs fixed τ
change: replaced fixed time-constant with learned per-neuron τ (12 LOC)
metric: rel_L2  0.041 → 0.029 ± 0.003   (best so far, n=5)   budget: 300s   seeds: 42,7,2024,314,99
baseline: classical Neural-ODE 0.034 → quantum BEATS classical ✓
artifacts: runs/h007/  commit: a1b2c3d
note: kept on mean of 5 seeds; improvement significant (>1σ); τ collapses to ~0 for 3 neurons → prune candidate (see H-008)
```

---

## Template (blank row — copy and fill for manual entries)

```
## H-NNN · YYYY-MM-DD · PENDING
hypothesis:
change:
metric:    →      budget: s   seed:
baseline:  →
artifacts: runs/hNNN/  commit:
note:
```

---

<!-- Experiment rows are appended below this line by the supervisor.
     Real rows live ONLY below this marker; anything above it (Format reference,
     Example, Template) is documentation and must never be read as a result.
     Newest row is at the bottom. Do not reorder. -->
