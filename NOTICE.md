# NOTICE — PHD Attribution and License Map

PHD is a curated merge of four upstream projects. Each component retains its
original license. The most restrictive license governs the combination.

---

## License map

| Component | Source | License | What PHD takes |
|---|---|---|---|
| PHD glue code | this repo (`plugin.json`, `commands/`, `templates/`, `hooks/`, `agents/` except surface) | **MIT** | The integration layer you are reading |
| gsd-core | [open-gsd/gsd-core](https://github.com/open-gsd/gsd-core) | MIT | Phase-loop command prompts, STATE/CONTEXT artifact pattern, plan-executor agent prompt |
| autoresearch | [karpathy/autoresearch](https://github.com/karpathy/autoresearch) | MIT | Loop protocol + `program.md` → `experiment.md` pattern; generalised for SciML/Yao.jl |
| ponytail | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | Compact minimalism ruleset → `code-minimalism` skill; one `UserPromptSubmit` anti-bloat hook |
| academic-research-skills | [Imbad0202/academic-research-skills](https://github.com/Imbad0202/academic-research-skills) | **CC BY-NC 4.0** | 4 skills, 3 agents, 10 commands — lives under `skills/surface/` with its own LICENSE + NOTICE |

---

## Effective license of PHD as a whole

**PHD is non-commercial.**

Because `academic-research-skills` is licensed under
[Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/),
and PHD bundles that content in `skills/surface/`, the combined work is
subject to the NC restriction.

**You may:**
- Use PHD for your own academic or personal research, free of charge.
- Share and adapt PHD for non-commercial purposes, with attribution.

**You may not:**
- Sell PHD or a product that incorporates PHD.
- Relicense PHD under MIT or any other license that permits commercial use.

The content in `skills/surface/` carries its own `LICENSE` and `NOTICE` files
(added in Slice 3) attributed to Imbad0202. If you need a commercial-friendly
version, remove `skills/surface/` entirely — the remaining components are all
MIT and the combination becomes fully MIT.

---

## Attribution

**gsd-core** — Copyright open-gsd contributors. MIT License.
<https://github.com/open-gsd/gsd-core>

**autoresearch** — Copyright Andrej Karpathy and contributors. MIT License.
<https://github.com/karpathy/autoresearch>

**ponytail** — Copyright Dietrich Gebert. MIT License.
<https://github.com/DietrichGebert/ponytail>

**academic-research-skills** — Copyright Imbad0202 and contributors.
Creative Commons Attribution-NonCommercial 4.0 International.
<https://github.com/Imbad0202/academic-research-skills>

---

## PHD glue code copyright

Copyright 2026 shawn (gibfords@gmail.com). MIT License — see LICENSE.
