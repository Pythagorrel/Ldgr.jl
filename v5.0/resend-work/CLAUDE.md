# resend-work: replace ldgr's Gmail SMTP email with Resend (handoff, 2026-09-28)

**Superseded 2026-09-28: this brief is implemented.** The send time is 17:30, not 18:30 as below, and the send-time question is settled. `E:\Ldgr\CLAUDE.md` (its 2026-09-28 block) describes what was built; read this file as history, not as instructions.

This folder is a workspace for one job: make ldgr's daily report email reliable, using **Resend** (an email API with a free tier) and **scheduled sending**, plus a **healthchecks.io** watchdog. Nothing here has been implemented yet. Every decision below is settled, and the design has been worked through. Your job is to build it, test it, and update the docs.

Read this whole file before touching code. `E:\Ldgr\CLAUDE.md` (the project notes) also applies. Where the two differ about email, this file is newer. The first-round analysis is in `..\handoff\email-delivery-2026-09-24.md`. Its **Apps Script recommendation is superseded** by the Resend decision below, but its code audit, flaw list and "why not Dropbox" section are still accurate.

`backup-2026-09-28\` holds untouched copies of every file this job will change, taken before any edit. `Notify.jl` is **not tracked by git**, so the backup is its only other copy. Two files there were renamed so no tool mistakes them for live files: the root `CLAUDE.md` is `root-CLAUDE.md.bak`, and `.gitignore` is `gitignore.bak`.

---

## 1. What ldgr is (one paragraph)

ldgr is a Julia 1.9.2 bookkeeping program for an urgent care clinic in **Guyana** (UTC−4, no daylight saving). It runs locally on one Windows PC. Staff type the day's cash figures into a local web form served by `v4.0\server.jl` on 127.0.0.1. Every save writes the books, and appends rows to `Records\Change Log.csv` (`Changes.jl`). Once a day, `Notify.build_digest` turns the change log into a plain-text report for the clinic owner. The report covers days entered, later edits with before → after, differences with their typed reasons, gaps filled, and ledgers still waiting. The report exists partly as oversight of the staff who use the PC.

## 2. Why this job exists

- **The current transport is dead.** It is SMTP to Gmail with an app password for `ldgrapp@gmail.com`, through SMTPClient.jl. A diagnostic sign-in on 2026-09-24 got `535-5.7.8 Username and Password not accepted (BadCredentials)`. Google revoked the password one day after it first worked, and nothing told anyone for a week.
  - The failures were on the developer's test laptop, whose `Records\` folder holds no real books. The four stuck "nothing to report" test messages in `Records\Notifications\outbox\` can be ignored or deleted.
- **Other defects the audit found:**
  - SMTPClient's `get_body` builds a malformed message: no blank line after the headers and no Content-Type, so the report's first lines land in the header block.
  - libcurl blocks the single-threaded server during a send, with no timeout.
  - Failures are visible only in `Records\audit_log.txt`.
  - An unreadable change log produces a false "nothing to report".
- **The owner's 2026-09-15 decision (Gmail SMTP, "no third-party email API") is replaced** by the 2026-09-28 decisions below.

## 3. Settled decisions: do not re-ask

From the owner, 2026-09-28:
1. **The clinic owner receives the report,** and a phone notification is wanted. Resend mail comes from a different sender (`onboarding@resend.dev`), so it notifies normally.
2. **The clinic is closed on Sundays.** The owner said "I think", so the watchdog schedule must be easy to change.
3. **ldgr is normally opened at closing time,** to type the day in, then closed. Sometimes it is opened at the start of or during the day to clear a backlog of missed days. **ldgr is usually NOT running at the send time.** So the PC must hand the report to Resend in advance, and Resend sends it at the fixed time.
4. **healthchecks.io is approved** as the watchdog. It holds no figures.
5. **No Dropbox folder.** An archive staff can't touch is acceptable in its place; with Resend, the owner's own inbox is that archive.
6. **Resend is the default transport.** The owner asked "why not just use Resend?" There is no integration difficulty, and the earlier objections were non-technical.

Still in force from 2026-09-16 (do not change):
- **One report a day at a fixed time,** never one email per save. `send_at` defaults to **18:30**.
- **A quiet day still sends** "nothing to report".
- **A missed report is caught up at the next start, as one email.** Section 5 refines this.
- **"Session" = one calendar day.** Edits on the calendar date a day was first saved are free and not reported; an edit on a later date is reported with before → after. A "pending day" (a saved day whose ledger is held waiting on a missing day before it) is reported when edited, even on the same date. These rules live in `Changes.jl` and `build_digest` today; keep them.
- **The entry form stays completely silent about email.** Do not change `public\app.js`, `index.html`, `styles.css` or `Checks.jl`, and do not change `/api/save`'s response.
- **Nothing is ever sent for a refused save.**
- **No warning codes** (L2-A etc.) appear in the report. Money is written `$1,234.00` and dates as "3 September 2026".
- **Never calculate or derive a closing balance anywhere.** It is a physical drawer count.
- **The owner starts the server from the Julia REPL** with `include("server.jl")` then `start()`. That path must keep working, as must `julia server.jl` and `ldgr.bat`.
- **Keep the Chrome app-window launcher in `server.jl`.**

Open: **the send time.** It must be after the day is normally typed in; if staff type after 18:30, the day lands in the next day's report and the watchdog raises a false alarm. The developer was asked and has not answered. Keep the code default at 18:30, make `send_at` easy to change in `notify.toml`, and raise it again in your final summary.

## 4. Resend facts (verified 2026-09-24/28 unless marked)

- **Free plan:** 100 emails a day (UTC calendar day), 3,000 a month, 30-day data retention. https://resend.com/docs/knowledge-base/account-quotas-and-limits, https://resend.com/pricing. "No credit card" is **unverified**.
- **No domain is needed.** The testing sender `onboarding@resend.dev` "can only send emails to the email address associated with your Resend account"; any other recipient gets 403 "You can only send testing emails to your own email address". So **the Resend account must be opened with the owner's address, and `to` must be that address.** Resend calls this sender "only available for testing purposes", and its terms let it change the free tier without notice. The fallback is a cheap domain, which changes only `from`. https://resend.com/docs/knowledge-base/403-error-resend-dev-domain
- **Send:** `POST https://api.resend.com/emails`, JSON `{from, to:[...], subject, text, scheduled_at?}`, header `Authorization: Bearer re_...`. The reply is `{"id": "<uuid>"}`. https://resend.com/docs/api-reference/emails/send-email
- **Scheduling:** `scheduled_at` accepts ISO 8601 (for example `2026-08-05T11:52:01.858Z`) or natural language, **up to 30 days ahead**. It works through the API only, not SMTP. https://resend.com/docs/dashboard/emails/schedule-email
- **Update:** `PATCH /emails/{id}` can change **only `scheduled_at`**, not the content. So a new version of the report means creating a new email and cancelling the old one. https://resend.com/docs/api-reference/emails/update-email
- **Cancel:** `POST /emails/{id}/cancel`. The reply is `{"object":"email","id":...}`. "Once an email is canceled, it cannot be rescheduled." What happens when you cancel an email already sent is **not documented**; treat any 4xx other than 401/403/429 as "nothing left to cancel".
- **Retrieve:** `GET /emails/{id}` returns `last_event` (for example "delivered") and `scheduled_at`. It is not needed in v1.
- **API key permissions:** `full_access` "can create, delete, get, and update any resource"; `sending_access` "can only send emails". A sending key gets 401 `restricted_api_key` ("This API key is restricted to only send emails") on anything else. **Cancel almost certainly needs a Full access key.** That is not confirmed, so test it once during setup and make the audit-log sentence for this 401 say exactly that. https://resend.com/docs/api-reference/api-keys/create-api-key
- **Idempotency:** the `Idempotency-Key` header takes 1–256 characters and expires after 24 h. The same key with a modified body gives 409 `invalid_idempotent_request`; a concurrent request gives 409 `concurrent_idempotent_requests`.
- **Errors:** https://resend.com/docs/api-reference/errors

  | Status | Meaning |
  |---|---|
  | 400 | `validation_error`, invalid idempotency key |
  | 401 | `missing_api_key`, `restricted_api_key` |
  | 403 | invalid or suspended key; "You can only send testing emails to your own email address"; domain not verified |
  | 404 | not found |
  | 409 | idempotency |
  | 422 | missing field, invalid parameter |
  | 429 | `daily_quota_exceeded`, `monthly_quota_exceeded`, `rate_limit_exceeded` |
  | 500 / 503 | temporary |

  The error body is JSON, roughly `{"statusCode":..,"name":..,"message":..}`. Parse it defensively.
- **Webhooks:** a webhook can subscribe to selected events. `email.delivered` fires when "Resend successfully delivered the email to the recipient's mail server". The endpoint must return 200; retries run from immediately to 10 h. The free plan appears to allow **1 endpoint** (third-party sources only). https://resend.com/docs/webhooks/event-types, https://resend.com/docs/webhooks/retries-and-replays
- **The watchdog needs no code on the PC.** A Resend webhook (event `email.delivered` only) points at the healthchecks.io ping URL; healthchecks accepts POST pings. Use a healthchecks **Cron** check at the send time, Mon–Sat (`30 18 * * 1-6`, time zone `America/Guyana`), with grace of about 1–2 h. It alerts the owner (and the developer) when a working day passes without a delivered report.
  - The healthchecks free plan emails alerts, gives 20 checks, and requires alert addresses to be confirmed. It closes accounts after a year with no log-in.
  - A holiday means pausing the check; it resumes on the next ping.

## 5. The design to build

### 5.1 Files

- **New `v4.0\Resend.jl`,** `module Resend`, using HTTP, JSON3 and Dates. It is an HTTP client only and knows nothing about ldgr. **It is included by `server.jl`, not by `main.jl`,** so the command-line path (`main.jl`) and anything that only includes `main.jl` never load HTTP.jl (about 3.5 s to load without the sysimage).
  - `const API_BASE = Ref("https://api.resend.com")`, so tests can point it at a local stub.
  - `const TIMEOUTS = Ref((connect = 10, read = 30))`.
  - `struct Failure <: Exception; kind::Symbol; words::String; end`, where `kind` is `:settings` (a person must fix notify.toml or the Resend account) or `:temporary`. `showerror` prints `words`.
  - `send(key, email::AbstractDict; idempotency_key) -> id::String`: POST /emails.
  - `cancel(key, id) -> Nothing`: POST /emails/{id}/cancel. A 404 or other non-auth 4xx means there is nothing left to cancel, so it returns normally.
  - Every call: `HTTP.request(...; connect_timeout, readtimeout, retry=false, status_exception=false, redirect=false)` inside try/catch. Network exceptions (ConnectError, TimeoutError, DNS) become `Failure(:temporary, "The internet or Resend could not be reached …")`.
  - Map statuses to one plain sentence each:
    - 401 `restricted_api_key`: "the key can only send; make a Full access key so an earlier version of the report can be cancelled";
    - 401/403 key missing, invalid or suspended: `:settings`;
    - 403 own-address rule: "Resend only sends to the address the Resend account was opened with; `to` in notify.toml must be that address";
    - 422: `:settings`;
    - 429, 5xx, 409: `:temporary`.
  - **The key never appears in any text it builds.**
- **`Notify.jl`:** pure logic, no HTTP.
  - `const MAILER = Ref{Any}(nothing)`, holding `(send = (key, email, idem) -> id, cancel = (key, id) -> nothing)`. `server.jl` sets `Notify.MAILER[] = (send = Resend.send-with-keyword-adapter, cancel = Resend.cancel)` right after including Resend.jl. Tests plug in a fake NamedTuple.
- **`Layout.jl`:**
  - Delete `outbox_dir`, `sent_dir`, `notice_name`, `outbox_path` and `sent_path` (lines 167–199).
  - Keep `notify_config_path` (163), `notifications_dir` (165) and `digest_marker_path` (186).
  - Add `scheduled_state_path() = joinpath(notifications_dir(), "scheduled report.toml")`.
  - README rule 2: **no path is built outside Layout.jl**.
- **`server.jl`:** see 5.6.
- **`main.jl`:** unchanged. The CLI never sends; the next server start picks up its rows.
- **`Changes.jl`:** a small read-status change (5.5).

### 5.2 notify.toml keys (replace the SMTP keys)

```toml
to = "owner@…"              # the owner; MUST be the address the Resend account was opened with
api_key = "re_…"            # a Resend Full access key (see §4)
from = "Clinic daily report <onboarding@resend.dev>"   # optional; this is the default
subject_prefix = "ldgr: "   # optional
send_at = "18:30"           # optional; 24-hour clock, clinic time
```

- `enabled()` needs both `to` and `api_key`.
- An old SMTP-style file (it has `password`, `smtp` and `user` but no `api_key`) counts as **off**. The banner must say why: `off (notify.toml has no Resend api_key)`.
- The real `v4.0\notify.toml` on the developer's laptop holds the dead Gmail app password. **Do not read or print its password.** Leave the file alone; the developer will rewrite it.
- `_scrub` removes `api_key` from any error or log text.

### 5.3 State that survives restarts

- **`Records\Notifications\last report.txt`** (existing marker): the cutoff up to which reports are known to be complete, meaning handed to Resend and past their send time. Keep `last_reported()` and `mark_reported!()` (atomic temp file + `mv`). Add a guard: a marker more than 5 minutes in the future is ignored (use `due − 1 day`), with a note in the next report.
- **`Records\Notifications\scheduled report.toml`** (new; write it with the stdlib `TOML` via a temp file + `mv`):
  - `id`: the Resend email id of the version currently waiting.
  - `cutoff`: when it will be sent, clinic local time.
  - `from`: the start of its window, or `""` meaning "from the beginning".
  - `rows`: the number of change-log rows in `(from, cutoff]` when it was built.
  - `generation`: an integer bumped after every successful create.
  - `cancel`: a list of earlier ids still to be cancelled.

### 5.4 `tick(; at = now(), force = false) -> Vector{Symbol}`

Runs under a lock, every 60 s from the timer and once right after each save (5.6). Everything is re-derived from notify.toml, the marker, the state file and the change log, so a restart at any moment resumes correctly.

0. **Preconditions.**
   - `cfg = settings()`; if it is `nothing`, return `[:off]`. If `MAILER[] === nothing` (the CLI), return `[:no_mailer]`.
   - Honour the backoff: after a `:temporary` failure wait 5 minutes; after a `:settings` failure wait 60 minutes, **or** until notify.toml's modified time changes. A save's poke may retry sooner.
1. **Cancel leftovers.** For each id in `state.cancel`, while its version's cutoff is still in the future: cancel it; remove it on success, keep it on a temporary failure. Once the cutoff has passed, drop the id and log "an earlier version may also have been sent".
2. **Settle a version whose time has come** (`state.cutoff <= at`):
   - Count the rows in `(state.from, state.cutoff]` now.
   - If the count equals `state.rows`, the version Resend sent was complete: `mark_reported!(state.cutoff)`, clear the state, and push `:settled`.
   - If there are more rows now, a save happened after the last version was handed over (offline, or less than a minute before the send time). Send a **corrected report immediately**, with no `scheduled_at`, for `(state.from, state.cutoff]`. Its subject says "corrected report for …" and its first body line is: "This replaces the report sent at 6:30 pm, which was prepared before the last entry of that day could be sent." On success, mark and push `:sent`; on failure, keep the state and stop this tick.
3. **A closed window nothing covered.**
   - `due_past = latest_cutoff(at, send_at)`.
   - If there are rows in `(marker, due_past]` (the marker may be `nothing`, meaning from the beginning), send them **now**, as one late report, in the existing catch-up style. Body note: "This report is late: it could not be sent at 6:30 pm, usually because ldgr was closed or offline before it could hand the report over." On success `mark_reported!(due_past)`.
   - This happens after CLI saves, offline saves, a crash, or Resend being down.
   - If there are **no** rows in the missed stretch, send nothing separately. The coming report simply starts at the old marker (it "folds"), so a closed Sunday does not produce a pointless Monday email.
4. **Schedule or refresh the coming report.**
   - `next = next_cutoff(at, send_at)`, the first cutoff strictly after `at`.
   - `from = marker`, after steps 2–3.
   - `n` = the number of rows in `(from, next]`.
   - If a state exists with the same `cutoff`, the same `from` and `rows == n`, do nothing.
   - If `next - at < 1 minute`, do nothing: a late change is caught by step 2 as a correction.
   - Otherwise, build `build_digest(from, next)` and **create the new version first** (`scheduled_at = next` converted to UTC, `"yyyy-mm-ddTHH:MM:SS.000Z"`). Compute the local offset at call time as `round(now() - now(UTC), Minute)`; do not hard-code −4.
   - On success: save the new state (`generation + 1`), move the old id to `cancel`, try the cancels at once, and push `:scheduled`. On failure: keep the old state, whose older version still goes out, and log.
   - **A report is scheduled on every day ldgr is opened, even with no saves** (a quiet report). That keeps "a quiet day still sends". A day ldgr is never opened sends nothing, and the watchdog alerts.
5. **`force = true`** (`LDGR_DIGEST_NOW=1`, for manual testing only): send `(marker, at]` immediately, mark `at`, then carry on with step 4, which reschedules from the new marker and cancels the old version.

**Idempotency keys** must be deterministic, so that a retry after a lost reply cannot create a duplicate:
- scheduled: `"ldgr-" * yyyymmddHHMM(cutoff) * "-g" * generation * "-" * first16hex(sha256(canonical body))`;
- late: `"ldgr-late-…"`;
- correction: `"ldgr-fix-…"`;
- forced: `"ldgr-now-…"`.

Use the stdlib `SHA`. The canonical body is `from|to|subject|text|scheduled_at`. **The report body must therefore be deterministic.** Do NOT put "prepared at <now>" in it. Instead add one line, "Includes everything saved up to 5:42 pm on 28 September", taken from the `when` of the last row in the window, and omit it when there are no rows. It also tells the owner which version is newest if two ever arrive.

**Audit log** (`AuditSession`, header "email", `echo=false`): one line per real action: scheduled (with the send time and the "saved up to" time), earlier version cancelled, settled, late report sent, correction sent. For failures, log a line only when the problem text changes or an hour has passed, so an offline evening does not write a line every 5 minutes. Also `@warn` in the terminal under the same throttle.

### 5.5 Report text changes (`build_digest`)

- **Signature:** `build_digest(from, to; note = "")`. `note` is printed under the heading, used by the late and correction paths.
- **Replace the multi-day line** (current 392–396, "This report is late: the program was not running…"): "This report covers more than one day: no report was sent at 6:30 pm on the days in between, usually because ldgr was not opened."
- **The "Includes everything saved up to …" line** (5.4).
- **Footer** (current 439–441): "This report is sent at 6:30 pm on each day ldgr is used. If none arrives on a working day, ldgr was not opened that day or the email settings need attention." Use `_clock(send_time)` as now.
- **Never a false all-clear.**
  - Add `Changes.rows_checked(from, to) -> (rows, problem::String)`.
  - `_read_log` and `_rows_from` report unreadable files, missing columns and skipped lines as a problem string, instead of only `@warn`ing; the existing `rows_between` keeps its behaviour.
  - When `problem` is non-empty, the subject becomes `"<prefix>CHANGE LOG COULD NOT BE READ — report for …"`. The first body line says the log could not be read properly, so this report may be missing entries and is not a quiet day. The "Nothing was entered or changed" sentence is suppressed.
- **Fix the next-morning edit bug** in `_entered_block` (current 539–553).
  - A day first saved after the send time and edited on a later calendar date before the next send time has both rows in one window. Today it shows only "Changed again by X at T", so the owner's later-date rule is silently broken.
  - Fix: when any row after the first save has `cross_day_edit` or `pending_day`, print that row's `changed` parts (split on `"; "`), as `_changed_block` does, plus "Changed on <date> by <who> at <time>".
- **Keep** every existing heading, wording and rule that tests groups 2–14 assert, including the exact quiet sentence "Nothing was entered or changed today, and every recorded day has its ledger."

### 5.6 Server wiring (`server.jl`)

- After `include("main.jl")` (line 38): `include("Resend.jl"); using .Resend`, then set `Notify.MAILER[]`.
- **Banner** (1097–1099): `on -> <to>  (daily report at 18:30, sent by Resend; last complete report: <marker or "none yet">)`, or `off (no notify.toml)`, or `off (notify.toml has no Resend api_key)`.
- **Delete the `Notify.preload()` block** (1124–1137). Keep `Notify.start_schedule!()`.
- **In `handle_save`,** after the `Changes.after_save` try block (573–577), inside its own try: `Notify.poke()`.
  - `poke()` returns at once unless the scheduler is running. It runs `@async` a locked tick, so **the save's response never waits on the network**, and a day typed right before ldgr is closed is handed to Resend within seconds.
  - Only `handle_save` calls it; `/api/next` writes nothing.
- **Locking:** `const BUSY = ReentrantLock()`. The timer callback uses `trylock` and skips a beat if busy; `poke` uses `lock` and waits. Both are wrapped so that nothing throws out of a Timer callback (a throwing callback kills the timer silently).
- **Guard against two timers.** Re-including `server.jl` in the same REPL redefines the module and leaves the old Timer running old code, so two schedulers would race and create duplicate versions. In `start_schedule!`, close any timer recorded in a process-global (for example `Main.LDGR_REPORT_TIMER`, set via `Core.eval(Main, …)`) before starting the new one.
- **Warm-up** (909–915): keep it read-only and network-free. Call `build_digest`, `next_cutoff`, `latest_cutoff`, the state reader, and `precompile(Resend.send, …)` / `precompile(Resend.cancel, …)` by signature.
- **Delete from Notify.jl:**
  - `TRANSPORT` (75, 1120), `LAST_FLUSH` (83), `SMTP_LOADED` (92), `FIRST_TICK` (89; the first tick is not special any more, except `LDGR_DIGEST_NOW`);
  - `enqueue`, `_read_notice`, `_bump_attempts` and `flush!` (827–958);
  - `_reachable` and `_host_and_port` (978–1032), `_load_smtp` and `preload` (1049–1070), `_addr` (1086), `_smtp_send` (1104–1118);
  - `Sockets` from `using`.
  - `SMTPClient` is then unused. The sysimage (`sysimage\*.jl`) never included it, so no rebuild is needed.
- **Keep** `settings`/`_send_at` (reworked), `enabled`, `recipient`, `send_at_text`, `latest_cutoff`, `last_reported`, `mark_reported!`, `build_digest` and all its helpers, `start_schedule!`, `stop_schedule!`, `LDGR_NO_DIGEST` and `LDGR_DIGEST_NOW`.
- **Add** `next_cutoff(t, at)`.
- **Rewrite the module header comment** so it describes the new design truthfully (the file's comment style is long, plain-English "why" blocks; match it).

## 6. Tests

- **Rewrite `v4.0\tests\test_notify.jl`.** Keep its safety preamble, and its groups 2–14 as they are, apart from the settings block in group 3 (which becomes the new keys; assert that the key never reaches the audit log).
  - Replace groups 1 (`flush!` line), 15 (add `next_cutoff` cases, including after midnight and exactly at the cutoff) and 16–19 (outbox and SMTP) with:
    - (a) a fake MAILER NamedTuple that records creates and cancels and can be made to fail with `Resend.Failure` of either kind, used to test every branch of 5.4: first schedule; a save reschedules (new create, then cancel of the old); no change means no call; within a minute of the cutoff nothing happens; settle after the cutoff moves the marker and schedules tomorrow; a correction when a row arrived after the last version; a late send for a missed window with rows; a quiet missed stretch folds (no send, and the next report covers several days and says so); a cancel that fails is retried and dropped after the cutoff; `:settings` backoff until notify.toml's mtime changes; a future marker is ignored; `scheduled_at` is the right UTC string; idempotency keys are stable across a rebuild of the same content and change with the generation.
    - (b) `include("Resend.jl")` and a **local stub server** (`HTTP.serve!` on 127.0.0.1, spare port) with `Resend.API_BASE[]` pointed at it. It checks the `Authorization`, `Idempotency-Key` and `Content-Type` headers, the JSON body fields, the cancel path, the classification of 401 restricted, 403 own-address, 422, 429, 500, a reply slower than `TIMEOUTS[].read` (set it to 2 s) and a refused connection. Finish with one end-to-end tick through the real `Resend` functions against the stub.
    - (c) New cases for the false all-clear guard (unreadable log, missing column) and the next-morning edit fix.
  - **No test may contact Resend or the internet.** The harness should refuse to run if `Resend.API_BASE[]` is not a 127.0.0.1 URL.
- **`tests\test_endpoints.jl`** must still pass, because the warm-up and `handle_save` change. The check count is in `E:\Ldgr\CLAUDE.md` (99).
- **How to run (Windows).** Tests `include("main.jl")` relative to their own folder, so run them from a flattened scratch copy. The pattern is in `..\handoff\verification.md` and `..\tests\TESTING.md`. In PowerShell:

  ```powershell
  $S = "$env:TEMP\ldgr-test"
  Remove-Item -Recurse -Force "$S\v4" -ErrorAction SilentlyContinue
  Copy-Item -Recurse E:\Ldgr\v4.0 "$S\v4"
  Remove-Item -Recurse -Force "$S\v4\Records","$S\v4\handoff","$S\v4\sysimage","$S\v4\notify.toml","$S\v4\resend-work" -ErrorAction SilentlyContinue
  Copy-Item "$S\v4\tests\*.jl" "$S\v4\"
  cd "$S\v4"
  $env:LDGR_NO_DIGEST = '1'; $env:LDGR_NO_BROWSER = '1'
  $env:LDGR_NOTIFY_CONFIG = "$S\no-such-file.toml"
  foreach ($t in 'test_checks_titles','test_endtoend','test_endtoend_edge','test_endpoints','test_notify') {
    $env:LEDGER_ROOT = "$S\root-$t"
    julia --startup-file=no "$t.jl" | Select-Object -Last 2
  }
  ```

  Earlier totals: titles 23, end-to-end 45, edge 32, endpoints 99, notify 156, all with FAILED 0. The notify count will change.
- **Safety rules, from `E:\Ldgr\CLAUDE.md`:**
  - Always set `LEDGER_ROOT` to a scratch folder; without it, everything is written into `v4.0\Records\`.
  - Always set `LDGR_NO_DIGEST=1` and a non-existent `LDGR_NOTIFY_CONFIG` for any test or scratch server.
  - `test_endtoend_edge.jl` **deletes** its `LEDGER_ROOT`.
  - To start a scratch server: `LDGR_NO_BROWSER=1`, then `julia --startup-file=no server.jl 8765`.
  - Don't commit or push unless asked.

## 7. Docs to update when the code is done

- **`v4.0\notify.example.toml`:** rewrite for Resend. Say what is sent and when, the scheduling behaviour in plain words, and the owner-address rule. Include the setup steps:
  1. Open a Resend account **with the owner's own address**.
  2. API Keys → Create → **Full access**, named "ldgr".
  3. Paste the key into notify.toml.
  4. Webhooks → add the healthchecks.io ping URL, event `email.delivered` only.
  5. healthchecks.io: a Cron check, `30 18 * * 1-6`, time zone America/Guyana, grace 1–2 h; add the owner's email and confirm it.
  6. In the owner's Gmail on a computer, add a filter for `from:onboarding@resend.dev OR from:healthchecks.io` → Never send it to Spam, Always mark as important, Categorize as Primary.
- **`v4.0\README.md`:** the email section (lines ~107–126), the `Records\Notifications\` tree line (~90), the Files table (add `Resend.jl`, reword `Notify.jl`), and the test line (~141).
- **`v4.0\tests\TESTING.md`:** the `test_notify.jl` section (~144–160).
- **`E:\Ldgr\CLAUDE.md`:** rewrite the email bullets (the "2026-09-16, later" block). Add `LDGR_DIGEST_NOW` / `LDGR_NO_DIGEST` meanings if they changed, and a new dated bullet for this work. Remove the pointer to this workspace once the job is finished.
- **`v4.0\handoff\email-delivery-2026-09-24.md`:** add a short note at the top: "Superseded 2026-09-28: the owner chose Resend with scheduled sending plus a healthchecks.io watchdog; see resend-work\CLAUDE.md."

## 8. Definition of done

- All five test scripts pass from a flattened copy.
- A scratch server starts, with the banner correct in the three states (off / no api_key / on), and saving a day triggers exactly one create call against a local stub.
- Nothing contacts Resend.
- The docs above are updated.
- The final summary to the developer includes:
  - what changed, with file and function;
  - the test counts;
  - the setup checklist (§7);
  - the open send-time question;
  - two things to verify on the first live run: that cancel works with the Full access key, and that the webhook ping reaches healthchecks.
- Nothing is committed.
