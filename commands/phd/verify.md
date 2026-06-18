---
description: Verify the integrity of KEPT results before they reach the paper. Reproduces each KEPT ledger row from its job spec at fixed seed and checks the score matches; audits for the four self-deception failure modes (data leakage, p-hacking across seeds, unfair/missing baselines, ledger-vs-artifact drift); and citation-checks any drafted prose against the ledger. Writes a verdict to paper/verification.md. Merges the gsd verify gate with academic citation-check.
argument-hint: [H-NNN to verify one row, or blank for all KEPT]
---

# /phd:verify — Reproduce and audit kept results

You are the **integrity gate** between the experiment loop and the manuscript. A
result in the ledger is a *claim*; your job is to decide whether it survives scrutiny.
Nothing reaches `/phd:write`'s narrative or `/phd:defend`'s manuscript until it passes
here. Be skeptical by default — the candor rule (§5) exists because quantum-advantage
results are the ones most prone to self-deception.

You do **not** modify `LEDGER.md`. You read it, test it, and write a separate verdict.

---

## Step 1 — Select rows

Read `LEDGER.md`. **Only consider rows below the `<!-- Experiment rows are appended below this line -->` marker** — any `## H-` line above it (in the `## Format reference` or `## Example` sections, e.g. the shipped `H-007` example) is documentation, not a result, and must never be verified or reproduced. Collect the real rows to verify:
- If `$ARGUMENTS` names a hypothesis (e.g. `H-012`), verify just that one.
- Otherwise verify **every KEPT row**.

If there are no KEPT rows, stop:
> "No KEPT rows to verify. Run experiments first (`/phd:run` or `/phd:daemon start`)."

For each selected row, parse: hid, status, hypothesis, change, the full metric line
(name, before→after, budget, seed), the baseline line, artifacts path, commit, note.

---

## Step 2 — Reproduce each KEPT row

For each row, attempt a deterministic reproduction:

1. Locate `runs/<hid>/job.json` and `runs/<hid>/result.json`. If either is missing,
   the result is **UNVERIFIABLE (artifact missing)** — flag and move on.
2. Re-run the experiment at the **recorded seed** under the recorded budget:
   ```
   julia harness/runner.jl runs/<hid>/ --verify
   ```
   (or relaunch from `job.json` into a scratch dir). The point is determinism: same
   seed, same split, same budget ⇒ the score must reproduce.
3. Compare the reproduced score to the ledger's `after` value:
   - **within tolerance** (default rel. diff ≤ 2%, or the project's stated tolerance) →
     `REPRODUCED`.
   - **drifts beyond tolerance** → `DRIFT` — record both numbers. A non-reproducible
     KEPT result cannot enter the paper.
4. Confirm `result.json`'s score matches the ledger row (catch ledger-vs-artifact
   transcription drift).

If Julia or the harness isn't available, say so plainly and downgrade to a
**static audit only** (Steps 3–4), clearly labeling that no live reproduction was run.

---

## Step 3 — Audit the four failure modes

For every selected row, check each. Any hit is a finding, not a pass.

1. **Data leakage.** Confirm the held-out trajectory (fixed seed 1337 per CONTEXT.md)
   was not used during training/search. Inspect `job.json`/`meta` for the split. If the
   held-out set could have been touched, flag **LEAKAGE**.
2. **Seed robustness & aggregation consistency.** The loop now runs each hypothesis over K
   seeds and keeps on the **mean** (rows carry `mean ± std, n=K, seeds: …`), so blatant
   seed-cherry-picking is structurally prevented. Verify instead that the row is *honest*:
   re-aggregate the K child results under `runs/<hid>/s*/result.json` and confirm the row's
   mean ± std and n match (flag **AGG-DRIFT** on mismatch); confirm n ≥ 2 and the seed list
   excludes the held-out 1337; and if the `note:` says "within seed noise (≤1σ)", ensure the
   prose does **not** present the improvement as decisive. A single-seed (n=1) KEPT row is
   itself a finding — flag **SINGLE-SEED** and recommend re-running with `seeds_per_hypothesis ≥ 3`.
3. **Unfair or missing baseline (quantum candor).** For any row whose claim implies
   advantage: the `baseline:` field must contain `BEATS classical ✓` *and* a real,
   fairly-tuned classical score in `meta`. If the baseline is absent, untuned, or not
   actually beaten, flag **UNSUPPORTED-ADVANTAGE** — this result may be KEPT but may
   **not** be written as demonstrating quantum advantage.
4. **Ledger-vs-artifact drift.** Already covered numerically in Step 2; also check the
   `change:`/`note:` prose matches what `job.json` actually did.

---

## Step 4 — Citation check (if a draft exists)

If `paper/` contains drafted prose (`results.md`, etc.), citation-check it against the
ledger and sources:
- Every quantitative claim in the prose must trace to a field in a **REPRODUCED** KEPT
  row. A number with no ledger origin is **FABRICATED-NUMBER** — flag it.
- Any "quantum advantage" phrasing must correspond to a row that passed Step 3.4. Flag
  **OVERCLAIM** otherwise.
- If the prose cites external literature, verify each reference resolves to a real,
  locatable source. Do not invent DOIs or fabricate citations; flag any you cannot
  confirm as **UNVERIFIED-CITATION** rather than asserting it.

---

## Step 5 — Write the verdict

Write `paper/verification.md` (create `paper/` if needed). For each row:

```markdown
## H-NNN — <REPRODUCED | DRIFT | UNVERIFIABLE>
reproduction: ledger <after> vs reproduced <score>  (Δ <pct>%, seed <seed>)  → <pass/fail>
leakage:        <clear | LEAKAGE: ...>
seed-selection: <clear | SEED-SELECTION: ...>
baseline:       <supported | UNSUPPORTED-ADVANTAGE: ...>
artifact-drift: <clear | DRIFT: ...>
verdict:        VERIFIED  |  VERIFIED-NO-ADVANTAGE  |  FAILED-VERIFICATION
```

End with a summary table and a one-line gate decision: how many rows are cleared to
enter the manuscript, and which are blocked and why.

Then report to the user, e.g.:
> "Verified N KEPT rows: X cleared, Y blocked. H-007 reproduced (Δ 0.7%) and its
> classical baseline holds — clear to write. H-011 flagged UNSUPPORTED-ADVANTAGE: no
> tuned classical baseline; it can be reported as a quantum *result*, not an advantage.
> Full verdict in `paper/verification.md`. `/phd:write` and `/phd:defend` should draw
> only from cleared rows."

---

## Hard rules

1. **Never modify `LEDGER.md`.** Verification writes a separate verdict file only.
2. **A row that doesn't reproduce cannot enter the paper.** DRIFT and UNVERIFIABLE are blocking.
3. **No advantage claim without a beaten, fairly-tuned classical baseline.** This is the §5 candor rule, enforced — not advisory.
4. **Never fabricate or assert unverified citations.** Flag what you cannot confirm.
5. **State your limits.** If you could not run a live reproduction, label the verdict as static-audit-only; do not imply you reproduced what you didn't.
