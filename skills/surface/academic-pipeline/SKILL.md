---
name: academic-pipeline
description: Orchestrates the end-to-end research-to-manuscript pipeline — literature review, gap analysis, outline, draft, peer review, and final compile — coordinating the deep-research, academic-paper, and academic-paper-reviewer skills and the research-architect, synthesis, and report-compiler agents in the right order. Auto-applies when running a multi-stage paper-production workflow. CC BY-NC 4.0 (see ../LICENSE).
---

# academic-pipeline — research-to-manuscript orchestration

The connective tissue of the academic surface. Individual skills draft, review, and
research; this one sequences them so `/phd:probe` and `/phd:defend` produce a coherent
manuscript rather than disconnected fragments. It owns *order and handoff*, not content.

CC BY-NC 4.0 — surface layer, attributed to academic-research-skills (../NOTICE.md).

---

## The pipeline (stage → who does it → artifact)

1. **Frame** → `/phd:frame` → falsifiable question in `CONTEXT.md`. (Precondition; not run here.)
2. **Literature & prior art** → `research-architect` agent plans the search; `deep-research`
   skill executes cited searches; `synthesis` agent condenses → `paper/related-work.md`
   + a gap analysis. (This is `/phd:probe`.)
3. **Experiments** → the loop (`/phd:run`, `/phd:daemon`) → `LEDGER.md`. (Not run here;
   the pipeline waits on the ledger.)
4. **Verify** → `/phd:verify` → `paper/verification.md`. **Gate:** drafting cannot
   proceed past unverified results.
5. **Outline + draft** → `academic-paper` skill → `paper/*.md` sections from verified rows.
6. **Peer review** → `academic-paper-reviewer` skill → review comments; loop back to 5
   until no MAJOR issues remain.
7. **Compile + disclose + export** → `report-compiler` agent → final manuscript +
   AI-disclosure statement + export format. (This is `/phd:defend`.)

## Orchestration rules

- **Respect the gates.** Never let stage 5 draw from results that didn't pass stage 4.
  Never let stage 7 compile a draft that still has open MAJOR review issues.
- **Spawn agents in fresh context** for the heavy stages (2, 7) so the orchestrator's
  context stays clean; pass each agent only the artifacts it needs.
- **Idempotent + resumable.** Each stage writes a file under `paper/`. Re-running the
  pipeline picks up from the last completed artifact rather than redoing finished work.
- **Anti-fabrication propagates.** Every downstream stage inherits the rule that claims
  trace to verified ledger rows and citations resolve to real sources.

## Hard rules

1. **Gates are blocking.** Verify before draft; resolve MAJOR review issues before compile.
2. **Never fabricate.** Sources are real and locatable; numbers trace to verified rows.
3. **Coordinate, don't duplicate.** Delegate content to the specialist skills/agents; this skill only sequences and hands off.
