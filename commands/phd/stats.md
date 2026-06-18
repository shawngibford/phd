---
description: Audit the hypothesis ledger and report project statistics. Runs the Julia report tool to cross-check ledger integrity (KEPT rows have artifacts, no held-out seed 1337 leakage, no lost seeds, monotone best, well-formed rows) and summarize lifetime stats (experiment count, keep rate, best mean ± std). Read-only over the ledger; surfaces integrity issues as actionable warnings.
argument-hint: (no args)
---

# /phd:stats — Ledger audit & project statistics

You give the researcher an honest, at-a-glance read of the experiment record and flag anything that
would undermine the paper. This is a deterministic audit, not a vibe check — it runs the harness.

---

## What to do

1. **Resolve the project root** (the directory with `runs/`, `LEDGER.md`) — same rule as `/phd:run`:
   the open workspace, else `project_root:` in `CONTEXT.md`, else ask.

2. **Run the audit:**
   ```
   julia harness/report.jl audit <project_root>
   ```
   It reports experiment counts (KEPT / DISCARDED / total groups), keep rate, the best result
   (mean ± std, n), and an **integrity** section. The integrity checks are:
   - every KEPT `H-NNN` has a `runs/hNNN/` artifact dir with a `result.json`,
   - no row's run `seeds:` include **1337** (the held-out eval seed — a leakage red flag),
   - no group lost seeds (`n` < the group's requested `seeds_per_hypothesis`),
   - the best score is monotone across KEPT rows (each KEPT actually improved),
   - no malformed/unparseable metric lines.

   If Julia or the harness isn't present, say so and stop (point to `harness/SETUP.md`).

3. **Relay the report**, then **interpret the findings** for the user. Integrity findings are
   warnings, not crashes — explain what each means and the fix (e.g. "H-012 used seed 1337; that's
   the held-out trajectory — re-run with other seeds and discard the leaked result before citing
   it"). If the audit is clean, say so plainly.

---

## Hard rules

1. **Never modify `LEDGER.md` or any artifact.** This command only reads and reports.
2. **Don't hand-wave integrity findings.** A 1337-leakage or missing-artifact finding is serious —
   surface it prominently; it can invalidate a result headed for the paper.
3. **Report the numbers as given.** Keep rate, best mean ± std, and counts come from the harness —
   relay them faithfully, don't recompute or round away the ± std.
