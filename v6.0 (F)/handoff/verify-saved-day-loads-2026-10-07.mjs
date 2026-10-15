/* verify-saved-day-loads-2026-10-07.mjs — browser verification of the owner's
   two requests of 2026-10-07: "For days that have already been saved ... just
   have the days load with their saved figures" (an Off day comes up switched
   to Off day), and "once they click clear, the 'show saved figures' link
   should then populate on the checks sidebar ... Tie it to a ctrl+alt+z
   shortcut." Plain JavaScript, no build step, same style as
   verify-date-change-2026-10-06.mjs.

   THE CONTRACT:
     1  Landing on a date (opening the page, picking a date in any list, Next
        day) shows that date as it is in the books. A saved Work day comes up
        with every figure and both reasons as saved, its reason boxes showing.
        A saved Off day comes up with the Off day switch on and every box blank
        and out of sight. A date that is not in the books is exactly what Clear
        leaves on it: every box empty, a Work day, both reason boxes hidden and
        empty, no grey note, no link, nothing under the buttons, no banner.
     2  The Checks panel says the day is saved: "Day saved, ledger generated"
        and the grey note #checks-regen for a day with a ledger; the grey note
        #checks-saved for a day whose ledger waits, and for an Off day. "Show
        saved figures" is never shown on landing.
     3  A saved day that came up can be left as it is: Save is green and Next
        day answers 200 and moves on.
     4  A saved Off day switched to a Work day has blank, unmarked boxes, no
        "... Not Entered" row before a box is left (the frozen timing), a grey
        Save and the opening hint. Leaving a box blank then shows its row.
     5  Next day goes to the top of the page. On a Work day (saved or not) the
        cursor is in the opening balance, put there by the page, so leaving it
        without typing is not "left blank". On an Off day no hidden box holds
        the cursor.
     6  Clear keeps the date and blanks the form. On a saved date, and only
        then, "Show saved figures" shows under the grey notes (not counted as a
        check). It, or Ctrl+Alt+Z (from inside a box after typing, and at 390
        px with the Checks sheet closed), brings the day back exactly, hides
        itself, goes to the top and puts the cursor in the opening balance (a
        Work day). Typing does not hide it; another date, Next day and a save
        do. A load that fails says why right under it and the link stays.
        Ctrl+Alt+Z with no link does nothing: no request, nothing typed, the
        key kept from the page.
     7  Nothing done while a date is being looked up is overwritten: a typed
        figure, another date, Clear, the Off day switch. Save (click or Ctrl+S)
        pressed meanwhile sends nothing and leaves no banner once things
        settle. Fast arrow keys on the day list end on the last day, as saved,
        with the focus still on the list. Two fast presses of the link load once.
        Next day pressed meanwhile is refused for the blank form it was sent
        with, and that refusal is never left showing beside the saved day that
        has come up since (this one FAILS on 2026-10-07: see below).
     8  A look-up that fails leaves the form blank and says "Could not look up
        <d Month yyyy>. <sentence>" in the Checks panel; the check still runs;
        the sentence goes on the next date change, on Clear and after a
        successful save.
     9  Saving an Off day or a day whose ledger waits is confirmed by the grey
        note alone on a wide window, and by "<date> saved to the books." under
        the buttons at 390 px, where the panel is hidden.
    10  No console or page errors.

   LETTERS in the labels (A..K) are the parts of the brief, each run at 1536 x
   900 (August 2026) and at 390 x 844 (June 2026):
     A a saved Work day with a ledger  B a saved day whose ledger waits
     C a saved Off day  D an unsaved date  E Next day landing  F opening the
     page on a saved today  G Clear and "Show saved figures"  H races
     I a failed look-up  J saving an Off day and a waiting day  K console
   The first run (on empty books) also checks the page opening blank on today
   before today is saved (F), and then saves today through the API.

   MUTATION PROOF:  MUTATE=1 serves the app.js of 2026-10-06 (before this
   change; OLD_APP names the copy) in place of public/app.js, through
   page.route. The real file is never edited. The auto-load checks (A, B, C,
   E, F) and the new link, Ctrl+Alt+Z, look-up and grey-note checks (G, H, I,
   J) must fail then, and D and K must not. On 2026-10-07: 437 checks, 280
   pass, 157 fail, no part stops early. At 1536: F 3, A 7, B 4, C 9, E 18,
   G 18, H 9, I 5, J 2 (75). At 390: F 3, A 7, B 4, C 9, E 18, G 26, H 9,
   I 5, J 1 (82; G has 8 more because at 390 the link is pressed with
   Ctrl+Alt+Z, which the old page does not know).

   HOW TO RUN (never against the real Records folder):
     1. A scratch server: LEDGER_ROOT=<scratch>, LDGR_NO_BROWSER=1,
        LDGR_NO_DIGEST=1, LDGR_NOTIFY_CONFIG=<a file that does not exist>,
        julia --startup-file=no server.jl <port>
     2. npm i playwright-core@1 in a scratch folder, copy this file there, then
        BASE=http://127.0.0.1:<port> LEDGER_ROOT=<the same scratch> OUT=<shots> \
          node verify-saved-day-loads-2026-10-07.mjs
        For the proof add MUTATE=1 OLD_APP=<app.js as it was on 2026-10-06>.
        WIDTHS=1536 or WIDTHS=390 runs one width only (default "1536,390").
     The script empties the books when it starts and refuses a path that
     mentions "Records". It saves today's date through the API (part F), so
     today is in those scratch books afterwards.

   COUNTS (2026-10-07, against the code of 2026-10-07): 437 checks, 220 at
   1536 and 217 at 390 (221 with WIDTHS=390 alone, which also checks the
   blank opening on today). 435 pass and 2 fail: the Next day race in H,
   once at each width. That is a suspected app bug, kept on purpose:
   onNextDay() lets go of its answer only when the DATE has changed, not when
   the form was started again (formSeq, as saveDay() does), so the refusal of
   the blank form lands after the saved day has come up and says "The figures
   on screen for <date> have not been saved." beside the saved figures. With
   no delay at all it happens every time a second Next day is pressed the
   moment the first one lands. Every other check passed at both widths, three
   runs in a row. */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE    = process.env.BASE || "http://127.0.0.1:8771";
const SHOTS   = path.resolve(process.env.OUT || "shots");
const MUTATE  = !!process.env.MUTATE;
const OLD_APP = process.env.OLD_APP ||
  "C:/Users/jorre/AppData/Local/Temp/claude/E--Ldgr/ba6ba167-8f5a-4f05-a078-d03460483249/scratchpad/pre-change/app.js";
const WIDTHS  = (process.env.WIDTHS || "1536,390").split(",").map((s) => s.trim());
const T       = MUTATE ? 6000 : 25000;         // how long a wait may take before it is a failure
const DELAY   = 800;                           // how long /api/day is held up in H
fs.mkdirSync(SHOTS, { recursive: true });

/* ---------------------------------------------------------------------- */
let pass = 0, fail = 0;
const failed = [];
const check = (cond, label, extra) => {
  if (cond) { pass++; console.log(`PASS  ${label}`); }
  else      { fail++; failed.push(label); console.log(`FAIL  ${label}${extra ? "  -- " + extra : ""}`); }
  return !!cond;
};
const eq = (got, want, label) => check(JSON.stringify(got) === JSON.stringify(want), label,
                                       `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
const section = async (name, fn) => {
  console.log(`\n--- ${name}`);
  try { await fn(); }
  catch (e) { check(false, `${name} · the section stopped early`, String((e && e.message) || e).split("\n")[0]); }
};

const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
const pretty = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${MONTHS[m - 1]} ${y}`; };
const getJSON = async (p) => (await fetch(BASE + p)).json();
const post = async (p, body) => {
  const r = await fetch(BASE + p, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  return { status: r.status, body: await r.json().catch(() => null) };
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function emptyBooks() {
  const root = process.env.LEDGER_ROOT;
  if (!root) { console.log("FAIL  LEDGER_ROOT must be set to the server's scratch folder"); process.exit(2); }
  if (/records/i.test(root)) { console.log("FAIL  refusing to empty a folder whose path mentions Records: " + root); process.exit(2); }
  for (const entry of fs.readdirSync(root)) fs.rmSync(path.join(root, entry), { recursive: true, force: true });
}

/* ---------------------------------------------------------------------- */
/* Words the page and the server use                                       */
/* ---------------------------------------------------------------------- */
const SAVED_TITLE = "Day saved, ledger generated";
const WAITING     = "Ledger waiting on the day before";
const CLOSED_ROW  = "Marked as closed";
const NOT_ENTERED = /Not Entered$/;
const LINK_WORDS  = "Show saved figures";
const SERVER_500  = "Something went wrong. Try again. If it keeps happening, contact the technician.";
const UNREACHABLE = "LDGR has stopped. Unsaved figures will need to be re-entered. Close this window and open LDGR again.";

/* ---------------------------------------------------------------------- */
/* Page helpers                                                            */
/* ---------------------------------------------------------------------- */
const value  = (page, sel) => page.$eval(sel, (e) => e.value).catch(() => null);
const bannerCount = (page) => page.$$eval("#banner-area .banner", (b) => b.length);
const dockSentence = (page) => page.$eval("#dock-msg", (e) => (e.hidden ? null : e.textContent.trim())).catch(() => null);
const loadMsg = (page) => page.$eval("#checks-load-msg", (e) => (e.hidden ? null : e.textContent.trim())).catch(() => null);
const rowTitles = (page) => page.$$eval("#checks-list li .check-title", (n) => n.map((x) => x.textContent.trim()));
const isClosed = (page) => page.$eval("#chk-closed", (e) => e.checked);
const saveGreen = (page) => page.$eval("#btn-save", (b) => !b.disabled);
const activeId = (page) => page.evaluate(() => document.activeElement && (document.activeElement.id || document.activeElement.tagName));
const scrollY = (page) => page.evaluate(() => window.scrollY);
const toBottom = (page) => page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
const atTop = (page) => page.waitForFunction(() => window.scrollY === 0, null, { timeout: 4000 }).then(() => true).catch(() => false);
const domOn = (page, sel) => page.$eval(sel, (e) => !e.hidden).catch(() => false);
const seen = (page, sel) => page.$eval(sel, (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
const shownDate = (page) => page.evaluate(() => {
  const v = (id) => document.getElementById(id).value;
  return `${v("sel-year")}-${String(v("sel-month")).padStart(2, "0")}-${String(v("sel-day")).padStart(2, "0")}`;
});
const untilRow = (page, test, on = true, ms = T) => page.waitForFunction(([src, v]) => {
  const re = new RegExp(src);
  return [...document.querySelectorAll("#checks-list .check-title")].some((n) => re.test(n.textContent.trim())) === v;
}, [test.source, on], { timeout: ms }).then(() => true).catch(() => false);
const activeInfo = (page) => page.evaluate(() => {
  const a = document.activeElement;
  const boxes = [...document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input")];
  return { id: a && (a.id || a.tagName), box: boxes.includes(a), body: a === document.body,
           onScreen: !!a && a.getClientRects().length > 0 };
});
const shot = (page, name) => page.screenshot({ path: path.join(SHOTS, name + ".png") }).catch(() => {});

/* Every /api request the page makes, so a step can wait for the page to fall
   quiet: no request in flight for a while, longer than the 350 ms re-check. */
function track(page) {
  const t = { inflight: 0, last: Date.now(), day: 0, save: 0, next: 0 };
  const api = (r) => r.url().includes("/api/");
  page.on("request", (r) => {
    if (!api(r)) return;
    t.inflight++; t.last = Date.now();
    const u = r.url();
    if (u.includes("/api/day")) t.day++;
    if (r.method() === "POST" && u.includes("/api/save")) t.save++;
    if (r.method() === "POST" && u.includes("/api/next")) t.next++;
  });
  const done = (r) => { if (api(r)) { t.inflight = Math.max(0, t.inflight - 1); t.last = Date.now(); } };
  page.on("requestfinished", done);
  page.on("requestfailed", done);
  return t;
}
async function settle(page, t, quiet = 500) {
  const since = Date.now();
  await sleep(120);
  while (Date.now() - since < T + 5000) {
    if (t.inflight === 0 && Date.now() - Math.max(t.last, since) >= quiet) { await sleep(60); if (t.inflight === 0) return true; }
    await sleep(40);
  }
  return false;
}

/* Pick a date through the lists, as a person does: only the lists that differ,
   each focused first. `go` also waits for the page to fall quiet. */
async function pick(page, iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const cur = await shownDate(page);
  if (cur === iso) return;
  const [cy, cm] = cur.split("-").map(Number);
  if (y !== cy) { await page.focus("#sel-year"); await page.selectOption("#sel-year", String(y)); }
  if (m !== cm) { await page.focus("#sel-month"); await page.selectOption("#sel-month", String(m)); }
  if (Number(await value(page, "#sel-day")) !== d) { await page.focus("#sel-day"); await page.selectOption("#sel-day", String(d)); }
}
const go = async (page, t, iso) => { await pick(page, iso); await settle(page, t); };

async function setAmount(page, key, v) {
  await page.fill("#in-" + key, v);
  await page.$eval("#in-" + key, (e) => e.blur());
}
async function clickSave(page, t) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/save") && r.request().method() === "POST", { timeout: T * 2 }),
    page.click("#btn-save"),
  ]);
  await settle(page, t);
  return { status: res.status(), body: await res.json().catch(() => null) };
}
async function nextDay(page, t) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: T * 2 }),
    page.click("#btn-next"),
  ]);
  await settle(page, t);
  return { status: res.status(), body: await res.json().catch(() => null) };
}
async function clickClear(page, t) { await page.click("#btn-clear"); if (t) await settle(page, t); }
// A real mouse press on Save, greyed out or not: Chrome reports the pointer
// going down on a disabled button, which is how the page answers it.
async function mouseOnSave(page) {
  const b = await page.$("#btn-save"); await b.scrollIntoViewIfNeeded();
  const bb = await b.boundingBox();
  const under = await page.evaluate(([x, y]) => { const e = document.elementFromPoint(x, y); return e && e.id; }, [bb.x + bb.width / 2, bb.y + bb.height / 2]);
  if (under !== "btn-save") throw new Error("the click would land on " + under);
  await page.mouse.click(bb.x + bb.width / 2, bb.y + bb.height / 2);
}

/* The form part of a blank day: what Clear leaves in the boxes. */
const formReport = (page) => page.evaluate(() => {
  const $ = (id) => document.getElementById(id);
  const ins = [...document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input")];
  return {
    nonBlank: ins.filter((i) => i.value !== "").map((i) => i.id),
    marked:   ins.filter((i) => i.classList.contains("invalid") || i.classList.contains("filled")).map((i) => i.id),
    errs:     document.querySelectorAll(".field .err.show").length,
    outlines: [...document.querySelectorAll("#view-entry .field[data-level]")].map((f) => f.dataset.key),
    reasonBoxes: [!$("opening-reason-box").hidden, !$("reason-box").hidden],
    reasonVals:  [$("txt-opening-reason").value, $("txt-reason").value],
    closed: $("chk-closed").checked,
    boxesShown: ins.length > 0 && ins.every((i) => i.getClientRects().length > 0),
    tick: $("chk-genesis").checked,
    totals: [$("tot-cash").textContent, $("tot-exp").textContent, $("tot-dep").textContent],
    predictedHidden: $("predicted").hidden,
  };
});
const formBlankOk = (b) => b.nonBlank.length === 0 && b.marked.length === 0 && b.errs === 0 && b.outlines.length === 0 &&
  !b.reasonBoxes[0] && !b.reasonBoxes[1] && b.reasonVals.every((v) => v === "") && !b.closed && b.boxesShown && !b.tick &&
  b.totals.every((x) => x === "$0.00") && b.predictedHidden;
/* The rest of the page around a blank day: nothing said anywhere. */
const quietReport = (page) => page.evaluate(() => {
  const $ = (id) => document.getElementById(id);
  return {
    regen: !$("checks-regen").hidden, saved: !$("checks-saved").hidden, link: !$("checks-load").hidden,
    loadMsg: !$("checks-load-msg").hidden, dockMsg: !$("dock-msg").hidden, dockNote: !$("dock-note").hidden,
    banners: document.querySelectorAll("#banner-area .banner").length, sheet: $("checks").classList.contains("open"),
  };
});
const quietOk = (q) => !q.regen && !q.saved && !q.link && !q.loadMsg && !q.dockMsg && !q.dockNote && q.banners === 0 && !q.sheet;

/* Everything a person can see, for "exactly what Clear gives". The focus is
   left out: Clear is a button, and pressing it puts the cursor on it. */
const snap = (page) => page.evaluate(() => {
  const $ = (id) => document.getElementById(id);
  const ins = [...document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input")];
  const vis = (e) => !e.hidden;
  return {
    date: [$("sel-year").value, $("sel-month").value, $("sel-day").value].join("-"),
    values: ins.map((i) => i.id + "=" + i.value + (i.classList.contains("invalid") ? "!" : "") + (i.classList.contains("filled") ? "+" : "")),
    errs: [...document.querySelectorAll(".field .err.show")].map((e) => e.id),
    outlines: [...document.querySelectorAll("#view-entry .field[data-level]")].map((f) => f.dataset.key + ":" + f.dataset.level),
    reasons: [vis($("opening-reason-box")), vis($("reason-box")), $("txt-opening-reason").value, $("txt-reason").value],
    closed: $("chk-closed").checked, isClosed: $("view-entry").classList.contains("is-closed"), closedNote: $("closed-note").textContent,
    genesis: [vis($("genesis-line")), $("chk-genesis").checked, $("chk-genesis").disabled],
    totals: [$("tot-cash").textContent, $("tot-exp").textContent, $("tot-dep").textContent],
    predicted: vis($("predicted")) ? $("predicted").textContent : null,
    prior: vis($("prior-hint")) ? $("prior-hint").textContent : null,
    errDate: $("err-date").textContent,
    rows: [...document.querySelectorAll("#checks-list .check-title")].map((n) => n.textContent.trim()),
    count: vis($("checks-count")) ? $("checks-count").textContent : null,
    empty: vis($("checks-empty")),
    notes: [vis($("checks-regen")), vis($("checks-saved")), vis($("checks-load"))],
    loadMsg: vis($("checks-load-msg")) ? $("checks-load-msg").textContent : null,
    dockMsg: vis($("dock-msg")) ? $("dock-msg").textContent : null,
    dockNote: vis($("dock-note")), pill: vis($("dock-status")) ? $("dock-status").textContent : null,
    banners: [...document.querySelectorAll("#banner-area .banner")].map((b) => b.textContent),
    buttons: [$("btn-save").disabled, $("btn-next").disabled], sheet: $("checks").classList.contains("open"),
  };
});

const formValues = (page) => page.evaluate(() => Object.fromEntries(
  [...document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input")].map((i) => [i.dataset.key, i.value])));
const reasonState = (page) => page.evaluate(() => ({
  openingShown: !document.getElementById("opening-reason-box").hidden, dayShown: !document.getElementById("reason-box").hidden,
  opening: document.getElementById("txt-opening-reason").value, day: document.getElementById("txt-reason").value,
}));
// Ctrl+Alt+Z as the page passes it on: a listener on window, after the page's
// own on document, records whether the key was kept from the page.
const zProbe = () => {
  if (window.__zProbe) return;
  window.__zProbe = [];
  window.addEventListener("keydown", (e) => { if (e.code === "KeyZ") window.__zProbe.push(e.defaultPrevented); });
};

/* ---------------------------------------------------------------------- */
async function main() {
  emptyBooks();
  if (MUTATE && !fs.existsSync(OLD_APP)) { console.log("FAIL  MUTATE=1 needs OLD_APP, the app.js of 2026-10-06: " + OLD_APP); process.exit(2); }
  const cfg = await getJSON("/api/config");
  const today = cfg.today;
  const OPEN = cfg.openingKey, CLOSE = cfg.closingKey;
  const ALL = cfg.groups.flatMap((g) => g.categories.map((c) => c.key));
  console.log(`today=${today}  base=${BASE}  mutate=${MUTATE}  widths=${WIDTHS.join(",")}  shots=${SHOTS}`);

  // The days every run saves through the API, in its own month.
  const DAY1 = { [OPEN]: 1000, cash_sales: 500, deposits: 300, [CLOSE]: 1200 };
  const DAY2 = { [OPEN]: 1250, cash_sales: 400, POS_Scotia: 150, POS_RBL: 75.5, doctor_fees: 100,
                 medical_supply_costs: 30, taxi_fare: 20, deposits: 200, [CLOSE]: 1350 };       // predicts 1,300: 50 over
  const WHY2 = { openingReason: "Found 50 in the safe", reason: "Extra change from a patient" };
  const DAY5 = { [OPEN]: 1600, cash_sales: 200, [CLOSE]: 1800 };
  const DAY6 = { [OPEN]: 1800, [CLOSE]: 1800 };
  const DAY6B = { [OPEN]: 1800, cash_sales: 100, [CLOSE]: 1900 };
  const TODAY = { [OPEN]: 2000, cash_sales: 300, taxi_fare: 50, [CLOSE]: 2250 };
  const amountsOf = (figs) => Object.fromEntries(ALL.map((k) => [k, figs[k] === undefined ? 0 : figs[k]]));
  const seedWork = (iso, figs, why = {}, genesis = false) => post("/api/save", {
    date: iso, amounts: amountsOf(figs), reason: why.reason || "", openingReason: why.openingReason || "",
    allowGenesis: genesis, force: true });
  const seedOff = (iso) => post("/api/save", { date: iso, status: "closed", force: true });
  // What the boxes show for a saved Work day: a drawer count always with two
  // decimals, any other figure blank when it is 0.
  const shownValues = (figs) => Object.fromEntries(ALL.map((k) => {
    const v = figs[k];
    if (k === OPEN || k === CLOSE) return [k, v === undefined || v === null ? "" : Number(v).toFixed(2)];
    return [k, v ? Number(v).toFixed(2) : ""];
  }));

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    for (const w of WIDTHS) {
      const W = w === "390"
        ? { tag: "390",  viewport: { width: 390,  height: 844 }, dsf: 2,    wide: false, ym: "2026-06" }
        : { tag: "1536", viewport: { width: 1536, height: 900 }, dsf: 1.25, wide: true,  ym: "2026-08" };
      await runWidth(W);
    }
  } finally {
    await browser.close();
  }

  /* ==================================================================== */
  async function runWidth(W) {
    const tag = W.tag;
    const D = (n) => `${W.ym}-${String(n).padStart(2, "0")}`;
    const L = (part, words) => `${tag} ${part} · ${words}`;
    // Something in the Checks panel is on: seen on screen on a wide window; at
    // 390 the panel is a closed sheet, so its DOM state is what can be read.
    const panelOn = (page, sel) => (W.wide ? seen(page, sel) : domOn(page, sel));
    const linkOn = (page) => panelOn(page, "#checks-load");

    /* ---- set-up -------------------------------------------------------- */
    console.log(`\n=== ${tag} x ${W.viewport.height}, ${W.ym}`);
    eq((await seedWork(D(1), DAY1, {}, true)).status, 200, L("set-up", `${pretty(D(1))} is the first day on record, closing 1,200`));
    eq((await seedWork(D(2), DAY2, WHY2)).status, 200, L("set-up", `${pretty(D(2))} opens 1,250 and closes 50 over, with both reasons`));
    eq((await seedOff(D(3))).status, 200, L("set-up", `${pretty(D(3))} is an Off day`));
    eq((await seedWork(D(5), DAY5)).status, 200, L("set-up", `${pretty(D(5))} is saved with ${pretty(D(4))} missing, so its ledger waits`));
    eq((await seedWork(D(6), DAY6)).status, 200, L("set-up", `${pretty(D(6))} is saved after it`));
    const day2 = (await getJSON("/api/day?date=" + D(2))).day;
    check(!!day2 && day2.openingReason === WHY2.openingReason && day2.reason === WHY2.reason,
          L("set-up", "GET /api/day holds both reasons"), JSON.stringify(day2 && [day2.openingReason, day2.reason]));
    const todaySaved = !!(await getJSON("/api/day?date=" + today)).day;

    const ctx = await browser.newContext({ viewport: W.viewport, deviceScaleFactor: W.dsf, acceptDownloads: false });
    if (MUTATE) {
      const old = fs.readFileSync(OLD_APP, "utf8");
      await ctx.route("**/app.js*", (route) => route.fulfill({ status: 200, contentType: "application/javascript; charset=utf-8", body: old }));
    }
    const page = await ctx.newPage();
    page.setDefaultTimeout(T);
    const t = track(page);
    const errors = [];
    // A refused Next day answers 409 on purpose, and /api/day fails on purpose
    // in G and I; Chrome logs each as a console error.
    const noise = (s) => /favicon/i.test(s) || /api\/day/.test(s) || (/api\/next/.test(s) && /\b409\b/.test(s));
    page.on("console", (m) => {
      if (m.type() !== "error") return;
      const line = `${m.text()} [${(m.location() && m.location().url) || ""}]`;
      if (!noise(line)) errors.push(line);
    });
    page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
    page.on("dialog", (d) => d.accept());
    await page.goto(BASE);
    await page.waitForSelector("#in-" + OPEN);
    await settle(page, t);

    // Shared assertions
    const assertWorkDay = async (figs, why, label) => {
      const got = await formValues(page), want = shownValues(figs);
      const bad = Object.keys(want).filter((k) => got[k] !== want[k]).map((k) => `${k}: ${JSON.stringify(got[k])} vs ${JSON.stringify(want[k])}`);
      check(bad.length === 0, `${label}: every box holds the saved figure`, bad.join("; "));
      const r = await reasonState(page);
      eq([await isClosed(page), r.opening, r.day], [false, why.openingReason || "", why.reason || ""],
         `${label}: a Work day, with both reasons as saved`);
    };
    const assertFormBlank = async (label) => {
      const b = await formReport(page);
      check(formBlankOk(b), `${label}: a blank Work day form (every box empty and unmarked, reason boxes hidden and empty, totals $0.00)`, JSON.stringify(b));
    };
    const assertBlankDay = async (label) => {
      await assertFormBlank(label);
      const q = await quietReport(page);
      check(quietOk(q), `${label}: no grey note, no link, nothing under the buttons or the notes, no banner, no open explanation`, JSON.stringify(q));
    };
    const pressLink = async (how) => {
      if (how === "key") { await page.keyboard.press("Control+Alt+KeyZ"); return true; }
      if (!W.wide) {
        // At 390 the link is in the Checks sheet, opened by the pill.
        if (!(await seen(page, "#dock-status"))) return check(false, L("G", "the pill that opens the Checks sheet is showing"));
        if (!(await page.$eval("#checks", (e) => e.classList.contains("open")))) await page.click("#dock-status");
      }
      if (!(await seen(page, "#checks-load"))) return check(false, L("G", "the link can be pressed (it is on screen)"));
      await page.click("#checks-load");
      return true;
    };

    /* ---- F · opening the page on a saved today ---------------------------- */
    await section(L("F", "opening the page"), async () => {
      if (!todaySaved) {
        eq(await shownDate(page), today, L("F", "the page opens on today"));
        await assertBlankDay(L("F", "today is not in the books yet, so the page opens blank"));
        eq((await seedWork(today, TODAY)).status, 200, L("F", "today is saved through the API (its day before is missing, so its ledger waits)"));
        await page.reload();
        await page.waitForSelector("#in-" + OPEN);
        await settle(page, t);
      }
      eq(await shownDate(page), today, L("F", "the page opens on today"));
      await assertWorkDay(TODAY, {}, L("F", "today is already saved, so the page opens with it"));
      check(await panelOn(page, "#checks-saved"), L("F", "the grey note says the day has been saved"));
      eq(await linkOn(page), false, L("F", "no \"Show saved figures\" link"));
      eq(await saveGreen(page), true, L("F", "Save is green"));
      await shot(page, `${tag}-F-today-saved`);
    });

    /* ---- A · a saved Work day with a ledger ------------------------------- */
    await section(L("A", "a saved Work day with a ledger"), async () => {
      await go(page, t, D(10));
      await go(page, t, D(2));
      eq(await shownDate(page), D(2), L("A", `the date on screen is ${pretty(D(2))}`));
      await assertWorkDay(DAY2, WHY2, L("A", `picking ${pretty(D(2))}`));
      const r = await reasonState(page);
      check(r.openingShown && r.dayShown, L("A", "both reason boxes are showing beside their figures"), JSON.stringify(r));
      const rows = await rowTitles(page);
      check(rows.includes(SAVED_TITLE), L("A", `the Checks list says "${SAVED_TITLE}"`), JSON.stringify(rows));
      check(await panelOn(page, "#checks-regen"), L("A", "the grey note about regenerating the ledger shows"));
      eq(await panelOn(page, "#checks-saved"), false, L("A", "the other grey note does not"));
      eq(await linkOn(page), false, L("A", "no \"Show saved figures\" link"));
      eq(await saveGreen(page), true, L("A", "Save is green"));
      eq([await bannerCount(page), await dockSentence(page), await loadMsg(page)], [0, null, null],
         L("A", "no banner, nothing under the buttons, nothing under the notes"));
      await shot(page, `${tag}-A-saved-work-day`);
      const n = await nextDay(page, t);
      eq(n.status, 200, L("A", "Next day answers 200 for the day as it came up"));
      eq(await shownDate(page), D(3), L("A", "and moves on to the day after"));
    });

    /* ---- B · a saved Work day whose ledger waits -------------------------- */
    await section(L("B", "a saved day whose ledger waits"), async () => {
      await go(page, t, D(10));
      await go(page, t, D(5));
      await assertWorkDay(DAY5, {}, L("B", `picking ${pretty(D(5))}`));
      check(await panelOn(page, "#checks-saved"), L("B", "the grey note \"This day has been saved.\" shows"));
      eq(await panelOn(page, "#checks-regen"), false, L("B", "the ledger note does not"));
      eq(await linkOn(page), false, L("B", "no \"Show saved figures\" link"));
      check((await rowTitles(page)).includes(WAITING), L("B", `the Checks list says "${WAITING}"`), JSON.stringify(await rowTitles(page)));
      eq(await saveGreen(page), true, L("B", "Save is green"));
    });

    /* ---- C · a saved Off day ------------------------------------------------ */
    await section(L("C", "a saved Off day"), async () => {
      await go(page, t, D(10));
      await go(page, t, D(3));
      eq(await isClosed(page), true, L("C", `picking ${pretty(D(3))}: the Off day switch is on`));
      const cards = await page.evaluate(() => ["card-figures", "card-evening"].map((id) => document.getElementById(id).getClientRects().length > 0)
        .concat([...document.querySelectorAll("#slot-opening input")].map((i) => i.getClientRects().length > 0)));
      eq(cards, [false, false, false], L("C", "the figure cards and the opening balance are out of sight"));
      const v = await formValues(page);
      eq(Object.values(v).filter((x) => x !== ""), [], L("C", "every box is blank (an Off day's balances were carried, not counted)"));
      check(await panelOn(page, "#checks-saved"), L("C", "the grey note \"This day has been saved.\" shows"));
      eq(await panelOn(page, "#checks-regen"), false, L("C", "the ledger note does not"));
      check((await rowTitles(page)).includes(CLOSED_ROW), L("C", `the Checks list says "${CLOSED_ROW}"`), JSON.stringify(await rowTitles(page)));
      eq(await saveGreen(page), true, L("C", "Save is green"));
      eq(await linkOn(page), false, L("C", "no \"Show saved figures\" link"));
      await shot(page, `${tag}-C-saved-off-day`);

      await page.click("label.daytype-toggle");
      await settle(page, t);
      eq(await isClosed(page), false, L("C", "switched to a Work day"));
      await assertFormBlank(L("C", "after the switch"));
      check(!(await rowTitles(page)).some((x) => NOT_ENTERED.test(x)), L("C", "no \"... Not Entered\" row before a box is left (the frozen timing)"), JSON.stringify(await rowTitles(page)));
      eq(await saveGreen(page), false, L("C", "Save is grey"));
      const hint = await page.$eval("#prior-hint", (e) => (e.hidden ? null : e.textContent)).catch(() => null);
      check(!!hint && hint.includes("closed with $1,350.00"), L("C", "the opening hint names the last close"), JSON.stringify(hint));
      await page.focus("#in-" + OPEN);
      await page.keyboard.press("Tab");
      check(await untilRow(page, /^Opening Balance Not Entered$/), L("C", "leaving the opening balance blank then shows its row, as on any day"), JSON.stringify(await rowTitles(page)));
    });

    /* ---- D · an unsaved date -------------------------------------------------- */
    await section(L("D", "an unsaved date"), async () => {
      await go(page, t, D(2));
      await go(page, t, D(10));
      await assertBlankDay(L("D", `${pretty(D(10))} after a saved day with figures and reasons`));
      eq(await linkOn(page), false, L("D", "no link"));
      let a = await snap(page);
      await clickClear(page, t);
      let b = await snap(page);
      eq(a, b, L("D", "it is exactly what Clear gives on that date"));
      await go(page, t, D(3));
      await go(page, t, D(4));
      await assertBlankDay(L("D", `${pretty(D(4))} (the gap) after the saved Off day`));
      a = await snap(page);
      await clickClear(page, t);
      b = await snap(page);
      eq(a, b, L("D", "it is exactly what Clear gives there too"));
    });

    /* ---- E · Next day landing ---------------------------------------------------- */
    await section(L("E", "Next day landing"), async () => {
      await go(page, t, D(1));
      await assertWorkDay(DAY1, {}, L("E", `${pretty(D(1))} as it came up`));
      // on a saved Work day
      await toBottom(page);
      check((await scrollY(page)) > 0, L("E", "the page is scrolled down before Next day"));
      let n = await nextDay(page, t);
      eq([n.status, await shownDate(page)], [200, D(2)], L("E", `Next day lands on ${pretty(D(2))}`));
      check(await atTop(page), L("E", "the page is back at the top"), String(await scrollY(page)));
      eq(await activeId(page), "in-" + OPEN, L("E", "the cursor is in the opening balance"));
      await assertWorkDay(DAY2, WHY2, L("E", `${pretty(D(2))} reached by Next day`));
      eq(await linkOn(page), false, L("E", "no link"));
      // on a saved Off day
      await toBottom(page);
      n = await nextDay(page, t);
      eq([n.status, await shownDate(page)], [200, D(3)], L("E", `Next day lands on ${pretty(D(3))}`));
      check(await atTop(page), L("E", "the page is back at the top"), String(await scrollY(page)));
      eq(await isClosed(page), true, L("E", "the Off day comes up switched on"));
      const a = await activeInfo(page);
      check(!a.box && (a.body || a.onScreen), L("E", "no hidden box holds the cursor"), JSON.stringify(a));
      // on an unsaved date
      await toBottom(page);
      n = await nextDay(page, t);
      eq([n.status, await shownDate(page)], [200, D(4)], L("E", `Next day from the Off day lands on ${pretty(D(4))}`));
      check(await atTop(page), L("E", "the page is back at the top"), String(await scrollY(page)));
      eq(await activeId(page), "in-" + OPEN, L("E", "the cursor is in the opening balance"));
      await assertBlankDay(L("E", `${pretty(D(4))} (not saved)`));
      await page.keyboard.press("Tab");
      await settle(page, t);
      check(!(await rowTitles(page)).some((x) => NOT_ENTERED.test(x)),
            L("E", "Tab out of the opening balance the page put the cursor in: no \"Not Entered\" row"), JSON.stringify(await rowTitles(page)));
      // the Off day reached by Next day, switched to a Work day
      await go(page, t, D(2));
      n = await nextDay(page, t);
      eq([n.status, await shownDate(page), await isClosed(page)], [200, D(3), true], L("E", `Next day from ${pretty(D(2))} again: the Off day`));
      await page.click("label.daytype-toggle");
      await settle(page, t);
      eq(await isClosed(page), false, L("E", "switched to a Work day"));
      await assertFormBlank(L("E", "after the switch"));
      check(!(await rowTitles(page)).some((x) => NOT_ENTERED.test(x)), L("E", "no early blank-count row (the box hidden by the Off day was not visited)"), JSON.stringify(await rowTitles(page)));
      eq(await saveGreen(page), false, L("E", "Save is grey"));
    });

    /* ---- G · Clear and "Show saved figures" ----------------------------------------- */
    await section(L("G", "Clear and Show saved figures"), async () => {
      await page.evaluate(zProbe);
      // an unsaved date
      await go(page, t, D(10));
      await clickClear(page, t);
      eq(await domOn(page, "#checks-load"), false, L("G", "Clear on an unsaved date: no link"));
      let days = t.day;
      await page.keyboard.press("Control+Alt+KeyZ");
      await settle(page, t);
      eq(t.day, days, L("G", "Ctrl+Alt+Z there asks nothing of the server"));
      await assertBlankDay(L("G", "and changes nothing"));

      // a saved Work day with a ledger, by the link
      await go(page, t, D(2));
      await toBottom(page);
      await clickClear(page, t);
      eq(await shownDate(page), D(2), L("G", "Clear on a saved Work day keeps the date"));
      await assertFormBlank(L("G", `${pretty(D(2))} after Clear`));
      check(await linkOn(page), L("G", "\"Show saved figures\" shows"));
      const attrs = await page.$eval("#checks-load", (e) => [e.textContent.trim(), e.title, e.getAttribute("aria-keyshortcuts"), e.tagName]);
      eq(attrs, [LINK_WORDS, "Show saved figures (Ctrl+Alt+Z)", "Control+Alt+Z", "BUTTON"], L("G", "its words, its tooltip naming Ctrl+Alt+Z, and aria-keyshortcuts"));
      check(await panelOn(page, "#checks-regen"), L("G", "with the ledger note above it"));
      eq(await panelOn(page, "#checks-saved"), false, L("G", "and not the other note"));
      const cnt = await page.evaluate(() => {
        const c = document.getElementById("checks-count");
        return { count: c.hidden ? null : c.textContent, rows: document.querySelectorAll("#checks-list li").length,
                 inList: document.getElementById("checks-list").contains(document.getElementById("checks-load")),
                 titles: [...document.querySelectorAll("#checks-list .check-title")].map((n) => n.textContent.trim()) };
      });
      check(cnt.titles.includes(SAVED_TITLE) && cnt.count === String(cnt.rows) && !cnt.inList,
            L("G", "the link is not a check and is not counted (the count is the rows alone)"), JSON.stringify(cnt));
      eq(await saveGreen(page), false, L("G", "Save is grey on the blank form"));
      await shot(page, `${tag}-G-link-after-clear`);
      await toBottom(page);
      check((await scrollY(page)) > 0, L("G", "the page is scrolled down before the press"));
      if (await pressLink("click")) await settle(page, t);
      await assertWorkDay(DAY2, WHY2, L("G", "pressing the link brings the day back"));
      eq(await domOn(page, "#checks-load"), false, L("G", "and hides the link"));
      check(await atTop(page), L("G", "the page goes to the top"), String(await scrollY(page)));
      eq(await activeId(page), "in-" + OPEN, L("G", "with the cursor in the opening balance"));
      eq(await saveGreen(page), true, L("G", "Save is green again"));

      // a saved day whose ledger waits, by Ctrl+Alt+Z
      await go(page, t, D(5));
      await clickClear(page, t);
      await assertFormBlank(L("G", `${pretty(D(5))} after Clear`));
      check(await linkOn(page), L("G", "the link shows for the day whose ledger waits"));
      check(await panelOn(page, "#checks-saved"), L("G", "with the grey note \"This day has been saved.\""));
      eq(await panelOn(page, "#checks-regen"), false, L("G", "and not the ledger note"));
      eq(await page.evaluate(() => [document.getElementById("checks-count").hidden, document.querySelectorAll("#checks-list li").length]), [true, 0],
         L("G", "no rows, and the count stays hidden: the link is not counted as a check"));
      if (!W.wide) eq(await page.$eval("#checks", (e) => e.classList.contains("open")), false, L("G", "the Checks sheet is closed (390 px)"));
      await toBottom(page);
      await page.keyboard.press("Control+Alt+KeyZ");
      await settle(page, t);
      await assertWorkDay(DAY5, {}, L("G", "Ctrl+Alt+Z brings the day back"));
      eq(await domOn(page, "#checks-load"), false, L("G", "and hides the link"));
      check(await atTop(page), L("G", "the page goes to the top"), String(await scrollY(page)));
      eq(await activeId(page), "in-" + OPEN, L("G", "with the cursor in the opening balance"));

      // a saved Off day
      await go(page, t, D(3));
      eq(await isClosed(page), true, L("G", `${pretty(D(3))} comes up as an Off day`));
      await clickClear(page, t);
      eq(await shownDate(page), D(3), L("G", "Clear on the Off day keeps the date"));
      await assertFormBlank(L("G", "Clear on the Off day gives a Work day form"));
      check(await linkOn(page), L("G", "the link shows for the saved Off day"));
      check(await panelOn(page, "#checks-saved"), L("G", "with the grey note \"This day has been saved.\""));
      eq(await panelOn(page, "#checks-regen"), false, L("G", "and not the ledger note (an Off day has no ledger)"));
      if (await pressLink(W.wide ? "click" : "key")) await settle(page, t);
      eq(await isClosed(page), true, L("G", "the link brings the Off day back, switched on"));
      eq(await domOn(page, "#checks-load"), false, L("G", "and hides itself"));
      const ai = await activeInfo(page);
      check(!ai.box, L("G", "no hidden box holds the cursor"), JSON.stringify(ai));
      check((await rowTitles(page)).includes(CLOSED_ROW), L("G", `"${CLOSED_ROW}" is back in the list`), JSON.stringify(await rowTitles(page)));

      // Ctrl+Alt+Z from inside a box, after typing
      await go(page, t, D(2));
      await clickClear(page, t);
      await page.click("#in-cash_sales");
      await page.keyboard.type("77");
      await settle(page, t);
      check(await linkOn(page), L("G", "typing after Clear does not hide the link"));
      eq([await activeId(page), await value(page, "#in-cash_sales")], ["in-cash_sales", "77"], L("G", "the cursor is still in the box with 77 typed"));
      await page.keyboard.press("Control+Alt+KeyZ");
      await settle(page, t);
      await assertWorkDay(DAY2, WHY2, L("G", "Ctrl+Alt+Z from inside the box: the typed 77 is replaced by the saved day"));
      eq(await domOn(page, "#checks-load"), false, L("G", "and the link is gone"));

      // Ctrl+Alt+Z with no link
      await page.click("#in-cash_sales");
      days = t.day;
      const z0 = await page.evaluate(() => window.__zProbe.length);
      await page.keyboard.press("Control+Alt+KeyZ");
      await settle(page, t);
      eq(t.day, days, L("G", "Ctrl+Alt+Z with no link asks nothing of the server"));
      eq([await activeId(page), await value(page, "#in-cash_sales")], ["in-cash_sales", "400.00"], L("G", "the cursor stays in the box, and nothing is typed into it"));
      eq(await page.evaluate((n) => window.__zProbe.slice(n), z0), [true], L("G", "the key is kept from the page (preventDefault), as the other shortcuts are"));

      // another date after Clear
      await clickClear(page, t);
      check(await linkOn(page), L("G", `the link shows again after Clear on ${pretty(D(2))}`));
      await go(page, t, D(1));
      eq(await domOn(page, "#checks-load"), false, L("G", "picking another date takes it away"));
      await assertWorkDay(DAY1, {}, L("G", `and ${pretty(D(1))} comes up as saved`));
      await go(page, t, D(2));
      eq(await domOn(page, "#checks-load"), false, L("G", "coming back to the cleared date: no link"));
      await assertWorkDay(DAY2, WHY2, L("G", "it comes up as saved"));

      // Next day after Clear
      await go(page, t, D(1));
      await clickClear(page, t);
      check(await linkOn(page), L("G", `the link shows after Clear on ${pretty(D(1))}`));
      let n = await nextDay(page, t);
      eq([n.status, await shownDate(page)], [409, D(1)], L("G", "Next day on the cleared form is refused (it is not what was saved) and the date stays"));
      eq(await dockSentence(page), `The figures on screen for ${pretty(D(1))} have not been saved. Save them before moving on.`,
         L("G", "the refusal is said under the buttons"));
      check(await linkOn(page), L("G", "the link stays beside it: the date did not change"));
      for (const [k, v] of Object.entries(DAY1)) await setAmount(page, k, String(v));
      await settle(page, t);
      n = await nextDay(page, t);
      eq([n.status, await shownDate(page)], [200, D(2)], L("G", "with the saved figures typed back by hand, Next day moves on"));
      eq(await domOn(page, "#checks-load"), false, L("G", "Next day takes the link away"));
      await assertWorkDay(DAY2, WHY2, L("G", `${pretty(D(2))} comes up as saved`));

      // saving new figures after Clear
      await go(page, t, D(6));
      await clickClear(page, t);
      check(await linkOn(page), L("G", `the link shows after Clear on ${pretty(D(6))}`));
      for (const [k, v] of Object.entries(DAY6B)) await setAmount(page, k, String(v));
      await settle(page, t);
      eq(await saveGreen(page), true, L("G", "new balanced figures typed: Save is green"));
      const s = await clickSave(page, t);
      eq(s.status, 200, L("G", "the new figures are saved"));
      eq(await domOn(page, "#checks-load"), false, L("G", "saving takes the link away"));
      const d6 = (await getJSON("/api/day?date=" + D(6))).day;
      eq(d6 && d6.amounts[CLOSE], 1900, L("G", "and the books hold the new closing balance"));

      // a load that fails, and one that finds nothing
      await go(page, t, D(2));
      await clickClear(page, t);
      const how = W.wide ? "click" : "key";
      const failing = async (handler) => {
        await page.route("**/api/day**", handler);
        try { if (await pressLink(how)) await settle(page, t); }
        finally { await page.unroute("**/api/day**"); }
      };
      await failing((r) => r.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ ok: false, error: SERVER_500 }) }));
      eq(await page.$eval("#checks-load-msg", (e) => (e.hidden ? null : e.textContent.trim())), SERVER_500, L("G", "a load answered 500 says the server's sentence"));
      eq(await page.$eval("#checks-load", (e) => e.nextElementSibling && e.nextElementSibling.id), "checks-load-msg", L("G", "right under the link"));
      check(await linkOn(page), L("G", "and the link stays"));
      await assertFormBlank(L("G", "the form stays blank"));
      await failing((r) => r.abort());
      eq(await page.$eval("#checks-load-msg", (e) => (e.hidden ? null : e.textContent.trim())), UNREACHABLE, L("G", "a load that cannot reach the server says so"));
      check(await linkOn(page), L("G", "and the link stays"));
      await failing((r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: true, day: null }) }));
      eq(await page.$eval("#checks-load-msg", (e) => (e.hidden ? null : e.textContent.trim())), `${pretty(D(2))} is not in the books.`,
         L("G", "an answer with no day says the date is not in the books"));
      if (await pressLink(how)) await settle(page, t);
      eq(await loadMsg(page), null, L("G", "a load that works takes the sentence down"));
      await assertWorkDay(DAY2, WHY2, L("G", "and brings the day back"));
    });

    /* ---- H · races: /api/day held up for 800 ms ---------------------------------------- */
    await section(L("H", "races"), async () => {
      let days;
      await go(page, t, D(10));
      await page.route("**/api/day**", async (route) => { await sleep(DELAY); await route.continue().catch(() => {}); });
      try {
        // a figure typed during the look-up
        await pick(page, D(2));
        await sleep(150);
        eq(await saveGreen(page), false, L("H", `while ${pretty(D(2))} is looked up, Save is grey`));
        await page.fill("#in-cash_sales", "55");
        await settle(page, t);
        eq(await value(page, "#in-cash_sales"), "55", L("H", "a figure typed during the look-up is kept"));
        eq([await value(page, "#in-" + OPEN), await value(page, "#in-" + CLOSE), await value(page, "#txt-reason")], ["", "", ""],
           L("H", "and the saved day does not overwrite the form"));
        eq(await domOn(page, "#checks-load"), false, L("H", "no link: the form was not cleared"));

        // another date picked during the look-up
        await go(page, t, D(10));
        await pick(page, D(2)); await sleep(200); await pick(page, D(5));
        await settle(page, t);
        eq(await shownDate(page), D(5), L("H", `${pretty(D(5))}, picked while ${pretty(D(2))} was looked up, stays`));
        await assertWorkDay(DAY5, {}, L("H", `and comes up as saved, not as ${pretty(D(2))}`));
        await pick(page, D(2)); await sleep(200); await pick(page, D(10));
        await settle(page, t);
        eq(await shownDate(page), D(10), L("H", `${pretty(D(10))}, picked while ${pretty(D(2))} was looked up, stays`));
        await assertBlankDay(L("H", `${pretty(D(2))}'s figures never reach ${pretty(D(10))}`));

        // Clear during the look-up
        await pick(page, D(2)); await sleep(200);
        await clickClear(page);
        await settle(page, t);
        eq(await shownDate(page), D(2), L("H", "Clear during the look-up keeps the date"));
        await assertFormBlank(L("H", "Clear during the look-up: the form stays blank"));
        check(await linkOn(page), L("H", "and, the date being saved, the link offers the day"));

        // the Off day switch during the look-up
        await go(page, t, D(10));
        await pick(page, D(2)); await sleep(200);
        await page.click(".daytype-toggle .opt-closed");
        await settle(page, t);
        eq(await isClosed(page), true, L("H", "the Off day switch moved during the look-up stays on"));
        eq(await value(page, "#in-" + OPEN), "", L("H", `and ${pretty(D(2))}'s figures did not come in`));

        // Save pressed during the look-up: a click, then Ctrl+S
        await go(page, t, D(10));
        const saves = t.save;
        await pick(page, D(2)); await sleep(150);
        eq(await saveGreen(page), false, L("H", "Save is grey during the look-up"));
        await mouseOnSave(page);
        await settle(page, t);
        eq(t.save, saves, L("H", "a click on Save during the look-up sends nothing"));
        eq([await bannerCount(page), await page.$eval("#dock-note", (e) => e.hidden), await dockSentence(page)], [0, true, null],
           L("H", "and once things settle there is no banner, no open explanation, nothing under the buttons"));
        await assertWorkDay(DAY2, WHY2, L("H", "the saved day still comes up"));
        await go(page, t, D(10));
        await pick(page, D(5)); await sleep(150);
        await page.keyboard.press("Control+s");
        await settle(page, t);
        eq(t.save, saves, L("H", "Ctrl+S during the look-up sends nothing"));
        eq([await bannerCount(page), await page.$eval("#dock-note", (e) => e.hidden), await dockSentence(page)], [0, true, null],
           L("H", "and leaves no banner, no open explanation, nothing under the buttons"));
        await assertWorkDay(DAY5, {}, L("H", "the saved day still comes up"));

        // fast arrow keys on the day list
        await go(page, t, D(1));
        await page.focus("#sel-day");
        for (let i = 0; i < 4; i++) { await page.keyboard.press("ArrowDown"); await sleep(120); }
        await settle(page, t);
        eq(await shownDate(page), D(5), L("H", `four fast ArrowDowns end on ${pretty(D(5))}`));
        await assertWorkDay(DAY5, {}, L("H", "with that day as saved"));
        eq(await activeId(page), "sel-day", L("H", "and the focus still on the day list"));
        for (let i = 0; i < 2; i++) { await page.keyboard.press("ArrowUp"); await sleep(120); }
        await settle(page, t);
        eq([await shownDate(page), await isClosed(page), await activeId(page)], [D(3), true, "sel-day"],
           L("H", `two fast ArrowUps end on the Off day ${pretty(D(3))}, switched on, focus on the list`));

        // the link pressed twice fast
        await go(page, t, D(2));
        await clickClear(page, t);
        days = t.day;
        if (W.wide) {
          await page.click("#checks-load"); await sleep(100); await page.click("#checks-load");
        } else {
          await page.click("#dock-status");
          await page.click("#checks-load"); await sleep(100); await page.click("#checks-load");
        }
        await settle(page, t);
        eq(t.day - days, 1, L("H", "two fast presses of the link ask for the day once"));
        await assertWorkDay(DAY2, WHY2, L("H", "and the day comes back"));

        // Next day pressed during the look-up, its answer (a refusal of the
        // blank form) arriving after the saved day has come up. With no delay
        // at all, a second Next day pressed the moment the first one lands does
        // the same. saveDay lets go of an answer meant for a form that has been
        // started again (formSeq); a refusal must not be shown beside the very
        // figures it says are unsaved.
        await go(page, t, D(10));
        await page.route("**/api/next", async (route) => { await sleep(DELAY * 2); await route.continue().catch(() => {}); });
        try {
          await pick(page, D(2)); await sleep(150);
          await page.click("#btn-next");
          await settle(page, t);
        } finally { await page.unroute("**/api/next"); }
        eq(await shownDate(page), D(2), L("H", "Next day pressed during the look-up of a saved day: the date stays (the blank form was refused)"));
        const open = await value(page, "#in-" + OPEN), dock = await dockSentence(page);
        check(!(open === shownValues(DAY2)[OPEN] && dock && /have not been saved/.test(dock)),
              L("H", "and once things settle, nothing under the buttons says the saved day now on screen has not been saved"),
              JSON.stringify({ opening: open, underTheButtons: dock }));
      } finally {
        await page.unroute("**/api/day**");
      }
    });

    /* ---- I · a failed look-up on a date change ----------------------------------------- */
    await section(L("I", "a failed look-up"), async () => {
      await go(page, t, D(10));
      await page.route("**/api/day**", (r) => r.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ ok: false, error: SERVER_500 }) }));
      try {
        await go(page, t, D(2));
        await assertFormBlank(L("I", `${pretty(D(2))} looked up with a 500: the form stays blank`));
        eq(await loadMsg(page), `Could not look up ${pretty(D(2))}. ${SERVER_500}`, L("I", "the Checks panel says it could not look the date up"));
        check(await panelOn(page, "#checks-load-msg") && await page.$eval("#checks-load-msg", (e) => !!e.closest("#checks")),
              L("I", "in the Checks panel, under the grey notes"));
        check((await rowTitles(page)).includes(SAVED_TITLE), L("I", `the check still runs: "${SAVED_TITLE}"`), JSON.stringify(await rowTitles(page)));
        check(await panelOn(page, "#checks-regen"), L("I", "and the ledger note"));
        eq(await domOn(page, "#checks-load"), false, L("I", "no link: nothing was cleared"));
        eq(await bannerCount(page), 0, L("I", "no banner at the top"));
        await shot(page, `${tag}-I-lookup-failed`);
      } finally { await page.unroute("**/api/day**"); }
      await go(page, t, D(10));
      eq(await loadMsg(page), null, L("I", "the sentence goes on the next date change"));

      await page.route("**/api/day**", (r) => r.abort());
      try {
        await go(page, t, D(5));
        await assertFormBlank(L("I", `${pretty(D(5))} looked up with the server out of reach: the form stays blank`));
        eq(await loadMsg(page), `Could not look up ${pretty(D(5))}. ${UNREACHABLE}`, L("I", "the Checks panel says so"));
        check(await panelOn(page, "#checks-saved"), L("I", "the check still runs: the grey note says the day is saved"));
        await clickClear(page, t);
        eq(await loadMsg(page), null, L("I", "the sentence goes when the form is started again (Clear)"));
        await go(page, t, D(10));
        await go(page, t, D(5));
        eq(await loadMsg(page), `Could not look up ${pretty(D(5))}. ${UNREACHABLE}`, L("I", "looked up again, still out of reach: the sentence is back"));
      } finally { await page.unroute("**/api/day**"); }
      for (const [k, v] of Object.entries(DAY5)) await setAmount(page, k, String(v));
      await settle(page, t);
      eq(await saveGreen(page), true, L("I", "the day typed back by hand: Save is green"));
      const s = await clickSave(page, t);
      eq(s.status, 200, L("I", "it is saved"));
      eq(await loadMsg(page), null, L("I", "the sentence goes after a successful save"));
    });

    /* ---- J · saving an Off day and a waiting day ------------------------------------------ */
    await section(L("J", "saving an Off day and a waiting day"), async () => {
      await go(page, t, D(12));
      await page.click(".daytype-toggle .opt-closed");
      await settle(page, t);
      eq(await saveGreen(page), true, L("J", "an Off day: Save is green"));
      let s = await clickSave(page, t);
      eq(s.status, 200, L("J", `${pretty(D(12))} is saved as an Off day`));
      if (W.wide) {
        check(await seen(page, "#checks-saved"), L("J", "the grey note says the day has been saved"));
        eq(await dockSentence(page), null, L("J", "and nothing is added under the buttons"));
      } else {
        eq(await dockSentence(page), `${pretty(D(12))} saved to the books.`, L("J", "the line under the buttons says it (the Checks panel is hidden at 390)"));
        check(await domOn(page, "#checks-saved"), L("J", "and the grey note is set in the Checks sheet"));
      }
      check((await rowTitles(page)).includes(CLOSED_ROW), L("J", `"${CLOSED_ROW}" is in the list`), JSON.stringify(await rowTitles(page)));
      eq(await domOn(page, "#checks-load"), false, L("J", "no link"));
      await shot(page, `${tag}-J-off-day-saved`);

      await go(page, t, D(15));
      await setAmount(page, OPEN, "1500");
      await setAmount(page, CLOSE, "1500");
      await settle(page, t);
      eq(await saveGreen(page), true, L("J", "a balanced day after a missing one: Save is green"));
      s = await clickSave(page, t);
      eq(s.status, 200, L("J", `${pretty(D(15))} is saved, its ledger waiting`));
      if (W.wide) {
        check(await seen(page, "#checks-saved"), L("J", "the grey note says the day has been saved"));
        eq(await dockSentence(page), null, L("J", "and nothing is added under the buttons"));
      } else {
        eq(await dockSentence(page), `${pretty(D(15))} saved to the books.`, L("J", "the line under the buttons says it (the Checks panel is hidden at 390)"));
        check(await domOn(page, "#checks-saved"), L("J", "and the grey note is set in the Checks sheet"));
      }
      check((await rowTitles(page)).includes(WAITING), L("J", `"${WAITING}" is in the list`), JSON.stringify(await rowTitles(page)));
      eq(await domOn(page, "#checks-load"), false, L("J", "no link"));
    });

    /* ---- K · console ------------------------------------------------------------------------- */
    check(errors.length === 0, L("K", "no console or page errors"), errors.slice(0, 3).join(" | "));
    await ctx.close();
  }

  console.log(`\n${pass} pass, ${fail} fail${MUTATE ? "  (MUTATE=1: the app.js of 2026-10-06)" : ""}`);
  if (fail) {
    const byPart = {};
    failed.forEach((f) => { const k = f.split(" · ")[0]; byPart[k] = (byPart[k] || 0) + 1; });
    console.log("FAILED BY PART: " + Object.entries(byPart).map(([k, n]) => `${k}=${n}`).join(", "));
    console.log("FAILED CHECKS:"); failed.forEach((f) => console.log("  - " + f));
  }
  console.log(fail === 0 ? "ALL PASS" : `${fail} FAILED`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.log("FAIL  the script itself stopped: " + ((e && e.stack) || e)); process.exit(2); });
