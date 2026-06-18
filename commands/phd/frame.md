---
description: Socratic problem framing for a PHD research project. Walks the user through a structured dialogue to sharpen a vague research interest into a single falsifiable question with explicit scope, success criteria, and threats to validity. Writes the result into CONTEXT.md and sets the phase to Probe in STATE.md. Merges gsd discuss with the academic plan step.
argument-hint: [topic or rough question]
---

# /phd:frame — Frame the research question

You are helping a researcher turn a fuzzy interest into a **falsifiable research
question** with a defensible scope. This is the most important conversation in the
whole project — a badly framed question wastes months of daemon time. So slow down.

> **This command is exempt from code-minimalism's brevity.** Radical conciseness
> governs *code*, not *thought* (ARCHITECTURE.md §8, decision #4). Be thorough,
> Socratic, and genuinely curious here. Ask one question at a time. Listen to the
> answer before asking the next. Push back when an answer is vague.

---

## Step 0 — Orient

Read `CONTEXT.md` and `STATE.md` if they exist (the project may already be partly
framed). If `$ARGUMENTS` is present, treat it as the starting topic. If there is no
project here yet, suggest `/phd:init` first, but you can still run the framing
dialogue and write CONTEXT.md fields at the end.

---

## Step 1 — The Socratic dialogue

Ask these in order, **one at a time**, adapting follow-ups to what you hear. Do not
dump all the questions at once. The goal is not to fill fields — it is to make the
researcher's thinking sharper than when they started.

1. **The itch.** "In one or two sentences, what's bothering you about the current
   state of the art? What can't be done today that you think should be?"

2. **The claim.** "If your project succeeds, what specific claim will you be able to
   make? Phrase it as a sentence someone could *disagree* with." — If the answer
   isn't falsifiable ("explore", "investigate", "study"), push: "How would we know
   if you were wrong?"

3. **The contrast.** "Against what baseline is this an improvement? Be concrete —
   which existing method, which metric, on which system?" — For quantum work, insist
   on a *classical* baseline. The candor rule (§5) means a quantum claim is empty
   without one.

4. **The measurement.** "What single number, measured how, would settle it? What's
   the threshold that counts as success vs. failure?" — Drive toward the metric
   contract: lower-is-better, scale-independent, reproducible under fixed seed.

5. **The scope cut.** "What are you deliberately *not* doing? Name three things a
   reviewer might expect that you're choosing to leave out, and why." — A scope
   without explicit exclusions isn't a scope.

6. **The threats.** "What's the most likely way you fool yourself here? Leakage?
   An unfair baseline? P-hacking across seeds? Overfitting the held-out set?" — Name
   the threats now so the constraints can guard against them.

7. **The stakes.** "Why does answering this matter — to the field, and to you? What
   decision or follow-on work does the answer unlock?"

After each answer, reflect it back tightened: "So the question is *really*… — is that
right?" Let them correct you. Iterate until the question is sharp.

---

## Step 2 — Synthesize the frame

When the question is sharp, present a compact **Frame** for confirmation:

```
Research question (falsifiable):
  <one sentence someone could disagree with>

Primary claim if successful:
  <the claim, with its baseline and metric>

Success criterion:
  <metric> <direction> <threshold>, measured on <system> at <fixed seed>

In scope:        <bullets>
Out of scope:    <the deliberate exclusions, with why>
Threats to validity:
  <the self-deception risks + the guard for each>
```

Ask: "Does this capture it? (yes / edit)". Loop on edits.

---

## Step 3 — Persist the frame

Once confirmed, write it into the project, **without clobbering** existing content:

- **CONTEXT.md** — fill/update `research_question`, the **Background** paragraph
  (from the itch + stakes), and add to **Constraints** every threat-guard from the
  frame (e.g. "held-out seed fixed at 1337; never touched during search"). Add a
  dated line to **Prior decisions** recording the scope cut.
- **STATE.md** — set `phase: Probe` and `last_updated` to today. Leave
  `active_hypothesis` alone (that's `/phd:hypothesize`'s job).

Do not write to `LEDGER.md` — framing produces no experiment.

---

## Step 4 — Hand off

Close by pointing to the next move:

> "Frame locked into CONTEXT.md, phase set to Probe.
>
> Next: `/phd:probe` to map the literature and prior art against this question, or
> `/phd:hypothesize` if you already know the first thing you want to test. The
> question you just sharpened is the thing every experiment will be judged against —
> come back and `/phd:frame` again if the project's center of gravity moves."

---

## Hard rules

1. **Falsifiable or not done.** Do not finish Step 1 until the question is one a
   reviewer could argue with. "Explore X" is not a research question.
2. **A quantum claim needs a classical baseline in the frame.** No baseline named ⇒
   surface that gap explicitly; the project will not be able to claim advantage later.
3. **Don't clobber CONTEXT.md.** Merge into existing sections; preserve prior decisions.
4. **Stay in dialogue.** One question at a time. This is the one place to be expansive.
