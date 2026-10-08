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

## `test_checks_titles.jl`
Unit-level, writes nothing. Reads `Checks.jl`'s own source, collects every
code raised in a `Finding("…")` call, and checks that `finding_title` gives
each one a short title — the few words shown on its row in the form's Checks
panel. Also checks that a blank balance (L1-C) is titled after its own box,
e.g. "Closing Balance Not Entered", and that an unknown code gets an empty
title rather than an error. Because the codes come from the source, a new warning added without a
title fails here. It also spells out the newest code, L3-E "Day after already on
record", so the exact words are asserted somewhere and not only discovered.
Prints PASS/FAIL lines and exits non-zero on any failure.

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
- The `server.jl` endpoints. No script here starts the server, so the
  server's side of the entry form was checked against a running server with
  a scratch `LEDGER_ROOT`:
  - `POST /api/check` also says three things about the date: `genesis`
    (nothing is on record before it, so the form shows its "first day on
    record" box), `hasDailyLedger` (the form offers to replace the ledger
    file) and `inBooks` (the date is already saved, so saving replaces it).
  - `POST /api/save` writes one day straight to the books. It refuses a Stop
    (`400` with the findings), a difference whose own reason is blank
    (`400`, `needsReason: true`; `openingReason` explains an opening that
    doesn't match the last close, `reason` a day that doesn't balance, and
    one does not count for the other) and a first day on record whose box was not
    ticked (`400`, `needsGenesis: true`). Saving a day again leaves its
    ledger file as it was (`skipped`) unless `force` is sent (`overwritten`).
  - `GET /api/day?date=` returns a saved day exactly as it was saved, both
    reasons included, for "Edit that day", or `day: null` for a date that has
    not been saved.
  - `POST /api/check` raises "Opening doesn't match last close" as soon as the
    opening balance is in, even while the closing balance is still blank, so
    the form can ask for that reason at the start of the day.

## `test_endpoints.jl`
In-process, no port bound: every request is handed to `router` the way the
browser's would arrive, against its own scratch `LEDGER_ROOT` (it refuses to
run against a folder named `Records`). Covers `/api/config`; `/api/check` on
the first day and with each balance blank; the three save refusals (a Stop,
a difference with no reason where each reason alone is shown insufficient,
an unticked first day); saving, re-saving (row replaced, ledger file kept, the
warning), the replace tick, an Off day; `/api/day` for saved, Off and unsaved
dates; the whole `POST /api/next` contract (unsaved 409, saved 200 with the
next date, a changed figure or reason 409, figures typed as strings, an Off day
sent both ways, today gives `next: null`, a future date 400, exactly six
keys); and `warmup()`, asserting that it writes nothing under `LEDGER_ROOT`
and leaves no scratch file behind. Prints PASS/FAIL lines and exits non-zero
on any failure (99 checks).

Added 2026-09-16, with the three changes they cover:
- **The first day is asked about once.** A date with a journal row is never
  asked to accept itself as the first day again: `/api/check` answers
  `genesis: false` for it, the first-day notice is gone, nothing claims the day
  before it is missing, and saving it again needs no tick and still regenerates
  its ledger with `force`. `/api/prior` still says it would be the first day on
  record, because that line is about the date, not about the tick box.
- **A gap filler is reminded about the day above it.** Entering a date whose
  following day already has a journal row raises the notice "Day after already
  on record" beside the closing balance, with the day after named in words. It
  is not raised while that day is not on record, nor for a date already in the
  books, and it neither blocks the day nor asks for a reason.
- **Two notices that name a date say it in words**, "1 April 2026" rather than
  `2026-04-01`: the ledger-already-made notice and the closed-day notice.

`test_endtoend.jl` also checks that the report writes money the way the form
does (`$1,500.00`, `-$2,950.00`), which it did not before.

## `test_notify.jl`
The change log and the one daily report, end to end against its own scratch
`LEDGER_ROOT` (it refuses to run if `LEDGER_ROOT` is unset or names a folder
called `Records`, and clears the folder first so the run is repeatable).

**It sends nothing.** `Notify.TRANSPORT[]` is replaced with a function that
collects what it was handed, which is the only reason the send path can be
tested at all. It isolates the settings too: `LDGR_NOTIFY_CONFIG` is pointed at
a file inside the scratch root *before* `main.jl` is loaded, so an installed
`notify.toml` is never read and never touched, and `LDGR_NO_DIGEST=1` keeps the
scheduler from ever starting. A fake password is planted in a throwing transport
to prove it cannot reach the audit log or a queued message.

Nineteen groups, in this order: email off by default (no `Notifications` folder
created); the log written even with email off, header once and later saves
appended; what a new day's row says; a correction on the same calendar date
staying out of the report; a correction on a later date reported with before →
after, who and when; a pending day (its ledger held on a missing day) reported
even on the same date; a day that did not balance and now does; a gap filled and
the ledger it releases, nested under it; the difference that only came to light
on release, including the case where no reason is on record and the ledger stays
held; the waiting list naming the missing date and then emptying; the wording
(no warning codes, every amount `$5,000.00`, dates spoken out loud, the subject
prefix); the quiet-day report; an Off day; a refused save leaving no row at all;
`latest_cutoff` at 18:29, 18:30, 18:31 and just after midnight; the tick that
decides whether a report is owed, the marker advancing when the message is
queued rather than when it is sent, and a second tick in the same minute doing
nothing; catching up after three days off as one report covering the whole
window; a send that fails leaving the message in the outbox with `Attempts: 1`,
nothing new in `sent/` and no password anywhere; and a mail package that is not
installed, where the day still saves and the message waits with a plain sentence
in the audit log. Prints PASS/FAIL lines and exits non-zero on any failure
(156 checks).

## Running these
Always point `LEDGER_ROOT` at a scratch folder, and always set
`LDGR_NO_DIGEST=1` — for every test run and every scratch server — so no daily
report is ever composed from scratch books or sent to the owner. The scripts
`include("Config.jl")` and similar files relative to their own folder but live
in `tests/`, so run them from a flattened copy of `v4.0` with `tests/*.jl`
copied next to the sources; `handoff/verification.md` §3 has the script.
