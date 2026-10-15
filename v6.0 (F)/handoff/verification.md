# Verification guide (main session)

This covers how to prove the work is done: the environment, safe commands, the Julia test runner, the contract cross-check, the browser script and the visual review. Write the scripts **while the agents work** (step 3 of the README's order of operations) and run them once all three have reported.

## 1. Environment (this machine)

- **Operating system:** Windows 11. Use Git Bash (POSIX) or PowerShell.
- **Julia:** 1.9.2 on PATH, with HTTP 1.11.0, JSON3 1.14.3, DataFrames 1.6.1 and CSV 0.10.16 installed. The README asks for 1.10+, but the server and every endpoint ran fine on 1.9.2.
- **Other tools:** Node v24, Google Chrome (and Edge), Python 3.14.
- **Playwright:** `playwright-core` is not installed globally. Install it in your own scratch folder:
  ```bash
  npm init -y && npm i playwright-core@1
  ```
  Then launch local Chrome with `chromium.launch({ channel: "chrome", headless: true })`. No browser download is needed.
- **Slow first requests:** Julia compiles each endpoint the first time it is called, which can take several seconds. Warm the endpoints with `curl` after starting the server. In scripts, wait for responses or selectors, never fixed sleeps.

## 2. Safety

- **Always set `LEDGER_ROOT`.** Every server or test run sets it to a folder in your scratchpad, so nothing is ever written to `v4.0/Records/`.
- **`test_endtoend_edge.jl` deletes its `LEDGER_ROOT`** as its first action.
- **One server only:** the main session's server runs on port **8765**. Agents use 8798 or 8799.
- **Starting the server.** From PowerShell, run it in the background from `E:\Ldgr\v4.0`:
  ```powershell
  $env:LEDGER_ROOT = '<scratch>\records-verify'; $env:LDGR_NO_BROWSER = '1'
  $env:LDGR_NO_DIGEST = '1'; $env:LDGR_NOTIFY_CONFIG = '<scratch>\no-such-file.toml'
  julia --startup-file=no server.jl 8765
  ```
  `LDGR_NO_DIGEST` and a `LDGR_NOTIFY_CONFIG` that does not exist are both required: a server started beside a working `notify.toml` would hand the owner a report built from the scratch books within seconds. The start-up `Email` line must read `off (no notify.toml)`.
- **When changes take effect:**
  - Front-end files are read on every request, so reloading the page is enough.
  - Julia changes need a server restart.
- **Resetting data between runs:** you may delete the *contents* of the scratch `LEDGER_ROOT` while the server runs. Each request re-reads the staging file and journals from disk.
- **Clean up:** stop the server when done, then confirm with `Get-NetTCPConnection -LocalPort 8765 -State Listen`.

## 3. Julia tests — `run-julia-tests.sh`

The test scripts `include("Config.jl")` and similar files relative to their own folder, but they live in `tests/`. Run them from a flattened copy:

```bash
#!/usr/bin/env bash
# usage: run-julia-tests.sh <scratch-folder-as-posix-path>
set -u
S="$1"
rm -rf "$S/v4" "$S"/root-* && mkdir -p "$S"
cp -r /e/Ldgr/v4.0 "$S/v4"
rm -rf "$S/v4/Records" "$S/v4/handoff" "$S/v4/notify.toml" "$S/v4/resend-work"
cp "$S"/v4/tests/*.jl "$S/v4/"
cd "$S/v4"
# No report may ever be composed from scratch books or handed to Resend.
export LDGR_NO_DIGEST=1
export LDGR_NOTIFY_CONFIG="$(cygpath -w "$S/no-such-file.toml")"
for t in test_checks_basic test_checks_edge test_checks_hints test_checks_titles test_endtoend test_endtoend_edge; do
  root="$S/root-$t"; mkdir -p "$root"
  echo "===== $t"
  LEDGER_ROOT="$(cygpath -w "$root")" julia --startup-file=no "$t.jl" > "$S/$t.log" 2>&1
  echo "exit=$?"; tail -4 "$S/$t.log"
done
```

**What each test must show:**
- `test_checks_basic`, `_edge` and `_hints` only print findings. They must exit 0 with no Julia errors in the log.
- `test_checks_titles` must pass.
- `test_endtoend` and `test_endtoend_edge` must end with `FAILED 0`.

## 4. Contract cross-check

This catches places where Agent B's markup and Agent C's logic don't agree.

```bash
cd /e/Ldgr/v4.0/public
# Every static id app.js looks up must exist in index.html
grep -o '\$("[A-Za-z0-9_-]*")' app.js | sed 's/^\$("//; s/")$//' | sort -u | while read -r id; do
  grep -q "id=\"$id\"" index.html || echo "MISSING in index.html: #$id"
done
# Every class app.js sets should be styled somewhere
grep -oE "(className *= *|classList\.(add|toggle|remove)\()[\"'\`][^\"'\`]*" app.js | sed -E "s/.*[\"'\`]//" | tr ' ' '\n' | grep -vE '^\$|^$' | sort -u | while read -r c; do
  grep -q "\.$c\b" styles.css || echo "no CSS for .$c"
done
# Old names that must be gone
grep -nE "findings-rail|findings-sticky|slot-closing-container|renderFindings" app.js index.html styles.css
git -C /e/Ldgr status --short    # only the owned files + handoff docs should show up
```

Also check `querySelector` and `querySelectorAll` selectors in `app.js` by hand, along with the IDs built from templates (`in-KEY`, `err-KEY`).

## 5. Browser script — `verify-ui.mjs`

This drives the real app at `http://127.0.0.1:8765`, with a fresh scratch `LEDGER_ROOT` for each timezone run.

**Skeleton:**

```js
import { chromium } from "playwright-core";
const BASE = "http://127.0.0.1:8765";
const TZ = process.env.TZ_ID || "America/Port_of_Spain";      // also run with Asia/Bangkok
const OUT = process.env.OUT || "shots";
const browser = await chromium.launch({ channel: "chrome", headless: true });

const fails = [];
const check = (label, cond, extra = "") => { console.log(`${cond ? "PASS" : "FAIL"}  ${label} ${extra}`); if (!cond) fails.push(label); };
const rect = (page, sel) => page.$eval(sel, el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; });
const hits = (a, b) => a.w > 0 && b.w > 0 && a.x < b.r && a.r > b.x && a.y < b.b && a.b > b.y;

async function newPage(width, height) {
  const ctx = await browser.newContext({ viewport: { width, height }, timezoneId: TZ });
  const page = await ctx.newPage();
  const errors = [];
  page.on("console", m => { if (m.type() === "error" && !/favicon/.test(m.text())) errors.push(m.text()); });
  page.on("pageerror", e => errors.push(e.message));
  page.on("dialog", d => d.accept());                  // the "mark as CLOSED?" confirmation
  await page.goto(BASE);
  await page.waitForSelector("#in-cash_sales");
  return { ctx, page, errors };
}
// …flows below…
await browser.close();
process.exit(fails.length ? 1 : 0);
```

Read `today` from `GET /api/config` (for example with `page.request.get(BASE + "/api/config")`). Choose dates relative to it:
- **D1** = today − 3 days
- **D2** = D1 + 1

To pick a date, call `selectOption` on `#sel-year`, then `#sel-month`, then `#sel-day`, in that order.

### Flows

Run them at 1440×900, once per timezone, starting each run from an **empty** `LEDGER_ROOT` so it is the first day on record.

1. **Calm start.**
   - After load, wait for `#checks-list li.check.todo` to have 2 rows (Opening and Closing).
   - Expect no `li.check:not(.todo)` rows and `#dock-note` hidden.
   - `#prior-hint` is visible and mentions the first day on record.
   - Screenshot `entry-calm`.
2. **A to-do turns red.**
   - Click `#in-closing_balance`, then click the page body so the box loses focus while still blank.
   - Expect `li.check.lv1:not(.todo)[data-field="closing_balance"]`.
   - Expect `#dock-note` visible with class `lv1`.
3. **Unbalanced day** (this also covers the W6 race).
   - Select D1. Fill opening `0`, cash sales `1500`, doctor's fees `100`, closing `1300`. The figures predict 1400 against 1300 counted.
   - **Race:** immediately after filling closing, click `#btn-next`. Expect **no** `POST /api/staged` returning 200 for D1, `#reason-box` visible and `#txt-reason` focused.
   - **Rows present:** `[data-code="L2-A"]` (title "Day doesn't balance", meta contains "Needs a reason"), `[data-code="L4-2"]` (tip) and `[data-code="L3-D"]` (first day).
   - **Dock and form state:**
     - `#dock-note.lv2` is visible and includes "does not balance", plus `.note-action`.
     - `.field[data-key="closing_balance"][data-level="2"]` is present.
     - `#btn-next` is disabled while the reason is empty.
   - **Dismissing:**
     - Click `.note-close`: `#dock-note` hides.
     - Change doctor's fees to `90` and wait for the next `/api/check` response. `#dock-note` must **stay hidden**.
     - Screenshot `entry-unbalanced`, then again after scrolling to the bottom.
   - **Server side of W6:** `page.request.post(BASE + "/api/staged", { data: { date: D1, amounts: {opening_balance:0, cash_sales:1500, doctor_fees:90, closing_balance:1300}, reason: "" } })` must return 400 with `needsReason: true`.
   - Type the reason `Miscounted the 20s`. `#btn-next` is enabled.
4. **Save & next day** (W3, W4, W5).
   - Click `#btn-next` and wait for `POST /api/staged` 200, then `GET /api/staged`.
   - The date selects show **D2**, in both timezones.
   - `#txt-reason` is `""` and `#reason-box` is hidden.
   - The figures are cleared and `#tot-staged` is `1`.
   - The banner mentions "saved".
   - A `GET /api/prior?date=D2` request was made.
5. **Closed day** (W7).
   - On D2, click `label.daytype-toggle`. Expect `#view-entry.is-closed`, with `#card-figures` and `#card-evening` hidden.
   - Wait for a `/api/check` whose request body has `"status":"closed"`. Expect a `[data-code="L3-C"]` row.
   - Screenshot `entry-closed`.
   - Click `#btn-review` (the confirmation dialog is auto-accepted) and wait for `POST /api/staged` 200.
   - `#view-review` is visible, and `#review-table tbody tr` has 2 rows.
   - The D2 row contains `.badge.closed`.
   - `#genesis-line` is visible (W1).
   - Screenshot `review`.
6. **Edit restores the day** (W4).
   - **Edit D1:** click Edit on the D1 row. Expect:
     - `#txt-reason` = `Miscounted the 20s`;
     - `#chk-closed` not checked;
     - `#in-opening_balance` = `0.00`;
     - `#in-doctor_fees` = `90.00`.
   - Click `#btn-cancel-edit`. Expect the reason to be empty.
   - **Edit D2:** click `#btn-review`, then Edit on D2. Expect `#chk-closed` checked and `#view-entry.is-closed`.
   - Click `#btn-cancel-edit`, then `#btn-review`.
7. **Failed commit shows the reasons** (W2).
   - With `#chk-genesis` unticked, click `#btn-commit` and wait for `/api/commit`.
   - Expect `#view-done` visible and `#done-title` = "Saved with problems".
   - Expect 2 × `.result.bad`, whose text includes "first day on record".
   - Screenshot `done-failed`.
8. **Successful commit.**
   - Click `#btn-restart`. The entry view shows, with a banner about 2 waiting days and `#tot-staged` = `2`.
   - Click `#btn-review` and tick `#chk-genesis`. `#btn-commit` reads "Save to the books".
   - Commit. Expect `#done-title` = "Saved to the books" and 2 × `.result:not(.bad)`.
   - Screenshot `done-ok`.
9. **No console errors.** The page's `errors` array is empty (the favicon 404 is ignored).

### Layout assertions

Run these at each width: 1440×900, 1280×800, 1024×768 and 390×844.

Use a fresh page on the entry view in the unbalanced state from flow 3. There's no need to save; clear the `LEDGER_ROOT` contents first so the state is repeatable.

**At every width:**
- `document.documentElement.scrollWidth <= innerWidth` (no horizontal scroll).
- **Dock doesn't cover content:** scroll to the bottom. The bottom of `#card-evening` is ≤ the top of `#dock` (1px tolerance).
- **Watermark doesn't collide:** `.watermark` does not intersect `#dock`, checked both at the top of the page and scrolled to the bottom.

**At 1100px and wider:**
- `#checks` is visible and intersects no `.card`, at the top of the page and mid-page.
- `#dock-status` is not visible.

**Below 1100px:**
- `#checks` is not visible, and `#dock-status` is visible.
- Click `#dock-status`: `#checks.open` becomes visible and does not intersect `#dock`.
- Press Escape: the sheet closes.

**Screenshots** at every width: `<tz>-<width>-entry-top`, `<tz>-<width>-entry-bottom`, and at widths below 1100 also `<tz>-<width>-checks-open`. Also take `<tz>-<width>-review` and `<tz>-<width>-done` from the flow run, at 1440 only.

## 6. Visual review

Look at every screenshot, keeping the owner's rule in mind: *simple enough for a non-technical, non-accountant employee; refined and minimal; same palette.*

- [ ] One obvious primary button per screen, and nothing else competing with it.
- [ ] Only green plus the warning colours, and no stray hues.
- [ ] The four warning levels are distinct by icon and word, not only colour.
- [ ] The Checks panel and dock read clearly and never cover inputs.
- [ ] The dock explanation is one calm row.
- [ ] Glass is subtle, and text on glass is fully readable.
- [ ] The card accent bars are the same green on all three cards, aligned, with no clipped corners.
- [ ] The header is tidy at 390px, and the stepper doesn't wrap awkwardly.
- [ ] The watermark is low-key, in the bottom-left or in the footer, and never touches the dock.
- [ ] Review: badges styled, table scrolls horizontally inside its card, checkbox rows are clear.
- [ ] Done: results are readable, and a failed day stands out.
- [ ] Copy is plain English. No "L2-A EXPLAIN" jargon is visible except the tiny codes.

## 7. Fix loop

- **Small issues** (a selector mismatch, spacing, a missing state class): fix them directly in the file.
- **Larger issues:** `SendMessage` to the agent that owns the file, with the failing check and the screenshot path. It still has its context.
- **After any fix:** re-run the affected part (the Julia tests, `verify-ui.mjs` for the affected timezone and widths, or both). Finish with one complete clean run of everything.
- **Then:** stop the server, and report to the owner with the change summary, test results and key screenshots. Don't commit unless asked.
