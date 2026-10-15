**Superseded 2026-09-28:** the owner chose Resend with scheduled sending plus a healthchecks.io watchdog; see `resend-work\CLAUDE.md`.

# ldgr daily report delivery: revised recommendation

Date: 2026-09-24. Produced by two research rounds: six researchers (code audit, machine probe, Google options, email services, synced folders, push channels and watchdogs), then three fact-checkers and three red teams (tampering, reliability, scope). Nothing under `E:\Ldgr` was changed while it was written, apart from saving this file.

In this document, **owner** means the clinic owner who receives the report. **Developer** means whoever maintains ldgr and does the setup. If they are the same person, see decision 2.

---

## 1. Recommendation

1. **ldgr stops sending email itself.** At 18:30, or at the next start if the PC was off, it sends the unchanged `build_digest` report and a shared secret over HTTPS (a POST) to a small Google Apps Script web app. The web app runs in the clinic's dedicated Google account, ldgrapp@gmail.com, which the developer operates.
2. **What the script does:**
   - mails the report to the owner's address, which is fixed inside the script;
   - saves every report in a Google Sheet that the owner can view but not edit;
   - flags anything odd: two different reports for one day, a report that arrives before its own cut-off time, or a stretch of time no report covered;
   - if nothing has arrived for 30 opening hours, emails "No clinic report for N days". Closed weekdays do not count toward the 30 hours.
3. **The independent watchdog.** The relay and its alarm share one Google account. So a free healthchecks.io check, pinged by the script only after each email has been accepted, emails the owner and the developer if nothing gets through for 2½ days.
4. **What it fixes and costs.** It removes the Gmail app password that died, the SMTP send that froze the server, and the silence when sending fails. The alarm and the watchdog run on clocks staff cannot touch. It is free and puts no Google password or token on the clinic PC. Saving a day never touches the network.
5. **What the owner does once.** A 15-minute call with the developer:
   - confirm a test email makes their phone buzz, and read back a 6-digit code;
   - set up one Gmail filter, on a computer;
   - click one healthchecks confirmation link;
   - keep an envelope with the reporting account's password.
   After that the owner has one standing rule: a "No clinic report" email, a healthchecks "DOWN" email, or two days with no email at all means call the developer.

---

## 2. Why not Dropbox

**What Dropbox would give:** a folder of report files the owner can browse in the Dropbox app, 30-day version history and deleted-file recovery on the free Basic plan, and no Google involvement.

**What it would not give** (every point verified):
- **No phone alert when a report lands.** Dropbox's iOS push covers only shared-folder invitations and shared links (help page updated 11 Sep 2026; a moderator confirmed it in Dec 2023). It is a folder the owner has to remember to open, so a quiet late edit sits unread. That defeats the oversight purpose.
- **No write-only access for the PC.**
  - File requests cannot be filled by a program: the published API has no upload route for them, Dropbox staff said so from 2015 to 2019, and the acceptable use policy forbids scripting the web page.
  - Uploading and deleting need the same permission (`files.content.write`). So any token on the PC can overwrite, rename, move or delete reports. Deleted files can be recovered for 30 days, but only if someone notices.
- **The simple design tells the owner nothing.** App folders cannot be shared or followed.
- **The workable design is heavy and still weaker.** It needs three accounts (the owner's Dropbox, a separate clinic Dropbox, and a watchdog), plus a shared folder the owner follows. Even then:
  - the follow emails only name the file, and are batched about every 10 minutes;
  - they are silent for renames and moves;
  - whether they fire at all for uploads made through the API is unverified;
  - the clinic account can permanently delete any file only it has touched.
- **Other gaps:** "Email to Dropbox" is paid only. A desktop sync app can be paused or signed out without anyone noticing. A second company holds the figures, and the same watchdog is still needed.

**The relay's Sheet covers the owner's idea (a folder holding every report) better:**
- The PC holds only a URL and a secret, so it can add reports but never edit or delete them.
- The owner opens the Sheet in the Google Sheets or Drive app.
- The same script sends the push email and the alarm.
- Google Drive, like Dropbox, does not notify you about new files in your own folders, so the email remains the push.

**If the owner still wants Dropbox (version 2, only on request):** the relay, not the PC, also uploads each report as a .txt file into a folder in the owner's Dropbox. It uses a Dropbox refresh token kept in the script's own settings (Script properties, which only the Google account can see). That is about 40 lines of script. No Dropbox token ever sits on the PC, Dropbox becomes a read-only copy, and the email and alarm are unchanged.

---

## 3. Architecture

### 3.1 Components, and which account hosts what

| Where | What runs there | Why there |
|---|---|---|
| **Clinic PC (ldgr)** | `build_digest` as today; a new sender `_relay_send` (HTTP.jl + JSON3, both installed). It holds `relay_url` and `relay_secret` in notify.toml, and no recipient address. | Nothing on the PC can read, delete or redirect mail. |
| **ldgrapp@gmail.com**: a dedicated clinic reporting account. The developer operates it; the owner keeps the password and backup codes and is its recovery contact. | The Apps Script **relay**, attached to the "Clinic daily reports" Sheet: `doPost` (receive), `checkMissing` (the daily alarm), `setup()`. The Sheet is shared with the owner as a viewer. | (1) Mail from another address reaches the owner as ordinary incoming mail. Mail an account sends to itself may land only in Sent or All Mail and not notify: Google's page on aliases; an Apps Script report from 2021; a developer issue dated today, 2026-09-24. (2) Redeploys, re-authorising the script and Google's failure emails land on the developer, not on a non-technical owner. (3) The "unverified app" consent and a web app open to anonymous callers stay out of the owner's main account. (4) It matches the owner's 2026-09-15 choice of "the clinic's own mailbox". |
| **healthchecks.io** (free Hobbyist plan; account under the developer's address; the owner's address added and confirmed) | One check, "Clinic daily report", pinged by `doPost` after each email is accepted. The ping carries no body. | It is the only alarm that survives ldgrapp itself failing: account disabled, locked, lost authorisation or daily limit used up. |
| **Owner's Google account** | Nothing runs there. Only a Gmail filter and view access to the Sheet. | Avoids asking the owner to operate Apps Script and avoids self-sent mail. |

**Hosting options rejected:**
- **Relay and alarm in the owner's account:** the report is then self-sent mail, which may not notify, and the owner would have to operate Apps Script.
- **Relay and alarm in ldgrapp with no outside watchdog:** one account's failure silences both, and its failure notices land in a mailbox nobody reads.
- **A watchdog in the owner's account that reads the owner's Gmail** (the verifier's option c): it puts an unverified app with a restricted Gmail-reading permission into the owner's main account, and it needs Calendar pop-ups because its own alarm would be self-sent. healthchecks gives the same independence with nothing in the owner's account. Kept as a version 2 alternative only.

### 3.2 ldgr's delivery rule (replaces the outbox)

- **The marker moves only on delivery.** The marker is the saved time of the last cut-off reported (`<ROOT>/Notifications/last report.txt`). It now moves only when the relay confirms delivery, not when a report is queued. After an outage the owner gets one report covering the whole undelivered stretch, which is the owner's own 2026-09-16 catch-up rule. The outbox, the sent folder and the files staff could edit while offline all disappear.
- **Retries resend identical bytes.** The payload is built once for each (marker, due) pair and kept in memory, so a retry sends exactly the same bytes and the relay can recognise it. `build_digest` has no clock in it: it depends only on (from, to), the change log and the live list of waiting ledgers.
- **Timing of attempts:**
  - Every 10 minutes while a report is owed.
  - Nothing is ever locked out: there is no Google sign-in to protect any more, and a wrong secret costs nothing.
  - Each attempt uses `connect_timeout=10, readtimeout=60, retry=false, status_exception=false` and follows the redirect by default. The probe showed the timeouts apply to each step separately, so the worst case per attempt is about 260 s.
  - The attempt runs in the timer task. The probe measured the server answering another request in 54 ms during a hung call.
- **Nothing reaches the form.** Results go to the audit log in plain words (once per kind of failure per hour) and to the start-up banner.

### 3.3 The POST contract

`POST <relay_url>`: the deployment URL ending in `/exec`, with nothing after it, never `/dev`. `Content-Type: application/json`.

| Field | Example | Meaning | In the hash? |
|---|---|---|---|
| `v` | `1` | Contract version | no |
| `secret` | 32 random characters | Shared secret (in the body, never the URL) | no |
| `id` | `"2026-09-24T18:30:00"` | The cut-off this report runs to, in clinic time (ldgr's `due`) | no |
| `from` | `"2026-09-23T18:30:00"` or `null` | The cut-off the last delivered report ran to (ldgr's marker) | no |
| `subject` | `"ldgr: report for 24 September 2026 — nothing to report"` | Unchanged | **yes** |
| `body` | plain text, at most 150 KB | Unchanged `build_digest` text, plus any notes | **yes** |
| `produced` | `"2026-09-24T18:30:05"` | PC local time when built | no |
| `sent_utc` | `"2026-09-24T22:30:07Z"` | PC time in UTC at this attempt | no |
| `utc_offset` | `"-04:00"` | The PC's time-zone offset | no |

The hash is the SHA-256 of `subject + "\n" + body`.

**Replies.** Apps Script cannot set an HTTP status code, so every relay answer is JSON with status 200, served after Google's 302 redirect. The relay wraps everything in try/catch so it always answers JSON:
- `{"ok":true,"id":"…","duplicate":"no|same|different","mailed":true,"relay":"1.0"}`
- `{"ok":false,"error":"bad-request|secret|unconfirmed|busy|mail|relay","detail":"…"}`

**How ldgr classifies what comes back.** The classification only chooses the words for the log; every failure is retried the same way.

| What comes back | ldgr's reading (audit log / banner) | Action |
|---|---|---|
| 200, JSON, `ok:true`, same `id` | Delivered (log notes "same" or "different" if it was a duplicate) | `mark_reported!(due)`, clear the pending payload |
| 200, JSON, `ok:true`, different `id` | "The relay answered for another report" | Retry in 10 min |
| `ok:false, error:"secret"` | "The relay refused the password in notify.toml" | Retry (harmless: the relay sends no email) |
| `ok:false, "unconfirmed"` | "The relay's recipient has not been confirmed yet" | Retry |
| `ok:false, "busy"/"mail"/"relay"` | "The relay could not send the email just now: <detail>" | Retry |
| 200 HTML, and the final host is `accounts.google.com` or the page mentions `ServiceLogin` | "Google asked for a sign-in: the relay's access setting or its account needs attention" | Retry |
| 200 HTML otherwise, or anything that is not JSON | "Google answered with an error page (usually temporary)" | Retry |
| 404 | "The relay address in notify.toml is wrong, or the deployment was removed" | Retry |
| 405 (Google changed the redirect to a 307/308, so the POST was re-sent) | "The relay's redirect changed; tell the developer" | Retry |
| 5xx, 429 | "Google had a temporary problem" | Retry |
| TimeoutError, ConnectError, DNS or other I/O error (these throw even with `status_exception=false`) | "The internet or Google could not be reached" | Retry |

### 3.4 The relay's rules (`doPost`, in order)

1. **Parse.** Malformed input or missing fields gets `bad-request`.
2. **Secret.** A wrong secret increments `BAD_SECRET_COUNT`, sends no email, writes no Sheet row, and returns `secret`.
3. **Recipient confirmed?** If `CONFIRMED` is not set (see setup), return `unconfirmed`. This guards against a mistyped recipient sending clinic figures to a stranger.
4. **Take the script lock** (`LockService.getScriptLock().tryLock(30000)`). If it is not free, return `busy`.
5. **Check whether this id has been seen** (the last 60 ids and their hashes are kept in Script properties):
   - **Same id, same hash:** a genuine retry, for example a lost reply or a second timer. Return `duplicate:"same"`. No email.
   - **Same id, different hash:** archive it and email the owner "[CHECK] Two different reports for 24 Sep" with both texts; the first comes from the Sheet. Return `ok:true, duplicate:"different"`. The relay never silently drops a report, so a forged early report cannot swallow the real one. The email says it can be harmless: the PC restarted between a lost reply and a retry, and the list of waiting ledgers changed in between.
   - **New id:** continue.
6. **Work out flags on Google's clock.** "Received" is Google's own `new Date()`; ids are read as America/Guyana time, which is fixed at UTC−4 with no daylight saving.
   - **Early:** received more than 10 minutes before the id's own cut-off. Subject gets `[CHECK]`, with the note "arrived before its own cut-off: the clinic PC's clock is wrong or this report is not genuine".
   - **Clock:** received and `sent_utc` differ by more than 10 minutes, or `utc_offset` is not `-04:00`. Note: "the clinic PC's clock or time zone is off".
   - **Continuity** against `LAST_TO`, the id of the last new report:
     - `from == LAST_TO`: fine.
     - `from > LAST_TO`: `[CHECK]` "nothing was received covering <LAST_TO> to <from>".
     - `from < LAST_TO`: "repeats part of the previous report (the PC did not hear back last time)".
     - `from == null` after the first report, or `id < LAST_TO`: `[CHECK]`.
   - **Late:** received more than 2 hours after the cut-off. The first body line says so. This is information, not an alarm.
7. **Caps.**
   - At most `DAILY_MAIL_CAP` (5) relay emails per Google day.
   - Always keep at least 3 of the day's email allowance (`MailApp.getRemainingDailyQuota()`) for the alarm.
   - Over the cap: archive only, return `ok:true, mailed:false`, and send one "too many reports today" notice to `TECH_EMAIL`.
   - This stops a flood from using up the 100-recipient daily limit that the alarm also needs.
8. **Send the email.** `MailApp.sendEmail(RECIPIENT, subject (at most 200 characters), notes + body + one relay line, {name:"Clinic daily report"})`. Plain text only; `noReply` is not used (it works only for Workspace accounts). If sending throws, record nothing and return `mail`, so ldgr retries.
9. **Only after the email is accepted:** record id → hash, `LAST_TO`, `LAST_RECEIVED = now`, and the day's mail count; reset `BAD_SECRET_COUNT`.
10. **Archive**, in its own try/catch.
    - One Sheet row: received time, id, from, produced, sent_utc, flags, subject, hash, body.
    - The body is split into chunks of 45,000 characters across cells; the Sheets cell limit is 50,000.
    - Every cell is written as text: values starting with `= + - @` get a leading `'`, and the sheet is formatted as plain text. This stops text typed into the form from turning into a live formula.
    - If the archive write fails, the email has still gone, and `TECH_EMAIL` gets a notice.
11. **Ping healthchecks** in its own try/catch (`UrlFetchApp.fetch(HC_PING_URL)`; empty body, `muteHttpExceptions`).
12. **Health checks for the developer.** If `LAST_CHECK_RAN` is more than 26 hours old, or there were more than 10 wrong-secret POSTs today, or the daily allowance is low, send one notice a day to `TECH_EMAIL`. If `TECH_EMAIL` is unset, add a line to the report instead.
13. Release the lock and return `{ok:true,…}`.

There is no `doGet`. Replies never echo the body or the secret.

**Manifest** (`appsscript.json`):
- `timeZone: "America/Guyana"`, V8 runtime;
- `webapp: {access:"ANYONE_ANONYMOUS", executeAs:"USER_DEPLOYING"}`;
- `oauthScopes`: `script.send_mail`, `spreadsheets`, `script.scriptapp`, `script.external_request`.

`MailApp` is used, never `GmailApp`, so the script asks for no Gmail permission; Gmail permissions are the only kind Google names as revoked when a password changes. The broader `spreadsheets` permission costs nothing, because ldgrapp holds no other files. The script opens the Sheet by the ID `setup()` stored, so it does not depend on `getActiveSpreadsheet()` inside a web app.

### 3.5 The alarm (`checkMissing`)

- **When it runs:** a daily trigger, `atHour(20).inTimezone('America/Guyana').everyDays(1)`, which Google fires at a fixed minute between 20:00 and 21:00.
- **Rule:**
  1. Write `LAST_CHECK_RAN`.
  2. Skip if today is in `CLOSED_DAYS` (default `Sun`), or if today is on or before the optional `PAUSE_UNTIL` date, which is for known closures.
  3. Count the **opening hours** since `LAST_RECEIVED`: hours falling on closed weekdays do not count, and only Google's receive time is used, never the PC's ids.
  4. If the count exceeds `ALARM_HOURS` (default 30) and no alarm has been sent today, email the owner.
- **The alarm email:**
  - Subject: "No clinic report for 2 days — last received Mon 21 Sep 6:31 pm".
  - Body: "If the clinic was open: ask staff to switch on the clinic computer and open ldgr. The report is sent as soon as it starts. If this email comes again tomorrow, call <developer>."
- **How it avoids false alarms:**

| Situation | Hours at the evening check | Result |
|---|---|---|
| Normal day, report at 18:30 | 1.5 | quiet |
| PC switched off before 18:30 one evening; the report comes as next morning's catch-up | 25.5 | quiet |
| Closed Sunday (in `CLOSED_DAYS`) | skipped, and not counted | quiet |
| One unlisted holiday or blackout, with the PC normally on at 18:30 | 25.5 | quiet |
| Two such days in a row | 49.5 | alarm (correct) |
| Delivery fails from Tuesday 18:30 onward | Tue 25.5, Wed 49.5 | alarm Wednesday evening |
| Clinic PC normally off before 18:30, so reports arrive each morning | about 12; a single unlisted holiday gives 36 | set `ALARM_HOURS=40`, or move `send_at` before the usual switch-off (decision 3) |

- **Detection time.** A real failure is caught the next evening, about 25 hours after the first missed report. The synthesis's "that same evening" claim is dropped: an alarm that fired on the evening of any day the PC was off early would teach the owner to ignore it.
- **What it is independent of:** the clinic PC, ldgr, notify.toml, the clinic's internet connection and the staff.
- **What it is not independent of:** ldgrapp. That gap is covered by §3.6.
- **Watching the alarm itself:**
  - `setup()` sets the trigger's owner to ldgrapp. The developer sets "Failure notification settings" to **Notify me immediately** by hand: code cannot set it, and blogs say the default is a weekly digest.
  - ldgrapp forwards its mail to the developer.
  - If the trigger is switched off (which also silences its failure emails), the relay's `LAST_CHECK_RAN` check (§3.4 step 12) tells the developer within a day.

### 3.6 Independent watchdog (recommended as part of v1)

- **What:** a healthchecks.io check of kind **Simple**, period **1 day**, grace **1 day 12 hours**. It goes DOWN if no email has been confirmed as sent for about 60 hours.
  - That is enough for a closed Sunday whether reports arrive in the evening or next morning: at most 48–50 hours between arrivals.
  - For known multi-day closures, pause the check. It resumes by itself on the next ping.
- **Where its alerts go:**
  - The developer's address, which is the sign-up address and so already verified.
  - The owner's address, which gets alerts only after the owner clicks healthchecks' confirmation link.
  - Recovery ("UP") emails are on by default.
- **What it catches:** ldgrapp disabled, locked or lost authorisation, the daily limit used up, a Google outage, or the relay and alarm both dead. Because the relay pings only after `MailApp` has accepted the email, one ping covers ldgr, the clinic PC, the network, the relay and Google's sending.
- **Limits:**
  - It does not prove the email reached the inbox. The Gmail filter and the setup test cover that.
  - It cannot catch the owner's own Gmail being full: the relay still succeeds. The bounce goes to ldgrapp and is forwarded to the developer.
  - It is a one-person service.
  - The account is closed after a year with no log-in, even while pings arrive.
  - Its emails carry a one-click Unsubscribe link.
  - These limits are why it is the backstop, not the main alarm.
- **Optional:** a Telegram channel for the owner, which also works when the owner's Gmail is full or unread.

---

## 4. v1 scope

### Step 0: live check before any Julia (developer, 15–20 min)

1. After the ldgrapp security check (§5 A1), deploy a throwaway `doPost` of about 15 lines. It returns JSON with `{bytes, sha256, sheetName}` and sends no email.
2. From the laptop (and ideally the clinic PC), POST a 5 KB JSON file with:
   - `curl.exe -L -H "Content-Type: application/json" --data-binary @p.json <…/exec>`;
   - the exact `HTTP.post(...)` call ldgr will use.

   The second test matters: HTTP.jl's redirected GET carries `Content-Length: 0`, which has not been tried against googleusercontent.com.
3. Switch access to "Anyone with Google account" once, to capture the real sign-in page as a test fixture.

**Pass:** JSON comes back with a matching byte count and hash. Build v1. **Fail**, after checking /exec, "Anyone", a new version, and two networks: go to the fallback in §6.

### v1: ordered implementation list

| # | File : function (current lines) | Change | ~Lines |
|---|---|---|---|
| 1 | **new** `v4.0/relay/ldgr-relay.gs`, `relay/appsscript.json`, `relay/README.md` | §3.4–3.5: `doPost`, `checkMissing`, `setup()`, plus pure helpers (`openHours`, `decideDuplicate`, `flagsFor`, `textSafe`, `chunk`). `setup()` does four things: (1) calls `ScriptApp.requireScopes(FULL, [...])`, so a box left unticked on the consent screen fails loudly; (2) refuses to run unless the script's time zone is `America/Guyana`; (3) installs the trigger after deleting old ones, and stores `SHEET_ID` and `LAST_RECEIVED`; (4) emails a 6-digit code to `RECIPIENT`. A constant `RELAY_VERSION` is returned in every reply. The top line says "Update ONLY via Manage deployments > Edit > New version". The README is the developer runbook. Kept outside `public/`, which is served by file name. | ~180 script + 15 manifest + ~60 doc |
| 2 | **new** `v4.0/relay/test_relay.mjs` | Node 24; loads the .gs with `vm` and stubs for `MailApp`, `PropertiesService`, `LockService`, `SpreadsheetApp`, `UrlFetchApp` and `Utilities`. Covers opening hours with a closed Sunday, a single holiday and two holidays; the 30/40-hour thresholds; same and different duplicates; early and clock flags; gap, overlap and backwards continuity; the cap and the reserve; formula escaping; chunking; wrong secret sends no email; unconfirmed. Never contacts Google. | ~130 |
| 3 | `Notify.jl`: `using` (3), `settings` (120–140), `enabled` (165), `recipient` (168–172), `_scrub` (1079–1083) | `using HTTP, JSON3` in place of `Sockets`. Keys: `relay_url`, `relay_secret`, `subject_prefix`, `send_at`. Warn if the URL does not end in `/exec`; refuse `/dev`. `enabled()` depends on `relay_url`. Delete `recipient()`. `_scrub` removes the secret. | −25 / +30 |
| 4 | `Notify.jl`: new `_relay_send(msg)`, `_classify`, `RELAY_TIMEOUTS = Ref((connect=10, read=60))`; `TRANSPORT` (75, 1120) | Builds the §3.3 payload, POSTs inside try/catch, and applies the §3.3 table. Returns the reply or throws a `RelayFailure(kind, words)`. The signature changes to `TRANSPORT[](msg)`. | +70 |
| 5 | `Notify.jl`: delete the SMTP scaffolding: `SMTP_LOADED` (92), reachability gate (926–931), `_reachable`/`_host_and_port` (978–1032), `_load_smtp`/`preload` (1049–1070), `_addr` (1086), `_smtp_send` (1104–1118) | Removed. The sysimage scripts do not mention SMTPClient, so no rebuild is needed. | −150 |
| 6 | `Notify.jl`: `tick` (748–778), `mark_reported!` docstring (280–301); delete `enqueue`/`_read_notice`/`_bump_attempts`/`flush!` (827–958); `LAST_FLUSH` (83) becomes `LAST_ATTEMPT` plus `PENDING` | Delivery as in §3.2: build once per (marker, due), send, mark only on success, 10-minute retry. **Marker in the future** (more than 5 minutes ahead of now): ignore it, use `due − 1 day`, and say so in the body; the relay's continuity flag names any stretch this skips. **Size cap:** a body over 150 KB is cut, with a line saying so. `build_digest` gains a `notes` keyword. | −135 / +55 |
| 7 | `Layout.jl`: delete `outbox_dir`, `sent_dir`, `notice_name`, `outbox_path`, `sent_path` (168–199); add `unlogged_log_path()` | Keeps README rule 2: every path is built in Layout.jl. | −20 / +6 |
| 8 | `Changes.jl`: `_rows_from` (380–402), `_read_log` (432–441), new `rows_between_checked`; `Notify.build_digest` (325–444) | **Never a false all-clear.** An unreadable file, a missing column, or any skipped line becomes a problem string. The subject then starts `CHANGE LOG COULD NOT BE READ — ` and the first line says "this is not a quiet day". The "Nothing was entered" sentence (398–400) is suppressed. This catches the change log being re-saved by Excel. | +35 |
| 9 | `Changes.after_save` catch (234–236), `_append!` (366) | **A row that fails to append is not lost.** If the append fails (for example while Excel has Change Log.csv open), the same rows go to `Notifications/unlogged changes.csv` in their own try. `_read_log` reads both, and the report notes "recorded separately because Change Log.csv was open in another program". A save still never fails (server.jl:573–577, main.jl:466–470 unchanged). | +25 |
| 10 | `Notify._entered_block` (539–552; "Changed again" at 549–550) | Separate from the transport. A day saved after 18:30 and edited on a later date shows that edit's date and before → after, reusing `_was_line`. Today the owner's later-date rule is broken for this case. | +10 |
| 11 | `Notify.build_digest` wording: late line (392–394), footer (440–441) | Late line: "This report covers more than one day: at 6:30 pm on the days in between the clinic computer was off, ldgr was closed, or the report could not be delivered." Footer: "If a report does not arrive you will get a 'No clinic report' email instead; if neither comes, call whoever looks after ldgr." | ~6 |
| 12 | `server.jl`: banner (1097–1099), preload block (1124–1137), `warmup` (912–915, beside the loopback round trip at 933ff) | Banner: `Daily report : on at 18:30 → clinic relay; last delivered <marker or "not yet">`, or `off (no notify.toml)`, or `off (notify.toml has no relay_url)`. Delete the preload block. The warm-up makes one `_relay_send` against a loopback stand-in that answers with a 302 and then JSON. This compiles the redirect path (about 4 s on first use) so it never stalls a save at 18:30. | −15 / +25 |
| 13 | `notify.example.toml`, `README.md` Files table, `tests/TESTING.md`, CLAUDE.md notes | Rewrite (no password); mention `relay/`; the test rules below. | ~60 doc |
| 14 | `tests/test_notify.jl` | See below. | −60 / +200 |

Notify.jl drops from about 1,120 to about 1,000 lines. Estimated effort: about 2 developer days, then about 1.5 hours of setup for the developer and about 15 minutes for the owner.

**Test changes.** No test may contact Google. Every relay test uses a stand-in on 127.0.0.1, and the harness refuses to run if `relay_url`'s host is anything else. The existing rules stay: scratch `LEDGER_ROOT`, `LDGR_NO_DIGEST=1`, and `LDGR_NOTIFY_CONFIG` inside the scratch folder.
- **Harness** (165–173): delete `outbox()`/`sentbox()`; `capture(msg)` records the payload NamedTuple.
- **Group 1** (185–191): drop the `flush!` line (189).
- **Group 3** settings block (244–256): relay keys, secret `SECRET`, drop the `recipient` assertions (255–256). "The secret is nowhere in the log" replaces the password checks.
- **Group 16** (528–554): drop the outbox/sent assertions (549–550). New: "the marker moves when the relay confirms".
- **Group 17:** unchanged apart from the capture signature.
- **Group 18** (572–608) rewritten:
  - a failing transport leaves the marker;
  - a tick within 10 minutes returns `:waiting` and makes no call;
  - after 10 minutes it resends byte-identical bytes (checked by SHA);
  - after the next cut-off, one report covers both days;
  - the audit log has the words and not the secret.
- **Group 19** (610–634) replaced by stand-in server cases:
  - 302 → `{ok:true}` (marks the marker);
  - 302 → 200 sign-in HTML;
  - 200 HTML "Error";
  - `{ok:false,error:"secret"}`;
  - 500;
  - a reply with a mismatched id;
  - a reply slower than the timeout (with `RELAY_TIMEOUTS[] = (connect=2, read=3)`).

  Only the first moves the marker; none throws out of `tick`.
- **New group 20:** a log that is unreadable, has a missing column, or has one line with a broken timestamp produces the warning subject and never "Nothing was entered".
- **New group 21:** Change Log.csv replaced by a folder (a way to force the append to fail). The save still succeeds, the row lands in the unlogged file, and the next report includes it.
- **New group 22:** a day saved at 19:00 and edited the next day shows before → after under DAYS ENTERED.
- **New group 23:** a marker in the future is ignored, with a note in the body.
- **Also:** re-run `tests/test_endpoints.jl`, because the warm-up changed. Run `node relay/test_relay.mjs`.

### v2 (only when a need is shown; the first item is recommended next)

1. **Write seal:** a SHA-256 of Change Log.csv and each Daily Journal after every ldgr write, checked before the next write and at report time. It adds a "FILES CHANGED OUTSIDE LDGR" section. This is the only defence against someone editing a journal directly in Excel or Notepad. About 60–80 lines, separate from the transport.
2. **A status file** holding the last problem and the next attempt, shown in the banner. This is the full version of T1 from the synthesis.
3. **A time base for stamps and cut-offs that ignores the PC's time zone** (`now(UTC) − 4h`); the digest re-derives "edited on a later date" from the rows' own dates instead of trusting the stored flag. Today's early and clock flags only catch time-zone games at report time.
4. **Change-log row count plus a hash of its first N rows in the payload**, so the relay can flag a log that got shorter.
5. **A second healthchecks check pinged by `checkMissing`;** a Telegram alert channel.
6. **A Dropbox copy made by the relay** (§2), only if the owner asks.
7. **Guyana's public-holiday calendar for the alarm.** Whether Google publishes one is unverified.
8. **Read the settings once per tick** (T10).
9. **The owner-account Gmail-reading watchdog,** only if the owner refuses healthchecks.

### Dropped, with the reason

- **T2's three-way error classification and lock-out:** it existed to protect a Google sign-in, which no longer exists. One 10-minute retry is enough.
- **T3's delivery ledger and backlog merge, and T4's safe queue:** there is no outbox now; the marker moving only on delivery produces one merged report by itself.
- **T7's settings hash and last-seen clock:** switching reporting off, deleting notify.toml or blanking the URL all stop reports, and the alarm catches that. Clock games are flagged at the relay.
- **T8's row cursors in v1:** the relay's time-continuity check catches marker edits; row cursors move to v2 item 4.
- **T9's lock file:** a second timer after re-including server.jl sends byte-identical reports, which the relay ignores. An environment-variable guard would keep stale code running instead.
- **T11's lateness stamps on the PC and T12's `PINGER` in Julia:** the relay stamps on Google's clock and pings healthchecks itself, so no ping URL sits on the PC.
- **Per-row hash chain at the relay, and mirroring each row to Google as it is saved:** they only protect rows the owner has already received. The local seal (v2 item 1) is the better use of that effort.
- **Task Scheduler wake job:** Windows 11 Home laptops do not wake for it, and the morning catch-up already covers a PC that was off.
- **An interim SMTP stopgap:** the failing machine was a test laptop with empty books, so no clinic report is at stake. Its four stuck test reports should be deleted by hand.
- **UptimeRobot:** heartbeat checks are not on the free plan.
- **Dead Man's Snitch:** the free plan cannot skip closed days.
- **Better Stack:** its free plan is labelled "for personal projects".
- **Hosting the relay in the owner's account, or putting the relay and the alarm alone in ldgrapp:** see §3.1.

---

## 5. Setup: who does what

**Never sign in to the owner's Google account or to ldgrapp on the clinic PC.** A Gmail filter added there could hide every report.

**A. Developer, on the developer's own computer (about 60 min including Step 0)**
1. **Check and secure ldgrapp.**
   - Sign in and open Security > Recent security activity to see what killed the app password. If the account is restricted, or shows a hijack or "verify it's you" response, use a fresh dedicated account instead.
   - Revoke the dead app password.
   - Recovery email and phone: the owner's.
   - 2-Step Verification on the developer's phone, with printed backup codes.
   - Settings > Forwarding: forward all mail to the developer. Google's failure summaries, security alerts and bounces then reach someone who can act.
2. **Run Step 0** (§4).
3. **Create the Sheet and script.** Create the Sheet "Clinic daily reports", open Extensions > Apps Script, paste `ldgr-relay.gs`, turn on "Show appsscript.json" and paste the manifest.
4. **Set the Script properties:**
   - `SECRET`: `julia -e "using Random; println(randstring(RandomDevice(), 32))"`;
   - `RECIPIENT` (the owner's address);
   - `CLOSED_DAYS`, `ALARM_HOURS` (from decision 3);
   - `DAILY_MAIL_CAP=5`;
   - `TECH_EMAIL` (the developer);
   - `HC_PING_URL` (filled in at step 7).
5. **Run `setup()`.** Click through Google's warning (Advanced > Go to …). Tick every box on the consent screen. `setup()` installs the trigger and emails the confirmation code.
6. **Triggers page:** `checkMissing` > Failure notification settings > **Notify me immediately**.
7. **healthchecks.io:**
   - sign up with the developer's address;
   - add the check "Clinic daily report — if DOWN, call <developer, phone>": Simple, 1 day, grace 1 day 12 hours;
   - add an email channel for the owner's address;
   - copy the ping URL into `HC_PING_URL`;
   - put a yearly log-in reminder in the calendar.
8. **Deploy.** Deploy > New deployment > Web app: Execute as **Me**; Who has access **Anyone** (not "Anyone with Google account"). Copy the `/exec` URL. From now on use only Manage deployments > Edit > **New version**.
9. **Share and test.** Share the Sheet with the owner as a Viewer. Send one test POST from the developer's machine: an email arrives, a Sheet row appears, and healthchecks shows "up".

**B. With the owner (15-minute call; the owner's own phone, plus a computer for the filter)**
1. **Test email.** With the owner's phone locked, the developer sends a test. Record whether the phone buzzed and which tab the email landed in. The owner reads back the 6-digit code, and the developer sets `CONFIRMED`.
2. **Gmail filter,** in Gmail on a computer (Google's filter help describes only the computer): `from:(ldgrapp@gmail.com OR healthchecks.io)` > Never send it to Spam, Always mark it as important, Categorize as Primary. Save ldgrapp as a contact.
3. **healthchecks link.** The owner clicks the healthchecks confirmation email.
4. **Sheet.** The owner opens the Sheet link on the phone.
5. **Hand-over.** Give the owner the envelope (ldgrapp password and backup codes). Confirm the owner's Google account is not signed in on the clinic PC.

**C. At the clinic PC (developer, in person or by remote help; no Google sign-in)**
1. **notify.toml:** `relay_url`, `relay_secret`, `send_at` (from decision 3). Delete any old SMTP-era `Notifications\outbox` and `sent` files. If `Notifications\last report.txt` is old or missing, set it to the last cut-off, so the first report is not a months-long catch-up.
2. **Restart and check.** Restart ldgr and check the banner. Optionally start once with `LDGR_DIGEST_NOW=1`, then confirm the email arrives and a Sheet row appears.

**What the owner is told:**
> From now on you will get one email a day from "Clinic daily report" (ldgrapp@gmail.com), soon after 6:30 pm. It lists the days entered, any later changes, every difference with the reason staff typed, and any ledgers still waiting. If the clinic computer was off at 6:30, the report comes the next morning when it is switched on. If no report has come in for more than a day of opening hours, you will get an email called "No clinic report" instead, and healthchecks.io may also email you that the report is "DOWN". Either of those, an email marked [CHECK], or two days with no email at all, means: call <developer>. Every report is also kept in the "Clinic daily reports" sheet shared with you. Keep the envelope somewhere safe, and never type that password, or your own Google password, on the clinic computer.

---

## 6. Residual risks, and when to switch to the fallback

| Risk | How it shows | Response |
|---|---|---|
| ldgrapp is restricted, disabled or loses the script's authorisation (undocumented for personal accounts; reported in 2023–2025) | healthchecks DOWN within about 60 hours, to the owner and the developer; forwarded Google notices; no daily email | Sign in on the developer's device and run `setup()` once (re-authorise). If the account is lost: rebuild in a new dedicated account (about 45 minutes) and change `relay_url` at the PC. |
| Owner's Google storage full: their account "can't send or receive emails" | Bounces reach ldgrapp and are forwarded to the developer. healthchecks stays "up". | The developer tells the owner. Optional Telegram channel. |
| Google changes anonymous web apps or the redirect, or POSTs fail with 5xx (one unresolved Nov 2025 report) | The §3.3 classification in the audit log; alarm; backstop | Redeploy a new version. Switch if it persists (below). |
| Report filed in Updates or Spam | Setup test; the Sheet still has every report | The filter from §5 B2 |
| healthchecks account closed after a year without log-in; one-person service; owner clicks Unsubscribe | — | Yearly log-in reminder; the developer is a second recipient; it is only the backstop |
| Staff copy the secret and post forged or pre-emptive reports | `[CHECK]` flags for duplicates, early arrival and gaps; the owner sees both texts | Rotate `SECRET` (one Script property and one line in notify.toml). Staff with the secret cannot read, redirect or delete anything. |
| Journal edited outside ldgr | Not detected in v1 | v2 write seal. The month-end comparison with QuickBooks is the residual check. |
| Time-zone or clock changes on the PC | Early and clock flags at report time | v2 item 3 closes the narrow remaining case of backdating an edit to "yesterday". |
| Developer unavailable | — | `relay/README.md` runbook; the owner holds the account. |

**Fallback: the Resend API** (onboarding@resend.dev, sending only to the account holder's own address; free: 100 a day, 3,000 a month).
- ldgr pings the same healthchecks check after an HTTP 200, and the healthchecks check becomes the only alarm, with a cron schedule matched to the clinic's open days and about 1 day of grace.
- It is about 50 lines swapped into `TRANSPORT[]` with the same subject and body.
- This needs decision 6. If the owner refuses a company that keeps the report text, the fallback is Gmail SMTP through `curl.exe` run as a separate process: a new app password, a hand-built message (CRLF line endings, a blank line after the headers, `text/plain; charset=UTF-8`, `8bit`, an RFC 2047 subject — **not** SMTPClient's `get_body` or `get_mime_msg`), and a byte-for-byte test. About half a day, and the password has to be replaced at the clinic PC whenever Google revokes it.

**Switch when:**
1. Step 0 fails after the checklist; or
2. Google announces, or the relay starts showing, sign-in pages for correctly set anonymous consumer web apps; or
3. The relay returns errors on 3 consecutive days despite a redeploy and re-authorisation; or
4. ldgrapp is lost, the appeal fails, and a replacement dedicated account is also restricted within 30 days; or
5. Reports keep landing in spam despite the filter.

---

## 7. Decisions needed from the owner

1. **Who receives the report, and do they read that Gmail on a phone with notifications on?** *Default:* the owner's own Gmail, read in the Gmail phone app with notifications for Primary. No second recipient.
2. **Who operates the reporting account?** *Default:* the developer operates ldgrapp@gmail.com; the owner keeps its password and backup codes in a sealed envelope and is its recovery contact. *If the developer is one of the people the report oversees:* the owner changes ldgrapp's password after setup, the developer asks for access for each change, and a test POST is sent right after the password change.
3. **Which weekdays is the clinic closed, and is the clinic PC normally on with ldgr open at 6:30 pm?** *Default:* closed Sundays; alarm after 30 opening hours. If the PC is usually switched off before 6:30 pm, move the send time to 15 minutes before the usual switch-off; otherwise use a 40-hour alarm. This revisits the 2026-09-16 "18:30" choice.
4. **May healthchecks.io watch for the report and email you and the developer if nothing arrives for 2½ days?** It is free and holds no figures, only "a report went out" pings, and it is not an email service. *Default:* yes.
5. **Instead of Dropbox, a Google Sheet of every report, shared with you view-only: acceptable?** *Default:* yes. A Dropbox copy only if you ask (version 2).
6. **If Google's relay ever stops working for good, may we switch to Resend, which keeps report text for 30 days?** *Default:* yes. If not, the fallback is Gmail with a new app password: free, but it dies without warning and must be replaced at the clinic PC.

---

## 8. Verified facts

| Claim | Status | Source | If unverified: how and when |
|---|---|---|---|
| "Anyone" = `ANYONE_ANONYMOUS` ("any user, even if not logged in"); `USER_DEPLOYING` runs as the deployer | Confirmed | https://developers.google.com/apps-script/manifest/web-app-api-executable (updated 2026-09-03) | — |
| Scripts attached to a Sheet can be web apps; the `/dev` URL needs edit access | Confirmed | https://developers.google.com/apps-script/guides/web | — |
| Script output is served through a one-time redirect to script.googleusercontent.com; clients must follow it | Confirmed | https://developers.google.com/apps-script/guides/content | — |
| HTTP.jl 1.11.0 follows the 302 as a GET; the POST body arrived whole; the JSON reply came back; a 307 keeps the POST | Confirmed locally | scratchpad `relay_probe.out`, `relay_probe2.out`; HTTP.jl `RedirectRequest.jl` 14–60 | Against Google: Step 0 |
| A live anonymous POST to a personal-account web app works in 2026 | **Unverified** (docs, a July 2025 article, an Aug 2026 guide) | https://dev.to/googleworkspace/youre-probably-using-curl-wrong-with-your-google-apps-script-web-app-1ed8 | Step 0, before any code |
| Google accepts HTTP.jl's redirected GET carrying `Content-Length: 0` | **Unverified** | relay probe | Step 0 using HTTP.jl, not only curl |
| POSTs failing with 500 while GET works (Workspace, Nov 2025, unresolved) | Partly (one report) | https://discuss.google.dev/t/apps-script-web-app-post-requests-fail-with-500-docs-error-and-dopost-never-runs/292239 | Caught by the alarm and backstop |
| Apps Script can answer 200 with an HTML "Error" page for passing faults | Partly (community) | https://github.com/tanaikech/taking-advantage-of-Web-Apps-with-google-apps-script | Treated as temporary |
| Timeouts and connection errors throw even with `status_exception=false`; `readtimeout` applies per step; defaults: no read timeout, 4 retries | Confirmed locally and in source | `relay_probe.out` test 4; HTTP.jl `TimeoutRequest.jl`, `RetryRequest.jl:29` | — |
| A slow POST does not block the server (a second request answered in 54 ms); the first call in a fresh process takes about 4 s to compile | Confirmed locally | `relay_probe.out` | — |
| Julia 1.9.2 runs a Timer's callbacks one at a time; one that never returns stops all later ticks | Confirmed (source) | base/asyncevent.jl (reliability red team) | — |
| Editing and deploying a new version keeps the URL; "New deployment" creates a new URL | Confirmed | https://developers.google.com/apps-script/concepts/deployments (2026-09-15) | — |
| Personal-account limits: 100 recipients/day, 200 KB body, 20 triggers, 6 min per run, 20,000 URL fetches/day, 9 KB per property | Confirmed | https://developers.google.com/apps-script/guides/services/quotas (2026-09-03) | — |
| `atHour(h).inTimezone(tz)` fires once within that hour, at a consistent time | Confirmed | https://developers.google.com/apps-script/reference/script/clock-trigger-builder ; https://developers.google.com/apps-script/guides/triggers/installable | — |
| Trigger failure emails go to the trigger's creator; their frequency can be set only in the web page; a switched-off trigger also stops its failure emails | Confirmed | installable triggers guide (above) | — |
| Default failure-email frequency | **Unverified** (blogs say weekly) | https://www.diazovate.com/blog/google-apps-script-triggers-tutorial-automate-sheets-docs-and-forms-on-a-schedule/ | Set "Notify me immediately" at setup |
| A failing `doPost` produces no Google email | Inferred from docs | installable triggers guide | Relay health notices plus the backstop |
| `MailApp.sendEmail` has `name`; plain-text body; `noReply` is Workspace-only; permission `script.send_mail` | Confirmed | https://developers.google.com/apps-script/reference/mail/mail-app | — |
| The script's authorisation survives a password change on the host account | **Unverified** for personal accounts (Workspace: Apps Script is excluded from token revocation; OAuth revokes only tokens with Gmail permissions) | https://knowledge.workspace.google.com/admin/apps/automatic-oauth-20-token-revocation-upon-password-change ; https://developers.google.com/identity/protocols/oauth2 | Send a test POST after any ldgrapp password change |
| Authorisation can be lost without the account holder doing anything | Confirmed (2017 Google incident; 2023–25 reports) | https://stackoverflow.com/questions/42631938 ; https://groups.google.com/g/google-apps-script-community/c/7EhJASEnJHY | Run `setup()` once to re-authorise |
| Granular consent reached web apps in Jan 2026; `ScriptApp.requireScopes` exists | Confirmed | https://workspaceupdates.googleblog.com/2025/11/granular-oauth-consent-in-webapps.html ; https://developers.google.com/apps-script/release-notes | — |
| Mail an account sends to itself reaches the inbox and notifies | **Unverified, probably not** | https://knowledge.workspace.google.com/admin/support/troubleshooting/messages-sent-to-email-alias-or-group-arent-in-my-inbox ; https://support.google.com/mail/thread/95969799 ; https://github.com/markmhendrickson/ateles/issues/1221 | Designed out: mail comes from ldgrapp |
| Phone notifications only for Primary by default; filters can set Primary, Never spam and Important, but not "mark unread" | Confirmed | https://support.google.com/mail/answer/3055016 ; https://support.google.com/mail/answer/1075549 | — |
| Mail from ldgrapp to the owner lands in Primary and notifies | **Unverified** | — | Setup step B1, phone locked |
| Gmail filters are made in Gmail on a computer | Partly (the help covers only "on your computer") | https://support.google.com/mail/answer/6579 | Do it on a computer |
| An account over its storage limit can't send or receive mail | Confirmed | https://support.google.com/mail/answer/6374270 | — |
| A Sheets cell holds at most 50,000 characters | Partly (community) | https://support.google.com/docs/thread/10999557 | Chunks of 45,000; Node test |
| healthchecks free plan sends email alerts; 20 checks; 100 log entries each | Confirmed | https://healthchecks.io/docs/healthchecks_cronitor_comparison/ (2026-09-22) ; https://healthchecks.io/pricing/ | — |
| healthchecks sends nothing to an unverified address (the sign-up address is auto-verified); alerts include the last ping body and a one-click Unsubscribe; "up" emails are on by default | Confirmed (source) | https://github.com/healthchecks/healthchecks/blob/master/hc/integrations/email/transport.py ; …/email/forms.py | — |
| healthchecks closes accounts with no log-in for over a year even while pinged; a one-person team; multi-day outages possible | Confirmed | https://healthchecks.io/faq/ | Yearly log-in reminder |
| UptimeRobot free has no heartbeats; Dead Man's Snitch free = one daily check at midnight UTC that cannot skip days; Cronitor free = 5 monitors with email | Confirmed | https://uptimerobot.com/pricing/ ; https://deadmanssnitch.com/docs/faq ; https://cronitor.io/pricing | — |
| Dropbox: no phone push for new files; file requests cannot be filled by the API; no upload-only permission; app folders cannot be shared or followed; "Email to Dropbox" is paid only; a sole toucher can permanently delete; 30-day recovery on Basic | Confirmed | https://help.dropbox.com/account-settings/notified-changes ; https://github.com/dropbox/dropbox-api-spec/blob/master/file_requests.stone ; https://github.com/dropbox/dropbox-api-spec/blob/master/files.stone ; https://help.dropbox.com/organize/follow-folder ; https://help.dropbox.com/share/shared-folder-faq ; https://help.dropbox.com/create-upload/email-files-to-dropbox ; https://help.dropbox.com/delete-restore/delete-files | — |
| Dropbox follow-folder emails fire for uploads made through the API | **Unverified** | follow-folder help | Moot unless the owner insists on Dropbox |
| The Drive app gives no notification for new files in your own folders | Confirmed | https://support.google.com/drive/answer/6318501 | — |
| SMTPClient 0.6.5 `get_body`: no blank line after the headers, no Content-Type; `get_mime_msg` labels the body quoted-printable without encoding it | Confirmed locally | scratchpad `smtp_body_probe.out`, `smtp_body_parse.out`; SMTPClient `user.jl` 53–58, 119–122 | Matters only for the SMTP fallback |
| Standard Windows users can change the time zone | Confirmed | https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/change-the-time-zone | — |
| Excel locks an open file, so an append by ldgr fails | Partly (Microsoft doc; not tried with CSV.jl) | https://support.microsoft.com/en-us/excel/excel-file-is-locked-for-editing | Test group 21 forces the failure |
| An Excel re-save rewrites the change log's timestamps | **Unverified** | — | Covered either way by the skipped-line warning (item 8) |
| America/Guyana is UTC−4 with no daylight saving | Confirmed | IANA tz database | — |
| Julia 1.9.2's bundled certificate list includes Google's roots (GTS) | Confirmed | `share/julia/cert.pem` (reliability red team) | Step 0 exercises TLS |
| The clinic PC's closed days and whether it is on at 18:30 | **Unknown** | — | Decision 3, before setup |
| A Google public-holiday calendar for Guyana exists | **Unverified** | — | Only for v2 item 7 |

Nothing under `E:\Ldgr` was changed, no server or tests were run, nothing was sent, and notify.toml was not opened. Code references were checked against `E:\Ldgr\v4.0\Notify.jl`, `Changes.jl`, `Layout.jl`, `server.jl`, `main.jl` and `tests\test_notify.jl` as they stand on 2026-09-24. The local probe scripts were run from a temporary folder and are not kept.