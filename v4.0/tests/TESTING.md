# ldgr v4.0 — Test Coverage

Summary of what the test suite verifies. Baseline suite (`test_checks_basic.jl`,
`test_checks_hints.jl`, `test_endtoend.jl`) covers the core Warnings Guide
checklist. `test_checks_edge.jl` and `test_endtoend_edge.jl` extend that with
edge cases and combinations found during a review pass — several of which
surfaced real bugs, since fixed (see "Bugs found and fixed" below).

## `test_checks_basic.jl` / `test_checks_hints.jl`
Unit-level, one `check_day` call per case. Baseline coverage: each Level 1–4
warning code firing on its own (negative figure, overspend, blank closing,
bad format, day imbalance, overnight mismatch, missing prior day, genesis,
closed day), plus the three hint types (divisible-by-9, matches an entered
figure, decimal-slip-by-9x).

## `test_checks_edge.jl`
Unit-level, cases not in the baseline suite:
- Bad number format (L1-D) on a journal key, a cash-book key, and `NaN` in a
  journal key — previously untested anywhere in the suite.
- Two Stops firing at once (negative figure + future date).
- Two hints matching the same difference simultaneously.
- All the meaningful Level 2 / Level 3 combinations that `check_day`'s
  branching allows: imbalance + no prior day, imbalance + genesis, imbalance
  + a ledger already existing, a closed day re-entered where a ledger
  already exists, a genesis day re-entered where a ledger already exists,
  and a closed day with no prior/not genesis (confirms closed days are
  exempt from the "no prior day" notice by design).
- All-zero day; very large figures.
- A genesis day that is also closed.

## `test_endtoend_edge.jl`
File-backed, multi-day chain scenarios (own `LEDGER_ROOT`, run in sequence):
- A gap occurring immediately after genesis.
- A closed day filling a gap, including confirming the released day's
  overnight variance is correctly **recomputed** against the real prior
  closing balance rather than replaying the stale value from first entry.
- Multiple closed days spanning a month boundary.
- A closed day sitting immediately before a separate gap.
- The leap-year Feb 29 → Mar 1 boundary.
- Re-entering the same day twice with `--force` (idempotency).
- Re-entering a day under a different status (trading ↔ closed) —
  exploratory, no defined expected behaviour; documents current output for
  manual review.
- The release-time reason gate: a day held on a gap that turns out, once
  recomputed, to have a genuine overnight discrepancy is **not**
  auto-released without a reason, and releases correctly once one is given.
- Cascading release across a multi-day (3-day) gap, filled forward in
  chronological order: each intermediate day posts normally on its own, and
  the originally-held day only releases once the true gap closes.

## Bugs found and fixed during this pass
1. **`/api/check` crashed on `NaN`** — the live preview endpoint threw
   whenever the opening balance was still blank (the default state of a
   fresh day). Fixed: `predicted` is now `nothing` for any non-finite value,
   not just for closed days.
2. **A Level-1 Stop and a Level-3 notice could fire together with
   contradictory text** — a blocked day could show "the day itself is
   saved" right next to the Stop that blocked it. Fixed: the L3-D/L3-A
   notices are now gated on no Stop being present.
3. **Filling a gap didn't recompute the released day's overnight variance**
   — it replayed the stale `0.0` computed at first entry (when the prior
   day didn't exist yet) instead of checking it against the real prior
   closing balance once known. Fixed: recomputed at release time, and now
   also gated on requiring a reason if the recomputed figure needs one.

## Confirmed correct, not bugs
- Backfilling a day earlier than the current earliest day on record
  correctly re-triggers the genesis prompt (though the wording may read as
  confusing for a true backfill — open UX question, not a defect).
- Closed days never receive Level 2 checks or the "no prior day" notice, by
  design.
- Re-entering a day under a different status succeeds silently in both
  directions with `--force` — open UX question on whether this should
  require confirmation, not a defect.

## Not yet covered
- The HTML/JS/CSS form itself — how these warnings actually render,
  colours, placement, and general UI/UX review.
