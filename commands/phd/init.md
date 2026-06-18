---
description: Scaffold a new PHD research project in the current directory. Runs an interactive setup dialogue (project name, research question, time budget, parallel workers) then creates STATE.md, CONTEXT.md, LEDGER.md, experiment.md, and empty runs/ and harness/ directories from the plugin templates.
argument-hint: [project-name]
---

# /phd:init — New Research Project Setup

You are about to scaffold a PHD research project. Walk through the setup dialogue below with the user, then create the project files. Be warm and conversational throughout — this is the beginning of potentially years of work, and the framing questions matter.

---

## Step 1 — Opening

Greet the user and explain what you are about to set up together:

> "Welcome to PHD — Persistent Hypothesis Daemon. I'll help you scaffold a research project that can run experiments autonomously, track every hypothesis in a persistent ledger, and eventually generate a manuscript from your results.
>
> This takes about five minutes. We'll nail down the core research question, set your compute budget, and wire everything up. Let's go."

If `$ARGUMENTS` was provided, treat it as the project name and skip asking for it. Otherwise, ask:

---

## Step 2 — Dialogue (ask these questions one at a time, wait for answers)

**Q1 — Project name**
"What's the short name for this project? (used as the directory handle — lowercase, hyphens ok, e.g. `qtrplm`, `fermentation-surrogate`)"

**Q2 — Research question**
"State your primary research question in one sentence. Make it falsifiable. For example: 'Does a quantum-adaptive τ-gating mechanism reduce trajectory error on the fermentation ODE relative to a classical Neural-ODE baseline?'
Your question:"

**Q3 — Active hypothesis**
"What is your current best guess at the answer — your starting hypothesis? This becomes H-001 in the ledger. One sentence."

**Q4 — Time budget T**
"How many seconds should each experiment run before being scored? This is the wall-clock budget per run. Typical values:
  - 300 s  → quick sanity checks, iterate fast (recommended to start)
  - 1800 s → deeper training, fewer iterations per night
  - 3600 s → overnight quality, K experiments in parallel
Default is 300. Enter a number, or press enter to accept 300:"

**Q5 — Parallel workers K**
"How many experiments should run in parallel? On one M1 Pro, throughput peaks around K=2–3 (more workers share memory bandwidth and slow each other down). Honest recommendation: start with K=2.
Enter a number, or press enter to accept 2:"

After collecting all answers, confirm with a summary:

> "Here's what I have:
>   Project: <name>
>   Research question: <question>
>   Starting hypothesis (H-001): <hypothesis>
>   Time budget per run: <T> seconds
>   Parallel workers: K=<K>
>
> Ready to scaffold? (yes / edit)"

If the user asks to edit, loop back to the relevant question.

---

## Step 3 — Scaffold the project

Once confirmed, create the following structure in the **current working directory**:

```
<cwd>/
├── STATE.md          ← from plugin templates/STATE.md, filled with answers
├── CONTEXT.md        ← from plugin templates/CONTEXT.md, filled with answers
├── LEDGER.md         ← from plugin templates/LEDGER.md, H-001 row added
├── experiment.md     ← from plugin templates/experiment.md, filled with answers
├── runs/             ← empty directory (experiment job dirs land here)
└── harness/          ← empty directory (Julia harness files go here)
```

### How to populate each file

**STATE.md** — copy the template and fill in:
- `phase` → `Hypothesize`
- `active_hypothesis` → H-001: <hypothesis text>
- `best_score` → `none yet`
- `last_updated` → today's date

**CONTEXT.md** — copy the template and fill in:
- `project` → <project name>
- `research_question` → <question>
- `time_budget_s` → <T>
- `parallel_workers` → <K>
- Leave constraints and prior decisions as placeholder text for the user to fill in.

**LEDGER.md** — copy the template. After the example row (H-007) and the blank template row, append a real H-001 entry:

```markdown
## H-001 · <today's date> · PENDING
hypothesis: <hypothesis text from Q3>
change: (initial baseline — no diff yet)
metric: (to be measured on first run)
baseline: (to be established on first run)
artifacts: (none yet)
note: starting hypothesis; /phd:run will populate this row
```

**experiment.md** — copy the template and fill in the project name and research question at the top. Leave the rest as editable instructions for the user.

**runs/** — create the empty directory with a `.gitkeep` file.

**harness/** — create the empty directory with a `.gitkeep` file and a `SETUP.md` that says:

```markdown
# Harness

Copy the Julia harness files from the PHD plugin into this directory:

  harness/device.jl      — hardware autodetect (CPU-threads only, v1)
  harness/metric.jl      — ExperimentResult contract + SciML/Yao.jl scorers
  harness/runner.jl      — detached-job launcher + per-epoch checkpoint writer
  harness/poller.jl      — watches runs/*/status, fires keep/discard actions
  harness/supervisor.jl  — the daemon loop: launch → poll → keep/discard → propose next

These files are built as part of the PHD plugin but are not auto-copied into new
projects. Copy or symlink them from the plugin directory:

  cp <plugin-dir>/harness/*.jl harness/

Then verify your Julia environment has: SciML, Yao, YaoML, KernelAbstractions.
```

---

## Step 4 — Closing

After writing all files, report what was created:

> "Your PHD project is ready. Here's what's next:
>
> 1. Review and expand `experiment.md` — tell the agent what to vary, what constraints apply, and which metric to optimize.
> 2. Copy the Julia harness into `harness/` (see `harness/SETUP.md`).
> 3. Run `/phd:run` to kick off your first experiment and populate H-001 in the ledger.
>
> Your hypothesis ledger starts at `LEDGER.md`. Every experiment — kept or discarded — will be recorded there. That ledger is your paper's results section in waiting.
>
> Good luck with the research."
