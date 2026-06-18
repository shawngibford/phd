---
name: academic-paper
description: Draft and structure an academic manuscript (abstract, intro, methods, results, discussion) in conference/journal style from verified PHD results. Auto-applies when writing or sectioning a paper, an abstract, or an outline from the hypothesis ledger. Anti-fabrication — every claim must trace to a verified ledger row. CC BY-NC 4.0 (see ../LICENSE).
---

# academic-paper — manuscript drafting

The drafting craft behind `/phd:write` and `/phd:defend`. You turn verified results
into publication-quality prose. The non-negotiable constraint: **you report only what
the ledger and verification verdict record. You never invent, extrapolate, or soften.**

CC BY-NC 4.0 — surface layer, attributed to academic-research-skills (../NOTICE.md).

---

## Source of truth, in order

1. `paper/verification.md` — the verdict. Draw narrative claims **only** from rows
   marked `VERIFIED` or `VERIFIED-NO-ADVANTAGE`. Never write from an unverified or
   DRIFT row. If no verdict exists, say so and recommend `/phd:verify` first.
2. `LEDGER.md` — the numbers (before→after, budget, seed, baseline).
3. `CONTEXT.md` — the research question, background, and constraints (frames the intro).

---

## Section craft

**Abstract** (150–250 words): problem → approach → the single headline result with its
number → one honest limitation. No citations in the abstract.

**Introduction**: the gap (from CONTEXT background), the falsifiable question, the
contribution as a bulleted-then-prose claim, against a named baseline.

**Methods**: the system, the metric (relative L2 / advantage ratio — define it),
the fixed held-out split and seed, the budget. Enough to reproduce. State the classical
baseline construction explicitly for any quantum comparison.

**Results**: chronological by verified hypothesis. Each: what changed (prose, not
bullets), the quantitative improvement as **mean ± std over n seeds** (never a bare
point estimate) and the % change of the means, whether the gain is **significant (>1σ)
or within seed noise** (from the ledger `note:`), and — using the §5 candor language —
whether quantum advantage is *supported*, *not demonstrated*, or *not assessed*.
**Reference the `paper/figures/` figures** (trajectory with error bars; per-hypothesis
seed-spread and convergence) with captions. Summary table allowed. Best overall result
stated plainly with its spread.

**Discussion**: what the trajectory means, the threats `/phd:verify` checked, and
honest limitations. Follow-up hypotheses from ledger `note:` fields become future work.

## Style

Third person, past tense, conference-paper register. Substantive paragraphs (3–5
sentences). Precise terms ("relative L2 error", "held-out trajectory", "surrogate
model"). Informative headings, not "Results". No hedging ("seems to", "may suggest")
unless the ledger note is itself hedged. No bullet points inside prose paragraphs.

## Hard rules

1. **Every number traces to a verified ledger field.** No origin ⇒ write "not recorded", never a guess.
2. **"Quantum advantage" only for rows with a beaten, fairly-tuned classical baseline.** Else state plainly no advantage was demonstrated — and say so in the closing if it's true across all rows.
3. **Never modify `LEDGER.md`.** Drafts live under `paper/`.
4. **Draw only from verified rows.** Unverified/DRIFT rows do not enter the narrative.
