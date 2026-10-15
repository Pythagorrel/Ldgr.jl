/* verify-ui-2026-09-15b.mjs — browser verification of the 2026-09-15 (evening)
   front-end work: implementation-2026-09-15.md §6 (decisions 5 and 7, review
   §3.2 #5–#10, §3.3 #1–#4, §3.4 #1–#8 and the Off-day Stop of §3.7).

   It walks the end-user scenarios of review-2026-09-15.md §5.2 in this order:

     (a) the first day on record        (k) crossing the month boundary
     (b) an ordinary balanced day       (d) a day that doesn't balance, with a tip
     (e) opening doesn't match          (f) both differences, two reasons
     (c) an Off day and the day after   (g) a Must-fix and a blank closing
     (h) mistyped figures               (i) a day out of order, then the gap filled
     (j) editing a saved day            (l) a future date, and saving today
     (m) an Off day with no day before  -> refused, no confirm dialog

   and then repeats the shapes of (b), (d), (j) and (m) at 390 px.

   WORDING THAT IS STILL MOVING. Three titles change when stream A's Checks.jl
   is integrated (L3-A "Waiting on the day before", L3-B "A file was already
   made for this day", L3-C "Off day"), and so do the tips: in (d) the row stays
   "Matches one of your figures · Tip · Taxi Fare" but its explanation is
   reworded, and in (i) the divisible-by-nine row is replaced by "Check this
   figure · Tip · Cash Sales". Every assertion about a moving title accepts the
   old wording and the new one; tips are found by level, printed, and not
   asserted word for word; no server MESSAGE is asserted at all. Rows are found
   by their data-code, which does not move. So this script passes on both sides
   of the integration.

   HOW TO RUN (never against the real Records folder):
     1. In a scratch folder:  npm init -y && npm i playwright-core@1   (uses the
        installed Chrome; no browser download), then copy this file there.
     2. From the v4.0 folder, with LEDGER_ROOT set to an EMPTY scratch folder,
        LDGR_NO_BROWSER=1, LDGR_NO_DIGEST=1, and LDGR_NOTIFY_CONFIG set to a
        path inside the scratch folder that does not exist:
           julia --startup-file=no server.jl 8798
        (A server started beside a working notify.toml would hand the owner a
        report built from the scratch books within seconds.) The start-up
        "Email" line must read "off (no notify.toml)".
        Wait for "Ready." (warm-up takes ~9 s after the ~7 s package load).
     3. node verify-ui-2026-09-15b.mjs        -> PASS/FAIL lines, screenshots in
        ./shots-b. Add --integration to run the flows that need stream B's new
        /api/save fields (nextDayStale, held, "removed"); without it those are
        printed as SKIP. Those three are written out at the end of the script
        and have never been run — this copy's server does not send the fields
        — so expect to fix them the first time they are used.
     4. Stop the server; confirm nothing listens on 8798.

   The root must be EMPTY: the first scenario is the first day ever on record,
   and every later scenario builds on the one before it. Dates are worked out
   from /api/config's `today` (the walkthroughs assume 15 September 2026, and
   the first day is 15 days earlier). */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE = "http://127.0.0.1:8798";
const INTEGRATION = process.argv.includes("--integration");
const SHOTS = path.resolve("shots-b");
fs.mkdirSync(SHOTS, { recursive: true });

let fails = 0, skipped = 0, shot = 0;
const ok    = (m) => console.log("PASS  " + m);
const bad   = (m, extra) => { fails++; console.log("FAIL  " + m + (extra ? "  -- " + extra : "")); };
const check = (cond, m, extra) => cond ? ok(m) : bad(m, extra);
const skip  = (m) => { skipped++; console.log("SKIP  " + m + "  (needs stream B: run with --integration)"); };
const note  = (m) => console.log("      " + m);
const head  = (m) => console.log("\n--- " + m);

/* An assertion about wording that is being changed elsewhere: any of the
   accepted forms passes, and what was found is printed either way. */
function oneOf(actual, accepted, m) {
  const hit = accepted.some(a => a === actual);
  check(hit, m, JSON.stringify(actual));
  if (hit) note("text: " + JSON.stringify(actual));
}

const shift = (iso, n) => {
  const [y, m, d] = iso.split("-").map(Number);
  const t = new Date(y, m - 1, d + n, 12);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
};
const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
const pretty = (iso) => {
  const [y, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]} ${y}`;
};

/* Console noise. A refusal provoked on purpose answers 400, and so does every
   check of a negative figure until stream B turns those into findings. */
const errors = [];
let expect400 = false;
const isNoise = (t) => /favicon/i.test(t) || (expect400 && /400/.test(t));
const watch = (page, tag) => {
  page.on("console", (m) => {
    if (m.type() !== "error") return;
    const line = `${tag}: ${m.text()} [${(m.location() && m.location().url) || ""}]`;
    if (!isNoise(line)) errors.push(line);
  });
  page.on("pageerror", (e) => errors.push(`pageerror(${tag}): ${e.message}`));
};

// ---------------------------------------------------------------- page helpers
const until = (page, fn, arg, ms) => page.waitForFunction(fn, arg, { timeout: ms || 20000 });

/* The prior-day hint is fetched separately from the checks, and the line from
   the date before stays on screen until the answer lands. So every assertion
   about it waits for the words it is about and then reads the line ONCE: two
   reads of a line that is still changing disagree with each other. A wait that
   runs out returns whatever is there, so the assertion reports it instead of
   the script stopping. */
async function hintWhen(page, re) {
  try {
    await until(page, (s) => {
      const e = document.getElementById("prior-hint");
      return !!e && !e.hidden && new RegExp(s).test(e.textContent);
    }, re.source, 8000);
  } catch { /* let the caller report what it found */ }
  return textOf(page, "#prior-hint");
}

async function setDate(page, iso) {
  const [y, m, d] = iso.split("-").map(Number);
  await page.selectOption("#sel-year", String(y));
  await page.selectOption("#sel-month", String(m));
  await page.selectOption("#sel-day", String(d));
  await page.waitForTimeout(80);
}

async function setAmount(page, key, value) {
  const sel = "#in-" + key;
  await page.fill(sel, value);
  await page.$eval(sel, (e) => e.blur());
}

// Type several boxes, leaving each one, in the order given.
async function setAmounts(page, pairs) {
  for (const [k, v] of pairs) await setAmount(page, k, v);
}

const waitCode   = (page, code) => until(page, c => !!document.querySelector(`#checks-list li[data-code="${c}"]`), code);
const waitNoCode = (page, code) => until(page, c => !document.querySelector(`#checks-list li[data-code="${c}"]`), code);
const waitSaved  = (page, iso) => until(page, d => document.getElementById("sel-day").value === String(Number(d.split("-")[2])), iso);

const readRows = (page) => page.$$eval("#checks-list li", (els) => els.map((li) => ({
  code:  li.dataset.code || "",
  field: li.dataset.field || "",
  level: (li.className.match(/lv(\d)/) || [])[1] || "",
  title: li.querySelector(".check-title").textContent,
  meta:  li.querySelector(".check-meta").textContent,
})));
const rowFor = async (page, code) => (await readRows(page)).find(r => r.code === code) || null;

const textOf = async (page, sel) => ((await page.textContent(sel)) || "").trim();
const shownText = (page, sel) => page.evaluate((s) => {
  const e = document.querySelector(s);
  return e && !e.hidden && e.getClientRects().length ? e.textContent.trim() : null;
}, sel);

const bannerNow = (page) => page.evaluate(() => {
  const b = document.querySelector("#banner-area .banner");
  if (!b) return null;
  const btn = b.querySelector("button");
  return { kind: b.className.replace("banner", "").trim(),
           text: b.querySelector("span").textContent.trim(),
           action: btn ? btn.textContent.trim() : null };
});

const totals = (page) => page.evaluate(() => ({
  takings:  document.getElementById("tot-cash").textContent,
  expenses: document.getElementById("tot-exp").textContent,
  banked:   document.getElementById("tot-dep").textContent,
}));

const fieldLevel = (page, key) => page.evaluate((k) => {
  const f = document.querySelector(`.field[data-key="${k}"]`);
  return f ? (f.dataset.level || null) : "no such field";
}, key);

async function snap(page, name) {
  shot++;
  const file = path.join(SHOTS, String(shot).padStart(2, "0") + "-" + name + ".png");
  await page.screenshot({ path: file, fullPage: true });
}

/* The codes are for the audit log and the tests, never for the people entering
   days (CLAUDE.md). Nothing on screen may show one. */
async function noCodesOnScreen(page, where) {
  const found = await page.evaluate(() => {
    const t = document.body.innerText || "";
    const m = t.match(/\bL[1-4]-[A-Z0-9]\b/g);
    return m ? [...new Set(m)] : [];
  });
  check(found.length === 0, `no warning code is shown on screen (${where})`, found.join(" "));
}

async function noSideScroll(page, where) {
  const clean = await page.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1);
  check(clean, `no sideways scrolling (${where})`);
}

/* Nothing may float over the page (CLAUDE.md): no fixed or sticky-to-the-window
   element other than the decorative wash, which cannot be clicked. */
async function nothingFloats(page, where) {
  const floating = await page.evaluate(() => {
    const out = [];
    for (const e of document.querySelectorAll("body *")) {
      const s = getComputedStyle(e);
      if (s.position === "fixed" && s.pointerEvents !== "none") {
        out.push(e.id || e.className || e.tagName);
      }
    }
    return out;
  });
  check(floating.length === 0, `nothing floats over the page (${where})`, floating.join(" "));
}

// ------------------------------------------------------------------ the script
async function main() {
  const cfg = await (await fetch(BASE + "/api/config")).json();
  const today = cfg.today;
  const D = (n) => shift(today, n);          // D(-15) is the first day of the story
  console.log(`today=${today}  first day ${D(-15)}  (${INTEGRATION ? "integration flows ON" : "integration flows skipped"})\n`);

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await ctx.newPage();
  watch(page, "1440");

  let dialog = null;
  page.on("dialog", (d) => { dialog = d.message(); d.accept(); });
  const tookDialog = () => { const d = dialog; dialog = null; return d; };

  await page.goto(BASE + "/index.html", { waitUntil: "networkidle" });

  /* ============================================================= (a) 31 August
     The very first day on record. */
  head("(a) the first day on record — " + pretty(D(-15)));
  await setDate(page, D(-15));
  await until(page, () => !document.getElementById("genesis-line").hidden);
  ok("the first-day tick box is showing");
  await page.waitForTimeout(500);                 // let /api/prior answer first
  // review §3.4 #5: the same thing was said three times. The hint goes.
  const noHint = await shownText(page, "#prior-hint");
  check(noHint === null, "the prior-day hint is hidden while the first-day tick box is showing",
        JSON.stringify(noHint));

  await setAmounts(page, [["opening_balance", "1670"], ["cash_sales", "174600"],
                          ["doctor_fees", "49000"], ["deposits", "126000"]]);
  await page.waitForTimeout(700);
  // decision 5: the predicted figure is held back until the count has been made.
  check((await shownText(page, "#predicted")) === null,
        "the predicted closing is not shown before the closing box has been reached",
        JSON.stringify(await textOf(page, "#predicted")));
  await snap(page, "a-first-day-before-count");

  check(await page.$eval("#btn-next", e => e.disabled), "Save is greyed while the first-day box is unticked");
  await setAmount(page, "closing_balance", "1270");
  await until(page, () => !document.getElementById("predicted").hidden);
  // The notice waits for the Stops to clear: beside "Closing Balance Not
  // Entered" it would say a day was accepted that was in fact refused.
  await waitCode(page, "L3-D");
  const genesisRow = await rowFor(page, "L3-D");
  oneOf(genesisRow.title, ["First day on record"], "the first day is announced in the Checks panel");
  check(/Good to know/.test(genesisRow.meta), "…as Good to know", genesisRow.meta);
  check((await textOf(page, "#predicted")) === "Predicted $1,270.00 and that is what was counted. The day balances.",
        "once counted, the line compares the two figures", await textOf(page, "#predicted"));
  await noCodesOnScreen(page, "a");

  await page.check("#chk-genesis");
  await until(page, () => !document.getElementById("btn-next").disabled);
  await snap(page, "a-first-day-ticked");
  await page.click("#btn-next");
  await waitSaved(page, D(-14));
  let b = await bannerNow(page);
  check(b && b.text === `${pretty(D(-15))} saved to the books.`, "the save is confirmed by date", b && b.text);
  check(await page.evaluate(() => document.activeElement === document.querySelector("#slot-opening input")),
        "the cursor is in the opening balance, ready for the next day");

  /* ============================================================ (k) 1 September
     Crossing the month boundary: the previous month's file is found. */
  head("(k) crossing the month boundary — " + pretty(D(-14)));
  let hint = await hintWhen(page, /closed with/);
  check(hint === `${pretty(D(-15))} closed with $1,270.00. Count the drawer and enter what is there — do not copy this figure.`,
        "the hint names what the previous month closed with", hint);
  check(await page.$eval("#genesis-line", e => e.hidden), "no first-day box on the second day");
  await setAmounts(page, [["opening_balance", "1270"], ["cash_sales", "98400"],
                          ["doctor_fees", "22400"], ["deposits", "75000"], ["closing_balance", "2270"]]);
  await page.waitForTimeout(700);
  check((await readRows(page)).length === 0, "nothing to fix on a day that balances",
        JSON.stringify(await readRows(page)));
  check(!(await page.$eval("#checks-empty", e => e.hidden)), "the panel says so");
  check((await textOf(page, "#checks-empty")) === "Nothing to fix so far", "…in those words");
  await page.click("#btn-next");
  await waitSaved(page, D(-13));

  /* ============================================================ (b) 2 September
     An ordinary balanced work day. */
  head("(b) an ordinary balanced work day — " + pretty(D(-13)));
  hint = await hintWhen(page, /\$2,270\.00/);
  check(/closed with \$2,270\.00/.test(hint), "the hint carries yesterday's close through", hint);
  await setAmounts(page, [["opening_balance", "2270"], ["cash_sales", "98400"],
                          ["doctor_fees", "22400"], ["deposits", "75000"]]);
  await page.waitForTimeout(700);
  const t = await totals(page);
  check(t.takings === "$98,400.00" && t.expenses === "$22,400.00" && t.banked === "$75,000.00",
        "the dock totals add up", JSON.stringify(t));
  check((await shownText(page, "#predicted")) === null, "the prediction still waits for the count");
  await setAmount(page, "closing_balance", "3270");
  await until(page, () => !document.getElementById("predicted").hidden);
  check(/The day balances\.$/.test(await textOf(page, "#predicted")), "the day balances",
        await textOf(page, "#predicted"));
  check(await page.$eval("#reason-box", e => e.hidden), "no reason box on a day that balances");
  check(await page.$eval("#genesis-line", e => e.hidden) && await page.$eval("#force-line", e => e.hidden),
        "no tick boxes either");
  await nothingFloats(page, "b");
  await snap(page, "b-balanced-day");
  await page.click("#btn-next");
  await waitSaved(page, D(-12));
  check((await page.inputValue("#in-cash_sales")) === "", "the form is blank for the next day");

  /* ============================================================ (d) 3 September
     A day that doesn't balance, with a tip that names the cause. */
  head("(d) a day that doesn't balance, with a tip — " + pretty(D(-12)));
  await setAmounts(page, [["opening_balance", "3270"], ["cash_sales", "98400"],
                          ["doctor_fees", "22000"], ["taxi_fare", "400"],
                          ["deposits", "75000"], ["closing_balance", "3870"]]);
  await waitCode(page, "L2-A");
  await until(page, () => !document.getElementById("predicted").hidden);
  check((await textOf(page, "#predicted")) ===
        "Predicted $4,270.00, counted $3,870.00 — $400.00 less than the figures account for.",
        "the predicted line says how far out the day is", await textOf(page, "#predicted"));
  const dayRow = await rowFor(page, "L2-A");
  oneOf(dayRow.title, ["Day doesn't balance"], "the difference is named");
  check(dayRow.meta === "Needs a reason · Closing Balance", "…beside its box and its level word", dayRow.meta);
  const tips = (await readRows(page)).filter(r => r.level === "4");
  check(tips.length >= 1, "a tip suggests where to look", JSON.stringify(await readRows(page)));
  tips.forEach(tp => note(`tip: ${JSON.stringify(tp.title)} · ${JSON.stringify(tp.meta)}`));
  check((await fieldLevel(page, "closing_balance")) === "2", "the closing balance is outlined amber");
  check(!(await page.$eval("#reason-box", e => e.hidden)), "the reason box is in End of day");
  check((await textOf(page, "#reason-lead")) === "Day doesn't balance.",
        "…and says what the reason is for", await textOf(page, "#reason-lead"));
  check(await page.$eval("#btn-next", e => e.disabled), "Save is greyed until a reason is typed");
  await noCodesOnScreen(page, "d");
  await snap(page, "d-difference-and-tip");
  await page.fill("#txt-reason", "Taxi paid twice, second trip not written down");
  await until(page, () => !document.getElementById("btn-next").disabled);
  ok("typing the reason makes Save available");
  await page.click("#btn-next");
  await waitSaved(page, D(-11));

  /* ============================================================ (e) 4 September
     The opening balance does not match the last close. */
  head("(e) opening doesn't match the last close — " + pretty(D(-11)));
  await setAmount(page, "opening_balance", "3770");
  await waitCode(page, "L2-B");
  const openRow = await rowFor(page, "L2-B");
  oneOf(openRow.title, ["Opening doesn't match last close"], "the overnight difference is named at once");
  check(openRow.meta === "Needs a reason · Opening Balance", "…beside the opening balance", openRow.meta);
  check(!(await page.$eval("#opening-reason-box", e => e.hidden)),
        "its reason box is in Start of day, while the closing is still blank");
  check((await page.inputValue("#in-closing_balance")) === "", "…the closing balance really is still blank");
  await snap(page, "e-opening-difference");
  await page.fill("#txt-opening-reason", "$100 note found in the safe, put back this morning");
  await setAmounts(page, [["cash_sales", "98400"], ["doctor_fees", "22400"],
                          ["deposits", "75000"], ["closing_balance", "4770"]]);
  await until(page, () => !document.getElementById("predicted").hidden);
  check(/The day balances\.$/.test(await textOf(page, "#predicted")), "the day itself balances",
        await textOf(page, "#predicted"));
  check(await page.$eval("#reason-box", e => e.hidden), "so there is no second reason box");
  await page.click("#btn-next");
  await waitSaved(page, D(-10));

  /* ============================================================ (f) 5 September
     Both differences, each with its own reason. */
  head("(f) both differences, two separate reasons — " + pretty(D(-10)));
  await setAmount(page, "opening_balance", "4270");
  await waitCode(page, "L2-B");
  check(!(await page.$eval("#opening-reason-box", e => e.hidden)),
        "the overnight difference asks for its reason in Start of day");
  await page.fill("#txt-opening-reason", "Envelope of small notes left in the safe overnight");
  await setAmounts(page, [["cash_sales", "98400"], ["doctor_fees", "22400"], ["deposits", "75000"]]);
  await page.waitForTimeout(700);
  /* The last figure and Save in the same instant: the check that brings up the
     second reason box has not run yet, so the button is live and the day would
     have gone without a reason. Save waits for its own check first, finds the
     empty box, and asks (the race in app.js's saveDay). */
  await page.evaluate(() => {
    const box = document.getElementById("in-closing_balance");
    box.focus();
    box.value = "4870";
    box.dispatchEvent(new Event("input", { bubbles: true }));
    box.blur();
    document.getElementById("btn-next").click();
  });
  await until(page, () => /Add a short reason/.test(document.getElementById("banner-area").textContent));
  check(!(await page.$eval("#opening-reason-box", e => e.hidden)) &&
        !(await page.$eval("#reason-box", e => e.hidden)),
        "each difference asks for its own reason, beside its own figure");
  b = await bannerNow(page);
  check(b.text === "Add a short reason before saving this day.", "saving with one reason missing says so", b.text);
  check(await page.evaluate(() => document.activeElement.id === "txt-reason"),
        "…and puts the cursor in the box that is empty");
  await snap(page, "f-two-reasons");
  await page.fill("#txt-reason", "Could not locate");
  await page.waitForTimeout(300);
  /* review §3.2 #6: a message about what just happened used to sit in the same
     place as the standing one and never give it back. Once the reason is typed
     the request goes by itself, and what is standing — here the confirmation
     of the day saved before this one — is on screen again. */
  b = await bannerNow(page);
  check(b === null || !/Add a short reason/.test(b.text),
        "the request for a reason clears itself once the reason is typed", b && b.text);
  check(b === null || b.text === `${pretty(D(-11))} saved to the books.`,
        "…and the standing message comes back in its place", b && b.text);
  await page.click("#btn-next");
  await waitSaved(page, D(-9));

  /* ========================================================= (c) 6, 7 September
     An Off day, then the day after it. */
  head("(c) an Off day and the day after — " + pretty(D(-9)));
  await page.click("label.daytype-toggle");
  await until(page, () => document.getElementById("chk-closed").checked);
  await waitCode(page, "L3-C");
  const offRow = await rowFor(page, "L3-C");
  oneOf(offRow.title, ["Marked as closed", "Off day"], "an Off day is noted in the Checks panel");
  note("level: " + JSON.stringify(offRow.meta));
  check((await shownText(page, "#card-figures")) === null, "the figure cards are gone");
  check((await shownText(page, "#prior-hint")) === null, "so is the prior-day hint");
  check((await textOf(page, "#closed-note")) ===
        "Nothing is posted for an Off day. The next work day carries this balance through.",
        "the note under the toggle is in the form's own words", await textOf(page, "#closed-note"));
  await snap(page, "c-off-day");
  await page.click("#btn-next");
  await page.waitForTimeout(400);
  const q = tookDialog();
  check(q !== null, "an Off day is confirmed before it is saved");
  if (q) {
    note("dialog: " + JSON.stringify(q));
    check(/Off day/.test(q) && !/CLOSED/.test(q), "the question says Off day and never shouts CLOSED", q);
    check(!/ledger/i.test(q) && !/erase/i.test(q), "…and mentions no ledger and no erasing", q);
    check(/work day/.test(q) && !/working day/.test(q), "…and says work day", q);
  }
  await waitSaved(page, D(-8));
  check(!(await page.$eval("#chk-closed", e => e.checked)), "the next day starts as a work day again");
  hint = await hintWhen(page, /\$4,870\.00/);
  check(/closed with \$4,870\.00/.test(hint), "the Off day's balance is carried to the next work day", hint);

  /* ============================================================ (g) 7 September
     A Must-fix, then a blank closing balance. */
  head("(g) a Must-fix and a blank closing balance — " + pretty(D(-8)));
  await setAmounts(page, [["opening_balance", "4870"], ["cash_sales", "98400"],
                          ["doctor_fees", "22400"], ["deposits", "200000"]]);
  await waitCode(page, "L1-B");
  const stopRow = await rowFor(page, "L1-B");
  oneOf(stopRow.title, ["Expenses exceed total cash"], "more paid out than came in is a Must fix");
  check(stopRow.meta === "Must fix", "…with no box to go to", stopRow.meta);
  check(await page.$eval("#reason-box", e => e.hidden), "a Must-fix asks for no reason");
  expect400 = true;
  await page.click("#btn-next");
  await until(page, () => /cannot be saved/.test(document.getElementById("banner-area").textContent));
  await page.waitForTimeout(300);
  expect400 = false;
  b = await bannerNow(page);
  check(b.text === "This day cannot be saved yet.", "the save is refused in one line", b.text);
  check(!(await page.$eval("#dock-note", e => e.hidden)),
        "the whole message opens in the dock, beside the button that was pressed");
  await waitCode(page, "L1-C");
  const blankRow = await rowFor(page, "L1-C");
  oneOf(blankRow.title, ["Closing Balance Not Entered"], "the blank count is named once Save has been pressed");
  check((await textOf(page, "#predicted")) ===
        "There's a deficit of $119,130.00 between the total cash available ($103,270.00) and total paid out ($222,400.00).",
        "a negative prediction is explained as a deficit", await textOf(page, "#predicted"));
  await noCodesOnScreen(page, "g");
  await snap(page, "g-must-fix");
  await setAmount(page, "deposits", "75000");
  await waitNoCode(page, "L1-B");
  check((await rowFor(page, "L1-C")) !== null, "the blank closing balance is still asked for");
  check((await textOf(page, "#predicted")) === "The figures predict $5,870.00. Input the actual amount of money left.",
        "with the box reached, the prediction is shown", await textOf(page, "#predicted"));
  await setAmount(page, "closing_balance", "5870");
  await until(page, () => document.querySelectorAll("#checks-list li").length === 0);
  ok("the panel is back to nothing to fix");
  await page.click("#btn-next");
  await waitSaved(page, D(-7));

  /* ====================================================================== (h)
     A mistyped figure, caught before it reaches the server. */
  head("(h) mistyped figures — on " + pretty(D(-7)) + ", nothing is saved");
  const typed = async (key, value) => {
    await setAmount(page, key, value);
    return { err: await textOf(page, "#err-" + key), value: await page.inputValue("#in-" + key) };
  };
  // review §3.2 #8: the clinic writes its figures with separators.
  let r = await typed("cash_sales", "98,400");
  check(r.err === "" && r.value === "98400.00", "a comma in a figure is accepted", JSON.stringify(r));
  r = await typed("cash_sales", "1 500");
  check(r.err === "" && r.value === "1500.00", "so is a space", JSON.stringify(r));
  r = await typed("cash_sales", "$1500");
  check(r.err === "" && r.value === "1500.00", "so is a dollar sign", JSON.stringify(r));
  r = await typed("cash_sales", "12a");
  check(r.err === "Numbers only — no letters or symbols.", "a letter is not", JSON.stringify(r));
  r = await typed("doctor_fees", "22400.505");
  check(r.err === "At most two decimal places.", "three decimal places is not", JSON.stringify(r));
  r = await typed("doctor_fees", "99999999");
  check(r.err === "That looks too large — please check it.", "an eight-digit figure is questioned", JSON.stringify(r));
  expect400 = true;
  r = await typed("doctor_fees", "-500");
  check(r.err === "Amounts cannot be negative.", "a negative figure is refused", JSON.stringify(r));
  check(await page.$eval("#btn-next", e => e.disabled), "…and Save is greyed while it is there");
  if (INTEGRATION) {
    await waitCode(page, "L1-A");
    const neg = await rowFor(page, "L1-A");
    oneOf(neg.title, ["Negative amount"], "the server sends it back as a Must-fix row");
  } else {
    skip("(h) the 'Negative amount' row — this copy's server still answers 400 for a negative figure");
  }
  await page.waitForTimeout(400);
  expect400 = false;
  await snap(page, "h-bad-figures");
  // review §3.4 #4: Clear asks first, but only when there is something to lose.
  await page.click("#btn-clear");
  await page.waitForTimeout(300);
  const clearQ = tookDialog();
  check(clearQ !== null, "Clear asks before throwing away typed figures");
  if (clearQ) note("dialog: " + JSON.stringify(clearQ));
  await until(page, () => document.querySelector("#in-cash_sales").value === "");
  ok("…and clears them when the answer is yes");
  await page.click("#btn-clear");
  await page.waitForTimeout(400);
  check(tookDialog() === null, "Clear on an empty form asks nothing");

  /* ========================================================= (i) 9, 8 September
     A day entered out of order, then the gap filled. */
  head("(i) a day out of order, then the gap filled — " + pretty(D(-6)) + " before " + pretty(D(-7)));
  await setDate(page, D(-6));
  hint = await hintWhen(page, /hasn't been entered yet/);
  check(hint === "The day before this one hasn't been entered yet. This day will still be saved; " +
                 "its paperwork finishes as soon as that day is entered.",
        "the hint says what will happen, without the word ledger", hint);
  check(await page.$eval("#prior-hint", e => e.classList.contains("off")), "…and is marked as something to note");
  await setAmounts(page, [["opening_balance", "6870"], ["cash_sales", "98040"],
                          ["doctor_fees", "22400"], ["deposits", "75000"], ["closing_balance", "7870"]]);
  await waitCode(page, "L2-A");
  await waitCode(page, "L3-A");
  const gapRow = await rowFor(page, "L3-A");
  oneOf(gapRow.title, ["Ledger waiting on the day before", "Waiting on the day before"],
        "a missing day before is a Good to know");
  check((await rowFor(page, "L2-B")) === null, "there is nothing to check the opening balance against");
  check((await textOf(page, "#predicted")) ===
        "Predicted $7,510.00, counted $7,870.00 — $360.00 more than the figures account for.",
        "the day is over, not short", await textOf(page, "#predicted"));
  const outOfOrderTips = (await readRows(page)).filter(x => x.level === "4");
  check(outOfOrderTips.length >= 1, "a tip suggests what $360.00 might be");
  outOfOrderTips.forEach(tp => note(`tip: ${JSON.stringify(tp.title)} — ${JSON.stringify(tp.meta)}`));
  await snap(page, "i-out-of-order");
  await page.fill("#txt-reason", "$360 over, cannot locate");
  await until(page, () => !document.getElementById("btn-next").disabled);
  await page.click("#btn-next");
  await waitSaved(page, D(-5));
  b = await bannerNow(page);
  // review §3.4 #1: the words come from what the server DID, never from its log text.
  check(b.text.startsWith(`${pretty(D(-6))} saved to the books.`), "the save is confirmed", b.text);
  check(/paperwork finishes as soon as that day is entered/.test(b.text),
        "…and says the paperwork is waiting on the missing day", b.text);
  check(!/ledger|NOT been|HELD/i.test(b.text), "no log text reaches the banner", b.text);
  note("banner: " + JSON.stringify(b.text));

  await setDate(page, D(-7));
  await setAmounts(page, [["opening_balance", "5870"], ["cash_sales", "98400"],
                          ["doctor_fees", "22400"], ["deposits", "75000"], ["closing_balance", "6870"]]);
  await until(page, () => document.querySelectorAll("#checks-list li").length === 0);
  await page.click("#btn-next");
  await waitSaved(page, D(-6));
  b = await bannerNow(page);
  check(new RegExp(`The file for ${pretty(D(-6))} was finished too\\.`).test(b.text),
        "filling the gap says which day it finished", b.text);
  note("banner: " + JSON.stringify(b.text));

  /* ============================================================ (j) 9 September
     Editing a day that is already saved. */
  head("(j) editing a saved day, and the replace tick — " + pretty(D(-6)));
  await until(page, () => !document.getElementById("force-line").hidden);
  b = await bannerNow(page);
  check(b.text === `${pretty(D(-6))} is already saved. Saving again will replace it.`,
        "a date already in the books says so", b.text);
  check(b.action === "Edit that day", "…and offers to open it", b && b.action);
  check(b.kind === "warn", "…as something to be careful about", b && b.kind);
  const ledgerRow = await rowFor(page, "L3-B");
  oneOf(ledgerRow.title, ["Ledger already made for this day", "A file was already made for this day"],
        "the file already made for that day is mentioned");
  // review §3.4 #2: the tick was unanswerable.
  const tick = (await textOf(page, "#force-line")).replace(/\s+/g, " ");
  check(tick === "This day's file has already been made. Tick this to make it again with the corrected figures. " +
                 "(Only leave this unticked if the old file was already sent to the accountant.)",
        "the replace tick says what ticking it does, and when not to", JSON.stringify(tick));
  await snap(page, "j-already-saved");

  await page.click("#banner-area button");
  await until(page, () => /Editing/.test(document.getElementById("banner-area").textContent));
  check((await page.inputValue("#in-cash_sales")) === "98040.00", "the day comes back exactly as it was saved");
  check((await page.inputValue("#txt-reason")) === "$360 over, cannot locate", "reason and all");
  check(!(await page.$eval("#btn-cancel-edit", e => e.hidden)), "Cancel edit is offered");
  await snap(page, "j-editing");
  // review §3.2 #6: cancelling an edit used to jump to today.
  await page.click("#btn-cancel-edit");
  await page.waitForTimeout(700);
  check((await page.evaluate(() => document.getElementById("sel-day").value)) === String(Number(D(-6).split("-")[2])),
        "Cancel edit stays on the day that was being edited");
  await until(page, () => /is already saved/.test(document.getElementById("banner-area").textContent));
  ok("…and the standing banner comes back");

  await page.click("#banner-area button");
  await until(page, () => /Editing/.test(document.getElementById("banner-area").textContent));
  await setAmount(page, "cash_sales", "98400");
  await waitNoCode(page, "L2-A");
  check(await page.$eval("#reason-box", e => e.hidden), "correcting the figure takes the reason box away");
  check((await page.inputValue("#txt-reason")) === "", "…and clears the reason with it");
  check((await readRows(page)).filter(x => x.level === "4").length === 0, "the tip goes too");
  expect400 = true;                                  // nothing is refused here; the flag is just noise cover
  await page.click("#btn-next");                     // deliberately left unticked
  await waitSaved(page, D(-5));
  expect400 = false;
  b = await bannerNow(page);
  check(b.text.startsWith(`${pretty(D(-6))} saved to the books.`), "an edit saved unticked is confirmed", b.text);
  check(/The file for this day was left as it was\./.test(b.text),
        "…and says the file was left alone, in plain words", b.text);
  check(!/NOT been overwritten|daily ledger/i.test(b.text), "no log text in the banner", b.text);
  note("banner: " + JSON.stringify(b.text));
  if (INTEGRATION) {
    await setDate(page, D(-6));
    await waitCode(page, "L3-F");
    const stale = await rowFor(page, "L3-F");
    oneOf(stale.title, ["This day's file is out of date"], "the file left behind is reported as out of date");
  } else {
    skip("(j) the 'file is out of date' row after saving unticked — needs stream A/B");
  }

  await setDate(page, D(-6));
  await until(page, () => !document.getElementById("force-line").hidden);
  await page.click("#banner-area button");
  await until(page, () => /Editing/.test(document.getElementById("banner-area").textContent));
  await page.check("#chk-force");
  await page.click("#btn-next");
  await waitSaved(page, D(-5));
  b = await bannerNow(page);
  check(b.text.startsWith(`${pretty(D(-6))} saved to the books.`), "ticking it and saving replaces the file", b.text);
  check(!/left as it was/.test(b.text), "…and says nothing more than that", b.text);

  if (INTEGRATION) {
    skip("(j) the 'Now open … and save it again.' sentence needs an edit that changes a closing balance");
  } else {
    skip("(j) nextDayStale — the 'Now open … and save it again.' sentence needs stream B");
  }

  /* ========================================================= (l) a future date
     and saving today. */
  head("(l) a future date, and saving today");
  let checksSent = 0;
  const countChecks = (req) => { if (req.url().includes("/api/check")) checksSent++; };
  page.on("request", countChecks);
  await setDate(page, D(1));
  await page.waitForTimeout(900);
  check((await textOf(page, "#err-date")) === "That day has not happened yet.",
        "a day that has not happened is refused", await textOf(page, "#err-date"));
  check(await page.$eval("#btn-next", e => e.disabled), "…Save is greyed");
  check(checksSent === 0, "…and nothing is sent to the server for it", String(checksSent));
  page.off("request", countChecks);
  await snap(page, "l-future-date");

  await setDate(page, today);
  await setAmounts(page, [["opening_balance", "1000"], ["cash_sales", "100"], ["closing_balance", "1100"]]);
  await until(page, () => !document.getElementById("btn-next").disabled &&
                          document.getElementById("reason-box").hidden);
  await page.click("#btn-next");
  await until(page, () => /Today is saved/.test(document.getElementById("banner-area").textContent));
  b = await bannerNow(page);
  check(/^Today is saved\. There is no next day to enter yet\./.test(b.text),
        "saving today says why the form did not move on", b.text);
  // The check that follows the save says the date is now in the books, and the
  // banner adds what saving it again would do.
  await until(page, () => /Saving again will replace it/.test(document.getElementById("banner-area").textContent));
  b = await bannerNow(page);
  check(/Saving again will replace it\.$/.test(b.text), "…and that saving again replaces it", b.text);
  check(b.action === "Edit that day", "…and offers to open it", b && b.action);
  note("banner: " + JSON.stringify(b.text));
  await snap(page, "l-today-saved");

  /* ================================================== (m) an Off day with no
     day before it on record: refused, and not asked about first. */
  head("(m) an Off day whose day before is missing — " + pretty(D(-4)));
  await setDate(page, D(-4));
  await page.click("label.daytype-toggle");
  await until(page, () => document.getElementById("chk-closed").checked);
  await waitCode(page, "L1-F");
  const offStop = await rowFor(page, "L1-F");
  oneOf(offStop.title, ["Enter the day before first"], "an Off day in a gap is a Must fix");
  check(offStop.meta === "Must fix", "…shown as one", offStop.meta);
  check(offStop.field === "date", "…and points at the date", offStop.field);
  await snap(page, "m-off-day-stop");
  expect400 = true;
  await page.click("#btn-next");
  await until(page, () => /cannot be saved/.test(document.getElementById("banner-area").textContent));
  await page.waitForTimeout(300);
  expect400 = false;
  check(tookDialog() === null, "Save asks no Off-day question when the day is already refused");
  b = await bannerNow(page);
  check(b.text === "This day cannot be saved yet.", "the server's refusal is what is shown", b.text);
  check(!(await page.$eval("#dock-note", e => e.hidden)), "with the whole message in the dock");
  note("message: " + JSON.stringify(await textOf(page, "#dock-note .note-text")));
  // The row's field is the date, so clicking it goes to the date selects.
  await page.click("#checks-list li[data-code='L1-F'] .check-btn");
  await page.waitForTimeout(400);
  check(await page.evaluate(() => document.activeElement.id === "sel-day"),
        "clicking the row goes to the date", await page.evaluate(() => document.activeElement.id));
  // review §3.2 #10: Escape closes the explanation.
  await page.keyboard.press("Escape");
  await page.waitForTimeout(200);
  check(await page.$eval("#dock-note", e => e.hidden), "Escape closes the explanation in the dock");
  await noCodesOnScreen(page, "m");
  await nothingFloats(page, "m");
  await noSideScroll(page, "1440px");

  /* ===================================================== decision 7: the date
     changes, the figures stay, everything about the old date goes. */
  head("decision 7 — changing the date keeps the figures and nothing else");
  await page.click("label.daytype-toggle");                 // back to a work day
  await until(page, () => !document.getElementById("chk-closed").checked);
  await setDate(page, D(-3));
  await setAmounts(page, [["opening_balance", "8270"], ["cash_sales", "500"]]);
  expect400 = true;
  await page.click("#btn-next");                            // Save with the closing blank
  await until(page, () => !!document.querySelector("#checks-list li[data-code='L1-C']"));
  await page.waitForTimeout(300);
  expect400 = false;
  ok("Save pressed with a blank closing balance asks for it");
  await setDate(page, D(-2));
  await page.waitForTimeout(900);
  check((await page.inputValue("#in-cash_sales")) === "500.00", "the figures stay when the date changes");
  check((await rowFor(page, "L1-C")) === null,
        "…but the red row for a box nobody has touched on this date does not",
        JSON.stringify(await readRows(page)));
  b = await bannerNow(page);
  check(b === null || !/cannot be saved|saved to the books/.test(b.text),
        "…and the last save's message does not follow the person to another date", b && b.text);
  await snap(page, "date-change-keeps-figures");
  await page.click("#btn-clear");
  await page.waitForTimeout(300);
  tookDialog();
  await until(page, () => document.querySelector("#in-cash_sales").value === "");

  /* =================================================================== 390 px */
  head("390 px — the same form on a phone-sized window");
  const narrow = await ctx.newPage();
  watch(narrow, "390");
  let ndialog = null;
  narrow.on("dialog", (d) => { ndialog = d.message(); d.accept(); });
  await narrow.setViewportSize({ width: 390, height: 780 });
  await narrow.goto(BASE + "/index.html", { waitUntil: "networkidle" });

  // (b) at 390: an ordinary balanced day, on the day after the last one saved.
  await setDate(narrow, D(-5));
  await until(narrow, () => !document.getElementById("prior-hint").hidden);
  await setAmounts(narrow, [["opening_balance", "7870"], ["cash_sales", "98400"],
                            ["doctor_fees", "22400"], ["deposits", "75000"]]);
  await narrow.waitForTimeout(700);
  check((await shownText(narrow, "#predicted")) === null,
        "390: the prediction waits for the count here too");
  check(await narrow.$eval("#checks", e => getComputedStyle(e).display === "none"),
        "390: the Checks panel is out of the way until it is asked for");
  await noSideScroll(narrow, "390px, balanced day");
  await snap(narrow, "n-390-balanced");

  // (d) at 390: a difference, its reason box and the Checks sheet.
  await setAmount(narrow, "closing_balance", "9270");
  await waitCode(narrow, "L2-A");
  check(!(await narrow.$eval("#dock-status", e => e.hidden)), "390: the dock shows how many checks there are");
  check(/check/.test(await textOf(narrow, "#dock-status")), "…in words", await textOf(narrow, "#dock-status"));
  await narrow.click("#dock-status");
  await until(narrow, () => document.getElementById("checks").classList.contains("open"));
  check(await narrow.evaluate(() => {
    const dock = document.getElementById("dock").getBoundingClientRect();
    const checks = document.getElementById("checks").getBoundingClientRect();
    return checks.top >= dock.top;            // below the dock, in the page, covering nothing
  }), "390: the panel opens below the dock rather than over the form");
  await noSideScroll(narrow, "390px, checks open");
  await nothingFloats(narrow, "390px");
  await snap(narrow, "n-390-checks-open");
  await narrow.keyboard.press("Escape");
  await until(narrow, () => !document.getElementById("checks").classList.contains("open"));
  ok("390: Escape closes the panel");
  // The link lives in the panel, so the panel has to be open to use it.
  await narrow.click("#dock-status");
  await until(narrow, () => document.getElementById("checks").classList.contains("open"));
  await narrow.click("#checks-list li[data-code='L2-A'] .check-more");
  await until(narrow, () => !document.getElementById("dock-note").hidden);
  check(await narrow.evaluate(() => document.activeElement.id === "dock-note"),
        "390: the explanation takes the cursor, so it is read out");
  await snap(narrow, "n-390-explanation");
  await narrow.keyboard.press("Escape");
  await until(narrow, () => document.getElementById("dock-note").hidden);
  ok("390: Escape closes the explanation");
  await setAmount(narrow, "closing_balance", "8870");
  await until(narrow, () => document.getElementById("reason-box").hidden &&
                            !document.getElementById("btn-next").disabled);
  await narrow.click("#btn-next");
  await waitSaved(narrow, D(-4));
  ok(`390: ${pretty(D(-5))} saved`);

  // (j) at 390: the standing banner for a day already in the books.
  await setDate(narrow, D(-6));
  await until(narrow, () => /is already saved/.test(document.getElementById("banner-area").textContent));
  const nb = await bannerNow(narrow);
  check(nb.action === "Edit that day", "390: a saved day still offers to be opened", nb && nb.action);
  await noSideScroll(narrow, "390px, banner with a button");
  await snap(narrow, "n-390-already-saved");

  // (m) at 390: an Off day with the day before missing.
  await setDate(narrow, D(-2));
  await narrow.click("label.daytype-toggle");
  await until(narrow, () => document.getElementById("chk-closed").checked);
  await waitCode(narrow, "L1-F");
  expect400 = true;
  ndialog = null;
  await narrow.click("#btn-next");
  await until(narrow, () => /cannot be saved/.test(document.getElementById("banner-area").textContent));
  await narrow.waitForTimeout(300);
  expect400 = false;
  check(ndialog === null, "390: no Off-day question when the day is already refused");
  await noSideScroll(narrow, "390px, refusal");
  await noCodesOnScreen(narrow, "390px");
  await snap(narrow, "n-390-off-day-stop");
  await narrow.close();

  /* ============================================== flows that need stream B
     These three sentences come from fields this copy's server does not send
     yet (`nextDayStale`, `held`, `dailyLedger: "removed"`). The flows are
     written out here so the main session can run them after the merge with
     --integration; until then they are skipped, and they have never been run.
     They assume the books this script has just built: 31 August to 10
     September and today, with 11 to 14 September free. */
  head("flows that need stream B's new save fields");
  if (INTEGRATION) {
    /* nextDayStale: change a saved day's closing balance, and the day after it
       is left comparing its opening against a figure that has moved. */
    await setDate(page, D(-7));
    await until(page, () => /is already saved/.test(document.getElementById("banner-area").textContent));
    await page.click("#banner-area button");
    await until(page, () => /Editing/.test(document.getElementById("banner-area").textContent));
    await setAmount(page, "cash_sales", "98500");
    await setAmount(page, "closing_balance", "6970");
    await until(page, () => document.getElementById("reason-box").hidden);
    await page.check("#chk-force");
    await page.click("#btn-next");
    await until(page, () => /Now open/.test(document.getElementById("banner-area").textContent));
    b = await bannerNow(page);
    check(b.text.includes(`Now open ${pretty(D(-6))} and save it again.`),
          "changing a closing balance says which day to open next", b.text);
    check(b.action === "Edit that day", "…and offers to open it", b && b.action);
    await snap(page, "x-next-day-stale");

    /* held: a day saved into a gap is released when the gap is filled, but its
       overnight difference turns out to need a reason, so it waits again. */
    await setDate(page, D(-2));                       // a gap: the day before it is not on record
    await setAmounts(page, [["opening_balance", "1000"], ["closing_balance", "1000"]]);
    await until(page, () => !document.getElementById("btn-next").disabled);
    await page.click("#btn-next");
    await waitSaved(page, D(-1));
    await setDate(page, D(-3));                       // the missing day, closing at a different figure
    await setAmounts(page, [["opening_balance", "2000"], ["closing_balance", "2000"]]);
    await until(page, () => !document.getElementById("btn-next").disabled);
    await page.click("#btn-next");
    await until(page, () => /still needs a reason/.test(document.getElementById("banner-area").textContent));
    b = await bannerNow(page);
    check(b.text.includes(`${pretty(D(-2))} still needs a reason: open it and save it again.`),
          "a released day that does not balance says so", b.text);
    check(b.action === "Edit that day", "…and offers to open it", b && b.action);
    await snap(page, "x-held-for-a-reason");

    /* "removed": a work day saved again as an Off day has no file of its own. */
    await setDate(page, D(-5));
    await until(page, () => !document.getElementById("force-line").hidden);
    await page.click("label.daytype-toggle");
    await until(page, () => document.getElementById("chk-closed").checked);
    await page.click("#btn-next");
    await page.waitForTimeout(400);
    check(tookDialog() !== null, "the Off-day question is still asked when nothing is refused");
    await until(page, () => /was removed/.test(document.getElementById("banner-area").textContent));
    b = await bannerNow(page);
    check(b.text.includes("The file made when this was a work day was removed."),
          "the file made when it was a work day is reported as removed", b.text);
    await snap(page, "x-work-day-to-off-day");
  } else {
    skip("nextDayStale — \"Now open <date> and save it again.\" with Edit that day");
    skip("held — \"<date> still needs a reason: open it and save it again.\" with Edit that day");
    skip("dailyLedger \"removed\" — \"The file made when this was a work day was removed.\"");
  }

  /* ------------------------------------------------------------------------ */
  console.log("");
  check(errors.length === 0, "no console errors beyond the favicon", errors.join(" | "));

  await browser.close();
  console.log(`\n${fails === 0 ? "ALL PASS" : fails + " FAILED"}   (${skipped} skipped)`);
  process.exit(fails === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
