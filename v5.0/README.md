# ldgr v4.0

Daily bookkeeping entry for the urgent care clinic. Produces a Daily Journal and
QuickBooks-importable ledgers, and checks every day's cash before it writes
anything.

v3.0 recorded what it was given. v4.0 subjects each day to a graded battery of
checks first, records unexplained differences instead of hiding them, and will
not produce a ledger for a day whose predecessor is missing.

---

## Requirements

- Julia 1.10 or later
- Packages: `DataFrames`, `CSV`, `HTTP`, `JSON3`

`Project.toml` and `Manifest.toml` fix the exact versions LDGR was tested with.
HTTP must stay on 1.x: 2.x breaks the email code. Install them once, from this
folder:

```
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

and start Julia with `--project=.` so those are the versions used.

`PackageCompiler` is needed only to build the optional system image described
under "Faster start with a sysimage" below; the program does not use it.

---

## Running it

### The form (normal use)

```
julia server.jl
```

The form opens by itself in its own window, with no address bar or tabs (Chrome
or Edge; otherwise the default browser). The window opens maximized and at 100%
zoom. Chrome remembers a zoom level for each address, so just before opening the
window the launcher clears any zoom saved for 127.0.0.1 and localhost; if that
cannot be done it carries on, and the window simply opens at whatever zoom Chrome
remembers. (It is maximized rather than true full screen so that the window's
close button stays visible.) If no window appears, open
<http://127.0.0.1:8000>. Use `julia server.jl 9000` for a different port.
Ctrl+C in the terminal window stops it. Set `LDGR_NO_BROWSER=1` to start the
server without opening a window.

Before it listens, the server warms itself up ("Warming up..." then "Ready"):
it runs the checks, a journal write and one request to itself against scratch
data so that the first Save of the day is not spent compiling. It writes nothing
to the books. Set `LDGR_NO_WARMUP=1` to skip it when restarting often during
development.

In the form, **Save** writes the day on screen to the books and stays on it. Every
save regenerates that day's ledger file from the figures on screen, so correcting
a day is simply changing the figure and pressing **Save** again; there is no
separate "edit" step and no box to tick. A date that is already in the books
comes up as it was saved whenever the form lands on it (opening the form,
picking the date, Next day): a Work day with its figures and reasons, an Off day
with the Off day switch on and every box blank. Any other date comes up blank.
**Clear** blanks the form and keeps the date; on a saved day the quiet "Show
saved figures" link then appears in the Checks panel, and pressing it (or
Ctrl+Alt+Z) brings the saved figures back. Once a day has a ledger, the Checks panel
shows "Day saved, ledger generated", and beneath the list a grey note says: "Saving
again will regenerate the ledgers with the current figures and accounts." The
full explanation behind that row tells staff to check QuickBooks before importing:
if a journal already exists for the date, delete it before importing the new one,
and if the numbers match there is nothing to change. ldgr cannot see inside
QuickBooks, so it cannot do that check for them. A day saved without a ledger (an
Off day, or a Work day whose ledger is waiting on a missing day) gets a second
grey note in the Checks panel instead: "This day has been saved. Saving again
will rewrite it with the current figures." An Off day has no figures on screen,
so its note says only "This day has been saved." The line "<date> saved to the
books." under the buttons is used only where the Checks panel cannot say it: on
a window too narrow to show the panel, or when the server has a warning to add.
An Off day is never the first day on record. With nothing but Off days before
the date, the first-day box stays in view on an Off day but greyed out, and the
Off day saves without it; the first Work day after it is the one asked. An Off
day passes the last close through, so a Work day after one is measured against
the nearest earlier day that is not an Off day; if that day is missing, the Work
day's ledger waits for it like any gap, and the notice for filling that gap names
the Work day waiting, never the Off day.
**Next day** asks the server whether that day is in the books exactly as shown
(`POST /api/next`) and moves to the day after only if it is; otherwise it says
what still has to be saved and stays put. If the day after is already saved, it
comes up with its saved figures.

**Keyboard shortcuts.** Only four (plus Esc, below): **Ctrl+S** is Save, **Ctrl+N** is Next day,
**Ctrl+Alt+C** is Clear, and **Ctrl+Alt+Z** presses "Show saved figures". Each
does exactly what pressing that button does,
including its refusal message. A greyed-out Next day or Clear does nothing;
Ctrl+S on a greyed-out Save sends nothing but says why, as a press on it does.
Ctrl+Alt+Z does nothing unless the link is showing, that is after Clear on a
saved day; on a narrow window it works while the Checks panel is closed.
Ctrl+S works from inside a box, and the box is tidied first, as it is when you
tab away from it. Ctrl+N works in ldgr's own window; in an ordinary browser tab
Chrome keeps Ctrl+N for "new window" and ldgr never sees it, so use the button
there. Hovering over a button, or over the link, shows its shortcut.
**Esc** closes an open full explanation, as its X does, and on a narrow window
it closes the Checks panel.

The server listens on 127.0.0.1 only — reachable from that machine and nowhere
else. **Do not change the bind address to 0.0.0.0**; it has no authentication
because it does not need any.

### Faster start with a sysimage

Julia compiles `HTTP`, `CSV` and `DataFrames` afresh at every start, which is
most of the wait before the form appears and before the first Save. Building a
system image once saves that work to a file and removes the wait:

```
julia --startup-file=no sysimage/build_sysimage.jl     # ten to twenty-five minutes, once
```

Then start the server by double-clicking **`ldgr.bat`**, which uses the image
when it is there and starts normally when it is not. It is entirely optional
and changes nothing about how the program behaves. `sysimage/README.md` has the
details, including when to build it again.

### Command line

```
julia main.jl day.csv                 # one day from a CSV
julia main.jl day.csv --force         # confirm a ledger may be regenerated
julia main.jl day.csv --first-day     # accept the very first opening balance
julia main.jl                         # interactive prompts
```

### Where the files go

`Records/` beside the source, or wherever `LEDGER_ROOT` points:

```
Records/
├── audit_log.txt
├── Change Log.csv                       ← one row per write to the books
├── Notifications/                       ← only once email is switched on
│   ├── last report.txt                  ← how far the reports are complete
│   └── scheduled report.toml            ← the version waiting at Resend
├── Reports/
│   └── Daily Report 2026-06-14.txt
└── 2026/06/
    ├── Daily Journal 06-2026.csv        ← source of truth, never delete
    ├── Monthly Ledger 06-2026.csv       ← rebuilt every run
    └── Daily Ledgers 06-2026/
        └── Daily Ledger 2026-06-14.csv
```

---

## The daily report

One email a day, to the owner, saying what happened in the books. It lists the
days entered and any differences with the reasons typed for them, days that were
changed later — after midnight or after the send time, whichever came first
after the day was first saved (a correction before then is free) — gaps that
were filled and the ledgers they released, and the ledgers still waiting. A quiet day still sends a
short "nothing to report", so silence means something is wrong.

**It is sent by Resend, an email service, not by this program.** ldgr is
normally opened at closing time, used for a few minutes and closed, so it is
usually not running at the send time (17:30 clinic time unless `send_at` in
`notify.toml` says otherwise). Instead, while the server is running, it hands
the coming report to Resend with its send time attached — within a minute of
starting, and again within seconds of every save, each new version cancelling
the one before — and Resend sends whichever version is waiting at the send
time, whether or not ldgr is still open. A day typed after the send time is in
the next day's report. The command line (`main.jl`) never sends; the next server
start picks up whatever it saved.

Whatever could not be handed over in time goes out as soon as the server is next
running. A save made after the last version was handed over (no internet at that
moment, or the last minute before the send time) goes out at once as a
**corrected** report. If instead part of the change log for that stretch has
become unreadable since the report went out, a **follow-up** report for the same
stretch goes out at once, saying so at the very top, so the owner knows that
report may have left an entry out. A stretch nothing covered at all — ldgr
closed or offline before it could hand the report over, days typed on the
command line — goes out at once as one **late** report. If ldgr was closed
before Resend's answer to the last hand-over arrived, Resend may still send that
version, so every report ldgr later sends that covers the same send time says it
may repeat the one sent then. A stretch in which nothing was saved, such as a
closed Sunday, is not sent on its own: the next report covers it too and says it
covers more than one day.

**A watchdog catches the day nothing is sent.** If ldgr is not opened at all
between one send time and the next, nothing was handed over and nothing goes
out, so a free **healthchecks.io** check watches instead: Resend tells it each
time a report is delivered (a webhook on `email.delivered`), and it emails the
owner when a working day passes without one. There is no code for this on the
clinic PC, and healthchecks.io never sees the report.

It is **off until `notify.toml` exists** beside the source with a `to` address,
a Resend `api_key` and a `from` address. Copy `notify.example.toml` to
`notify.toml` and follow the setup steps in it. Two things matter most: a domain
of the clinic's own must be verified in Resend and `from` must be an address on
it — there is no fallback sender, because a scheduled report from Resend's
shared testing sender (`onboarding@resend.dev`) was accepted and then failed at
its send time on the first live run; and the
key must be **Full access**, because a sending-only key almost certainly cannot
cancel an earlier version (the first live run confirmed that a Full access key
can).
`notify.toml` is git-ignored. An old `notify.toml` from the Gmail version
(`smtp`, `user`, `password`, no `api_key`) counts as off. The server says which
at every start:

```
  Email          : on -> owner@example.com  (daily report at 17:30, sent by Resend; last complete report: 5:30 pm on 27 September 2026)
  Email          : off (no notify.toml)
  Email          : off (notify.toml has no Resend api_key)
  Email          : off (notify.toml has no from address)
```

What has to survive a restart is on disk under `Records/Notifications/`:
`last report.txt` (how far the reports are known to be complete — handed over
and past their send time) and `scheduled report.toml` (the version waiting at
Resend, earlier ones still to be cancelled, and a hand-over whose answer has not
arrived yet, which is asked about again with the very same request so that a
dropped connection cannot turn into a second email). The program writes both;
do not edit them. The `outbox/` and `sent/` folders the Gmail version left there
are no longer used and can be deleted by hand. The owner's inbox is the archive
of what was sent.

Problems — no internet, a key or an address Resend refuses — go to
`Records/audit_log.txt` and the terminal as one plain sentence, and are tried
again: after five minutes, or, for a settings problem, after an hour or as soon
as `notify.toml` is saved again.

`Records/Change Log.csv` is the paper trail the report is built from — one row
per write to the books, appended by both front doors, written whether or not
email is configured. If it cannot be read properly, the report says so in its
subject line and in its very first paragraph, and never claims a quiet day; a
damaged line is named by its line number, counting the heading as line 1. Each
save first mends a last line left unfinished (a power cut, a hand edit), so the
damage stays on that one line.

**The form never mentions email.** Nothing about it appears on screen, and an
email service that is down or misconfigured cannot fail or slow a save.

---

## Testing

**Always point `LEDGER_ROOT` at a scratch folder first.** Every test writes to
disk.

```
LEDGER_ROOT=/tmp/ldgr_test julia test_endtoend.jl    # 47 checks, the Warnings Guide §9 list and the ledger number format
julia test_checks_basic.jl                           # each warning, in isolation
julia test_checks_hints.jl                           # the diagnostic hints
LEDGER_ROOT=/tmp/ldgr_ep julia test_endpoints.jl     # the form's endpoints, /api/next and the warm-up, in-process
LEDGER_ROOT=/tmp/ldgr_lc julia test_launcher.jl       # the launcher's flags and its zoom reset, on scratch files. Opens no window.
LEDGER_ROOT=/tmp/ldgr_nt julia test_notify.jl        # the change log and the daily report. Sends nothing: a fake mailer, and a local stub in Resend's place.
```

Set `LDGR_NO_DIGEST=1` for every test run and every scratch server, so no report
is ever composed from scratch books or handed to Resend. Nothing a test runs may
reach the real Resend: `test_notify.jl` points `Resend.API_BASE[]` at a stub
server on 127.0.0.1 and refuses to run otherwise.

`test_endtoend.jl` prints PASS/FAIL per case and exits non-zero on any failure.

---

## The identity

    Opening + Cash sales − Expenses − Deposit − Mr. Boyle = Closing

Two checks come from it:

- **Day check** — does the counted drawer match what the figures predict?
- **Overnight check** — does this morning's opening match the last working day's
  closing?

Both differences are recorded as journal columns *and* posted to the Cash
Over/Short account, so QuickBooks' petty cash balance keeps matching the drawer.

The three POS figures appear in neither check. Card money settles bank-side and
never enters the drawer, so nothing in this program can verify a POS figure —
only the bank statement can.

---

## Files

| File | |
|---|---|
| `Config.jl` | Chart of accounts, the cash book, the identity. **Never change a category `key`.** |
| `Layout.jl` | Every path in the system. Nothing else builds one. |
| `Checks.jl` | **New.** All four warning tiers. Codes match the Warnings Guide. |
| `Chain.jl` | **New.** Previous-day lookup across month/year, and the ledger gate. |
| `Report.jl` | **New.** The daily report text file. |
| `Changes.jl` | **New.** The change log: one row per write to the books, the paper trail the daily report reads. |
| `Notify.jl` | **New.** The one daily report: what it says, and when each version of it is handed to Resend, cancelled, settled or sent late. Never touches the network itself. Off until `notify.toml` has a `to` and an `api_key`. |
| `EmailHtml.jl` | **New.** The daily report's HTML body, beside its plain text: the same facts, with what needs attention first and routine days as compact rows. Included by `Notify.jl` (not a module of its own); it works nothing out itself. Design: `handoff/email-html-design.md`. |
| `Resend.jl` | **New.** The email service's two calls, send and cancel, with every failure turned into one plain sentence. Loaded by `server.jl` only, so the command line never sends. |
| `DayInput.jl` | Input → one `DayRecord`. Blank-vs-zero lives here. |
| `Journal.jl` | The Daily Journal. Read, write, upsert, totals. |
| `Ledger.jl` | Double-entry rows, including the over/short posting. |
| `AuditLog.jl` | Who ran what, when, and what it touched. |
| `main.jl` | `process_day` — the pipeline both front doors call. |
| `server.jl` | The only place browser and bookkeeping code meet. |
| `public/` | The form. Holds no category names of its own. |

---

## Rules that must not be broken

1. **Never change a category `key` in Config.jl.** Keys are the column headings
   in every journal ever written. Labels and account strings are safe to change
   at any time.
2. **Never build a path outside Layout.jl.**
3. **Never calculate the closing balance for the user.** It is the only figure
   that comes from counting the drawer. Fill it in automatically and every day
   balances by construction and the check detects nothing, permanently.
4. **Never pre-fill the opening balance either** — the overnight check would
   compare a number against itself.
5. **Never let a Level 2 be dismissed with one click.** The typed reason is the
   entire value of the warning.
6. **Never edit a Daily Journal in Excel.** It reformats the date column on save
   and the file becomes unreadable. Correct figures by re-entering that date.
7. **Never change the server bind address from 127.0.0.1.**
8. Do not run two servers against the same Records folder. Concurrent writes can
   still lose a day; the informal rule is one person entering at a time.

---

## Before this goes live

- [x] **Confirm the Cash Over/Short account.** `Config.jl` uses the clinic's
      temp account, `"Cash & Cash Equivalent:Temp Account"`: a dedicated account
      could not be approved. Other entries may share it, so staff describe each
      posting in QuickBooks.
- [x] **Verify every account string.** Done before 6 October 2026: every name
      matched on a CSV import into QuickBooks.
- [ ] Decide whether a month can be locked once exported to QuickBooks.
- [ ] Decide whether refunds, bank withdrawals to the till, or money in from
      Mr. Boyle need their own fields. Today they would be rejected as negatives.
