# Handoff: Resend job, end of session 2026-09-28

**Done 2026-09-28 (later session).** Items 1–4 below are finished: the docs were updated, the DoD check re-ran on the final code, the Work-in-progress pointer was removed from `E:\Ldgr\CLAUDE.md`, and the summary was given. A second, independent review of the round-3 fixes (round 4) found gaps, which were fixed; `E:\Ldgr\CLAUDE.md` describes them. Kept as history.

The previous session's context filled up, so it stopped here. The implementation is **done and green**; what's left is small. Read `E:\Ldgr\CLAUDE.md` (its "Also uncommitted (2026-09-28)" block describes the whole design as built), then this file. The original brief is `CLAUDE.md` in this folder. `backup-2026-09-28\` holds the pre-change copies.

## State right now

- **Send time is 17:30** (5:30 pm). The developer decided this today, replacing the brief's 18:30. The healthchecks cron is `30 17 * * 1-6`. The brief's open send-time question is closed.
- **Code:**
  - `Resend.jl` is new.
  - `Notify.jl` was rewritten.
  - `Changes.jl`, `Layout.jl` and `server.jl` were changed.
  - `main.jl` is unchanged.
  - Nothing is committed (don't commit unless asked).
- **Tests, all green, run from a flattened copy** with `bash <scratchpad>/run-tests.sh <scratch-dir>`. The script is `C:\Users\jorre\AppData\Local\Temp\claude\E--Ldgr\54fa50d5-7526-4c14-96e1-d080490a06a5\scratchpad\run-tests.sh`; it copies v4.0, drops Records/handoff/sysimage/notify.toml/resend-work, and sets the safety env vars.

  | Test | Checks | Result |
  |---|---|---|
  | titles | 23 | FAILED 0 |
  | end-to-end | 45 | FAILED 0 |
  | edge | 32 | FAILED 0 |
  | endpoints | 99 | FAILED 0 |
  | notify | 616 | FAILED 0 |

  The notify count is 615 without `openssl` on PATH.
- **Definition-of-done server check:** passed on the round-two code. `scratchpad\dod.jl` starts a real server with the scheduler on, points `Resend.API_BASE` at a local stub, and makes a save. Results:
  - The banner is right in all three states (on / `off (no notify.toml)` / `off (notify.toml has no Resend api_key)`).
  - A save causes exactly one create plus one cancel.
  - The `/api/save` response is unchanged.
  - The key is in no file.
  - **Re-run it once on the final code:** from a flattened copy with `public\` and `dod.jl`, unset `LDGR_NO_DIGEST`, then `LEDGER_ROOT=<scratch> LDGR_NOTIFY_CONFIG=<scratch>\dod-notify.toml LDGR_NO_BROWSER=1 julia dod.jl 8766`.

## Review history (4 rounds, all fixes applied)

Round 1 used 4 lenses, round 2 used 2, and round 3 was a single review plus mutation testing; each finding was checked by a sceptic agent. About 30 confirmed findings were fixed. The main ones:

- **Scheduling state:**
  - The problem text is kept in the state file.
  - Unconfirmed hand-overs are recorded as `[pending]` and replayed with the same key; a scheduled one whose send time has come is never replayed.
  - `unsure` in the state file makes a later late report say it "may repeat" the 5:30 pm one.
  - `Resend.Failure.reached` marks a request that never left the PC.
- **Timing:** the whole-second rule (`ripe`), and the clock read after the lock.
- **Change-log reader and writer:**
  - The reader parses bytes, with a fixed delimiter and per-column types; this fixed a CSV.jl out-of-bounds write that could crash the process.
  - Strict cells: dates, flags, and `released by`; invalid UTF-8 is cleaned.
  - The writer mends a torn tail with a CSV-aware quote check.
- **Report text:** every reported edit is printed; releases caused by edits are reported; "did not balance before" comes from the first edit shown.
- **Resend client:** TLS failures are worded as a certificate problem; the key is scrubbed before truncation; `cancel` has a narrower rule.
- **Robustness:** throttled audit lines, including for unexpected errors.

The last fixes of round 3 have regression checks, and the whole file passes. But round 3's fixes (`_ends_in_quote`, the `unsure` field, `LAST_UNEXPECTED`) got **no second independent review**. A quick look is worthwhile.

## Left to do

1. **Docs polish.** `CLAUDE.md` and `tests\TESTING.md` were updated to 616 at handoff; add these three to the CLAUDE.md block if they're missing: `Scheduled.unsure`, `_ends_in_quote`, `LAST_UNEXPECTED`. `README.md`, `notify.example.toml`, the handoff `.mjs` run instructions and `handoff\verification.md` are already updated.
2. **Re-run the DoD server check** (above) on the final code.
3. **Remove the "Work in progress" pointer** in `E:\Ldgr\CLAUDE.md` to this handoff once done. The brief (§7) asks for the pointer to `resend-work` to go when the job is finished. Keep `backup-2026-09-28\` either way; it is the only other copy of the old untracked `Notify.jl`.
4. **Final summary to the developer**, as brief §8 asks:
   - what changed, by file and function;
   - the test counts above;
   - the setup checklist (in `notify.example.toml`);
   - two things to verify on the first live run: that cancel works with the Full access key, and that the webhook ping reaches healthchecks.io.

   Also tell the developer:
   - **The owner question:** a same-date correction made after that day's 5:30 pm report has gone out is not reported. The rules "same-date edits are free" and "differences and a day made to balance are reported" conflict. Only the quiet sentence was made truthful ("Nothing new was entered … The only changes were corrections made on the same date …"). A related nit is in the same bucket: CHANGES announces "It balances now" even when the clearing edit was a silent same-date one.
   - `v4.0\notify.toml` still holds the dead Gmail settings, so the banner says off until the developer rewrites it. Don't read it.
   - The laptop's old `Records\Notifications\outbox\` and `sent\` folders can be deleted by hand.
   - A review agent ran `taskkill //F //IM node.exe` around 19:15 local time, which would have killed any other node.exe running on the machine then.
   - Test group 6, one of the groups kept unchanged from before, backdates a row by 2 hours, so it can fail if run between 00:00 and 02:00.
   - A clock stepped back more than 5 minutes after settling makes the marker look like it is in the future. The report then restarts, with the clock note (brief §5.3 behaviour).

## Gotchas for whoever continues

- **Line endings:** `Layout.jl`, `server.jl` and `tests\TESTING.md` are CRLF. `Notify.jl`, `Changes.jl`, `Resend.jl`, `tests\test_notify.jl`, the READMEs and `CLAUDE.md` are LF. Python edits with `newline=''` preserve them.
- **Backslashes:** the Bash tool collapses `\\` inside heredocs. Put Python patch scripts in files (Write tool) and run them from there.
- **Safety:** always set `LDGR_NO_DIGEST=1` and a non-existent `LDGR_NOTIFY_CONFIG` for tests and scratch servers (the DoD check deliberately unsets `LDGR_NO_DIGEST` and uses a fake config plus a 127.0.0.1 stub). Never contact Resend.
