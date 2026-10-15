# Agent A — Backend (Julia)

You are one of three sub-agents working **in parallel** on ldgr v4.0 (`E:\Ldgr\v4.0`). You own the small Julia changes that the redesigned form needs. Two other agents are editing `public/` at the same time, so do not touch those files. The main session will review your work when you report back.

## Read first
1. `E:\Ldgr\CLAUDE.md` — safety rules, especially `LEDGER_ROOT`.
2. `E:\Ldgr\v4.0\handoff\issues-and-design.md`, specifically W1, W6 and section 3 "Backend changes".
3. `v4.0/Checks.jl` and `v4.0/server.jl`, in full. Match their comment style: comments explain *why*, in plain English.

## You own (edit only these)
- `v4.0/Checks.jl`
- `v4.0/server.jl`
- `v4.0/tests/test_checks_titles.jl` (new)
- `v4.0/tests/TESTING.md`

## Must not
- Edit anything in `v4.0/public/` or any other `.jl` file.
- Change `Finding`, `check_day`, or any existing warning message, code or level.
- Start a server on port **8765**, which is the main session's. For a smoke test, use port **8799** and stop the server afterwards.
- Run the server or any test without `LEDGER_ROOT` pointing inside your scratch folder. **`test_endtoend_edge.jl` deletes its `LEDGER_ROOT` folder when it starts.**
- Commit.

## Tasks

### 1. `Checks.jl` — short titles
Add `finding_title(code) -> String` and export it. Return a short plain-language phrase for each code, and `""` for an unknown code.

Put the table next to the tiers it describes, with a comment explaining why it exists:
- The form's side panel needs a few words per warning.
- The full `message` is still the explanation.
- The code still traces back to the Warnings Guide.

| Code | Title |
|---|---|
| L1-A | Negative amount |
| L1-B | More paid out than was in the drawer |
| L1-C | Drawer not counted |
| L1-D | Not a valid amount |
| L1-E | Date not allowed |
| L2-A | Day doesn't balance |
| L2-B | Opening doesn't match last close |
| L3-A | Ledger waiting on the day before |
| L3-B | Ledger already made for this day |
| L3-C | Marked as closed |
| L3-D | First day on record |
| L4-1 | Digits may be swapped |
| L4-2 | Matches one of your figures |
| L4-3 | Decimal point may be off |
| L4-4 | Card and cash may be mixed up |

### 2. `server.jl`
- **`findings_json`:** add `title = Checks.finding_title(f.code)` to each finding. Keep every existing field (`code`, `level`, `levelName`, `field`, `message`).
- **`handle_staged`:** add `genesis = Chain.is_genesis_date(rec.date)` to each day, next to `inJournal` and `hasDailyLedger`. Comment it: the form shows the "first day on record" checkbox only when a staged day needs it. Before this, `allowGenesis` was never sent as true, so the first commit could never succeed from the form (W1).
- **`handle_stage`:** right after the existing STOP refusal, refuse a day that needs a reason but has none:
  ```julia
  if any(f -> f.level == Checks.LEVEL_EXPLAIN, fs) && isempty(strip(rec.reason))
      return json(400, (ok=false, error="This day doesn't balance. Add a short reason before saving it.",
                        findings=fs, needsReason=true))
  end
  ```
  Comment it the same way as the STOP refusal: the browser checks this too, but the server's copy is the one that counts (Handover §4 rule 5). Closing a race in the browser also depends on it (W6). Closed days never produce EXPLAIN findings, so they are unaffected.

### 3. `tests/test_checks_titles.jl` (new)
Copy the style of the other test files: `include("Config.jl")`, `getdate.jl`, `DayInput.jl` and `Checks.jl` relative to itself, then print `PASS`/`FAIL` lines and exit non-zero on any failure.
- Read `Checks.jl`'s source text next to the test and collect every code matching `Finding\("(L\d-[A-Z0-9]+)"`.
- Assert the list is non-empty.
- Assert each collected code has a non-empty `finding_title`.
- Assert `finding_title("XX-9") == ""`.

### 4. `tests/TESTING.md`
Add a short section for `test_checks_titles.jl`. Add a line noting the two server changes (the `genesis` flag on staged days, and refusing a needs-reason day with no reason at staging), in the document's existing style.

## Check your work
1. **Make a flattened scratch copy.** The tests include their sources relative to themselves:
   ```bash
   S="<your scratch folder>"            # e.g. <scratchpad>\agent-a  (use a Git Bash path, e.g. /c/Users/...)
   rm -rf "$S/v4" && mkdir -p "$S" && cp -r /e/Ldgr/v4.0 "$S/v4"
   rm -rf "$S/v4/Records" "$S/v4/handoff" && cp "$S"/v4/tests/*.jl "$S/v4/"
   cd "$S/v4"
   ```
2. **Run each test with its own fresh `LEDGER_ROOT`.** Pass a Windows path, e.g. `LEDGER_ROOT="$(cygpath -w "$S/root-basic")"`:
   - `julia --startup-file=no test_checks_basic.jl` — prints findings only; confirm it runs without errors.
   - `test_checks_edge.jl` and `test_checks_hints.jl` — the same.
   - `test_checks_titles.jl` — must pass.
   - `test_endtoend.jl` — must end with `FAILED 0`.
   - `test_endtoend_edge.jl` — must end with `FAILED 0`. Give it a different root.
3. **Server smoke test** (optional, recommended). From the scratch copy: `LEDGER_ROOT=<scratch root> julia --startup-file=no server.jl 8799`. The first request to each endpoint is slow while Julia compiles. Then use `curl`:
   - `POST /api/check` with `{"date":"<a past date>","amounts":{"opening_balance":0,"cash_sales":1500,"doctor_fees":100,"closing_balance":1300}}` — every finding has a non-empty `title`.
   - `POST /api/staged` with the same body and `"reason":""` — HTTP 400 with `"needsReason":true`.
   - The same with `"reason":"Miscounted"` — HTTP 200.
   - `GET /api/staged` — the day has `"genesis":true` on a fresh root.

   Stop the server when done.

Julia 1.9.2 is on PATH with the needed packages. The README says 1.10+, but this code runs on 1.9.2.

## Report back (your final message)
- **Per file:** what changed, in a few lines.
- **Tests:** the exact commands, plus each test's closing summary lines (PASS/FAIL counts, or "ran without error").
- **Smoke test:** the results.
- **Judgement calls:** anything you had to decide that the docs didn't cover.
