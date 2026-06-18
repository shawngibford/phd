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
metric: <metric_name>  <before> → <after>   (best so far | no improvement)   budget: <T>s   seed: <seed>
baseline: <classical baseline score> → <quantum result> <BEATS classical ✓ | does NOT beat classical ✗ | no baseline recorded>
artifacts: runs/<id>/  commit: <git-sha or "uncommitted">
note: <optional free text — observations, follow-up hypotheses, pruning candidates>
```

STATUS values: `PENDING` | `RUNNING` | `KEPT` | `DISCARDED` | `FAILED`

---

## Example

> Illustrative only — fenced so tools never parse it as a real result. Real rows
> are appended (unfenced) below the marker at the bottom of this file.

```
## H-007 · 2026-06-17 · KEPT
hypothesis: QLNN with adaptive τ-gating lowers rel-L2 on the fermentation ODE vs fixed τ
change: replaced fixed time-constant with learned per-neuron τ (12 LOC)
metric: rel_L2  0.041 → 0.029   (best so far)   budget: 300s   seed: 1337
baseline: classical Neural-ODE 0.034 → quantum BEATS classical ✓
artifacts: runs/h007/  commit: a1b2c3d
note: τ collapses to ~0 for 3 neurons → candidate for pruning (see H-008)
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
