---
name: deep-research
description: Cited literature search and prior-art mapping for academic work. Auto-applies when surveying related work, finding prior art, or building a references list for a research question. Runs broad-then-deep source discovery, extracts verifiable claims with citations, and produces a gap analysis — with a hard anti-fabrication rule: every reference must resolve to a real, locatable source. CC BY-NC 4.0 (see ../LICENSE).
---

# deep-research — cited literature review

The literature engine behind `/phd:probe`. You map what is already known against the
project's research question, find the gap the project fits into, and produce a sourced
related-work foundation the manuscript can build on. **Every citation must be real.**

CC BY-NC 4.0 — surface layer, attributed to academic-research-skills (../NOTICE.md).

---

## Method

1. **Scope from the question.** Read `CONTEXT.md` for the research question and
   background. Derive the search themes (the method, the baseline, the domain/system).
2. **Broad sweep.** Search multiple angles — by method, by application domain, by the
   baseline being challenged, by key authors. Use the available web/search tools; do not
   rely on memory for what exists. Breadth first.
3. **Deep read.** For the most relevant hits, fetch and read the actual source. Extract:
   the claim, the method, the reported result, and the precise citation (authors, year,
   venue, DOI/URL).
4. **Map the gap.** Position the project's question against what you found: what's been
   done, what's been assumed, what's unaddressed — the gap the project occupies.

## Output → `paper/related-work.md`

- A structured related-work synthesis grouped by theme, each claim followed by its
  citation.
- A **references list** where every entry resolves to a locatable source.
- A short **gap analysis**: 2–4 sentences naming what prior work leaves open and how
  the project's question addresses it.

## Anti-fabrication (the hard part)

1. **No invented sources.** Never fabricate a title, author, year, venue, or DOI. If you
   cannot confirm a source exists, do not cite it — list it as "unconfirmed lead" instead.
2. **Quote-or-paraphrase faithfully.** Don't attribute a claim to a paper you didn't read.
3. **Mark confidence.** If a claim is inferred rather than directly stated in a source,
   say so. `/phd:verify`'s citation check will later test every reference — fabrications
   get caught, so don't create them.
4. **Prefer primary sources** over secondary summaries; cite the original where possible.

## Hard rules

1. **Every citation resolves to a real source.** This is the whole point — a fabricated reference is the worst possible output.
2. **Search, don't recall.** Use the tools to find current literature; memory is a starting point, not a source.
3. **Separate confirmed from unconfirmed.** Leads you couldn't verify go in their own list, never in the references.
