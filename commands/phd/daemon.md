---
name: daemon
description: Manage the PHD background daemon. Subcommands: start (register a scheduled tick every N minutes), stop (remove the schedule), status (summarise runs/ + best ledger entry). Once started, the session can be closed — all state lives on disk.
---

# /phd:daemon — Start, stop, and check the background research daemon

The PHD daemon is the engine that keeps your experiment loop running while you
sleep. It is not a long-lived process inside Claude — it is a **scheduled task**
that fires every N minutes, calls one tick of `julia harness/poller.jl`, reaps
finished jobs, advances the loop, and exits. Between ticks, nothing runs inside
Claude at all. All state lives on disk: `runs/*/`, `LEDGER.md`, `best.json`.
You can close the session entirely; the loop continues.

---

## Subcommands

### `/phd:daemon start [--interval N] [--max-parallel K]`

Register a scheduled task that fires `/phd:run --tick` every N minutes
(default: 5 minutes). Steps:

1. Resolve the project root (directory containing `runs/`, `LEDGER.md`,
   `experiment.md`). Confirm with the user if ambiguous.

2. Confirm Julia is on PATH by running `julia --version`. If not found, stop
   and instruct the user to install Julia and add it to PATH before proceeding.

3. Build the exact shell command for the tick:

   ```bash
   julia /absolute/path/to/harness/poller.jl /absolute/path/to/project_root
   ```

   All paths must be absolute. Relative paths break when cron or the scheduler
   sets a different working directory.

4. Register the command as a scheduled task using the `scheduled-tasks` tool:

   ```
   task_name: phd-daemon-<project_slug>
   command:   julia /abs/path/harness/poller.jl /abs/path/project_root
   interval:  N minutes
   ```

   `<project_slug>` is the last component of the project root path, lowercased
   and with spaces replaced by hyphens (e.g. `my-qml-project`). This makes it
   easy to identify and stop the right task when multiple projects are running.

5. Write a `daemon.json` file in the project root to record the registration:

   ```json
   {
     "task_name":    "phd-daemon-my-qml-project",
     "interval_min": 5,
     "max_parallel": 2,
     "project_root": "/absolute/path/to/project",
     "registered":   "2026-06-17T14:00:00",
     "command":      "julia /abs/path/harness/poller.jl /abs/path/project"
   }
   ```

   This file is what `/phd:daemon stop` and `status` read to find the task.

6. Launch one immediate tick so the user can see it working right now:
   ```
   julia harness/poller.jl <project_root>
   ```

7. Report warmly:

   ```
   Daemon started. ✓

   Schedule:    every 5 minutes
   Task name:   phd-daemon-my-qml-project
   Tick command: julia /abs/path/harness/poller.jl /abs/path/project
   First tick:  ran now (see output above)

   You can close this session — the loop will continue on disk.
   Next tick:   in ~5 minutes
   Stop with:   /phd:daemon stop
   ```

**What happens at each tick (for the user's mental model):**
- The scheduler fires the tick command.
- `poller.jl` scans `runs/*/status`.
- DONE jobs are reaped: score compared to `best.json`; LEDGER.md gets a new
  KEPT or DISCARDED row; the `.reaped` marker is written; the next experiment
  is proposed and launched detached.
- FAILED or stale-heartbeat jobs are retried (up to 3 times via `--resume`),
  or discarded with "unrecoverable" if the cap is reached.
- Fresh RUNNING jobs are left alone.
- The tick process exits. The scheduler sleeps until the next interval.

**Max-parallel cap:** if `--max-parallel K` is given, the poller will count
RUNNING jobs and skip launching new ones when at the cap. Reaping always runs
regardless of the cap. The default is K=2 (suitable for a single M1 Pro laptop
without overloading the system). Increase to 4 for a desktop or workstation,
or when the toy self-test is running (it's cheap).

---

### `/phd:daemon stop`

Remove the scheduled task.

1. Read `daemon.json` from the project root to find the task name.
2. Use the `scheduled-tasks` tool to remove the task by name.
3. Delete (or rename to `daemon.json.stopped`) the `daemon.json` file.
4. Report:

   ```
   Daemon stopped. ✓
   Task phd-daemon-my-qml-project removed from the schedule.

   Running jobs (if any) will complete normally — they are detached OS processes
   unaffected by stopping the schedule. Use /phd:daemon status to check them.
   To restart: /phd:daemon start
   ```

If `daemon.json` does not exist, check `scheduled-tasks list` for any task
whose name starts with `phd-daemon-` and remove it, then warn the user that
`daemon.json` was missing (possible manual deletion or first-time stop after
an interrupted start).

---

### `/phd:daemon status`

Print a concise summary of the daemon and the current experiment state.

1. Read `daemon.json` to check if the daemon is registered. If not, note it.
2. Count jobs by status (scan `runs/*/status`):
   - RUNNING: N
   - PENDING: N
   - DONE (and reaped): N
   - FAILED: N
3. Read `best.json` for the current best score and hypothesis.
4. Read the last 3 entries from `LEDGER.md` (parse by `## H-` header lines).
5. Read `heartbeat` from any RUNNING job directory for live epoch progress.
6. Report:

   ```
   PHD Daemon Status
   -----------------
   Schedule:     every 5 minutes  [ACTIVE]
   Task name:    phd-daemon-my-qml-project

   Jobs:
     RUNNING  2   (H-041: epoch 37/100, H-042: epoch 12/100)
     PENDING  0
     DONE     18  (17 reaped)
     FAILED   1   (H-039: retry 2/3)

   Best so far:  H-037  score=0.029  (rel_L2)  2026-06-15
   Total runs:   21

   Recent ledger:
     H-040 · KEPT      score 0.031 → 0.029  (best so far)
     H-039 · DISCARDED  score 0.047  (retry in progress)
     H-038 · DISCARDED  score 0.051  (no improvement)

   Next tick:    in ~3 minutes
   ```

If the daemon is not registered:
   ```
   Daemon: NOT RUNNING  (no daemon.json found)
   Start with: /phd:daemon start
   ```
   But still show the job counts and best score — state is on disk and visible
   even without a running schedule.

---

## Important notes for implementation

### Scheduled-tasks wiring

The `scheduled-tasks` tool manages platform-appropriate scheduling (cron on
macOS/Linux, Task Scheduler on Windows). When registering:
- Use the tool's `create_scheduled_task` action with the exact shell command.
- Set the interval in minutes (not seconds) — confirm what unit the tool expects.
- The task must run in a shell that has Julia on PATH. On macOS, cron often has
  a stripped PATH; prepend the Julia bin directory explicitly:
  ```bash
  /usr/local/bin/julia /abs/path/harness/poller.jl /abs/path/project
  ```
  Find the Julia binary path with `which julia` and use that absolute path.

### Absolute paths are mandatory

Both the Julia binary path and the `poller.jl` path must be absolute in the
scheduled command. Relative paths silently fail when cron's working directory
differs from the expected location. Always use `realpath` or `abspath` before
writing to `daemon.json` and the task registration.

### The session does not need to stay open

This is the core promise of the daemon. Once `/phd:daemon start` returns, every
piece of state is on disk:
- `runs/<hid>/status` — what each job is doing
- `runs/<hid>/heartbeat` — proof of life from each epoch
- `runs/<hid>/epoch/*.ckpt` — crash-safe checkpoints every epoch
- `LEDGER.md` — permanent record of every result
- `best.json` — the current best score
- `daemon.json` — the schedule registration

The Claude session is just a window into this state. Close it, reopen it later,
and `/phd:daemon status` will show you exactly what happened while you were gone.

### Idempotency of start

If `/phd:daemon start` is called when a daemon is already registered (i.e.,
`daemon.json` exists), check whether the task is still active via the
`scheduled-tasks` tool. If active, report it and ask whether to update the
interval or leave it. If the task has been removed externally (e.g., the user
deleted it manually), re-register without complaint.

### Multiple projects

Each project gets its own task name (`phd-daemon-<slug>`), so multiple research
projects can run daemons simultaneously. Each writes to its own `runs/` and
`LEDGER.md`. The max-parallel cap is per-project.

---

## Tone

The daemon is the heartbeat of the research loop — treat it with appropriate
weight. When it starts, the user deserves to understand exactly what will happen
while they're away: what fires, how often, what the files look like, and how to
check in. When it's running, `status` should make the research feel alive. Be
specific about epoch counts, scores, and times rather than vague ("things are
running fine"). When something fails, be clear about the retry logic and when
the human needs to intervene.
