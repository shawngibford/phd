# NOTICE — Academic Research Surface

The skills and agents in this directory implement the **academic surface** layer
of PHD: the lit-review → outline → draft → peer-review → disclosure pipeline that
produces *the paper*.

## Attribution

This surface follows the design, scope, and skill/agent decomposition of:

**academic-research-skills** — Copyright Imbad0202 and contributors.
Licensed under Creative Commons Attribution-NonCommercial 4.0 International.
<https://github.com/Imbad0202/academic-research-skills>

These PHD-native prompts were re-authored for the Quantum-ML / SciML research
domain and to integrate with the PHD ledger spine (`LEDGER.md`), the verification
gate (`/phd:verify`), and the `code-minimalism` governor. Changes were made from
the upstream; per the license, those changes are indicated here.

## License

CC BY-NC 4.0 — see `LICENSE` in this directory. This license governs everything
under `skills/surface/`. The PHD repository-root `NOTICE.md` explains how this
makes the combined PHD distribution non-commercial, and how to strip the surface
for a fully-MIT build.

## What lives here

| Skill / agent | Role | Wired into |
|---|---|---|
| `academic-paper/` | Draft and section a manuscript from verified results | `/phd:write`, `/phd:defend` |
| `academic-paper-reviewer/` | Adversarial peer review of a draft | `/phd:review` |
| `academic-pipeline/` | Orchestrate the full lit-review→draft→review→compile flow | `/phd:probe`, `/phd:defend` |
| `deep-research/` | Cited literature search + gap analysis, anti-fabrication | `/phd:probe` |
| `../../agents/research-architect.md` | Plan the literature search & prior-art map | `/phd:probe` |
| `../../agents/synthesis.md` | Synthesize sources into a structured findings memo | `/phd:probe` |
| `../../agents/report-compiler.md` | Assemble + format the final manuscript for export | `/phd:defend` |

> The three agents physically live in the plugin's top-level `agents/` directory
> (where Claude Code discovers subagents) but are part of this CC BY-NC surface and
> carry the same attribution and license as the skills above.
