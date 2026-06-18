---
description: Compile the final manuscript for submission. Runs the closing gates (verification clear, no open MAJOR review issues), assembles the drafted sections into one document, adds the AI-disclosure statement, runs a final citation pass, and exports to the requested format (Markdown/LaTeX/PDF/docx) via the report-compiler agent. The terminal Defend step. Surface layer, CC BY-NC 4.0.
argument-hint: [--format markdown|latex|pdf|docx]
---

# /phd:defend — Compile and export the manuscript

You are at the **Defend** finish line: turning verified results and reviewed sections
into one submittable manuscript. This command is mostly gates plus assembly — it refuses
to compile a paper that hasn't earned it, then makes the final document clean and honest.

> Surface command (CC BY-NC 4.0). Depends on `skills/surface/` and the report-compiler
> agent. The AI-disclosure statement it adds is mandatory.

---

## Step 1 — The closing gates (blocking)

Refuse to proceed if any fails; report exactly what's missing:

1. **Verification.** `paper/verification.md` exists and the rows feeding the paper are
   `VERIFIED` / `VERIFIED-NO-ADVANTAGE`. Any DRIFT or UNVERIFIABLE row used in the
   narrative blocks the compile → send the user to `/phd:verify`.
2. **Review.** No open **MAJOR** manuscript issues in `paper/review.md`. If there are,
   send the user to `/phd:write` to revise, then `/phd:review` again.
3. **Sections present.** The required sections exist under `paper/` (abstract, intro,
   related-work, methods, results, discussion, references). A missing section is reported,
   never fabricated.

If a gate fails, stop with a precise checklist of what to do. Do not compile around a
failed gate.

## Step 2 — Compile

Spawn the **report-compiler** agent (fresh context). It:
- stitches the sections into one coherent manuscript (headings, cross-refs, numbering,
  consistent citation style and terminology),
- runs the final citation pass (every in-text cite ↔ references entry; orphans flagged),
- adds the **AI-disclosure statement** describing how PHD/Claude were used (autonomous
  loop, drafting from the verified ledger), matched to the venue's policy,
- exports to the requested `--format` (default Markdown). For PDF/docx it uses `pandoc`
  if present, else emits the source format with the exact finishing command.

## Step 3 — Final candor pass

Before declaring done, do the honesty check the §5 candor rule demands: scan the compiled
manuscript for any "quantum advantage" / "speedup" / "beats classical" language and
confirm each maps to a row that passed verification with a beaten, fairly-tuned classical
baseline. If none was demonstrated anywhere, ensure the manuscript says so plainly — this
sentence must survive into the final document, not be softened away.

## Step 4 — Report

> "Manuscript compiled → `paper/manuscript.<ext>` (<format>).
>   Sections: <list>   Citations: N (all matched / X flagged)
>   AI-disclosure: added
>   Quantum advantage: <demonstrated for H-NNN | none demonstrated — stated plainly>
>
> Gates passed: verification ✓, review ✓. Ready for submission.
> If you exported source-only (LaTeX/Markdown), finish with: <exact pandoc command>."

If phase tracking is in use, set `phase: Defend` in `STATE.md`.

---

## Hard rules

1. **Gates are blocking.** No compile past failed verification or open MAJOR review issues. No exceptions.
2. **Disclosure is mandatory.** Never export a manuscript without the AI-disclosure statement.
3. **No new claims at compile.** Assemble and format only; results and citations come from the reviewed, verified draft.
4. **Candor on advantage survives to the final document.** If no advantage was shown, the paper says so.
5. **Report missing sections; never invent them.**
