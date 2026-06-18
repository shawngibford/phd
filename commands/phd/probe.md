---
description: Map the literature and prior art for the project's research question. Plans a search (research-architect), runs cited source discovery (deep-research skill), and synthesizes findings into a related-work foundation with a gap analysis (synthesis), writing paper/related-work.md. Anti-fabrication — every citation resolves to a real source. The Probe verb. Surface layer, CC BY-NC 4.0.
argument-hint: [optional focus, e.g. "classical baselines" or "qLNN prior art"]
---

# /phd:probe — Literature review & prior-art map

You are running the **Probe** phase: finding out what is already known so the project's
contribution is positioned honestly against prior work. This command coordinates the
academic surface — it plans, searches, and synthesizes, and it never fabricates a source.

> Surface command (CC BY-NC 4.0). It depends on `skills/surface/` and the
> research-architect / synthesis agents. If those are absent, this command is inert.

---

## Step 1 — Orient

Read `CONTEXT.md` for the research question and background. If there is no sharp,
falsifiable question yet, recommend `/phd:frame` first — a literature map without a
question to map *against* wanders. If `$ARGUMENTS` gives a focus, scope the probe to it
(e.g. only the classical-baseline literature).

## Step 2 — Plan the search

Spawn the **research-architect** agent (fresh context) with the research question. It
returns a search plan: themes, query angles, venues/authors, and the prior-art questions
the review must answer. Review the plan; tighten it if a theme is missing.

## Step 3 — Execute cited discovery

Hand the plan to the **deep-research** skill. It runs the broad-then-deep search using
the available web/search tools, reads the strongest sources, and extracts claims with
verifiable citations. Enforce the anti-fabrication rule throughout: a source that can't
be confirmed real is logged as an *unconfirmed lead*, never cited.

## Step 4 — Synthesize

Spawn the **synthesis** agent with the gathered sources. It writes
`paper/related-work.md`: themed synthesis (cited inline), points of agreement and
disagreement, a real references list, and a 2–4 sentence **gap analysis** ending in how
this project's question addresses the gap.

## Step 5 — Report

> "Probe complete → `paper/related-work.md`.
>   Themes covered: <list>
>   Sources cited: N (M unconfirmed leads kept separate)
>   The gap: <one sentence>
>
> This related-work foundation feeds the introduction (`/phd:write`) and the final
> manuscript (`/phd:defend`). Next: `/phd:hypothesize` to plan the first experiment that
> attacks the gap, or expand the probe with a focus argument."

If phase tracking is in use, set `phase: Probe` in `STATE.md` (don't clobber other fields).

---

## Hard rules

1. **Every citation resolves to a real source.** Unconfirmed leads are listed separately, never cited as fact.
2. **Search, don't recall.** Use the tools for current literature; memory seeds the search, it isn't the source.
3. **Cover the baseline.** The prior-art map must include the strongest classical baseline — the advantage claim depends on it.
4. **Don't touch `LEDGER.md`.** Probing produces no experiment row.
