---
name: code-minimalism
description: Anti-bloat governor for all code the daemon writes. Auto-applies whenever Claude is about to write, edit, or refactor code in a PHD project — Julia harness, model code, scripts, or glue. Enforces the smallest correct change: no speculative abstraction, no unrequested features, no 400 lines where 12 will do. Adapted from ponytail (MIT).
---

# Code Minimalism — the PHD governor

> The daemon writes a lot of code unattended. Without a brake, autonomous loops
> bloat: every experiment grows a helper, every helper grows options, and the
> codebase rots faster than the research advances. This skill is the brake.
> It is **always on** — apply it to every code change, not just when asked.

Adapted from [ponytail](https://github.com/DietrichGebert/ponytail) (MIT). Default mode: **lite**.

---

## The one rule

**Write the smallest change that makes the next experiment run correctly — and nothing more.**

Everything below is that rule, made concrete.

---

## Before writing code, ask

1. **Does this already exist?** Search the harness and project first. Reuse a
   function before writing a new one. Extend `metric.jl` before adding a parallel scorer.
2. **Is it needed *now*?** If the current hypothesis doesn't require it, don't write it.
   "We might want X later" is a ledger note, not code.
3. **What's the smallest diff?** One change, reviewable by a human in under two minutes
   (this is the same bar `experiment.md` sets for an experiment diff).

If you can't answer all three, stop and say so rather than writing speculatively.

---

## Hard rules (lite mode — always enforced)

1. **No speculative abstraction.** No interface, base class, plugin system, or config
   knob until there are ≥2 real callers that need it. Solve the case in front of you.
2. **No unrequested features.** Implement exactly what the hypothesis or the user asked.
   Do not add CLI flags, logging frameworks, retry wrappers, or "while I'm here" extras.
3. **No premature optimization.** Correct and simple first. Optimize only a path the
   ledger shows is hot, and record the before/after — an optimization is itself a hypothesis.
4. **Prefer deletion.** When a change lets you remove code, remove it. Net-negative diffs
   are good diffs. Dead code from discarded hypotheses gets deleted, not commented out.
5. **One concern per change.** Don't mix a refactor into an experiment diff. The ledger
   must be able to attribute a score change to a single cause.
6. **Match the surrounding code.** Reuse existing naming, style, and idiom. A change that
   reads like the file it lives in is smaller, cognitively, than one that doesn't.
7. **No new dependencies without justification.** A new package must earn its place against
   what SciML / Yao.jl / Base already provide. Record the reason if you add one.

## Strict mode (opt in via `PHD_PONYTAIL=strict`)

Everything in lite, plus:
- **Line budget.** Flag any single function over ~40 lines or any new file over ~150;
  justify or split.
- **No comments that restate code.** Comment *why*, never *what*. Delete narration.
- **Challenge every helper.** A helper used once should be inlined.

---

## When the minimal change isn't obvious

Say so. Offer the smallest version that works and name what you deliberately left out
("I did not add a config flag for K — it's hard-coded to the value in CONTEXT.md; say the
word if you want it tunable"). Let the human pull complexity in, rather than pushing it on them.

This is the **only** place radical conciseness does *not* apply: the framing and research
dialogue (`/phd:frame`, `/phd:probe`) stays full and Socratic. Minimalism governs **code**,
not thought. (ARCHITECTURE.md §8, locked decision #4.)
