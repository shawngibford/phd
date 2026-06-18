---
description: Turn research findings into a concrete, testable hypothesis and an experiment plan. Reads CONTEXT.md, the ledger, and experiment.md; proposes one falsifiable hypothesis with a single reviewable change and an expected effect; appends a PENDING row to LEDGER.md and sets it as the active hypothesis in STATE.md. The planning step that feeds /phd:run. Merges the gsd plan step.
argument-hint: [free-text hypothesis idea]
---

# /phd:hypothesize — Plan the next experiment

You are converting understanding into a **single testable hypothesis** plus the
experiment plan to test it. This is the gsd "plan" step, specialized for the PHD
loop: the output is one PENDING ledger row and an updated active hypothesis, ready
for `/phd:run` to execute.

The `code-minimalism` governor applies to the *change* you propose: one diff,
reviewable by a human in under two minutes. No "refactor everything" plans.

---

## Step 1 — Gather the state

Read, in this order:
1. `CONTEXT.md` — the research question, constraints, and prior decisions.
2. `STATE.md` — current phase and active hypothesis.
3. `LEDGER.md` — **the whole ledger**. You must know:
   - the current best KEPT score (what to beat),
   - which axes already produced KEPT improvements (what's working),
   - the recent DISCARDED hypotheses (dead ends — do not re-propose them).
4. `experiment.md` — the search axes and hard constraints.
5. `paper/related-work.md` — **if present** (written by `/phd:probe`): its closing
   **gap-analysis** paragraph states what prior work leaves open and how this project's
   question addresses it. Read it so the hypothesis targets that gap. If it's absent, note
   that running `/phd:probe` first would ground the hypothesis in the literature and
   strengthen its novelty claim.

If `$ARGUMENTS` contains a free-text idea, treat it as the candidate hypothesis and
your job is to sharpen and de-risk it. Otherwise, propose one yourself from the ledger
history (pick the most promising unexplored axis).

---

## Step 2 — Form the hypothesis

A PHD hypothesis has four parts. Draft all four:

1. **Claim** — one falsifiable sentence: "*<change>* lowers *<metric>* on *<system>*
   vs *<current best / baseline>*." It must be disprovable by a single experiment.
2. **Change** — the *one* concrete modification, with approximate scale ("replace
   fixed τ with learned per-neuron τ, ~12 LOC"). One axis from `experiment.md`. If your
   idea touches two axes, split it and pick the higher-leverage one; note the other as
   a follow-up.
3. **Expected effect + mechanism** — "I expect rel_L2 to drop because…". This goes in
   the ledger `note:` and is what makes a discard informative later.
4. **Kill criterion** — what result would refute it. (Default: score ≥ current best ⇒
   discarded.)

**Anti-dead-end check:** before finalizing, scan the DISCARDED rows. If this change —
or a near-duplicate — was already tried and discarded, say so and either propose a
materially different variant or explain why it's worth retrying (e.g. a confound has
since changed). Negative results in the ledger exist precisely to stop this.

**Novelty / gap-alignment check (advisory):** if `paper/related-work.md` exists, weigh the
hypothesis against its gap analysis: does this change actually attack the stated gap, and
is it genuinely novel versus the prior work surveyed there? If it's off-target or appears
already-done in the literature, **warn** the user and suggest a sharper, gap-aligned
variant — but this never blocks: the researcher may proceed deliberately. State the
alignment in one line so it carries into the confirmation summary.

**Quantum candor:** if the change is to a quantum model and the claim implies advantage,
the plan must include a fairly-tuned classical baseline in the experiment's `meta`. State
how it will be produced. No baseline ⇒ the result can only ever be logged "speculative."

---

## Step 3 — Confirm with the user

Present the plan compactly and get a yes before writing:

```
Next hypothesis: H-<NNN>
  Claim:    <falsifiable sentence>
  Change:   <one diff, ~N LOC, axis: <axis>>
  Expect:   <effect> because <mechanism>
  Beats:    current best <metric> = <value> (H-<best>)
  Baseline: <classical baseline plan, for quantum work | n/a>
  Kill if:  <refutation condition>

Append as PENDING and set active? (yes / edit)
```

Determine `H-<NNN>` by scanning `LEDGER.md` for the highest existing `H-` number and
adding one. (Keep the ledger's `H-NNN` format; note `/phd:run` uses `hNNN` for run dirs —
same number, different surface.)

---

## Step 4 — Persist

On confirmation:

- **LEDGER.md** — append a PENDING row in the exact contract format (do not reorder
  fields), newest at the bottom:

  ```markdown
  ## H-NNN · <today> · PENDING
  hypothesis: <claim>
  change: <the one change + scale>
  metric: <metric_name>    →      budget: <T from CONTEXT.md>s   seed: <seed>
  baseline:  →
  artifacts: runs/hNNN/  commit:
  note: <expected effect + mechanism; kill criterion>
  ```

  Append only. Never edit or reorder existing rows.

- **STATE.md** — set `active_hypothesis: H-NNN: <claim>`, `phase: Hypothesize`,
  `last_updated: <today>`.

- **experiment.md** — only if the user wants to steer the search (e.g. reprioritize
  axes). Otherwise leave it; it's the human's file.

If the change needs scaffolding code before it can run, optionally spawn the
**plan-executor** subagent to make that change in fresh context — give it the change,
the file pointers, and the leakage constraints from CONTEXT.md.

---

## Step 5 — Hand off

> "H-NNN appended to the ledger as PENDING and set as the active hypothesis.
>
> Run it with `/phd:run` (one detached experiment), or `/phd:daemon start` to let the
> loop test it and propose successors unattended. After it lands, `/phd:verify` will
> reproduce it before it can reach the paper."

---

## Hard rules

1. **One change per hypothesis.** Single axis, single reviewable diff. Split anything bigger.
2. **Check the ledger for dead ends first.** Do not re-propose a DISCARDED change without justification.
3. **Append-only ledger.** Add the PENDING row; never edit existing rows.
4. **Falsifiable + kill criterion mandatory.** A hypothesis with no refutation condition is not a hypothesis.
5. **Quantum advantage requires a planned classical baseline.** State it now or the claim is unprovable later.
