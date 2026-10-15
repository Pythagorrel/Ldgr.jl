# Implementation plan and interface contract — 2026-09-15 (evening)

Companion to [`review-2026-09-15.md`](review-2026-09-15.md). That document has the findings, the designs (§2 email, §3 bugs, §4 tips, §5 scenarios) and the reasoning; this one records the owner's decisions, splits the work into three streams with disjoint file ownership, and pins down every interface the streams share. **When this document and the review disagree, this document wins.**

## 0. Owner decisions (2026-09-15, final)

1. **Email transport:** SMTP through the clinic's own mailbox, via **SMTPClient.jl** (one `Pkg.add`, not yet installed on this machine). No third-party email API.
2. **Email policy:** send on the first save of a day with a difference; send again marked "(updated)" when an edit changes the figures or the reasons; send a short "now balances" notice when an edit makes a previously unbalanced day balance. Never for Off days, never for refused saves.
3. **The form stays silent about email.** The save response carries a `notified` flag for tests and logs; the banner never mentions it.
4. **Off day with no day before on record: refuse.** Level 1 Stop `L1-F` "Enter the day before first" (a gap) and `L1-G` "The first day must be a work day" (the first day ever). No code path may compute, guess or carry an invented balance.
5. **Predicted closing:** shown only after the closing balance box has been reached (left once, or Save pressed), behind the same gate as the deficit line.
6. **Tips:** a tip may appear beside the "Expenses exceed total cash" Stop (the save stays refused), and `check_day` may be handed the previous day's saved figures, read-only, for the "yesterday's deposit" tip. **Owner's condition: anything that uses the previous day must cope with a gap.** A prior-day tip may only populate when the previous day's record is on file, and nothing may error or misfire when it is not.
7. **Date change with figures typed: keep the figures.** Clear only the "been there" state (touched boxes, save attempts, the figures the findings were checked against, the open explanation, the last save's notice).
8. **No v3.0 migration story.** The clinic's counted books start with v4.0. Older journals only have to be readable without error; no special first-counted-day wording or acceptance.

Also standing (from CLAUDE.md): the closing balance is a physical count and is never computed or overwritten; simplicity is the product; plain words ("Work day"/"Off day", "Start of day"/"End of day", no "closed"/"trading"/"working day", no drawer talk, no warning codes on screen); warn about a box only once it has been left or Save pressed; one reason per difference beside its figure; no redundant messages; nothing floats; the checks are the gate; the chromeless window launcher and the REPL `include("server.jl"); start()` path stay.

## 1. Already done in the main session (do not redo)

`Checks.jl` now has the shared interface. Everything below is in place and probed:

```julia
check_day(rec; prior_closing, prior_date, is_genesis, ledger_exists,
          prior_amounts::Union{Nothing,Dict{Symbol,Float64}} = nothing,   # previous day's SAVED figures (its journal row)
          stale::Bool = false,                                            # this saved date's day-before changed since it was saved
          stale_ledger::Bool = false)                                     # this date's ledger file no longer matches its journal row
hint_checks(rec, findings; prior_amounts = nothing)
```

New codes, all with titles in `FINDING_TITLES`:

| Code | Level | Field | When | Title |
|---|---|---|---|---|
| `L1-F` | 1 | `:date` | Off day, `prior_closing === nothing`, not genesis | Enter the day before first |
| `L1-G` | 1 | `:date` | Off day, `prior_closing === nothing`, genesis | The first day must be a work day |
| `L3-E` | 3 | `nothing` | `stale = true` (not gated on Stops: the form checks a saved date with blank boxes) | Save this day again |
| `L3-F` | 3 | `nothing` | `stale_ledger = true`; an Off-day variant says the file will be removed | This day's file is out of date |
| `L4-5` | 4 | `:opening_balance` | an `L2-B` shortage equal to `prior_amounts[:deposits]`; silent when `prior_amounts === nothing` | Yesterday's deposit |

`L3-C` (Off day notice) is now gated on no Stop, like `L3-A`/`L3-D`. The sort is explicitly stable.

## 2. Streams and file ownership (disjoint; nobody edits another stream's files)

| Stream | Owns | Does not touch |
|---|---|---|
| **A — checks** (Opus) | `Checks.jl`; `tests/test_checks_basic.jl`, `test_checks_edge.jl`, `test_checks_hints.jl`, `test_checks_titles.jl` | everything else |
| **B — books & server** (Opus) | `Chain.jl`, `main.jl`, `server.jl`, `Report.jl`, `Journal.jl`, `Layout.jl`, `DayInput.jl`, `Ledger.jl`, `AuditLog.jl`, **new** `Notify.jl`, **new** `notify.example.toml`, **new** `.gitignore` (in `v4.0/`); `tests/test_server.jl`, `test_endtoend.jl`, `test_endtoend_edge.jl`, **new** `tests/test_notify.jl`, **new** `tests/test_chain_stale.jl` | `Checks.jl`, `public/*`, docs |
| **C — form** (Opus) | `public/app.js`, `public/index.html`, `public/styles.css`; `handoff/ui-contract.md`; **new** `handoff/verify-ui-2026-09-15b.mjs` | every `.jl` file |
| **Main session** | integration, the full test run, the browser run, `README.md`, `tests/TESTING.md`, `CLAUDE.md`, this folder's other documents | |

Each stream works in **its own copy** of `v4.0` (made by the main session), runs its tests from a flattened copy of that copy with its own scratch `LEDGER_ROOT`, and reports the exact list of files it changed. The main session copies owned files back into `E:\Ldgr\v4.0` and runs everything together. Stream C tests against the server **as it is in its copy** (without stream B's new response fields); the flows that need those fields are written to this contract and verified by the main session after integration.

## 3. Interface contract

### 3.1 Findings (unchanged shape)
`{code, level, levelName, title, field|null, message}` — the six keys of `FindingJSON`. Codes are never shown on the form. Stream A may reword any title or message; it may not change a code, a level, a field or a keyword argument without updating this document.

### 3.2 `POST /api/check` — 200 body (unchanged keys)
`ok, findings, today, predicted, available, paidOut, needsReason, blocked, genesis, hasDailyLedger, inBooks`. Findings may now include `L1-F`, `L1-G`, `L3-E`, `L3-F`, `L4-5`, and — because the bare 400s go — `L1-A` for a negative figure and `L1-E` for a date not allowed. Stream B passes:

- `prior_amounts` = the previous calendar day's saved figures (`Chain.saved_record(prior.date).amounts`) when `Chain.prior_day(d)` finds one, else `nothing`;
- `stale` = `in_books(d) && Chain.stale_day(d)`;
- `stale_ledger` = `in_books(d) && Chain.stale_ledger(d)`.

Structural 400s that remain (prose `error`, no findings): no date, unparseable date, unknown category key, a value that is not a number. **Removed:** the future-date, year-before-2000 and negative-amount 400s; those reach `check_day` and come back as findings.

### 3.3 `POST /api/save` — 200 body (now a `Dict{String,Any}`, one shape)
```json
{ "ok": true, "date": "2026-09-09", "closed": false,
  "journal": "added" | "replaced",
  "dailyLedger": "written" | "overwritten" | "skipped" | "held" | "not applicable (closed)" | "removed",
  "released": ["2026-09-10"],          // held days whose ledgers this save produced
  "held": ["2026-09-12"],              // held days that now need a reason before they can be released
  "nextDayStale": "2026-09-10" | null, // d+1 is in the books and its overnight comparison is now against an older closing
  "notified": "queued" | "none" | "off" | "failed",
  "warnings": ["..."] }                // still sent, but the form no longer shows raw log text
```
`"removed"`: an Off day was saved over a date that had a daily ledger file (a work day changed to an Off day); the orphan file was deleted and the deletion logged and reported. Refusals are unchanged: 400 with `findings` for a Stop; 400 with `findings` and `needsReason` for a difference whose own reason is blank; 400 with `needsGenesis` for an unticked first day. Every refusal is now written to the audit log.

### 3.4 `Chain` additions (stream B)
```julia
saved_record(d)::Union{Nothing,DayRecord}   # moved here from server.jl; server.jl calls it
stale_day(d)::Bool        # d saved, d-1 saved (contiguous) and |(opening − overnight_variance) − prior.closing| ≥ 0.005
                          # (an Off day's overnight_variance is 0, so it is stale when its carried opening ≠ prior.closing;
                          #  NaN openings, genesis rows and rows with no contiguous prior are never stale)
stale_days(y, m)::Vector{Date}
stale_ledger(d)::Bool     # a ledger file exists for d and either the saved row is an Off day, or rebuilding the rows from the
                          # saved row (build_ledger_rows(group_amounts(rec)...; dv, ov)) differs from the file (Account, Debit, Credit, ±0.005)
stale_ledgers(y, m)::Vector{Date}
```
All derived from the files, state-free, and **none of them computes a balance**. `pending_ledgers` stays as it is.

### 3.5 `Checks` behaviour stream A must keep or provide
- `L3-B` is raised for **work days** only. For an Off day with `ledger_exists`, raise the `L3-F` Off-day variant instead ("A file was made for this day when it was a work day…will be removed"), once, whether or not `stale_ledger` is also passed. For a work day with `stale_ledger = true`, raise `L3-F` and not `L3-B` (it already tells the person to confirm the replacement).
- Tips beside the `L1-B` Stop: when the only Stops are `L1-B` and the closing balance is counted, run the "check this figure" rule (P2) against the day residual so the day that most needs help gets one tip. Nothing else runs beside a Stop.
- `L4-5` and every other prior-day rule: silent, never an error, when `prior_amounts === nothing`.

### 3.6 Notify (stream B)
- `v4.0/Notify.jl`, included from `main.jl` after `Report.jl`. `using SMTPClient` at the top (a hard dependency; add it with `Pkg.add("SMTPClient")` and list it in the README Requirements note you hand back).
- Settings in `v4.0/notify.toml` (stdlib `TOML`; path from `Layout.notify_config_path()`), git-ignored via `v4.0/.gitignore`; `v4.0/notify.example.toml` committed with `to`, `from`, `smtp` (e.g. `smtps://smtp.gmail.com:465`), `user`, `password` (an app password), `subject_prefix`. No file → notifications off; the password is never logged or printed.
- `Notify.enabled()`, `Notify.after_save(outcome; previous=nothing) -> "queued"|"none"|"off"`, `Notify.enqueue(msg)`, `Notify.flush!() -> (sent, failed)`, `Notify.TRANSPORT[]::Ref{Function}` called as `TRANSPORT[](to::String, subject::String, body::String)`; tests inject a capture function.
- Policy (decision 2): Off day → `"none"`. Day now balanced: if `previous` (the day's earlier journal row, read in `handle_save` with `Chain.saved_record(d)` **before** `process_day`) had a difference → a short "now balances" message, else `"none"`. Day with a difference: if `journal == "replaced"` and `previous` has the same two variances (±0.005) and the same two reasons → `"none"`; otherwise one message, subject `ldgr: 3 September 2026 did not balance (shortage $1,900.00)` with ` (updated)` appended when replaced. Also one message per **released** day whose recomputed overnight variance is non-zero (subject says it was found when the missing day was entered).
- Body: the day; each difference on its own line from `Report.difference_lines(outcome)` (factor it out of `build_report` so file and inbox cannot drift); who entered it (`USERNAME`) and when, clinic local time; the day's figures and the predicted closing (`Checks.money`, `Checks.predicted_closing`); then the full daily report text under a rule.
- Queue then send, never block: `enqueue` writes `<ROOT>/Notifications/outbox/<yyyy-mm-dd HHMMSS> <day>.txt` (header block `To:`, `Subject:`, `Attempts:`, blank line, body) from `Layout.outbox_dir()`; `flush!` sends each file through `TRANSPORT[]`, moves sent ones to `Layout.sent_dir()`, leaves failures (Attempts +1), logs to the audit log and console, and raises one `@warn` in plain words ("The owner could not be emailed just now. It will be sent on the next save."). `flush!` runs `@async` after `handle_save` has composed its response, once at `start()`, and after every later save.
- `start()` prints `Email notifications: off (no notify.toml)` or `on → <to>`.
- CLI front door (`main()`): call `after_save` and `flush!` the same way, after the report.

### 3.7 Form (stream C) — what it reads
- `dailyLedger` decides the words after a save (never the raw `warnings` text): `"skipped"` → "Saved. The file for this day was left as it was."; `"removed"` → "Saved. The file made when this was a work day was removed."; `"held"` → the existing held wording; otherwise nothing extra.
- `released` → "The file for 10 September was finished too." (one sentence, dates joined with "and").
- `held` → "10 September still needs a reason: open it and save it again." with an **Edit that day** button for the first one.
- `nextDayStale` → "Now open 10 September and save it again." with an **Edit that day** button. Shown after the save banner text, in the same banner.
- `notified` → ignored (decision 3).
- An `L1-F`/`L1-G` Stop on an Off day: the Checks row shows at once ("Enter the day before first · Must fix"; its `field` is `date`, so clicking it goes to the date selects). Pressing Save on an Off day while a Must-fix row is showing skips the Off-day confirm dialog and lets the server's refusal show as for any Stop.

## 4. Stream A — checks: tasks and acceptance

1. **Tips redesign** (review §4, P1–P6) inside `hint_checks`, keeping the signature above:
   - `typed` from `KEY_ORDER` (+ `:opening_balance` only where a rule needs it); never a counted closing balance, never a variance.
   - **P2 first** (code `L4-3`, title "Check this figure", field = the box): for each typed box the value that would make the day residual zero (opening → O+d; cash sales → S+d; an outflow → out−d; **never the closing balance**); propose only if ≥ 0 and exactly an adjacent-digit swap, ×10 or ÷10 of what was typed; one best candidate, preferring cash sales and expenses over the opening. Words: `If "Cash Sales" were $98,400.00 instead of $98,040.00, the day would balance. Check that figure.`
   - **P4** (`L4-4`): each POS box and the POS total, with sign; shortage → card money may have been entered in the Cash Sales box as well; surplus → cash may have been entered as a card deposit; one row, not two, when only one POS box is filled. Suppresses P1 for the same amount.
   - **P1** (`L4-2`, replaces the old rule): `|d| == v` with sign and side: surplus & outflow → the money may not have gone out, or was written down but never taken out; shortage & outflow → paid twice, written once; shortage & cash sales → takings entered twice, or card money entered as cash; shortage == opening balance → the closing count may have left out the money that was there at the start of the day; also shortage == cash sales / 2 → the Cash Sales figure may have been entered twice. Surplus vs cash sales or opening → say nothing.
   - **P3** (`L4-1`): only when P2 found nothing for that difference, `|d| ≥ $1.00`, and `|d|/9` in cents is a digit 1–9 × a run of ones × a power of ten. Worded for the opening balance (field `:opening_balance`) when the difference is `L2-B`.
   - **P5**: for `L2-B` run only P3 and `L4-5` (never today's figures against an overnight difference). `L4-5` stays as implemented; move it into the new structure.
   - **P6**: cap two tips per difference and three per day, order P2 → P4 → P1 → P3; de-duplicate by (code, amount) and by message; P2 beside the `L1-B` Stop as in §3.5.
   - No "drawer"/"till" talk; no codes; plain words; money through `money`.
2. **Wording and titles** (review §3.4 #3, #6): `L3-A` title "Waiting on the day before", message "The day before this one hasn't been entered yet. This day will still be saved; its paperwork finishes as soon as that day is entered."; `L3-B` title "A file was already made for this day", message without "ledger"/ISO date, telling the person to confirm the replacement only if the old file was never imported into QuickBooks or that import was deleted; `L3-C` title "Off day", message "<date> is an Off day. Nothing is posted for it, and the next work day opens with $X, carried straight through." (use the date the way the other messages do). Keep every other title.
3. **§3.5 behaviours** above (L3-B/L3-F split; P2 beside L1-B).
4. **Tests:** rewrite `tests/test_checks_hints.jl` as a PASS/FAIL script (same style as `test_checks_titles.jl`, exits non-zero on failure) covering every worked example in review §4 and the owner's gap condition: swap, ×10, ÷10 for P2; the 11 % false-positive case (2,619 is silent; 450 fires); each P1 sign/side branch and its silences; P4 per box and total with one row; P5 (nothing from today's figures on an overnight difference; `L4-5` fires only with `prior_amounts`, is silent for a surplus, for a prior with no deposits, and with `nothing`); the caps; P2 beside `L1-B`; `L1-F`/`L1-G`; `L3-B` vs `L3-F`. Update the comments/expectations in `test_checks_basic.jl` and `test_checks_edge.jl` where the output changes. `test_checks_titles.jl` must still pass (it reads codes from the source).

Acceptance: `test_checks_titles.jl` and the new `test_checks_hints.jl` pass; the three print-by-eye scripts run without a Julia error and their output was read.

## 5. Stream B — books & server: tasks and acceptance

1. `Chain.saved_record`, `stale_day(s)`, `stale_ledger(s)` (§3.4). `main.jl`'s `_retry_pending!` and `server.jl` use `saved_record` instead of building rows by hand.
2. `day_findings` and `process_day` pass `prior_amounts`; `day_findings` passes `stale` and `stale_ledger` (§3.2).
3. **Off day with no prior**: nothing to add beyond the Stop — but `record_from_payload` and the CLI must no longer *invent* `0.0`: build the closed record with the carried balance when there is a prior, and with `NOT_COUNTED` when there is none (the Stop refuses it before anything is written). `main()` carries an Off day's balance from `Chain.prior_day` itself; `DayInput.read_day_interactive` stops asking for a typed carried balance, and its false "asks for a reason" comment goes. `read_day_csv` reads the `Status`, `Reason` and `Opening Reason` columns when present.
4. **Work day → Off day**: saving an Off day over a date with a daily ledger file deletes that file (behind nothing — an Off day cannot have one), logs it, reports it, `dailyLedger = "removed"`.
5. **Stale checks in the pipeline**: `/api/save` returns `nextDayStale`; the report gains "DAYS TO SAVE AGAIN" (stale days, with why and what to do) and "FILES OUT OF DATE" (stale ledgers) and lists held-for-a-reason days; it scans the months of this run's outcomes **plus the month before and after each** (review §3.1 #7); `_retry_pending!` returns the months it touched and every one of them gets its monthly ledger rebuilt; the outcome gains `held::Vector{Date}` and `released_days::Vector{NamedTuple{(:date,:day_variance,:overnight_variance,:reason,:opening_reason)}}` (keep `released::Vector{Date}`).
6. **Notify** (§3.6) with `tests/test_notify.jl` using a capture transport: balanced day → nothing; day difference → one message with the date and the reason; both differences → both lines; Off day → nothing; re-save with unchanged variances and reasons → nothing; edit to balanced → "now balances"; released day with a difference → a message; transport failure → the file stays in the outbox and the next `flush!` sends it; no `notify.toml` → `"off"` and the save still succeeds; `Report.difference_lines` text identical to what the report file carries; the password never appears in any log line.
7. **Severity B backend** (review §3.1): #5 a process-wide `ReentrantLock` around `handle_save` and atomic journal writes (`Layout.temp_path(p)`, write, then `mv(…; force=true)`); #6 an `AuditSession` opened at the top of `handle_save`, each refusal logged, the session passed into `process_day` (new keyword, default `nothing` = make one); #8 the bare 400s (§3.2); #9 `Report._money` deleted, `Checks.money` used (`using ..Checks` in Report); #12 `Layout.audit_log_path()`, `reports_dir()`, `report_path(d)` used by `main.jl`/`Report.jl`; #14 thread one prior lookup through `process_day` (`ledger_ready` no longer repeats it) if it falls out naturally; #15 the deposit group through `merged_totals`; #16 NaN guard in `month_chain_check`'s sums.
8. **warmup()**: cover the new shapes (a save-response Dict, an Off day check with `L1-F`, a stale check, `Notify` composition with the transport stubbed to a no-op — never a real send, never a file under ROOT). `test_server.jl` keeps asserting that warm-up writes nothing to the books.
9. **Tests:** extend `test_server.jl` (Off day in a gap refused with `L1-F`; Off first day refused with `L1-G`; a negative figure comes back as an `L1-A` finding from `/api/check`, not a 400; edit of a closing makes d+1 stale → `nextDayStale`, `/api/check` on d+1 shows `L3-E`, re-saving d+1 clears it; edit without `force` → `L3-F` on the next check; Work→Off → `"removed"` and no file; two-window race no longer loses a day — two saves of different dates through `router` in interleaved tasks both survive; refusals appear in the audit log; save response keys stable across kinds of day; `notified` present). New `tests/test_chain_stale.jl` for the Chain predicates. Keep the existing counts passing (`test_endtoend` 43 → whatever it becomes, `test_endtoend_edge` 32, `test_server` 38+). Print the final counts.

Acceptance: all file-backed tests pass from a flattened copy with scratch roots; nothing under any real Records folder is touched; `include("server.jl"); start()` from the REPL still works (do not actually open the browser: set `LDGR_NO_BROWSER=1`; do not bind 8000 or 8765).

## 6. Stream C — form: tasks and acceptance

1. Decision 5: hold `#predicted` until the closing balance box has been reached (`reached(state.config.closingKey)`), for the positive case as the deficit case already does.
2. Decision 7 and review §3.2 #3: on a date change clear `touched`, `saveTried`, `checkedFor`, `selected` and `notice`; keep the figures; `checkedFor` includes the date so `checkedIsCurrent()` cannot re-use another date's answer.
3. Review §3.2: #5 a failed pre-save check shows one plain line ("Could not check this day just now. Try Save again.") and keeps the previous findings, and the save does not proceed on a failed check; #6 Cancel edit returns to the date being edited (`resetForm(null, {date: currentDate()})`), Clear during an edit clears `editing`, the standing status and transient messages are kept apart so the "already saved / Edit that day" banner returns after a transient one, a stale confirmation never follows the person to another date; #7 after saving today: "Today is saved. There is no next day to enter yet. Saving again will replace it." with **Edit that day**; #8 accept `1,500`, `1 500`, `$1500` (strip before validating and sending); #9 `money()` pinned to `en-US`; #10 Escape closes the dock explanation.
4. Review §3.4: #1 (§3.7 above; raw log text never shown); #2 replace tick: "This day's file has already been made. Tick this to make it again with the corrected figures." + muted "(Only leave this unticked if the old file was already sent to the accountant.)"; #3 `CLOSED_NOTE` → "Nothing is posted for an Off day. The next work day carries this balance through."; #4 Clear asks first only when something has been typed; #5 hide the prior hint while the first-day tick box is showing; #6 prior-hint gap wording "The day before this one hasn't been entered yet. This day will still be saved; its paperwork finishes as soon as that day is entered."; #7 `released`/`held`/`nextDayStale` sentences (§3.7); #8 subtitle "Enter one day at a time and save it." and reason boxes `maxlength="400"`.
5. §3.7's Off-day Stop behaviour (skip the confirm when a Must-fix row is showing).
6. Review §3.3: #1 move `#checks-live` directly under `#view-entry`; #2 `:root { color-scheme: light; }`; #3 the Work day / Off day toggle distinguishable in forced-colours mode; #4 a `SMOOTH` helper from `prefers-reduced-motion` for the six smooth scrolls, a visible `#dock-note:focus` outline; #6 delete `.btn-danger` and the stale `#prior-hint` comment; #5 update `handoff/ui-contract.md` to the current ids, classes, endpoints and response fields (this document's §3.3 and §3.7).
7. **Browser verification:** write `handoff/verify-ui-2026-09-15b.mjs` (playwright-core + installed Chrome, server on **8798** with an empty scratch root, 1440 px and 390 px) that walks review §5.2 scenarios (a), (k), (b), (d), (e), (f), (c), (g), (h), (i), (j), (l) and the new Off-day refusal (m: L1-F row, no confirm dialog, refusal banner), asserting the words in §5.1 as updated by this document. Flows that need stream B's new fields (`nextDayStale`, `held`, `released` sentences, `"removed"`) are written but marked `INTEGRATION` and skipped unless run with `--integration`. Everything else must pass against the copy's own server. Look at every screenshot against the owner's simplicity rule and report anything that looks wrong.

Acceptance: the script passes (integration flows skipped) at both widths; no horizontal scroll at 390 px; nothing floats; palette unchanged.

## 7. How every stream runs things (safety)

- Work only in your copy (`<scratch>/agents/<stream>/v4.0`). The authoritative reference copies of the review and this document are in `E:\Ldgr\v4.0\handoff\` (read-only for you).
- **Always set `LEDGER_ROOT` to a scratch folder** before running any test, probe or server. `tests/test_endtoend_edge.jl` deletes its `LEDGER_ROOT` when it starts. Never write under any folder named `Records`.
- Tests run from a flattened copy: copy `<your copy>/v4.0/.` to `<scratch>/v4`, delete its `Records` and `handoff`, copy `tests/*.jl` next to the sources, and run each script with its own root, e.g. (Git Bash)
  `LEDGER_ROOT="$(cygpath -w "$S/root-test_server")" julia --startup-file=no test_server.jl`.
- Servers: stream C only, from its copy, `LDGR_NO_BROWSER=1`, port **8798** (8799 spare), never 8000 or 8765, never two servers on one root; stop it when done and confirm nothing listens on the port.
- Julia is single-threaded here; compilation does not yield. JSON3 compiles a writer per response type: keep one shape per endpoint.
- Long files: use the Write tool; Bash heredocs with long quoted text have failed in this harness.
- Report back: the files you changed (full paths in your copy), the test commands you ran with their final counts, anything you could not do and why, and any wording you chose that the owner should see.
