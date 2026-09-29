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

Install the packages once:

```
julia -e 'using Pkg; Pkg.add(["DataFrames","CSV","HTTP","JSON3"])'
```

`PackageCompiler` is needed only to build the optional system image described
under "Faster start with a sysimage" below; the program does not use it.

---

## Running it

### The form (normal use)

```
julia server.jl
```

The form opens by itself in its own window, with no address bar or tabs (Chrome
or Edge; otherwise the default browser). If no window appears, open
<http://127.0.0.1:8000>. Use `julia server.jl 9000` for a different port.
Ctrl+C in the terminal window stops it. Set `LDGR_NO_BROWSER=1` to start the
server without opening a window.

Before it listens, the server warms itself up ("Warming up..." then "Ready"):
it runs the checks, a journal write and one request to itself against scratch
data so that the first Save of the day is not spent compiling. It writes nothing
to the books. Set `LDGR_NO_WARMUP=1` to skip it when restarting often during
development.

In the form, **Save** writes the day on screen to the books and stays on it.
**Next day** asks the server whether that day is in the books exactly as shown
(`POST /api/next`) and moves to the day after only if it is; otherwise it says
what still has to be saved and stays put.

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
├── Notifications/                       ← only if notify.toml exists
│   ├── last report.txt
│   ├── outbox/
│   └── sent/
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

One email a day, to the owner, saying what happened in the books — sent at 18:30
machine time by the server, or when the server next starts if it was off at
18:30 (one email covering the whole missed stretch). It lists the days entered
and any differences with the reasons typed for them, days that were changed
after the date they were first saved, gaps that were filled and the ledgers they
released, and the ledgers still waiting. A quiet day still sends a short
"nothing to report", so silence means the program was not running.

It is **off until `notify.toml` exists** beside the source. Copy
`notify.example.toml` to `notify.toml` and fill it in. The password is a Gmail
**app password** (Google Account → Security → 2-Step Verification → App
passwords), not the account password. `notify.toml` is git-ignored.

Everything is on disk: each message is written to `Records/Notifications/outbox`
before any network call and moves to `sent/` once it goes, so a message that
could not be sent is still there to read. `Records/Change Log.csv` is the paper
trail the report is built from — one row per write to the books, appended by
both front doors, written whether or not email is configured.

**The form never mentions email.** Nothing about it appears on screen, and a
mailbox that is misconfigured cannot fail a save.

---

## Testing

**Always point `LEDGER_ROOT` at a scratch folder first.** Every test writes to
disk.

```
LEDGER_ROOT=/tmp/ldgr_test julia test_endtoend.jl    # 45 checks, the Warnings Guide §9 list
julia test_checks_basic.jl                           # each warning, in isolation
julia test_checks_hints.jl                           # the diagnostic hints
LEDGER_ROOT=/tmp/ldgr_ep julia test_endpoints.jl     # the form's endpoints, /api/next and the warm-up, in-process
LEDGER_ROOT=/tmp/ldgr_nt julia test_notify.jl        # the change log and the daily report. Sends nothing.
```

Set `LDGR_NO_DIGEST=1` for every test run and every scratch server, so no report
is ever composed from scratch books or sent to the owner.

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
| `Notify.jl` | **New.** The one daily report, by email. Off until `notify.toml` exists. |
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

- [ ] **Confirm the Cash Over/Short account.** `Config.jl` currently uses
      `"Unidentified Income"`. Check it is not already used for unidentified
      *receipts* — if it is, a shortage and a receipt would net against each
      other and the balance-sheet review would show nothing.
- [ ] **Verify every account string** against a CSV export of the chart of
      accounts, opened in a text editor rather than Excel. Two of the handful
      checked so far were wrong.
- [ ] Decide whether a month can be locked once exported to QuickBooks.
- [ ] Decide whether refunds, bank withdrawals to the till, or money in from
      Mr. Boyle need their own fields. Today they would be rejected as negatives.
