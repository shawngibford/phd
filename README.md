# PHD — Persistent Hypothesis Daemon

[![CI](https://github.com/shawngibford/phd/actions/workflows/ci.yml/badge.svg)](https://github.com/shawngibford/phd/actions/workflows/ci.yml)

A Claude Code plugin that fuses four research tools into one operating system for a PhD: **research → experiment → write → defend**.

## The four-layer thesis

PHD stacks four upstream tools without overlap: **gsd-core** (backbone) provides the phase loop and STATE/CONTEXT persistence that makes "daemon" real across sessions; **autoresearch** (loop) drives the overnight edit→measure→keep/discard experiment engine generalised for SciML/Yao.jl; **academic-research-skills** (surface) handles everything that produces the paper — lit review, citation check, outline, abstract, peer review, disclosure; and **ponytail** (governor) enforces code minimalism with an always-on anti-bloat hook so the daemon doesn't write 400 lines where 12 will do. The persistent hypothesis ledger (`LEDGER.md`) is the spine that connects all four: every experiment appends an immutable row, `/phd:write` turns KEPT rows into a results section, and `/phd:defend` compiles the verified subset into a manuscript.

## Install

```bash
claude plugin install github:shawngibford/phd
```

Or for local development:

```bash
claude --plugin-dir ./phd
```

## Commands (Slices 1–4 built)

The full `/phd:*` lifecycle is wired. Verbs: **P**robe · **H**ypothesize · **D**efend.

| Command | Verb | Does |
|---|---|---|
| `/phd:init` | — | Interactive setup → scaffolds `STATE.md`, `CONTEXT.md`, `LEDGER.md`, `experiment.md`, `runs/`, `harness/` |
| `/phd:frame` | Probe | Socratic framing → one falsifiable research question + scope, into `CONTEXT.md` |
| `/phd:probe` | Probe | Cited literature review + prior-art map + gap analysis → `paper/related-work.md` |
| `/phd:hypothesize` | Hypothesize | Turn findings into one testable hypothesis; append a PENDING row to `LEDGER.md` |
| `/phd:run` | Hypothesize | Launch a hypothesis as a multi-seed group (or `--tick` one supervisor pass) |
| `/phd:daemon` | Hypothesize | `start`/`stop`/`status` the scheduled experiment loop; session can close |
| `/phd:verify` | Defend | Reproduce KEPT rows; audit leakage / seed-robustness / baselines / citations |
| `/phd:stats` | Defend | Audit the ledger (integrity + leakage/lost-seed checks) and report keep-rate + best mean ± std |
| `/phd:analyze` | Defend | Generate figures (trajectory ± std, convergence, seed-spread) → `paper/figures/` |
| `/phd:write` | Defend | Draft the results section (mean ± std, figures) from verified KEPT rows |
| `/phd:review` | Defend | Dual review: code over-engineering (governor) + manuscript peer review |
| `/phd:defend` | Defend | Gate → compile → AI-disclosure → export the final manuscript |

Experiments run over **K seeds** (`seeds_per_hypothesis`, default 3); results are kept on the
**mean ± std** and figures lead with error bars — single-seed point estimates are never reported.

**Skills** (auto-trigger, no slash): `code-minimalism` (governor), `experiment-loop` (loop
protocol), and the academic surface `academic-paper`, `academic-paper-reviewer`,
`academic-pipeline`, `deep-research`.

**Subagents** (fresh 200k context): `experiment-runner` (proposes the next experiment),
`plan-executor`, `research-architect`, `synthesis`, `report-compiler`.

> **License note:** the academic surface lives under `skills/surface/` (CC BY-NC 4.0) — so
> `/phd:probe`, `/phd:review`, and `/phd:defend` are non-commercial. Remove `skills/surface/`
> and those three commands for a fully-MIT build (see [NOTICE.md](NOTICE.md)).

## Quick start

```bash
cd my-research-project
claude --plugin-dir /path/to/phd
/phd:init
```

Answer the six setup questions. Then copy the Julia harness into `harness/` (see `harness/SETUP.md`) and run `/phd:run` to kick off your first experiment.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design: language tiers, the four-layer stack, the experiment loop protocol, detached-job lifecycle, per-epoch checkpointing, the LEDGER row format, and the build plan.

## Tests

The Julia harness has a stdlib-`Test` suite (no third-party deps) covering the metric/aggregation/Welch logic, JSON + job-control helpers, and a fixture-based group reap:

```bash
julia harness/test/runtests.jl
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs it on every push/PR to `main`, plus a manifest/hooks lint.

## License

PHD's own glue code is MIT. It bundles components under different licenses — see [NOTICE.md](NOTICE.md). Because academic-research-skills is CC BY-NC 4.0, **PHD as a whole is non-commercial**.
