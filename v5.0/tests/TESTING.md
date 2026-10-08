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
- The `server.jl` endpoints over a real socket. `test_endpoints.jl` calls the
  router in-process (113 checks), but no script here binds a port, so the
  server's side of the entry form was also checked against a running server
  with a scratch `LEDGER_ROOT`:
  - `POST /api/check` also says three things about the date: `genesis`
    (nothing is on record before it, so the form shows its "first day on
    record" box), `hasDailyLedger` (the form shows its grey note, "Saving again
    will regenerate the ledgers…", in the Checks panel) and `inBooks` (the date is already saved, so saving replaces it).
  - `POST /api/save` writes one day straight to the books. It refuses a Stop
    (`400` with the findings), a difference whose own reason is blank
    (`400`, `needsReason: true`; `openingReason` explains an opening that
    doesn't match the last close, `reason` a day that doesn't balance, and
    one does not count for the other) and a first day on record whose box was not
    ticked (`400`, `needsGenesis: true`). Saving a day again leaves its
    ledger file as it was (`skipped`) unless `force` is sent (`overwritten`). The
    form now sends `force: true` on every save, so from the form a re-save always
    regenerates the ledger; the server still honours the unforced case, which the
    command line uses.
  - `GET /api/day?date=` returns a saved day exactly as it was saved, both
    reasons included, or `day: null` for a date that has not been saved.
    (2026-10-07) The form asks it whenever it lands on a date (opening the
    page, picking a date, Next day), so a saved day comes up by itself, and
    again for "Show saved figures" after Clear.
  - `POST /api/check` raises "Opening doesn't match last close" as soon as the
    opening balance is in, even while the closing balance is still blank, so
    the form can ask for that reason at the start of the day.

## `test_endpoints.jl`
In-process, no port bound: every request is handed to `router` the way the
browser's would arrive, against its own scratch `LEDGER_ROOT` (it refuses to
run against a folder named `Records`). Covers `/api/config`; `/api/check` on
the first day and with each balance blank; the three save refusals (a Stop,
a difference with no reason where each reason alone is shown insufficient,
an unticked first day); saving, re-saving (row replaced; unforced, the ledger file kept and the
warning; forced, the ledger file rewritten), an Off day; `/api/day` for saved, Off and unsaved
dates; the whole `POST /api/next` contract (unsaved 409, saved 200 with the
next date, a changed figure or reason 409, figures typed as strings, an Off day
sent both ways, today gives `next: null`, a future date 400, exactly six
keys); and `warmup()`, asserting that it writes nothing under `LEDGER_ROOT`
and leaves no scratch file behind. Prints PASS/FAIL lines and exits non-zero
on any failure (113 checks).

Added 2026-10-06 (late):
- **An Off day is never the first day on record.** An Off day on 31 March, with
  nothing before it, is offered the first-day box (`genesis: true`, which the
  form greys out) but gets no first-day notice, and saves without the box. 1
  April, the Work day after it, is still the first day on record (box offered,
  notice shown, not measured against the Off day nor held for it), and its
  ledger has nothing posted to the Temp Account.
- **An Off day typed into a gap.** With 1 June saved, 2 June missing and 3 June
  saved as an Off day (stored as 0.00), 4 June is not measured against 0.00: no
  "Opening doesn't match last close", its ledger waits ("Ledger waiting on the
  day before"), it saves with no opening reason, and filling 2 June releases it
  with no difference posted to the Temp Account. With the old `Chain.prior_day`
  swapped back in, these 5 checks fail. While 4 June is not yet saved, filling 2
  June gets no "Day after already on record" notice (only the Off day follows);
  once it is, the notice names 4 June and not 3 June.

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

Since 2026-10-06 (late) it also checks the ledger file's number format (2 checks,
47 in all): an amount of a million or more is written out in full
(`1350000.00`, not `1.35e6`), and a sum of cents is written to the cent
(`0.10`, not `0.09999999999999998`), with no exponent anywhere in the file.

## `test_checks_titles.jl`, after 2026-09-29
The title of the ledger-already-made notice (L3-B) is now "Day saved, ledger
generated", and its message keeps its first sentence ("A ledger has already been
generated for 1 April 2026.") and then tells staff to check QuickBooks before
importing: no journal may already exist for the date, an existing one is deleted
first, and if the numbers match nothing needs changing. The count is unchanged
(23). `test_endpoints.jl` checks only the first sentence.

## `test_launcher.jl`
Added 2026-09-29. Tests the launcher in `server.jl` without opening a window or
touching anything real: it sets its own scratch `LEDGER_ROOT`, `LDGR_NO_BROWSER`,
`LDGR_NO_DIGEST`, `LDGR_NO_WARMUP` and a `LDGR_NOTIFY_CONFIG` that does not exist,
and works on scratch copies of Chrome's `Preferences` file. **23 checks:**
- The launch flags include `--start-maximized` and no `--window-size`.
- `reset_zoom!` removes the saved zoom for `127.0.0.1` and `localhost` (whether
  Chrome wrote it as a number or an object, and in more than one partition) and
  `default_zoom_level`, and keeps every other address.
- A round trip keeps everything else in the file (a very large integer written
  as a string, nested objects, non-English text).
- A file with nothing to remove is not rewritten (same bytes, same modified
  time); a missing file returns false; invalid JSON is left untouched byte for
  byte; no temporary file is left beside the result.

Run it from a flattened copy like the others. Its real-Chrome counterpart was
done by hand on a scratch profile: with 80% saved for 127.0.0.1 the window opened
at 80%, and after `reset_zoom!` it opened at 100% (a CSS width of 1536 at a
device pixel ratio of 1.25 on a 1920 by 1080 screen at 125% scaling).

## `handoff/verify-save-next.mjs`, `handoff/verify-ui-2026-09-29.mjs`, `handoff/verify-date-change-2026-10-06.mjs`, `handoff/verify-save-gate-2026-10-06.mjs` and `handoff/verify-saved-day-loads-2026-10-07.mjs`
Browser scripts, not Julia tests. They drive the real form in Chrome through
`playwright-core` against a scratch server (`LEDGER_ROOT` under a scratch folder,
`LDGR_NO_BROWSER=1`, `LDGR_NO_DIGEST=1`, a `LDGR_NOTIFY_CONFIG` that does not
exist; the server's Email line must read "off (no notify.toml)"). None
touch the owner's Chrome profile. Each starts with the how-to-run steps in its
own header comment, which are the ones to follow: `npm i playwright-core@1` in a
scratch folder, start the server on the port the script expects (8798 for the
first two, 8771 for the others, or any port named in `BASE=http://127.0.0.1:<port>`),
run `node <script>.mjs` with `LEDGER_ROOT` set to the same folder, then
stop the server by process id. The scripts empty the books in `LEDGER_ROOT`
as they run, so never run two at once against the same server.

**Changed 2026-10-07: a saved day comes up by itself.** Whenever the form lands
on a date (opening the page, picking a date, Next day), it asks `GET /api/day`:
a saved Work day comes up with its figures and both reasons, a saved Off day
with the Off day switch on and every box blank, and any other date blank, as
before. "Show saved figures" shows only after Clear on a saved day, and
Ctrl+Alt+Z presses it. The grey note `#checks-saved` now also shows for a saved
Off day, so on a wide window an Off day's save puts nothing under the buttons;
below 1100 px, where the panel is hidden, "<date> saved to the books." is still
said there. The first four scripts were changed for this, and the fifth is new.
No check was weakened: each one the change made untrue was replaced by the new
rule's equivalent.

- `verify-save-next.mjs` — Save and Next day, the banners, the dock and the
  Checks panel, at 1440 px and again at 390 px: **185 checks at each width**
  (86 until 2026-10-06, when a block on picking another date was added; 132
  until the Save-gate change of the same day, after which the reason race is
  opened from a green, checked day; 134 until 2026-10-07). Updated
  on 2026-09-29: a successful save leaves no banner at the top, there is no
  "Edit that day", "Cancel edit" or replace tick box, and every save sends
  `force: true`. (2026-10-07) Part (e), the Off day: the grey note
  `#checks-saved` with the owner's words ("This day has been saved." only, as an
  Off day has no figures) and nothing under the buttons at 1440,
  the line under the buttons at 390. Part (i): figures typed on an unsaved date
  never follow to another date; picking a saved Work day, a saved Off day or a
  day whose ledger waits brings it up as saved, with no link; Clear on it shows
  the link, and the link (or Ctrl+Alt+Z) brings it back; Clear on an unsaved
  date shows none. New part (j): Next day onto saved days (a Work day, an Off
  day, a day with a reason) brings each up as saved, and onto an unsaved one
  blank. This script has no `MUTATE`; run against the front end of 2026-10-06
  it fails 15 checks at 1440 and then stops at Ctrl+Alt+Z, which that page
  does not know.
- `verify-ui-2026-09-29.mjs` — **319 checks**, 295 at 1536 and 24 at 390 (187
  until 2026-10-06, when a part on picking another date was added; 267 until
  the Save-gate change of the same day, after which the three refusal banners
  are each reached from a green button; 270 until that night, when a day whose
  ledger waits stopped getting a line under the buttons and is confirmed by the
  grey note `#checks-saved` instead; 271 until 2026-10-07) at 1536 by 730 at a
  device pixel
  ratio of 1.25 (the owner's screen, maximized at 100% zoom), plus a pass at
  390 px: the "LDGR" header and "Urgent Care" caption; nothing at the top after a
  save; the "Day saved, ledger generated" row and its exact full explanation; the
  grey note (present for a Work day with a ledger, absent otherwise, not counted
  as a check); no replace tick box, and a re-save with a changed figure rewriting
  the daily ledger file; (2026-10-07) for an Off day and for a day whose
  ledger waits, the grey note "This day has been saved. Saving again will rewrite
  it with the current figures." with nothing under the buttons at 1536, and the
  line under the buttons at 390; the
  refusal banners word for word; Ctrl+S, Ctrl+N and Ctrl+Alt+C, including that
  Ctrl+S on a grey Save sends nothing; (2026-10-07) a saved day, Off day or day
  whose ledger waits coming up by itself, with no link; the "Show saved
  figures" link shown only after Clear on a saved day (not after Clear on an
  unsaved one), kept while typing, hidden by another date, Next day, a save or
  pressing it; its title "Show saved figures (Ctrl+Alt+Z)" and
  `aria-keyshortcuts`; not counted as a check; pressing it, or Ctrl+Alt+Z
  (from inside a box mid-typing, and at 390 px with the Checks sheet closed),
  restores figures, reasons and the Off day switch, scrolls to the top and puts
  the cursor in the opening box; Ctrl+Alt+Z with no link does nothing and asks
  nothing; a failed load or a day that is not in the books says so right under
  the link; Esc closing an open full explanation and, at 390 px, the Checks
  sheet; no console errors, no warning codes
  and no sideways scrolling. (2026-10-07) With `MUTATE=1` it serves `app.js`
  with the link shown on every saved date and Ctrl+Alt+Z taken out (the real
  file is not touched), and 29 checks fail, all of them about the link or the
  key.
- `verify-date-change-2026-10-06.mjs` — picking a different date (day, month or
  year list) starts the form again on that date: nothing typed for the old date
  follows, and the Checks panel then shows only what the server says about the
  new date. (2026-10-07) A date not in the books is left exactly as Clear leaves
  it; a saved date comes up as saved (a Work day with its figures and both
  reasons, an Off day with the switch on and the boxes blank), with the right
  grey note and no link; Clear on it then shows the link. A look-up that fails
  says "Could not look up <d Month yyyy>." in the Checks panel and leaves the
  form blank. A look-up still on its way never puts a saved day over a figure
  typed meanwhile, or over another date picked meanwhile. Next day onto a saved
  date brings it up. **350 checks** at 1536 px and a shorter pass at 390 px
  (265 when it was written on 2026-10-06, and 266 from the Save-gate change of
  the same day, whose in-flight Save test starts from a green button, until
  2026-10-07). It
  runs the same way as `verify-ui-2026-09-29.mjs`. With `MUTATE=1` it serves
  the page the oldest behaviour (figures kept, nothing looked up) and 89 of its
  350 checks fail (57 of 266 before 2026-10-07), which shows it catches the
  bug it was written for.
- `verify-save-gate-2026-10-06.mjs` — the Save button follows the server's
  verdict (the owner's decision of 2026-10-06, after an independent verification
  run found Save green for "Expenses exceed total cash", a blank balance, a blank
  form and a difference whose reason box was still held back): a blank form and
  every Must fix grey Save out, shown row or not, and a click or Ctrl+S on the
  grey button sends nothing but says why (the held-back row, the server's
  sentence at the top, the explanation in the dock); a held-back difference
  greys it until its reason is typed; a saved day edited into a Must fix is
  left untouched; the race (a press in the moment before the check answers) is
  answered beside the button and the sentence goes once the day is clean; the
  closing balance typed and Ctrl+S at once saves with one press; Save is grey
  until the server has looked (a loaded day, Off day to Work day); a check
  that cannot reach the server leaves the server's refusal as the answer; the
  notices never grey Save; the first-day tick still does; 390 px.
  (2026-10-07) A saved day that comes up by itself is blank with a grey Save
  while it is looked up, and Save stays grey until the check of its figures
  answers; parts F and I now pick the saved date instead of pressing the link.
  **138 checks** (133 until 2026-10-07). With `MUTATE=1` it serves the page the
  old `formValid()` and the 27 "greyed out" checks fail (25 until 2026-10-07),
  nothing else.
- `verify-saved-day-loads-2026-10-07.mjs` — new on 2026-10-07, for the owner's
  two requests of that day: a saved day loads with its saved figures (an Off
  day switched to Off day), and after Clear on a saved day "Show saved figures"
  shows, with Ctrl+Alt+Z. It saves its own days through `POST /api/save` (a
  first day, a day with both differences and both reasons, an Off day, a gap,
  a day whose ledger waits) and checks, at 1536 by 900 and at 390 by 844: each
  kind of saved day coming up exactly as `GET /api/day` holds it, with its
  Checks rows, the right grey note, a green Save and no link (A, B, C); a saved
  Off day switched to a Work day showing no early row (C); an unsaved date
  identical to what Clear leaves (D); Next day landing on saved and unsaved
  days, at the top with the cursor in the opening balance on a Work day (E);
  opening the page on a saved today (F); Clear and the link, its words, title
  and `aria-keyshortcuts`, the link not counted, a click, the pill then the
  link at 390, Ctrl+Alt+Z from inside a box and with the sheet closed,
  Ctrl+Alt+Z with no link doing nothing, what hides the link, and a failed
  load said right under it (G); a look-up still on its way never overwriting a
  typed figure, another date, Clear or the Off day switch, Save pressed
  meanwhile sending nothing, fast arrow keys, two fast presses of the link
  loading once (H); a failed look-up's sentence and when it goes (I); the
  confirmation of an Off day's and a waiting day's save at each width (J); no
  console errors (K). **437 checks**: 220 at 1536 and 217 at 390 (221 with
  `WIDTHS=390` alone, which also checks the blank opening on today). **On the
  code of 2026-10-07, 435 pass and 2 fail**: the same check at each width, the
  last step of part H. A Next day pressed while a saved day is being looked up
  is refused for the blank form it sent, and that refusal ("The figures on
  screen for <date> have not been saved. Save them before moving on.") is left
  under the buttons beside the saved day's figures, which came up meanwhile.
  That is a fault in `onNextDay` (it lets go of its answer only when the date
  has changed, not when the form was started again, as `saveDay` does). It was
  reported on 2026-10-07 and is not fixed yet; the check is kept so the fix can
  be seen. With `MUTATE=1` it serves the `app.js` of 2026-10-06 in place of the
  real one (`OLD_APP` names that copy) and 157 of the 437 checks fail; D and K
  do not, as they should not. `OLD_APP` defaults to a copy in that session's
  scratch folder, which will not last: keep a copy of the 2026-10-06 `app.js`
  and point `OLD_APP` at it. `WIDTHS=1536` or `WIDTHS=390` runs one width.

The first three shortcuts were also confirmed once with real key presses in a real
Chrome app window on a scratch profile: Ctrl+N is not kept by Chrome in that
window (the page received it and no new window opened). In an ordinary browser
tab Chrome keeps Ctrl+N for itself. Ctrl+Alt+Z, added on 2026-10-07, was not
part of that test; the browser scripts press it through Playwright.

## `test_notify.jl`
The change log and the one daily report, end to end against its own scratch
`LEDGER_ROOT` (it refuses to run if `LEDGER_ROOT` is unset or names a folder
called `Records`, and clears the folder first so the run is repeatable).

**It sends nothing and reaches nothing.** `Notify.MAILER[]` is a fake — a
NamedTuple of `send` and `cancel` that records every email and cancel, answers a
repeated idempotency key with the id it gave the first time (as Resend does),
and can be made to fail with either `Resend.Failure` kind or to accept an email
and then lose the answer. `Resend.jl` itself is tested against a local stub
(`HTTP.serve!` on a spare 127.0.0.1 port), and a second self-signed HTTPS stub
when `openssl` is on PATH (Git for Windows has it). `Resend.API_BASE[]` is
pointed at the stub on the line after `Resend.jl` is included, and every call
goes through a guard that refuses anything but a 127.0.0.1 address. The
settings are isolated too: `LDGR_NOTIFY_CONFIG` points at a file inside the
scratch root *before* `main.jl` is loaded, so an installed `notify.toml` is
never read, and `LDGR_NO_DIGEST=1` keeps the scheduler from starting. A fake
`re_…` key is planted throughout to prove it never reaches the audit log, the
state files or any email.

**Time is controlled, not waited for.** The scheduling groups call
`Notify.tick(at = …)` with explicit times in 2031–2033 and write the change-log
rows they need with explicit timestamps, so the file passes at any hour of the
day, 17:29 included.

Fifty groups, in this order:

1. Email off: no `notify.toml`, an old Gmail-style file (no `api_key`), an
   unparseable file, a key with no `to` and a file with no `from` (there is no
   fallback sender) all leave email off, the start-up
   line says why, `tick()` is `[:off]`, no Notifications folder is made.
2–14. Unchanged from before this job: the change log kept with email off; what
   a new row says (group 3 now switches email on with the Resend keys and checks
   the banner and that the key is never logged); a same-date correction staying
   out of the report (these groups save on the real clock with `send_at =
   nothing`, so only midnight ends a session there; group 49 adds the send time); a later-date one reported with before → after, who and
   when; a pending-day edit reported even on the same date; a day put right; a
   gap filled and the ledger it releases; a difference seen only on release; the
   waiting list; plain words and money; the quiet day; an Off day; a refused
   save leaving no row.
15. The 5:30 pm cutoff: `latest_cutoff` and `next_cutoff` before, at and after
   17:30, after midnight and at the year's end; `send_at` fallbacks.
16. First hand-over, no change, a save: the email's fields, `scheduled_at` in
   UTC, the key's form, the state file, the generation seeded from the clock,
   create-then-cancel order, the audit lines.
17. Idempotency: the same books give the same bytes and key; a lost reply is
   retried with the same key; a lost or unreadable state file restarts the
   generation from the clock.
18. The last minute, a correction, settling: nothing handed over within a
   minute of the send time; a late save corrected after it; settling moves the
   marker; the banner names the last complete report.
19. Days ldgr was not opened: a quiet stretch folds; command-line saves give a
   correction and a late report; the first-ever report says so.
20. Cancels that fail: retried after the pause, dropped after their send time
   with an audit line; a sending-only key never blocks a hand-over.
21. Hand-over failures: the 5-minute and 1-hour pauses, a poke skipping only
   the short one, a `notify.toml` save ending the long one, throttled audit
   lines, the key scrubbed.
22. The clock: a marker in the future is ignored, with a note; UTC conversion.
23. `LDGR_DIGEST_NOW`: sends now, moves the marker, reschedules and cancels.
24. Settings changed while a version waits; the state file's exact fields.
25. `Resend.jl` against the stub: headers, JSON body, the cancel path, every
   status class, timeouts, a refused connection, the key never in the words.
26. One tick end to end through `Resend.jl` and HTTP to the stub.
27. Never a false all-clear: a missing column or unreadable rows give CHANGE LOG
   COULD NOT BE READ, as the first paragraph, before the heading.
28. The next-morning edit spelled out under DAYS ENTERED.
29. The timer and the poke; a second `start_schedule!` closes the first timer.
30. A row torn after the report was handed over: the waiting version is
   replaced (the problem is kept in the state file), and a torn row found only
   after the send time gives an immediate follow-up.
31. A last line with no newline, and an empty log: the next save still reads.
32. Two rows run together on one line: the current report is flagged, other
   rows still read, near the top it costs only that line, and as the last line
   (read in a separate process) it neither misreads nor crashes.
33. A row cut short is skipped and named, never "balanced"; TRUE/FALSE read.
34. CSV.jl's line warnings are silenced; ldgr's own warning is said once.
35. Every reported edit printed (CHANGES, GAPS FILLED, DAYS ENTERED), with
   "It balances now." where an edit cleared a difference.
36. A window holding only same-date corrections gets its own sentence, not the
   quiet one; an empty window keeps the exact quiet sentence.
37. A hand-over whose answer was lost: replayed with the same key and a
   byte-identical email, adopted, never two emails left waiting; given up on
   after 23 hours or when refused; a scheduled one whose send time has come is
   not replayed but sent late, saying it may repeat the 5:30 pm one.
38. The marker and the state file are replaced in place (rename, not mv).
39. A sending-only key's cancel failure is logged once, not once per save.
40. A send time counts as passed only when its whole second is over; a clock
   stepped back after settling hands nothing over.
41. The clock is read once `BUSY` is held; time spent waiting counts against the
   last minute.
42. A `send_at` with seconds is read as whole minutes.
43. `Resend.jl` again: the key never survives a cut; stale keys masked;
   certificate failures worded as a clock/antivirus problem (with a real
   self-signed HTTPS stub); cut-off replies; `cancel`'s narrower rule.
44. A ledger released by an edit is reported; "did not balance before" is the
   difference before the first edit shown.
45. The writer mends a line cut inside quotation marks; a date cut short, a
   released row cut short and an emptied (byte-order-mark only) log; a log that
   cannot be read at all says so in plain words and stays mendable.
46. A hand-over that never left the computer leaves nothing pending; a replay
   confirmed during a cancel pause cancels what it replaced at once; a stray
   byte in the change log does not stop the report; a version given up on in
   the last minute keeps its send time (`unsure`) across later ticks and is
   forgotten once covered; an unexpected failure inside a tick is written to
   the audit log once an hour (`LAST_UNEXPECTED`); a quotation mark typed by
   hand in the middle of a cell is ordinary text, not a cut.
47. A line cut after spaces or a tab before an opening quotation mark is mended
   as a quoted cell, as CSV.jl reads it; a log holding only a heading cut short
   is written afresh, and any other damaged heading is left alone.
48. The "may repeat" sentence in every report that covers a given-up send time
   (corrected, follow-up, late, the first-ever, a forced one, and the scheduled
   version itself), and in none that does not; an unexpected error warns on the
   terminal once an hour, not once a minute; an audit log that could not be
   written gets the failure's line on the next tick.
49. A day's session ends at midnight or at the send time, whichever comes first
   (`Changes._session_over`, to the second): a correction after the send time
   on the same date is reported, with the first save's time, what moved and
   "It balances now."; a day typed after the send time is free until midnight
   and reported the next morning; the send time comes from `Notify` without the
   front doors passing it, and a send time that cannot be read still lets the
   row be written. The saves run at fixed 2034 times and the log is put back.
50. The key, after everything: in no file the run wrote (apart from the test's
   own `notify.toml`) and in no email or idempotency key.

Groups 51 to 60 (added 2026-09-29) cover the HTML body of the report
(`EmailHtml.jl`). They build reports from rows made in memory for days in 2035,
over a corpus of 16 cases (quiet, balanced, Off day, shortage and opening less,
surplus and more, the day before on record, a later edit that balances a day,
a pending-day edit, a gap that releases a ledger and one with nothing to say,
same-date corrections, an unreadable log quiet and not, late and corrected
notes, a hostile reason and name), and check each case for the same properties.
51. `_digest` is the first two values of `_report`, `build_digest` the first
   two of `build_report`; the HTML is a page of its own.
52. Doctype, `lang`, charset, viewport and both colour-scheme metas, `<title>`
   is the escaped subject; the preheader is the first element after `<body>`
   with the spacer after it, and says the counts and up to two differences (or
   the quiet sentence, or the unreadable-log sentence).
53. (Reworked 2026-09-30, round two, `handoff/email-html-round2.md`.) The
   unreadable-log warning comes AFTER the Days entered section, in the danger
   card with both fills set; the title band (one row, `LDGR | Daily Report |
   dd-mm-yyyy`, no "(Urgent Care)", "Corrected Report" for a corrected one);
   the caption; notes as plain soft text in parentheses with no grey box; the
   late note and the several-days paragraph dropped from the HTML while the
   corrected, follow-up, possible-repeat, first-report and clock notes stay.
54. Escaping: a hostile reason and name never appear raw and their escaped
   form does; a problem with markup in it is escaped.
55. For every case: no warning codes, no "trading", tags balance, two builds
   are byte-identical, every element has an inline style, NO fill set with the
   `background:` shorthand anywhere (the `<style>` block included), and every
   `td`/`table`/`body` fill carries a `bgcolor` attribute beside its
   `background-color` (`fills_ok`). Edits: a kind-of-day change shows ONLY the
   row `Day type | Work day | Off day` and the tag Work status update; a cleared
   difference is Balanced with `(Previously Not Balanced)` and the row `CB
   Shortage | ($2,000.00) | $0.00`; a revised day that is still or newly
   unbalanced is Numbers revised only, with its new difference row and its
   added explanation kept; a CLEARED explanation has no row; the labels
   Explanation and OB explanation; the difference row's label (Shortage,
   Surplus, Difference, for CB and OB) and values, by table; one table per edit
   with a caption when there are several; "(not counted)"; a part the layout
   cannot read shown as it stands; an edit that moved nothing says so on its
   bullet. Tags: CB/OB Shortage in parentheses (red), Surplus plain (amber), the
   opening above the closing, Balanced, Off day, never wrapped; explanation
   bullets (`with explanation:`, `with explanations: OB – …; CB – …`, `, no
   explanation given`); none of the old furniture (last-close line, stripe,
   captions); a gap day's `(Previous Gap Day)` and its `Ledger made for` line
   with its tags and `explanation:` lines.
56. One section: Days entered is the only day section, newest date first, one
   card shape for every day; no "Needs attention", "Gaps filled" or "Changes"
   heading in any case; no summary card (the counts are in the preheader only).
57. Quiet cases (the quiet sentence and a tick; same-date corrections with no
   tick; an unreadable log with no tick and no Days entered heading), parity
   (every amount, explanation, name and long date in the text is in the HTML,
   for every case, the report's own date accepted as the band's `dd-mm-yyyy`;
   the HTML has the "Powered by SolRegia" credit and no "Records folder:" line
   while the text keeps both its footer and the folder; with a check that the
   parity test can fail), and size (one day under 30 KB, 31 balanced days under
   100 KB). THE PARITY TEXT EXEMPTS EXACTLY THE OWNER'S LIST and nothing else
   (`parity_text`): the last-close amount, the late and several-days notes, a
   cleared explanation's row, the figures (and the "did not balance before"
   line) of a day whose kind changed, the Records folder line, and every
   intermediate "Changed again" but the last. Each exemption is also asserted
   to be a real omission (present in the text, absent from the HTML).
58. A real held ledger (a day in August 2026 whose day before is missing): the
   Saved Days with Pending Ledgers section (the date bold on its own line with
   a real line break before the caption, the closing sentence, the old three
   lines gone), the preheader's count, the page's order (band, caption, notes,
   Days entered, change-log warning, pending section, footer), and an entered
   day waiting on a missing day with its `Ledger pending` tag and `(Awaiting
   Gap Day)` suffix.
59. `_email_dict` has `html` only when it is not empty; `_hash16` changes with
   the HTML and equals the old formula without it; `_utf8` is applied to it;
   the pending table round-trips it exactly (group 37's tab, quote and accent
   string) and replays byte for byte; a pending table written before the HTML
   existed reads back and replays with no `html` key and the same key; the JSON
   a stub on this machine receives carries `html` beside `text`; a child
   process with a broken `_html_body` still gets the text, an empty `html` and
   an email with no `html` key.
60. The key again, after these groups: not in the audit log, any file, any email
   or any HTML body.
62. The kind of day in words: the writer writes `Kind of day Work day -> Off day`
   (and back); a legacy `trading -> closed` row prints the new words in the text
   and the HTML, identically to a new-form row; anything else stays verbatim.
63. The HTML revisions of 2026-09-30 (see `handoff/email-html-design.md` and
   `handoff/email-html-round2.md`): the title band (green fill set twice, white
   text on every piece, pale-green `#B9D9CE` separators and no rgba, one row,
   the report's own `dd-mm-yyyy`, the first visible thing, the font sizes: 18.5
   and 16 px inline, the media steps at 375/390/412/430/600, the step down under
   360, the 28 px cap, the dark-mode band); no "Covering" line and no summary
   card; 24-hour times only (`_clock24`, `_times24` with noon and midnight, the
   notes converted, an explanation, a name and the change log's problem left as
   typed); 14px section headings; a day's events as table-row bullets in time
   order, with no `<ul>`; the footer credit and no Records folder in the HTML.
64. The second round: a revised day not entered in this report opens with
   `First saved on <dd-mm-yyyy> at <time>` and the explanation in force before
   the first reported edit (the before side of a changed or cleared one, else
   the row's own), `with explanations: OB – …; CB – …`, `, no explanation
   given`, no bullet when the log has no first save; the next-morning case (the
   entry bullet, then `Changed on …`, in one card, Numbers revised); the
   precedence of the tags (Work status update over everything, then Balanced or
   Numbers revised, then the day's own state; a same-session edit does not
   count); the shape of a card (two columns, the right holding only the tags in
   nowrap blocks, the change table a colspan-2 row, a 12px spacer between
   cards, the date 15px semibold).

`handoff/email-preview.jl` builds a set of scenario reports at fixed times
(with real saves) and writes each as `.subject.txt`, `.txt` and `.html`; run on
the code before and after a change to the report, the `.txt` and `.subject.txt`
files must be byte-identical, and the `.html` files can be opened in a browser.
`email-preview.jl samples` writes the owner's 19 samples the same way (sample 20,
"a difference with no explanation", does not exist because no real save can make
one: both front doors refuse it and a held ledger with one is not released).

Prints PASS/FAIL lines and exits non-zero on any failure (1169 checks, or 1168
when `openssl` is not on PATH).

## Running these
Always point `LEDGER_ROOT` at a scratch folder, and always set
`LDGR_NO_DIGEST=1` and point `LDGR_NOTIFY_CONFIG` at a file that does not
exist — for every test run and every scratch server — so no daily report is
ever composed from scratch books and handed to Resend. Nothing a test runs may
reach Resend or the internet: anything calling `Resend.jl` points
`Resend.API_BASE[]` at a 127.0.0.1 stub first. The scripts
`include("Config.jl")` and similar files relative to their own folder but live
in `tests/`, so run them from a flattened copy of `v4.0` with `tests/*.jl`
copied next to the sources; `handoff/verification.md` §3 has the script.
