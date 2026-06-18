---
description: Dual review of the project — code and manuscript. The governor side audits recent code (harness, model, glue) for over-engineering and bloat against the code-minimalism ruleset; the academic side runs an adversarial peer review of the paper draft (academic-paper-reviewer). Produces a combined review report. Merges ponytail-review with academic peer review. Surface half is CC BY-NC 4.0.
argument-hint: [--code | --paper | both (default)]
---

# /phd:review — Dual review: governor + peer reviewer

You run **two reviews** that a PHD project always needs and rarely does itself: is the
*code* lean, and is the *paper* defensible. By default run both; `--code` or `--paper`
runs one. Each produces concrete, actionable findings — not vibes.

---

## Side A — Code review (governor)

The always-on `code-minimalism` ethos, applied as a deliberate audit of recent changes.

1. **Scope the diff.** Review code touched since the last review (recent commits, or the
   working tree). Prefer the harness, model code, and glue — where the daemon writes
   unattended and bloat accumulates.
2. **Audit against the ruleset** (`code-minimalism` skill):
   - speculative abstraction with <2 real callers,
   - unrequested features / flags / helpers,
   - premature optimization with no ledger evidence the path is hot,
   - dead code from discarded hypotheses left in place,
   - multi-concern diffs that muddy ledger attribution,
   - new dependencies that Base / SciML / Yao already cover.
3. **Report findings** with the smallest fix for each, and a **debt ledger** line per
   item (file, issue, suggested deletion/simplification, est. LOC removed). Favor
   net-negative diffs.

## Side B — Manuscript review (peer reviewer)

The `academic-paper-reviewer` skill, run adversarially against the draft in `paper/`,
cross-checked with `paper/verification.md` and `LEDGER.md`:
- unsupported claims (numbers with no verified ledger origin),
- unfair or missing classical baselines,
- overclaiming ("quantum advantage", "SOTA", "proves"),
- weak statistics (single-seed or best-of-N without the distribution),
- reproducibility gaps,
- scope/framing drift from CONTEXT.md.

Output a severity-ranked review with a recommendation (accept / minor / major / reject)
and the exact revision each finding requires.

---

## Combined report

Write `paper/review.md` (and surface a summary in chat):

```
PHD Review — <date>

CODE (governor)
  Findings: N   Est. LOC removable: ~X
  [sev] <file> — <bloat> → <smallest fix>
  ...

MANUSCRIPT (peer review)
  Recommendation: <accept | minor | major | reject>
  MAJOR: [sev] <finding> → <required fix>
  MINOR: ...
  Questions for authors: ...

GATE: <are there blocking MAJOR manuscript issues or critical code debt before /phd:defend?>
```

Close by pointing forward: code findings → fix inline or via `plan-executor`; manuscript
MAJOR issues → loop back through `/phd:write`; when both are clean → `/phd:defend`.

---

## Hard rules

1. **Actionable or omit it.** Every finding names a file/sentence and the exact fix. No "could be cleaner".
2. **Code review prefers deletion.** Net-negative diffs are the goal; record removable LOC.
3. **Manuscript: an unsupported number is always MAJOR.** Never wave it through.
4. **Don't fix during review.** Review names the fixes; application happens after (inline, `plan-executor`, or `/phd:write`).
5. **Check claims against `verification.md`.** The verdict file is ground truth, not the prose's own confidence.
