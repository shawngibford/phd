---
description: Draft the Results section of the paper from the hypothesis ledger. Reads LEDGER.md, filters to KEPT rows, and writes a full academic prose results section to paper/results.md. Only reports what the ledger records — no fabrication.
argument-hint: [--section <intro|methods|results|all>]
---

# /phd:write — Results Section Drafter

You are drafting the results section of an academic manuscript from the hypothesis ledger of this PHD research project. Your job is to transform the structured records in `LEDGER.md` into full, publication-quality prose. You do **not** invent, extrapolate, or speculate beyond what the ledger explicitly records.

---

## Step 1 — Read the ledger

Read `LEDGER.md` in the current working directory. If it does not exist, stop and tell the user:

> "No LEDGER.md found in the current directory. Run `/phd:init` to scaffold a project, then `/phd:run` to populate the ledger with experiment results before drafting the paper."

Parse every entry that begins with `## H-`. **Only parse rows that appear below the `<!-- Experiment rows are appended below this line -->` marker.** Any `## H-` line above it — inside the `## Format reference` or `## Example` sections — is documentation (the shipped example is `H-007`), not a real result. Never draft from it. For each real entry, extract:

- **hid** — the hypothesis identifier (e.g., `H-007`)
- **date** — the ISO date from the header line
- **status** — the status token from the header (`KEPT`, `DISCARDED`, `FAILED`, `PENDING`, `RUNNING`)
- **hypothesis** — the `hypothesis:` field value
- **change** — the `change:` field value
- **metric line** — the full `metric:` field value. For multi-seed rows this is `name  before → mean ± std   (… n=K)   budget: Ts   seeds: …` — capture the **mean, the ± std, and n** (single-seed/legacy rows have no `± std` and use `seed:`).
- **baseline line** — the full `baseline:` field value
- **artifacts** — the `artifacts:` field value (run directory + commit)
- **note** — the `note:` field value (may be absent)

---

## Step 2 — Filter to KEPT rows only

Collect only entries whose status is exactly `KEPT`. If there are no KEPT rows, stop and report:

> "The ledger contains no KEPT hypotheses yet. Results can only be drafted from experiments the daemon has verified and kept. Run `/phd:run` or `/phd:daemon start` to accumulate results, then re-run `/phd:write`."

### Verification gate (warn, don't hard-block)

Before drafting, check `paper/verification.md`. If it is **absent**, or any KEPT row you are about to draft is not marked `VERIFIED` / `VERIFIED-NO-ADVANTAGE` there, warn the user:

> "⚠ These results have not been verified. `/phd:write` will draft from the ledger as-is, but a draft built on unreproduced results is fragile — `/phd:verify` reproduces each KEPT row and flags leakage, p-hacking, and unsupported advantage claims. Recommend running `/phd:verify` first. Draft anyway? (yes / run verify first)"

If the user proceeds, draft only the rows that exist; for any row lacking a `VERIFIED` verdict, do not assert quantum advantage for it regardless of its `baseline:` field (an unverified baseline is not evidence). This mirrors the `academic-paper` skill's rule: draw narrative claims only from verified rows.

---

## Step 3 — Determine quantum-advantage status for each row

For each KEPT row, determine the quantum-advantage claim as follows. This is governed by the **§5 candor rule** from the architecture: a quantum advantage claim is only valid if a fairly-tuned classical baseline was present and beaten.

Inspect the `baseline:` field:

- If it contains the token `BEATS classical ✓` → **advantage demonstrated**. Record the baseline score and the quantum score for citation in the prose.
- If it contains `does NOT beat classical ✗` → **no advantage**. The quantum result was kept because it improved on a prior quantum result, but it does not claim advantage over classical.
- If it contains `no baseline recorded` or is absent or blank → **speculative; no advantage demonstrated**. The ledger flagged this as speculative. Do not claim advantage in the prose. Note this openly.

The draft **must not** claim quantum advantage for any row that does not have `BEATS classical ✓` in the baseline field. This is a hard constraint, not a stylistic preference.

---

## Step 4 — Plan the narrative structure

Before writing, construct a brief internal outline (do not include in the output):

1. Identify the progression of best scores across KEPT rows (chronological order by date, then by hid). This is the story arc: what improved, when, and by how much.
2. Identify whether any KEPT rows demonstrate quantum advantage. If yes, group them and note what system they apply to.
3. Identify the best overall result (lowest score if rel_L2; clearly stated as "best achieved" in the draft).
4. Note any follow-up hypotheses or pruning candidates from the `note:` fields — these may appear as future-work hints in the discussion.

---

## Step 5 — Write the results section

Write the full results section as **academic Markdown** to `paper/results.md`. Create `paper/` if it does not exist.

### Output file: `paper/results.md`

The results section must:

1. **Open with a paragraph** that states the research goal (derived from the `hypothesis:` field of H-001 if present, otherwise inferred from the KEPT rows), the primary metric being optimized, and the number of experiments that were kept from the total run.

2. **Report each KEPT hypothesis** in chronological order (by date, then hid) as a dedicated subsection: `### H-NNN — <short title derived from the hypothesis text>`. Each subsection must include:

   - A full prose description of what was changed (from the `change:` field), written as a complete academic sentence. Do not use bullet points for this — prose only.
   - The metric improvement in precise quantitative terms, reported as **mean ± std over n seeds** (e.g. "rel-L2 fell from 0.041 to 0.029 ± 0.003 across n=5 seeds"), the percentage improvement of the means, and whether the gain was **statistically meaningful** (the ledger `note:` flags "significant (>1σ)" vs "within seed noise"). Never report a multi-seed result as a bare point estimate — always carry the ± std. If a row is single-seed, say so explicitly (it is weaker evidence).
   - Whether a quantum-advantage claim is supported, using the language prescribed in Step 3. If advantage is demonstrated, state the ratio explicitly (quantum score vs. classical baseline score). If no baseline is recorded or the baseline was not beaten, state this plainly and without apology — negative or inconclusive findings are still findings.
   - A reference to the artifact directory and commit (if available), phrased as: "Full experiment artifacts are archived in `<artifacts path>`" or similar.
   - Any observation from the `note:` field, incorporated naturally into the prose — do not reproduce the note verbatim but paraphrase it as a scientific observation.

3. **Reference the figures.** If `paper/figures/` exists (produced by `/phd:analyze`), embed the
   relevant figures in the prose with Markdown image links — at minimum `trajectory.svg` (the
   best-score arc with error bars) near the summary, and the per-hypothesis `seed-spread-hNNN.svg` /
   `convergence-hNNN.svg` beside the subsection that discusses that hypothesis. Each figure gets a
   caption stating what it shows and its n. If `paper/figures/` is absent, note that figures have
   not been generated and recommend running `/phd:analyze` before `/phd:defend`.

4. **Include a summary table** (Markdown table) after all individual subsections, with columns:

   | Hypothesis | Date | Change | Metric (before → mean ± std, n) | Quantum Advantage |
   |---|---|---|---|---|

   Populate each row from the KEPT ledger entries. In the "Quantum Advantage" column, write `Yes (ratio: X.XX)`, `No (classical baseline not beaten)`, or `Not assessed (no baseline)` as appropriate.

5. **Close with a short paragraph** summarizing the overall trajectory of results: what the best achieved score was, how many hypotheses were tested in total (KEPT + DISCARDED + FAILED; read all rows to count), what fraction were kept, and — if any quantum advantage was demonstrated — a one-sentence statement of what it was. If no quantum advantage was demonstrated across any KEPT row, state that plainly: "No quantum advantage over classical baselines was demonstrated in this experimental run." This sentence must appear whenever it is true; it must not be omitted or softened.

### Prose style requirements

The prose must be written in the third person, past tense, in the style of a machine learning or scientific computing conference paper. Sentences should be complete and grammatically correct. Paragraphs should be substantive — at minimum three to five sentences each. Headings should be informative, not generic (not "Results" but something like "Adaptive Time-Gating Reduces Trajectory Error by 29%"). Technical terminology should be used precisely: "relative L2 error" not "error metric"; "surrogate model" not "model"; "held-out trajectory" not "test set."

Do not use bullet points in prose paragraphs. Tables are acceptable for summary material only.

Do not use hedging language such as "seems to," "appears to," or "may suggest" unless the ledger's `note:` field itself is hedged. Report what happened, not what might have happened.

---

## Step 6 — Report what was written

After writing `paper/results.md`, report to the user:

> "Results section drafted to `paper/results.md`.
>
> Summary:
> - KEPT hypotheses drafted: N
> - Total experiments in ledger: M (N kept, X discarded, Y failed)
> - Best score achieved: <score> (<metric name>) — H-NNN, <date>
> - Quantum advantage demonstrated: Yes / No / N/A (no quantum experiments)
>
> Review `paper/results.md` and run `/phd:verify` before submitting — the verifier will reproduce each KEPT result and flag any discrepancy between the ledger and the actual artifact."

If `$ARGUMENTS` contains `--section` followed by a section name (e.g., `--section intro`, `--section methods`, `--section all`), note that those sections are not yet implemented and offer to draft only the results section now.

---

## Hard rules (non-negotiable)

1. **No fabrication.** Every number in the draft must come from a field in a KEPT ledger row. If a field is blank, missing, or marked as "to be measured," write that it was not recorded rather than inventing a value.
2. **No advantage claims without evidence.** The phrase "quantum advantage" and any synonym (speedup, improvement over classical, etc.) must only appear in the context of a row with `BEATS classical ✓` in the baseline field. All other cases require explicitly noting that no classical comparison was available or that the classical baseline was not beaten.
3. **Do not modify LEDGER.md.** The ledger is append-only and owned by the daemon and the user. The write command reads it; it never writes to it.
4. **Do not read or cite DISCARDED or FAILED rows in the main narrative.** They may appear only in the aggregate count in the closing paragraph.
5. **Create `paper/` if absent.** If the directory does not exist, create it before writing the file.
