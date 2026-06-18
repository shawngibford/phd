# PHD — Persistent Hypothesis Daemon

**Architecture & integration design — v0.1 (design pass, pre-scaffold)**

A single Claude Code plugin that fuses four upstream tools into one research operating
system for a PhD: research → build/experiment → write → defend. Curated merge — only the
non-overlapping core of each repo is vendored; everything host-specific or redundant is
dropped.

Domain tuning: **Quantum ML / SciML** (qGANs, qLNNs, qAANs). **Julia-only** — SciML for
dynamics/optimization, Yao.jl + YaoML.jl for quantum (Julia-native). Hardware-adaptive:
detects available compute (Apple MPS via Metal.jl, CPU threads, CUDA if present) and runs the
experiment search on the most efficient backend, parallelized across the search axis.

> qTinyRecursive Protein LM (QTRPLM) is a **separate project** — a *target* PHD helps you
> build, not part of PHD's own harness. PHD ships no Python; it can still drive Python/torch
> work in any project it operates on.

---

## 0. Languages — what is written in what

Three tiers, deliberately different languages. The plugin is *not* a Julia program; it's a
prompt bundle that drives Julia compute.

| Tier | What | Language | Why |
|---|---|---|---|
| 1. The PHD plugin (glue) | `plugin.json`, `commands/*.md`, `skills/*`, `agents/*.md` | **JSON + Markdown** | Claude Code plugins *are* prompts + manifest, not compiled code |
| 1b. Hooks | `hooks/*.mjs` (2 files, ~30 LOC total) | **Node.js** | Matches ponytail + gsd-core convention; Node is ubiquitous; runs per-prompt so startup must be fast |
| 2. The harness | `harness/*.jl` (device, metric, runner, poller, supervisor) | **Julia** | All real orchestration + compute: launch, checkpoint, poll, score |
| 3. Your models | qGAN / qLNN / qAAN in Yao.jl + SciML | **Julia** | Your research artifacts; PHD runs and iterates them, never authors them for you |

**Julia is the language of all compute and every model.** The plugin wrapping it is Markdown +
JSON + a sliver of Node. No Rust, Go, or Mojo anywhere.

---

## 1. Thesis: four tools, four non-overlapping layers

The reason this merges without bloat is that each repo owns a *distinct* layer. They do not
compete; they stack.

```
            ┌──────────────────────────────────────────────────────────┐
   GOVERNOR │  ponytail  →  code-minimalism skill + 1 hook + /phd:review │  (always-on)
            ├──────────────────────────────────────────────────────────┤
    SURFACE │  academic-research-skills  →  probe · write · review · defend
            │  (lit-review, citation-check, outline, abstract, peer-review, disclosure)
            ├──────────────────────────────────────────────────────────┤
       LOOP │  autoresearch  →  /phd:run + experiment-runner agent
            │  (edit → run ≤T → measure → keep/discard, QML/SciML metric contract)
            ├──────────────────────────────────────────────────────────┤
   BACKBONE │  gsd-core  →  phase loop + fresh-context subagents + STATE/CONTEXT
            │  (fights context rot; persists state across sessions = the "daemon")
            └──────────────────────────────────────────────────────────┘
```

| Layer | From | Owns | One-line role |
|---|---|---|---|
| Backbone | `open-gsd/gsd-core` (MIT) | Orchestration, context engineering, persistence | The phase loop + subagent discipline that keeps long projects coherent |
| Loop | `karpathy/autoresearch` (MIT) | Autonomous experiment iteration | The overnight edit→measure→keep/discard engine |
| Surface | `Imbad0202/academic-research-skills` (CC BY-NC 4.0) | Research & manuscript pipeline | Everything that produces *the paper* and verifies its claims |
| Governor | `DietrichGebert/ponytail` (MIT) | Code/scope discipline | Stops the daemon from writing 400 lines where 12 will do |

The **"Persistent Hypothesis Daemon"** name = the loop layer (autoresearch) running *on top
of* the persistence layer (gsd STATE/CONTEXT). The daemon keeps a hypothesis ledger that
survives session boundaries and runs experiments unattended; the backbone is what makes
"persistent" real.

---

## 2. What gets dropped (the anti-bloat budget)

Curated merge means we vendor *concepts and prompts*, not build systems. Hard cuts:

**gsd-core** — it ships as a ~85% JS/TS npm package with a multi-runtime installer.
- DROP: npm package, installer, `eslint-rules/`, `stryker.config`, build tooling, the 5 i18n
  READMEs, OpenCode/Gemini/Cursor/Windsurf/Kimi/Codex adapters.
- KEEP (as markdown): the phase-loop command prompts, the executor/planner subagent prompts,
  and the `STATE.md` / `CONTEXT.md` artifact templates. Re-authored for research, not shipping.

**autoresearch** — it's nanochat training code for a single NVIDIA H100.
- DROP: `train.py`, `prepare.py`, nanochat model, GPU-specific assumptions, `val_bpb` metric.
- KEEP (as pattern): the loop protocol and the `program.md` → editable-instructions idea,
  generalized into a `experiment.md` + a metric **contract** (§5) so it works for SciML.

**academic-research-skills** — keep most of it; it *is* the surface.
- DROP: `ars-mark-read` / `ars-unmark-read` (Zotero read-tracking — niche), the i18n READMEs.
- KEEP: 4 skills (`academic-paper`, `academic-paper-reviewer`, `academic-pipeline`,
  `deep-research`), 3 agents (`research_architect`, `synthesis`, `report_compiler`), and core
  commands (`plan`, `lit-review`, `citation-check`, `outline`, `abstract`, `reviewer`,
  `revision`, `revision-coach`, `disclosure`, `format-convert`).
- LICENSE BOUNDARY: this content is CC BY-NC 4.0. It lives in `surface/` with its own
  `LICENSE` + `NOTICE`, attributed to Imbad0202. Consequence: **PHD as a whole is
  non-commercial.** Fine for personal/academic use; it cannot be sold or relicensed MIT.

**ponytail** — keep the governor, drop the 13-agent portability matrix.
- DROP: `.cursor/`, `.windsurf/`, `.clinerules/`, `.kiro/`, `.codex-plugin/`, `.opencode/`,
  `gemini-extension.json`, `pi-extension/`, benchmarks.
- KEEP: the compact ruleset as an always-on `code-minimalism` skill, one `UserPromptSubmit`
  hook (default `lite`), and `/phd:review` (folds in ponytail-review + ponytail-debt ledger).

Net: ~4 repos, hundreds of files each → one plugin, **~30–40 markdown/JS files**.

---

## 3. Command surface (unified `/phd:*`)

Ten commands map the research lifecycle onto the three PHD verbs — **P**robe · **H**ypothesize
· **D**efend — with the backbone phase loop underneath.

| Command | Verb | Merges | Does |
|---|---|---|---|
| `/phd:init` | — | gsd-new-project + autoresearch setup | Scaffold a research project: `STATE.md`, `CONTEXT.md`, `LEDGER.md`, `experiment.md`, `harness/`, `paper/` |
| `/phd:frame` | Probe | ars `plan` + gsd `discuss` | Socratic problem framing → falsifiable research question + scope |
| `/phd:probe` | Probe | ars `lit-review` + `deep-research` skill + `research-architect` | Literature review, gap analysis, prior-art map (cited, anti-fabrication) |
| `/phd:hypothesize` | Hypothesize | gsd `plan` | Convert findings → testable hypothesis + experiment plan; append to `LEDGER.md` |
| `/phd:run` | Hypothesize | autoresearch loop + `experiment-runner` | One experiment or a batch: edit→run≤T→measure→keep/discard against the metric contract |
| `/phd:daemon` | Hypothesize | autoresearch (persistent) | `start/stop/status` — registers a `scheduled-tasks` tick that runs the detached-job poller loop (§5.2); session can be closed |
| `/phd:run --tick` | Hypothesize | poller | One pass of the supervisor loop: reap done jobs → keep/discard → launch next. Fired by the schedule. |
| `/phd:verify` | Defend | gsd `verify` + ars `citation-check` | Reproduce kept results; flag p-hacking, leakage, unsupported claims, fabricated cites |
| `/phd:write` | Defend | `academic-paper` skill + `outline` + `abstract` | Draft/section the manuscript from the ledger + verified results |
| `/phd:review` | Defend | ponytail-review + ars `reviewer`/`revision-coach` | Dual review: code over-engineering (governor) + manuscript peer-review |
| `/phd:defend` | Defend | gsd `ship` + `report_compiler` + `disclosure` + `format-convert` | Compile, final citation pass, AI-disclosure statement, export (LaTeX/PDF/docx) |

Skills (model-invoked, auto-trigger — no slash needed): `code-minimalism`, `academic-paper`,
`academic-paper-reviewer`, `academic-pipeline`, `deep-research`, `experiment-loop`.

Subagents (fresh 200k context, spawned by commands): `research-architect`, `synthesis`,
`report-compiler`, `experiment-runner`, `plan-executor`.

Hooks: ponytail anti-bloat (`UserPromptSubmit`, default `lite`); STATE/CONTEXT injector
(`SessionStart`) that loads `STATE.md` + `LEDGER.md` summary so the daemon is "persistent".

---

## 4. Directory layout

```
phd/
├── .claude-plugin/
│   └── plugin.json                 # manifest: name=phd, commands/skills/agents/hooks
├── README.md
├── LICENSE                         # MIT (PHD's own glue code)
├── NOTICE.md                       # attribution to all 4 upstreams + license map
├── commands/
│   └── phd/                        # /phd:init, frame, probe, hypothesize, run,
│       └── *.md                    #   daemon, verify, write, review, defend
├── skills/
│   ├── code-minimalism/            # ← ponytail ruleset (MIT)
│   ├── experiment-loop/            # ← autoresearch pattern (MIT), SciML-generalized
│   └── surface/                    # ← academic-research-skills (CC BY-NC 4.0)
│       ├── LICENSE  NOTICE         #   license boundary lives here
│       ├── academic-paper/
│       ├── academic-paper-reviewer/
│       ├── academic-pipeline/
│       └── deep-research/
├── agents/
│   ├── research-architect.md       # ← ars
│   ├── synthesis.md                # ← ars
│   ├── report-compiler.md          # ← ars
│   ├── experiment-runner.md        # ← autoresearch (loop executor)
│   └── plan-executor.md            # ← gsd (fresh-context executor)
├── hooks/
│   ├── ponytail.mjs                # anti-bloat (lite default)
│   └── state-inject.mjs            # SessionStart: load STATE.md + LEDGER summary
├── templates/
│   ├── STATE.md  CONTEXT.md        # ← gsd artifacts (re-authored for research)
│   ├── LEDGER.md                   # hypothesis ledger (the daemon's memory) — §6
│   └── experiment.md               # ← autoresearch program.md, SciML-tuned — §5
└── harness/                        # QML/SciML scaffolding dropped into new projects
    ├── metric.jl                   # Julia metric contract — SciML + Yao.jl/YaoML.jl quantum
    ├── device.jl                   # hardware autodetect → CPU threads (v1) (§5.1)
    ├── runner.jl                   # ≤T-budget driver: launches DETACHED jobs, checkpoints per epoch
    ├── poller.jl                   # watches job dirs, fires next action on completion (§5.2)
    └── supervisor.jl               # the daemon loop: launch → poll → keep/discard → propose next
```

---

## 5. The experiment loop, generalized for QML/SciML

autoresearch hardcodes `val_bpb` over a fixed 5-min **NVIDIA-GPU** budget. We replace *both*
assumptions: a **metric contract** so the loop drives any objective, and a **device layer**
(§5.1) so it runs on whatever hardware is actually present — your M1 Pro included.

With Yao.jl + YaoML.jl, quantum is **Julia-native**, so Julia is the only language in the
harness. The loop drives differential-equation surrogates, Yao.jl circuits (qGAN/qLNN/qAAN),
and SciML optimization uniformly.

Contract (what `/phd:run` and `experiment-runner` expect a project to expose):

```julia
# harness/metric.jl  — Julia / SciML side
"""Lower is better. Must be vocab/scale-independent and reproducible under fixed seed."""
struct ExperimentResult; score::Float64; wall_s::Float64; meta::Dict{String,Any}; end

evaluate(model, data; budget_s::Float64)::ExperimentResult
# default scores for SciML:
#   relative L2 on held-out trajectory  |û−u|₂ / |u|₂
#   energy/invariant drift for Hamiltonian/conservative systems
#   NLL or CRPS for probabilistic time-series (bioreactor/fermentation)
```

```julia
# harness/metric.jl (quantum, Yao.jl/YaoML.jl) — quantum-advantage ratio
#   score = cost_quantum / cost_classical_baseline    (< 1 ⇒ advantage)
# report it HONESTLY: if no baseline beats classical, the ledger records "no advantage".
# Yao.jl gives exact statevector + AD gradients, so the classical baseline runs in-process.
```

### 5.1 Device layer + parallelism (`device.jl`, `runner.jl`)

`device.jl` probes the machine once and returns a ranked backend list. On your M1 Pro the
realistic picture — stated plainly, not optimistically:

| Backend | Reachable from Julia | Covers | M1 Pro reality |
|---|---|---|---|
| CPU threads | `Threads`, BLAS, `KernelAbstractions.jl` | everything | **primary** — 8P+2E cores, the workhorse |
| Apple GPU (MPS) | `Metal.jl` | dense array ops | partial — Yao/SciML GPU paths on Metal are immature; use only where a kernel is verified faster |
| CUDA | `CUDA.jl` / `CuYao` | quantum + SciML | **absent** on this machine; auto-selected only if a CUDA device appears |

**v1 decision: CPU threads only.** `device.jl` ships CPU-only — the mature path on M1. The
backend is still recorded per experiment in the ledger, and the table above documents the
extension points (Metal/CUDA) for later, but no GPU selection code lands in v1.

**Parallelism — where it pays, where it doesn't (candor):**
- ✅ **Across the search** — run K independent experiments concurrently, each pinned to a
  thread group. This is the real speedup and matches autoresearch's "100 experiments/night."
- ⚠️ **Cap K honestly.** On one M1 Pro, K experiments share L2/memory bandwidth; throughput
  saturates well before K = core count. `runner.jl` sets `K = clamp(perf_cores ÷ threads_per_exp, 1, 4)`
  by default and the scheduler measures effective throughput, backing off if added workers stop
  helping. More workers ≠ faster past that knee.
- ❌ **Within one experiment on a single GPU** — no win. One MPS device can't run N circuits
  in true parallel; serializing through it just adds contention. So we parallelize the search,
  thread *inside* an experiment (BLAS / batched statevector), and leave the device to one
  worker group at a time.

Net: "most efficient hardware, parallelized" = **autodetected backend + parallel experiment
search with a measured, capped worker pool** — not GPU magic the Apple/Julia stack can't yet
deliver.

### 5.2 Detached jobs, polling, crash-safe checkpointing

The daemon never runs inside the Claude session or inside the harness call. Experiments are
**detached OS processes**; the harness only *launches* and *reads files*. A poller watches for
completion and fires the next action. This is what makes the loop survivable: a crash kills one
job, not the run, and never the ledger.

**Job lifecycle (file-based, atomic, external to the harness):**

```
runs/
└── h007/
    ├── job.json        # spec: hypothesis id, diff to apply, budget T, backend, seed, K
    ├── status          # PENDING → RUNNING → DONE | FAILED   (atomic rename, never partial)
    ├── heartbeat       # epoch index + unix-ts, rewritten every epoch (staleness = crash)
    ├── epoch/
    │   ├── 0001.ckpt   # model params + optimizer state + RNG state  ← per-epoch, crash-safe
    │   ├── 0001.json   # metrics this epoch (loss, score-so-far, wall_s)
    │   └── ...         # written BEFORE status flips; last good ckpt always recoverable
    ├── result.json     # final ExperimentResult {score, wall_s, meta, backend}
    └── stdout.log / stderr.log
```

**Per-epoch checkpointing is mandatory, not optional.** `runner.jl` writes `epoch/NNNN.{ckpt,json}`
and updates `heartbeat` at the end of every epoch, *flushed to disk before* the loop continues.
If training dies mid-run (OOM, kernel panic, lid close), no data is lost beyond the in-flight
epoch, and the job can resume from the last `.ckpt`.

**Poller / supervisor loop (`poller.jl` + `supervisor.jl`):**
1. Scan `runs/*/status`.
2. `DONE` → read `result.json` → compare to best → **keep** (commit + ledger row) or **discard**
   (ledger row + reason) → propose next experiment from `experiment.md` → launch detached.
3. `FAILED`, **or** `RUNNING` with a stale heartbeat (> 2× median epoch time) → mark `FAILED`,
   then **resume** from the latest `epoch/NNNN.ckpt` (relaunch with `--resume`) up to a retry
   cap; after the cap, discard with reason "unrecoverable" and move on. The run never stalls.
4. `RUNNING` fresh → leave it.

**Who fires the poller** (resolves the "Claude can't run unattended" problem): the
`scheduled-tasks` tool runs `/phd:run --tick` every N minutes; each tick is one pass of the
loop above and exits. `/phd:daemon start` registers that schedule; `stop` removes it; `status`
summarizes `runs/` + ledger. The session does not need to stay open — state lives entirely on
disk, which is exactly the gsd "persistence" layer doing its job.

Loop protocol (autoresearch, unchanged in spirit):
1. Read `experiment.md` (the human-edited "research org" instructions).
2. Propose one change to the model/optimizer/architecture (one diff, reviewable).
3. Run under fixed wall-clock budget `T` (default 5 min; configurable per hardware).
4. `evaluate()` → score. Compare to current best.
5. **Keep** if improved (commit + ledger entry), else **discard** (ledger entry, with reason).
6. Repeat. In `daemon` mode, loop until stopped; ~`K · 3600/T` experiments per hour, where `K`
   is the measured-safe parallel worker count from §5.1.

> **Candor flag.** Quantum advantage is the metric most prone to self-deception. The contract
> *requires* a classical baseline in `meta`; `/phd:verify` refuses to mark a quantum result
> "kept-with-advantage" unless a fairly-tuned classical baseline is present and beaten. No
> baseline ⇒ logged as "speculative, no advantage demonstrated."

---

## 6. The hypothesis ledger (what makes it "persistent")

`LEDGER.md` is the daemon's long-term memory and the spine that connects loop → paper. Every
experiment appends an immutable row; `/phd:write` reads it to build the results section.

```markdown
## H-007 · 2026-06-17 · KEPT
hypothesis: QLNN with adaptive τ-gating lowers rel-L2 on the fermentation ODE vs fixed τ
change: replaced fixed time-constant with learned per-neuron τ (12 LOC)
metric: rel_L2  0.041 → 0.029   (best so far)   budget: 300s   seed: 1337
baseline: classical Neural-ODE 0.034 → quantum BEATS classical ✓
artifacts: runs/h007/  commit: a1b2c3d
note: τ collapses to ~0 for 3 neurons → candidate for pruning (see H-008)
```

`/phd:verify` reproduces KEPT rows; `/phd:write` cites them; `/phd:defend` filters to the
subset that survived verification. Discarded hypotheses stay in the ledger (negative results
are data, and protect against re-testing dead ends across sessions).

---

## 7. Build plan — thin vertical slice first

Decision: validate the **ledger spine end-to-end** on a minimal command set before vendoring
the full academic surface. The slice is `init → run → write`, proving loop → ledger → draft
round-trips with crash-safe jobs. Everything else is layered on only after the spine holds.

**Slice 1 — vertical spine (the validation gate):**
1. `plugin.json`, dir tree, `/phd:init`, STATE/CONTEXT/LEDGER/experiment templates, NOTICE +
   license boundary.
2. Harness: `device.jl` (CPU-only), `metric.jl` contract, `runner.jl` (detached + per-epoch
   checkpoint), `poller.jl` + `supervisor.jl`. `/phd:run`, `/phd:run --tick`, `/phd:daemon`.
3. `/phd:write` — minimal results-section draft straight from `LEDGER.md`.
4. **Gate:** dry run on a toy SciML project (Lotka–Volterra surrogate). Confirm: parallel
   search runs detached; a killed job resumes from last `.ckpt`; KEPT rows reach the draft.
   *Do not proceed until this passes.*

**Slice 2 — governor + backbone:** ponytail → `code-minimalism` skill + hook; gsd phase-loop
prompts + `plan-executor` agent; `/phd:frame`, `/phd:hypothesize`, `/phd:verify`.

**Slice 3 — full academic surface:** vendor ars skills/agents/commands under `skills/surface/`;
wire `/phd:probe`, `/phd:review`, `/phd:defend`.

---

## 8. Locked decisions

1. **Daemon = detached jobs + scheduled poller.** Experiments run as detached external
   processes; `/phd:daemon` registers a `scheduled-tasks` tick that runs the supervisor loop
   (§5.2). Jobs are external to the harness; the session can be closed. Per-epoch checkpointing
   is mandatory and crash-safe.
2. **CPU-only for v1.** No Metal/CUDA selection code; `device.jl` ships CPU-threads only.
   Extension points documented in §5.1 for later.
3. **Thin vertical slice first.** Build + validate the `init → run → write` ledger spine
   (Slice 1, §7) before vendoring the full academic surface.
4. **`/phd:frame` keeps the full Socratic dialogue.** Radical conciseness applies to *code*,
   not to the framing/research dialogue.
```
