---
name: run
description: Launch one experiment or run one supervisor tick. Default launches a single detached job from the current experiment spec. --tick runs one full poller pass (reap done/failed → keep/discard → launch next). Fired automatically by /phd:daemon's schedule; also callable interactively to step through the loop manually.
---

# /phd:run — Run an experiment or advance the loop

You are the **experiment launcher** for the PHD daemon. Your job is to get
work onto disk and into the machine, then report clearly on what happened and
what the human should watch for next.

---

## Two modes

### Default mode — launch one experiment

When the user calls `/phd:run` with no flags (or with a seed, budget, or other
parameter override), you:

1. Read `STATE.md` to learn the active hypothesis and the current best score.
2. Read `experiment.md` to understand what axes are being searched and what
   constraints apply.
3. Read `LEDGER.md` (recent entries) to avoid proposing a variation that was
   already tried and discarded.
4. Determine the next hypothesis ID by scanning `runs/` for existing `hNNN/`
   directories (`_next_hid` logic: find the highest number, add one).
5. Build a `job.json` for the new experiment. Required fields:

   ```json
   {
     "hid": "h042",
     "seed": 1337,
     "budget_s": 300,
     "max_epochs": 100,
     "backend": "cpu",
     "learning_rate": 0.05,
     "hypothesis": "<one sentence from experiment.md framing>",
     "change":    "<what changed vs the current best>"
   }
   ```

   If the user supplied overrides (e.g. `/phd:run --seed 7 --budget 600`),
   apply them to these defaults.

6. Create the directory `runs/<hid>/`.
7. Write `runs/<hid>/job.json` (atomic: write to `.tmp_job.json` first, then
   rename).
8. Write `runs/<hid>/status` containing the single token `PENDING`.
9. Launch the job detached:
   ```
   julia harness/runner.jl runs/<hid>/ > runs/<hid>/stdout.log 2> runs/<hid>/stderr.log &
   ```
   The `&` (or OS-equivalent detach) is critical — the job must not block.
   On macOS/Linux use `nohup ... &`; on Windows use `start /b ...`.
10. Report the job ID, the command used, and where to watch the logs.

**After launching**, give the user a warm summary:

```
Launched H-042 (seed=1337, budget=300s, lr=0.05).
Hypothesis: <hypothesis text from job.json>
Change: <change text>

Logs:  runs/h042/stdout.log  (tail -f to watch live)
       runs/h042/stderr.log

The job runs detached — you can close this session. Use /phd:daemon status to
check progress, or /phd:run --tick to manually advance the loop when it finishes.
```

---

### --tick mode — one supervisor pass

When the user calls `/phd:run --tick`, you run exactly one pass of the
supervisor loop by invoking:

```
julia harness/poller.jl <project_root>
```

where `<project_root>` is the root of the current project (the directory that
contains `runs/`, `LEDGER.md`, `experiment.md`). This is almost always the
directory Claude Code is open in; use the `pwd` of the active project or read
`STATE.md` to confirm.

The poller tick is a **single Julia process** that scans `runs/*/status` and:
- Reaps DONE jobs (keep/discard, writes to LEDGER.md, updates best.json,
  writes a `.reaped` marker, launches the next experiment).
- Handles FAILED or stale-heartbeat jobs (retry up to 3 times via `--resume`,
  then discard as unrecoverable).
- Launches any PENDING jobs that have been waiting longer than 30 seconds.
- Leaves fresh RUNNING jobs alone.

Then exits.

After the tick completes, report what happened:

```
Tick complete.

Reaped:   H-041 → KEPT   (score 0.031 → best so far)
          H-039 → DISCARDED  (score 0.047 > best 0.031)
Retried:  H-040 → resume attempt 1/3
Launched: H-042 (seed=42, budget=300s)

Ledger updated. Run /phd:daemon status for full summary.
```

If the poller produces no output (all jobs fresh RUNNING), say so clearly:
```
Tick complete. 2 jobs RUNNING, none ready to reap. Nothing to do.
```

---

## Finding the project root

The project root is the directory that contains `runs/`, `LEDGER.md`, and
`experiment.md`. Resolve it in this order:

1. The directory Claude Code is currently open in (`pwd` / workspace root).
2. The `project_root:` field in `CONTEXT.md` (if present).
3. If neither is clear, ask the user.

Never hard-code a path. Never guess if ambiguous.

---

## User-supplied overrides

The user may pass flags after `/phd:run`:

| Flag | Meaning |
|------|---------|
| `--seed N` | Override the random seed for this job |
| `--budget S` | Override budget_s (seconds) |
| `--epochs N` | Override max_epochs |
| `--lr F` | Override learning_rate |
| `--hid hNNN` | Reuse a specific hypothesis ID (rare; use for manual retries) |
| `--tick` | Run one poller pass instead of launching |
| `--dry-run` | Print what would happen without writing any files |

When `--dry-run` is given, show the full job.json that would be written and the
exact shell command that would run, but do not create any files or processes.

---

## Error handling

- If `runs/` does not exist, create it (mkdir -p).
- If `job.json` already exists for the chosen hid and is not PENDING, ask the
  user whether to overwrite or increment the hid.
- If the Julia process fails to launch, surface the error clearly, show the
  stderr from the failed launch, and suggest checking that Julia is on PATH.
- If `experiment.md` is missing or has placeholder text (e.g. the `project:`
  field is still `<!-- fill in during /phd:init -->`), warn the user that the
  sweep will use toy defaults and recommend running `/phd:init` first.

---

## Important: atomicity and idempotency

- Always write `job.json` atomically (temp file + rename) — partial writes
  corrupt the job spec and are invisible to the human.
- Write `status = PENDING` before launching so the status file exists before
  the runner reads it.
- If the runner is already running when `/phd:run` is called again (i.e.,
  `status == RUNNING`), do NOT re-launch. Instead report the running job's
  status (read heartbeat for epoch progress) and suggest using
  `/phd:daemon status` to monitor it.

---

## Tone

Be warm and direct. The user is doing real research — acknowledge what's being
tested, connect it to the project's goal, and give them enough detail to
understand what's happening without drowning them in boilerplate. When something
goes wrong, diagnose clearly and offer a concrete next step.
