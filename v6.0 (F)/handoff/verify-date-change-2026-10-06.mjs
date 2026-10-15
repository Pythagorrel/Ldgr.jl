/* verify-date-change-2026-10-06.mjs — browser verification of the owner's bug
   report of 2026-10-06: "Changing the date does not clear the form nor does it
   clear the checks sidebar." Plain JavaScript, no build step, same style as
   verify-ui-2026-09-29.mjs.

   THE CONTRACT (the owner reversed the older "changing the date keeps the typed
   figures" decision on 2026-10-06; on 2026-10-07 the owner asked for a saved
   date to come up as it was saved, and for "Show saved figures" to show only
   after Clear on a saved day, tied to Ctrl+Alt+Z. Items 2 and 3 replace the
   2026-10-06 ones, which said every date came up blank and the link showed for
   any saved date; the passages marked (2026-10-07) are new):
     1  Picking a different date (day, month or year list; mouse or keyboard)
        that is NOT in the books leaves exactly what Clear gives on that date:
        every money box empty and unmarked, both reason boxes hidden and empty,
        Work day, the first-day tick unticked, totals $0.00, no predicted line,
        no open explanation, no sentence under the buttons, no top banner, no
        sentence under the link, the narrow Checks sheet closed. Focus stays on
        the list used; the page does not scroll. Nothing typed for the old date
        is kept, whichever date is picked.
        (2026-10-07) A saved date whose look-up fails stays blank too, and says
        "Could not look up <date>. ..." under the grey notes in the Checks
        panel; the next date change takes that sentence down.
     2  (2026-10-07) Picking a SAVED date brings that day up as it was saved,
        exactly as GET /api/day has it: a Work day with its figures and both
        reasons; an Off day with the switch on and every box blank (its stored
        balances were carried, not counted). Focus stays on the list used and
        the page does not scroll here either. The Checks sidebar shows what the
        server says about the NEW date with what is now on screen: nothing for
        an unsaved date; "Day saved, ledger generated" and the grey note
        #checks-regen for a day with a ledger; "Ledger waiting on the day
        before" and the grey note #checks-saved for a day whose ledger waits;
        "Marked as closed" and #checks-saved for an Off day. (Until 2026-10-07
        every date came up blank and the sidebar described the blank form.)
     3  (2026-10-07) "Show saved figures" never shows on a date change, saved
        date or not. It shows only after Clear on a saved date (Clear keeps the
        date and blanks the form, saved or not), and pressing it brings the day
        back as GET /api/day has it and hides it again. (Until 2026-10-07 it
        showed after picking any saved date.)
     4  A date that is not in the books never shows the link, not even after
        Clear.
     5  Unchanged: Clear keeps the date; Save stays on the day; Next day moves on
        with the cursor in the opening balance (2026-10-07: to a blank form, or
        to the next date as saved when that date is in the books); a future
        date says "That day has not happened yet." and greys out Save and Next
        day.
     6  A slow answer never repaints a date that has been left: a check, a
        "Show saved figures" load or (2026-10-07) a date's own look-up that
        answers after another date was picked is dropped, and a look-up that
        answers after a figure was typed on that same date does not put the
        saved figures over what was typed.

   LETTERS in the labels (A..Q) are the parts of the brief:
     A set-up  B the owner's case  C pick 4 May  D the owner's question (a
     pending day)  E a ledger day  F an Off day  G unsaved typing is dropped
     H reasons  I an open explanation  J month / year / clamp / future
     K keyboard  L the first-day tick  M a slow answer never repaints
     N Clear, Next day, scrolling  O in-flight guards  P 390 px  Q console
   (2026-10-07) D, E and F now check the saved day coming up by itself and
   then reach "Show saved figures" through Clear (F over an opening balance
   typed on 3 May); C clears 1 May before its failed load and adds a failed
   look-up; G adds Clear on an unsaved date and a saved date picked after
   typing; H adds a saved day whose two reasons come back (8 and 9 May, saved
   here); M reaches the link through Clear and adds a look-up in flight and a
   figure typed during one; N adds Next day onto a saved date; O no longer
   presses the link (6 May comes up by itself) and clears 6 May before its
   refused Next day; P follows D and F at 390, bringing the Off day back with
   Ctrl+Alt+Z because the sheet cannot be opened with no rows. Every other
   check is as it was.

   COUNT: 350 checks, all passing at 1536 and 390 on 2026-10-07. There were
   266 before that day; run unchanged against the 2026-10-07 form, 248 of them
   passed and 18 failed, every one of them about items 2 and 3.

   MUTATION PROOF:  MUTATE=1 serves app.js to the page with onDateChange() put
   back to the OLDEST behaviour (validateDate(); loadPrior(); scheduleCheck();),
   which keeps the figures and looks nothing up. Since 2026-10-07 the real
   function is `if (currentDate() === dateShown) return; openDate(currentDate());`
   and the same pattern replaces it whole; the script stops if it is not found.
   The real file is never edited. Then 350 checks, 261 pass and 89 fail
   (2026-10-07), and no part stops early (see fresh() below): the clearing
   checks of C, G, H, I, J, K, M, O and P/C, P/F fail, and so do the come-up
   checks of C (the failed look-up), D, E, F, G, H, N, O and P/D, P/F. What
   still passes is not about onDateChange: L (the first-day tick is unticked by
   the date facts), Clear and Ctrl+Alt+C, the link once reached, the in-flight
   guards of saveDay, onNextDay and onLoadSaved. The new look-up-in-flight
   checks of M are proved by stripping openDate's own guards instead (a one-off
   run on 2026-10-07, not kept here: 5 of them failed).

   HOW TO RUN (never against the real Records folder):
     1. A scratch server: LEDGER_ROOT=<scratch>, LDGR_NO_BROWSER=1,
        LDGR_NO_DIGEST=1, LDGR_NOTIFY_CONFIG=<a file that does not exist>,
        julia --startup-file=no server.jl <port>    (or julia --startup-file=no
        -J sysimage/ldgr.dll server.jl <port>, which starts faster)
     2. npm i playwright-core@1 in a scratch folder, copy this file there, then
        BASE=http://127.0.0.1:<port> LEDGER_ROOT=<the same scratch> OUT=<shots> \
          node verify-date-change-2026-10-06.mjs          (add MUTATE=1 for the proof)
     The script empties the books when it starts and refuses a path that
     mentions "Records". Dates are in May 2026 and the run starts from empty
     books, so 1 May 2026 is the first day on record. It runs at 1536 x 730
     (device scale 1.25, the owner's window) and then at 390 x 844 (part P). */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE   = process.env.BASE || "http://127.0.0.1:8771";
const SHOTS  = path.resolve(process.env.OUT || "shots");
const MUTATE = !!process.env.MUTATE;
const T      = MUTATE ? 6000 : 25000;          // how long a wait may take before it is a failure
fs.mkdirSync(SHOTS, { recursive: true });

/* ---------------------------------------------------------------------- */
let pass = 0, fail = 0;
const failed = [];
const check = (cond, label, extra) => {
  if (cond) { pass++; console.log(`PASS  ${label}`); }
  else      { fail++; failed.push(label); console.log(`FAIL  ${label}${extra ? "  -- " + extra : ""}`); }
  return !!cond;
};
const eq = (got, want, label) => check(got === want, label, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
const section = async (name, fn) => {
  console.log(`\n--- ${name}`);
  try { await fn(); }
  catch (e) { check(false, `${name} · the section stopped early`, String((e && e.message) || e).split("\n")[0]); }
};

const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
const pretty = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${MONTHS[m - 1]} ${y}`; };
const getJSON = async (p) => (await fetch(BASE + p)).json();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function emptyBooks() {
  const root = process.env.LEDGER_ROOT;
  if (!root) { console.log("FAIL  LEDGER_ROOT must be set to the server's scratch folder"); process.exit(2); }
  if (/records/i.test(root)) { console.log("FAIL  refusing to empty a folder whose path mentions Records: " + root); process.exit(2); }
  for (const entry of fs.readdirSync(root)) fs.rmSync(path.join(root, entry), { recursive: true, force: true });
}

/* ---------------------------------------------------------------------- */
/* Page helpers                                                            */
/* ---------------------------------------------------------------------- */
const text   = (page, sel) => page.$eval(sel, (e) => e.textContent.trim()).catch(() => null);
const hidden = (page, sel) => page.$eval(sel, (e) => e.hidden).catch(() => true);
const value  = (page, sel) => page.$eval(sel, (e) => e.value).catch(() => null);
const bannerCount = (page) => page.$$eval("#banner-area .banner", (b) => b.length);
const dockSentence = (page) => page.$eval("#dock-msg", (e) => (e.hidden ? null : e.textContent.trim())).catch(() => null);
const rowTitles = (page) => page.$$eval("#checks-list li .check-title", (n) => n.map((x) => x.textContent.trim()));
const SAVED_TITLE = "Day saved, ledger generated";
const WAITING     = "Ledger waiting on the day before";
const AFTER       = "Day after already on record";
const OFF_TITLE   = "Marked as closed";
const noteOn = (page) => page.$eval("#checks-regen", (e) => !e.hidden).catch(() => false);
const savedNoteOn = (page) => page.$eval("#checks-saved", (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
const shownDate = (page) => page.evaluate(() => {
  const v = (id) => document.getElementById(id).value;
  return `${v("sel-year")}-${String(v("sel-month")).padStart(2, "0")}-${String(v("sel-day")).padStart(2, "0")}`;
});
const linkOn = (page) => page.$eval("#checks-load", (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
const untilLink = (page, on, ms = T) => page.waitForFunction((v) => {
  const e = document.getElementById("checks-load");
  return (!e.hidden && e.getClientRects().length > 0) === v;
}, on, { timeout: ms }).then(() => true).catch(() => false);
const untilRow = (page, title, on = true, ms = T) => page.waitForFunction(([t, v]) =>
  [...document.querySelectorAll("#checks-list .check-title")].some((n) => n.textContent.trim() === t) === v,
  [title, on], { timeout: ms }).then(() => true).catch(() => false);
const untilText = (page, sel, needle, ms = T) => page.waitForFunction(
  ([s, t]) => { const n = document.querySelector(s); return !!n && !n.hidden && n.textContent.includes(t); },
  [sel, needle], { timeout: ms }).then(() => true).catch(() => false);
const untilVisible = (page, sel, on = true, ms = T) => page.waitForFunction(
  ([s, v]) => { const n = document.querySelector(s); return !!n && (!n.hidden && n.getClientRects().length > 0) === v; },
  [sel, on], { timeout: ms }).then(() => true).catch(() => false);

const checkFor = (page, iso) => page.waitForResponse((r) => {
  if (!r.url().includes("/api/check")) return false;
  try { return JSON.parse(r.request().postData() || "{}").date === iso; } catch { return false; }
}, { timeout: T });

const daysIn = (y, m) => new Date(y, m, 0).getDate();
const isoOf = (y, m, d) => `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

/* Pick a date through the lists, as a person does, changing only the lists that
   differ and focusing each one first. Waits for the check of the new date to
   answer and a moment more, unless `wait` is false (a future date asks nothing). */
async function pick(page, iso, { wait = true } = {}) {
  const [y, m, d] = iso.split("-").map(Number);
  const cur = await shownDate(page);
  if (cur === iso) return;
  const w = wait ? checkFor(page, iso).catch(() => null) : null;
  const [cy, cm] = cur.split("-").map(Number);
  if (y !== cy) { await page.focus("#sel-year"); await page.selectOption("#sel-year", String(y)); }
  if (m !== cm) { await page.focus("#sel-month"); await page.selectOption("#sel-month", String(m)); }
  if (Number(await page.$eval("#sel-day", (e) => e.value)) !== d) {
    await page.focus("#sel-day"); await page.selectOption("#sel-day", String(d));
  }
  if (w) await w;
  await page.waitForTimeout(700);
}
/* One list only, with its focus; returns the date that results. */
async function pickVia(page, list, val) {
  const cur = (await shownDate(page)).split("-").map(Number);
  let [y, m, d] = cur;
  if (list === "year") y = Number(val); else if (list === "month") m = Number(val); else d = Number(val);
  d = Math.min(d, daysIn(y, m));
  const iso = isoOf(y, m, d);
  const w = checkFor(page, iso).catch(() => null);
  await page.focus("#sel-" + list);
  await page.selectOption("#sel-" + list, String(val));
  await w;
  await page.waitForTimeout(700);
  return iso;
}

async function setAmount(page, key, v) {
  await page.fill("#in-" + key, v);
  await page.$eval("#in-" + key, (e) => e.blur());
}
async function clickSave(page) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/save"), { timeout: T * 3 }),
    page.click("#btn-save"),
  ]);
  return { status: res.status(), body: await res.json().catch(() => null) };
}
const untilSavedShown = (page) => page.waitForFunction(() => {
  const row = [...document.querySelectorAll("#checks-list .check-title")].some((n) => n.textContent.trim() === "Day saved, ledger generated");
  const msg = document.getElementById("dock-msg");
  const note = document.getElementById("checks-saved");
  return row || (!!note && !note.hidden && note.getClientRects().length > 0) || (!msg.hidden && msg.textContent.includes("saved to the books"));
}, null, { timeout: T }).then(() => true).catch(() => false);

/* The whole state a blank form is made of, read in one go. */
const blankReport = (page) => page.evaluate(() => {
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
    tick: $("chk-genesis").checked,
    totals: [$("tot-cash").textContent, $("tot-exp").textContent, $("tot-dep").textContent],
    predictedHidden: $("predicted").hidden,
    noteHidden: $("dock-note").hidden,
    msgHidden: $("dock-msg").hidden,
    banners: document.querySelectorAll("#banner-area .banner").length,
    loadMsgHidden: $("checks-load-msg").hidden,
    sheetOpen: $("checks").classList.contains("open"),
  };
});

/* Contract item 1, as a handful of checks. */
async function assertBlank(page, label) {
  const b = await blankReport(page);
  check(b.nonBlank.length === 0 && b.marked.length === 0 && b.errs === 0 && b.outlines.length === 0,
        `${label}: every box is empty, with no red marks or outlines`, JSON.stringify([b.nonBlank, b.marked, b.errs, b.outlines]));
  check(!b.reasonBoxes[0] && !b.reasonBoxes[1] && b.reasonVals[0] === "" && b.reasonVals[1] === "",
        `${label}: both reason boxes are hidden and empty`, JSON.stringify([b.reasonBoxes, b.reasonVals]));
  check(b.closed === false && b.tick === false, `${label}: Work day, and the first-day tick is unticked`, JSON.stringify([b.closed, b.tick]));
  check(b.totals.every((t) => t === "$0.00") && b.predictedHidden, `${label}: totals are $0.00 and the predicted line is hidden`, JSON.stringify([b.totals, b.predictedHidden]));
  check(b.noteHidden && b.msgHidden && b.banners === 0 && b.loadMsgHidden && !b.sheetOpen,
        `${label}: no open explanation, no line under the buttons, no banner, no sentence under the link, sheet closed`, JSON.stringify(b));
}
/* The same in one check, for the steps of a long walk. */
async function isBlank(page) {
  const b = await blankReport(page);
  return b.nonBlank.length === 0 && b.marked.length === 0 && b.errs === 0 && b.outlines.length === 0 &&
    !b.reasonBoxes[0] && !b.reasonBoxes[1] && b.reasonVals.every((v) => v === "") && !b.closed && !b.tick &&
    b.totals.every((t) => t === "$0.00") && b.predictedHidden && b.noteHidden && b.msgHidden && b.banners === 0 && b.loadMsgHidden && !b.sheetOpen;
}

/* (2026-10-07) Contract item 2: how the form differs from a saved day as GET
   /api/day returns it. The Off day switch; every box, written the way the form
   writes a saved figure (a drawer count as 0.00 even when 0, any other box
   blank for 0), and every box blank on an Off day, whose stored balances were
   carried, not counted; and both reasons, word for word. Empty when the form
   shows the day exactly as saved. */
const dayMismatch = (page, day, cashKeys) => page.evaluate(([d, cash]) => {
  const bad = [];
  const closed = d.status === "closed";
  if (document.getElementById("chk-closed").checked !== closed) bad.push(`Off day switch should be ${closed ? "on" : "off"}`);
  for (const i of document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input")) {
    const k = i.dataset.key, v = d.amounts[k];
    const num = !closed && v !== null && v !== undefined && v !== "" && isFinite(Number(v));
    const want = !num ? "" : cash.includes(k) || Number(v) !== 0 ? Number(v).toFixed(2) : "";
    if (i.value !== want) bad.push(`${k}: ${JSON.stringify(i.value)} vs ${JSON.stringify(want)}`);
  }
  for (const [id, sent] of [["txt-opening-reason", "openingReason"], ["txt-reason", "reason"]]) {
    const want = closed ? "" : (d[sent] || "");
    const got = document.getElementById(id).value;
    if (got !== want) bad.push(`${id}: ${JSON.stringify(got)} vs ${JSON.stringify(want)}`);
  }
  return bad;
}, [day, cashKeys]);

/* ---------------------------------------------------------------------- */
async function main() {
  emptyBooks();
  const cfg = await getJSON("/api/config");
  const today = cfg.today;
  const OPEN = cfg.openingKey, CLOSE = cfg.closingKey, DEP = cfg.depositKey;
  const d1 = "2026-05-01", d2 = "2026-05-02", d3 = "2026-05-03", d4 = "2026-05-04", d5 = "2026-05-05",
        d6 = "2026-05-06", d7 = "2026-05-07", d8 = "2026-05-08", d9 = "2026-05-09", d10 = "2026-05-10",
        d11 = "2026-05-11", d12 = "2026-05-12", d14 = "2026-05-14", d15 = "2026-05-15";
  console.log(`today=${today}  base=${BASE}  mutate=${MUTATE}  shots=${SHOTS}`);

  /* (2026-10-07) One check: the form shows `iso` exactly as GET /api/day has it. */
  const asSaved = async (page, iso, label) => {
    const day = (await getJSON("/api/day?date=" + iso)).day;
    const bad = day ? await dayMismatch(page, day, [OPEN, CLOSE]) : ["GET /api/day says it is not saved"];
    return check(bad.length === 0, label, bad.join("; "));
  };

  const typeBalanced = async (page, open) => {
    await setAmount(page, OPEN, open);
    await setAmount(page, CLOSE, open);
    await untilText(page, "#predicted", "The day balances.");
  };
  const typeUnbalanced = async (page) => {        // 50 more in the drawer than the figures account for
    await setAmount(page, OPEN, "1300");
    await setAmount(page, "cash_sales", "100");
    await setAmount(page, CLOSE, "1450");
    await untilVisible(page, "#reason-box", true);
  };

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const errors = [], errors2 = [];
  try {
    const mkCtx = async (viewport, dsf) => {
      const ctx = await browser.newContext({ viewport, deviceScaleFactor: dsf, acceptDownloads: false });
      if (MUTATE) {
        // The OLD behaviour: a date change only re-validates and re-checks.
        await ctx.route("**/app.js*", async (route) => {
          const res = await route.fetch();
          let body = await res.text();
          const re = /function onDateChange\(\) \{[\s\S]*?\n\}/;
          if (!re.test(body)) throw new Error("onDateChange() not found in app.js");
          body = body.replace(re, "function onDateChange() { validateDate(); loadPrior(); scheduleCheck(); }");
          await route.fulfill({ response: res, body });
        });
      }
      return ctx;
    };
    const listen = (page, sink, saves, nexts) => {
      // A refused save or move answers 4xx on purpose, and /api/day is aborted on purpose in C (a load, and a date's own look-up); Chrome logs each as a console error.
      const noise = (t) => /favicon/i.test(t) || /api\/day/.test(t) || (/api\/(next|save)/.test(t) && /\b(400|409)\b/.test(t));
      page.on("console", (m) => {
        if (m.type() !== "error") return;
        const line = `${m.text()} [${(m.location() && m.location().url) || ""}]`;
        if (!noise(line)) sink.push(line);
      });
      page.on("pageerror", (e) => sink.push("pageerror: " + e.message));
      page.on("dialog", (d) => d.accept());
      page.on("request", (r) => {
        if (r.method() !== "POST") return;
        if (r.url().includes("/api/save")) saves.push(1);
        if (r.url().includes("/api/next")) nexts.push(1);
      });
    };

    const ctx = await mkCtx({ width: 1536, height: 730 }, 1.25);
    const page = await ctx.newPage();
    const saves = [], nexts = [];
    listen(page, errors, saves, nexts);
    await Promise.all([checkFor(page, today), page.goto(BASE)]);
    await page.waitForSelector("#in-" + OPEN);
    const slow = async (p, pattern, ms, fn) => {
      await p.route(pattern, async (route) => { await sleep(ms); await route.continue().catch(() => {}); });
      try { await fn(); } finally { await sleep(ms + 300); await p.unroute(pattern); }
    };
    /* (2026-10-07) MUTATE=1 only: each part from B on, except C, starts with
       Clear, which the mutation leaves alone, so what the old behaviour leaves
       behind in one part (an Off day switch still on, figures still typed) does
       not stop the next part before its own checks have run. C is left out on
       purpose: its checks are about what B left on screen. It is also pressed
       inside F and P/F, before a figure is typed on the date that is about to
       be left, so the Off day switch the old behaviour leaves on neither hides
       that box nor lets a kept Off day pass for one that came up. Every part
       types its own figures after this, so no check is made to pass by it.
       Without MUTATE nothing is pressed here. */
    const fresh = async (p = page) => {
      if (!MUTATE) return;
      await Promise.all([checkFor(p, await shownDate(p)).catch(() => null), p.click("#btn-clear")]);
      await p.waitForTimeout(400);
    };

    /* ---- A · set-up -------------------------------------------------------- */
    await section("A", async () => {
      await pick(page, d1);
      await setAmount(page, OPEN, "1000");
      await setAmount(page, "cash_sales", "500");
      await setAmount(page, DEP, "300");
      await setAmount(page, CLOSE, "1200");
      check(await untilText(page, "#predicted", "The day balances."), "A · 1 May typed through the form balances");
      check(await untilVisible(page, "#genesis-line", true), "A · the first-day box shows for 1 May");
      await page.check("#chk-genesis");
      const s = await clickSave(page);
      eq(s.status, 200, "A · 1 May is saved as a balanced Work day");
      await untilSavedShown(page);
      check((await rowTitles(page)).includes(SAVED_TITLE), "A · its ledger was made: the Checks row says Day saved, ledger generated", JSON.stringify(await rowTitles(page)));
    });

    /* ---- B · the owner's case --------------------------------------------- */
    await section("B", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d5);
      await typeBalanced(page, "1300");
      const s = await clickSave(page);
      eq(s.status, 200, "B · 5 May (2-4 May not in the books) is saved");
      check(await untilRow(page, WAITING), "B · the Checks list holds \"Ledger waiting on the day before\"", JSON.stringify(await rowTitles(page)));
      check(await untilVisible(page, "#checks-saved", true), "B · the grey note #checks-saved confirms the save");
      eq(await dockSentence(page), null, "B · and #dock-msg stays empty while the Checks panel is visible");
    });

    /* ---- C · pick 4 May: nothing from 5 May lingers ------------------------ */
    await section("C", async () => {
      await page.evaluate(() => window.scrollTo(0, 150));
      const y0 = await page.evaluate(() => window.scrollY);
      check(y0 > 0, "C · the page is scrollable, so the no-scroll check means something", String(y0));
      await pickVia(page, "day", 4);
      eq(await shownDate(page), d4, "C · the date on screen is 4 May");
      eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "sel-day", "C · focus stays on the day list");
      eq(await page.evaluate(() => window.scrollY), y0, "C · the page did not scroll");
      await assertBlank(page, "C");
      await page.waitForTimeout(1200);         // a late answer must not repaint anything
      await assertBlank(page, "C (a moment later)");
      const titles = await rowTitles(page);
      eq(titles.length, 0, "C · the Checks list has no rows", JSON.stringify(titles));
      check(!titles.includes(WAITING) && !titles.includes(AFTER), "C · in particular no \"Ledger waiting on the day before\" and no \"Day after already on record\"", JSON.stringify(titles));
      eq(await untilVisible(page, "#checks-empty", true, 1500), true, "C · #checks-empty is visible");
      eq(await hidden(page, "#checks-count"), true, "C · #checks-count is hidden");
      eq(await linkOn(page), false, "C · \"Show saved figures\" is hidden (4 May is not saved)");
      eq(await noteOn(page), false, "C · and so is the grey note");
      // The owner's other date: a failed load's sentence goes on a date change too.
      // (2026-10-07) The link shows only after Clear on a saved day, so 1 May,
      // which now comes up as saved, is cleared first.
      await pick(page, d1);
      await Promise.all([checkFor(page, d1).catch(() => null), page.click("#btn-clear")]);
      check(await untilLink(page, true), "C · Clear on 1 May (saved) shows \"Show saved figures\"");
      await page.route("**/api/day**", (r) => r.abort());
      await page.click("#checks-load");
      check(await untilVisible(page, "#checks-load-msg", true, 5000), "C · a failed load puts its sentence under the link");
      await page.unroute("**/api/day**");
      await pick(page, d4);
      eq(await hidden(page, "#checks-load-msg"), true, "C · …and a date change takes that sentence down");
      eq(await linkOn(page), false, "C · and the link with it");
      // (2026-10-07) A saved date whose own look-up fails stays blank and says
      // so in the same place, never in the banner; the next date change takes
      // that down too.
      await page.route("**/api/day**", (r) => r.abort());
      try {
        await pick(page, d1);
        check(await untilText(page, "#checks-load-msg", `Could not look up ${pretty(d1)}.`, 5000),
              "C · picking 1 May with its look-up failing says \"Could not look up 1 May 2026.\" under the grey notes", await text(page, "#checks-load-msg"));
        const b = await blankReport(page);
        check(b.nonBlank.length === 0 && !b.closed && b.reasonVals.every((v) => v === ""), "C · and the form stays blank: nothing is guessed", JSON.stringify(b.nonBlank));
        eq(await bannerCount(page), 0, "C · with no banner at the top");
        eq(await linkOn(page), false, "C · and no \"Show saved figures\"");
      } finally { await page.unroute("**/api/day**"); }
      await pick(page, d4);
      eq(await hidden(page, "#checks-load-msg"), true, "C · …and the next date change takes that sentence down");
    });

    /* ---- D · the owner's question: a pending day --------------------------- */
    await section("D", async () => {
      await fresh();                           // MUTATE=1 only
      // (2026-10-07) The saved day comes up by itself, from the day list, with
      // the focus left on the list and the page where it was.
      await page.evaluate(() => window.scrollTo(0, 150));
      const y0 = await page.evaluate(() => window.scrollY);
      await pickVia(page, "day", 5);
      eq(await shownDate(page), d5, "D · the date on screen is 5 May");
      await asSaved(page, d5, "D · 5 May comes up as saved: every box equals GET /api/day");
      eq(Number(await value(page, "#in-" + OPEN)), 1300, "D · (its opening balance is 1300)");
      eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "sel-day", "D · focus stays on the day list");
      eq(await page.evaluate(() => window.scrollY), y0, "D · the page did not scroll");
      eq(await linkOn(page), false, "D · \"Show saved figures\" is not shown on a date change");
      check(await untilRow(page, WAITING), "D · \"Ledger waiting on the day before\" is in the list, truthfully, for the figures on screen", JSON.stringify(await rowTitles(page)));
      let titles = await rowTitles(page);
      check(!titles.includes(SAVED_TITLE), "D · no \"Day saved, ledger generated\" row", JSON.stringify(titles));
      eq(await noteOn(page), false, "D · the grey note about regenerating is hidden (no ledger yet)");
      check(await untilVisible(page, "#checks-saved", true, 3000), "D · the grey note #checks-saved says the day is saved");
      await page.waitForTimeout(1200);         // nothing comes along afterwards to change it
      await asSaved(page, d5, "D · 5 May is still as saved a moment later");

      // After Clear, and only then, the link brings the day back.
      await Promise.all([checkFor(page, d5).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      eq(await shownDate(page), d5, "D · Clear keeps 5 May");
      await assertBlank(page, "D (5 May, cleared)");
      check(await untilLink(page, true), "D · after Clear, \"Show saved figures\" is visible for the saved day whose ledger is pending");
      titles = await rowTitles(page);
      eq(titles.length, 0, "D · and the blank pending day has no rows at all", JSON.stringify(titles));
      const [r] = await Promise.all([
        page.waitForResponse((x) => x.url().includes("/api/day"), { timeout: T }).catch(() => null),
        page.click("#checks-load"),
      ]);
      eq(r ? r.status() : 0, 200, "D · the link asks GET /api/day");
      await page.waitForTimeout(1200);
      await asSaved(page, d5, "D · every box equals GET /api/day for 5 May");
      eq(await linkOn(page), false, "D · the link hides after loading");
      check(await untilRow(page, WAITING), "D · \"Ledger waiting on the day before\" is back in the list, now truthfully", JSON.stringify(await rowTitles(page)));
      eq(await shownDate(page), d5, "D · still on 5 May");
    });

    /* ---- E · a day with a ledger ------------------------------------------- */
    await section("E", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d1);
      // (2026-10-07) 1 May comes up as saved.
      await asSaved(page, d1, "E · 1 May comes up as saved: every box equals GET /api/day");
      eq(Number(await value(page, "#in-" + CLOSE)), 1200, "E · (its closing balance is 1200)");
      check(await untilRow(page, SAVED_TITLE), "E · the row \"Day saved, ledger generated\" shows", JSON.stringify(await rowTitles(page)));
      check(await untilVisible(page, "#checks-regen", true, 3000), "E · the grey note is visible");
      eq(await savedNoteOn(page), false, "E · and #checks-saved is not (the row already says the day is saved)");
      eq(await linkOn(page), false, "E · \"Show saved figures\" is not shown on a date change");
      // After Clear the link brings it back.
      await Promise.all([checkFor(page, d1).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      await assertBlank(page, "E (1 May, cleared)");
      check(await untilRow(page, SAVED_TITLE), "E · the cleared day still has its \"Day saved, ledger generated\" row", JSON.stringify(await rowTitles(page)));
      check(await untilLink(page, true), "E · after Clear, \"Show saved figures\" is visible");
      await page.click("#checks-load");
      check(await untilLink(page, false), "E · loading hides the link");
      eq(Number(await value(page, "#in-" + CLOSE)), 1200, "E · and the saved figures are in the boxes");
    });

    /* ---- F · an Off day ------------------------------------------------------ */
    await section("F", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d2);
      await Promise.all([checkFor(page, d2).catch(() => null), page.click(".daytype-toggle .opt-closed")]);
      const s = await clickSave(page);
      eq(s.status, 200, "F · 2 May is saved as an Off day");
      // (2026-10-07) The grey note confirms an Off day's save; the line under
      // the buttons is kept for a window too narrow for the panel (P/F).
      check(await untilVisible(page, "#checks-saved", true), "F · the grey note #checks-saved confirms the Off day's save");
      eq(await dockSentence(page), null, "F · and #dock-msg stays empty while the Checks panel is visible");
      await pick(page, d3);
      eq(await page.$eval("#chk-closed", (e) => e.checked), false, "F · picking 3 May: the Off day switch is off");
      check(await page.$eval("#in-" + OPEN, (e) => e.getClientRects().length > 0), "F · and the boxes are showing");
      await assertBlank(page, "F (3 May)");
      // (2026-10-07) 2 May comes up as the saved Off day, over an opening
      // balance typed on 3 May (the same 1200 the Off day carried, so a leak of
      // either would show).
      await fresh();                           // MUTATE=1 only
      await setAmount(page, OPEN, "1200");
      await pick(page, d2);
      eq(await page.$eval("#chk-closed", (e) => e.checked), true, "F · picking 2 May again: it comes up as an Off day, switch on");
      eq(await page.$eval("#in-" + OPEN, (e) => e.getClientRects().length), 0, "F · with the boxes hidden");
      await asSaved(page, d2, "F · and every box blank: the carried $1,200.00 is not put in (README rules 3 and 4)");
      eq(await page.$eval("#closed-note", (e) => e.textContent.trim()), "No ledger will be generated. The next working day carries this balance through.", "F · the Off day note is shown");
      check(await untilVisible(page, "#checks-saved", true, 3000), "F · the grey note #checks-saved says the day is saved");
      eq(await noteOn(page), false, "F · with no regenerate note (an Off day has no ledger)");
      check(await untilRow(page, OFF_TITLE), "F · and the server's \"Marked as closed\" row", JSON.stringify(await rowTitles(page)));
      eq(await linkOn(page), false, "F · \"Show saved figures\" is not shown on a date change");
      // After Clear: a blank Work day, and the link brings the Off day back.
      await Promise.all([checkFor(page, d2).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      await assertBlank(page, "F (2 May, cleared: Work-day blank)");
      check(await untilLink(page, true), "F · after Clear, \"Show saved figures\" shows for the saved Off day");
      eq(await noteOn(page), false, "F · with no regenerate note");
      eq((await rowTitles(page)).length, 0, "F · and no rows");
      await page.click("#checks-load");
      check(await untilLink(page, false), "F · loading hides the link");
      await page.waitForTimeout(500);
      eq(await page.$eval("#chk-closed", (e) => e.checked), true, "F · and the Off day switch turns on");
    });

    /* ---- G · unsaved typing is dropped ---------------------------------------- */
    await section("G", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await setAmount(page, OPEN, "1300");
      await setAmount(page, "cash_sales", "100");
      await pick(page, d7);
      await assertBlank(page, "G (7 May)");
      await pick(page, d6);
      await assertBlank(page, "G (6 May again)");
      eq(await linkOn(page), false, "G · no link: 6 May was never saved");
      // (2026-10-07) Contract item 4: not after Clear either.
      await setAmount(page, "cash_sales", "100");
      await Promise.all([checkFor(page, d6).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      await assertBlank(page, "G (6 May, cleared)");
      eq(await linkOn(page), false, "G · Clear on 6 May (never saved) shows no link either");
      // (2026-10-07) Typing is dropped on the way to a saved date as well: the
      // saved day comes up, not what was typed for the date that was left.
      await setAmount(page, OPEN, "999");
      await setAmount(page, "cash_sales", "100");
      await pick(page, d1);
      await asSaved(page, d1, "G · picking 1 May (saved) after typing on 6 May shows 1 May as saved, nothing typed");
      eq(await linkOn(page), false, "G · with no link");
    });

    /* ---- I · an open explanation, then H · reasons ------------------------------ */
    await section("I", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await typeUnbalanced(page);
      check(await untilVisible(page, "#checks-list li .check-more", true), "I · a row with \"See full explanation\" is in the list", JSON.stringify(await rowTitles(page)));
      await page.click("#checks-list li .check-more");
      check(await untilVisible(page, "#dock-note", true, 3000), "I · the full explanation is open in the dock");
      await pick(page, d7);
      eq(await hidden(page, "#dock-note"), true, "I · a date change closes it");
      await assertBlank(page, "I (7 May)");
    });

    await section("H", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await typeUnbalanced(page);
      await page.fill("#txt-reason", "Change given by mistake");
      check(!(await hidden(page, "#reason-box")) && (await value(page, "#txt-reason")) !== "", "H · the End of day reason box shows with a reason typed");
      await pick(page, d7);
      eq(await hidden(page, "#reason-box"), true, "H · picking another date hides the End of day reason box");
      eq(await value(page, "#txt-reason"), "", "H · and empties its text");
      await assertBlank(page, "H (7 May)");
      // the opening reason: 5 May closed with 1300, so 1350 differs
      await pick(page, d6);
      await setAmount(page, OPEN, "1350");
      await setAmount(page, CLOSE, "1350");
      check(await untilVisible(page, "#opening-reason-box", true), "H · an opening that differs from the last close shows the opening reason box");
      await page.fill("#txt-opening-reason", "Counted again in the morning");
      await pick(page, d7);
      eq(await hidden(page, "#opening-reason-box"), true, "H · picking another date hides the opening reason box");
      eq(await value(page, "#txt-opening-reason"), "", "H · and empties its text");
      await assertBlank(page, "H (7 May, after the opening reason)");

      // (2026-10-07) A saved day's two reasons come back with it, each in its
      // own box, and go again on the next date change. 8 May is saved balanced
      // at 1000 (7 May is missing, so its opening has nothing to differ from);
      // 9 May opens at 1350 against that 1000 and counts 50 more than its
      // figures account for, and is saved with both reasons typed.
      await pick(page, d8);
      await typeBalanced(page, "1000");
      let s = await clickSave(page);
      eq(s.status, 200, "H · 8 May is saved, balanced at 1000");
      await untilSavedShown(page);
      await pick(page, d9);
      await setAmount(page, OPEN, "1350");
      await setAmount(page, "cash_sales", "100");
      await setAmount(page, CLOSE, "1500");
      check(await untilVisible(page, "#opening-reason-box", true) && await untilVisible(page, "#reason-box", true), "H · 9 May asks for both reasons");
      await page.fill("#txt-opening-reason", "Counted again in the morning");
      await page.fill("#txt-reason", "Change given by mistake");
      await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: T }).catch(() => {});
      s = await clickSave(page);
      eq(s.status, 200, "H · 9 May is saved with both reasons");
      await untilSavedShown(page);
      await pick(page, d10);
      await assertBlank(page, "H (10 May, after 9 May was saved with both reasons)");
      await setAmount(page, "cash_sales", "7");    // dropped when 9 May comes up
      await pick(page, d9);
      await asSaved(page, d9, "H · picking 9 May again brings back its figures and both reasons, word for word");
      check(!(await hidden(page, "#opening-reason-box")) && !(await hidden(page, "#reason-box")), "H · each reason in its own box, beside its figure");
      eq(await linkOn(page), false, "H · with no link");
      await pick(page, d10);
      await assertBlank(page, "H (10 May, after 9 May came up with its reasons)");
    });

    /* ---- J · month, year, clamp, future ------------------------------------------ */
    await section("J", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await setAmount(page, "cash_sales", "100");
      let iso = await pickVia(page, "month", 6);
      eq(await shownDate(page), iso, "J · the month list changed the date (6 June)");
      await assertBlank(page, "J (month list)");
      await setAmount(page, "cash_sales", "100");
      iso = await pickVia(page, "year", 2025);
      eq(await shownDate(page), "2025-06-06", "J · the year list changed the date (2025)");
      await assertBlank(page, "J (year list)");
      await pick(page, "2026-05-31");
      await setAmount(page, "cash_sales", "100");
      iso = await pickVia(page, "month", 6);
      eq(iso, "2026-06-30", "J · 31 May + June clamps to 30 June");
      eq(await value(page, "#sel-day"), "30", "J · the day list shows 30");
      eq(await page.$$eval("#sel-day option", (o) => o.length), 30, "J · and has 30 options");
      await assertBlank(page, "J (30 June)");
      // a future date
      const future = `${today.slice(0, 4)}-12-31`;
      check(future > today, "J · the future date used is really after today", future);
      await pick(page, d6);
      await setAmount(page, "cash_sales", "100");
      await pick(page, future, { wait: false });
      eq(await shownDate(page), future, "J · the future date is on screen");
      eq(await text(page, "#err-date"), "That day has not happened yet.", "J · \"That day has not happened yet.\" shows");
      await assertBlank(page, "J (future date)");
      eq((await rowTitles(page)).length, 0, "J · the Checks list is empty");
      eq(await page.$eval("#btn-save", (b) => b.disabled), true, "J · Save is greyed out");
      eq(await page.$eval("#btn-next", (b) => b.disabled), true, "J · Next day is greyed out");
    });

    /* ---- K · keyboard ------------------------------------------------------------- */
    await section("K", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, "2026-05-10");
      let expect = 10;
      for (const key of ["ArrowDown", "ArrowDown", "ArrowDown", "ArrowUp", "ArrowUp", "ArrowUp"]) {
        await setAmount(page, "cash_sales", "100");
        await page.focus("#sel-day");
        const want = expect + (key === "ArrowDown" ? 1 : -1);
        const w = checkFor(page, isoOf(2026, 5, want)).catch(() => null);
        await page.keyboard.press(key);
        await w;
        await page.waitForTimeout(500);
        expect = want;
        eq(await shownDate(page), isoOf(2026, 5, want), `K · ${key} steps the date to ${want} May`);
        check(await isBlank(page), `K · ${key}: the form is blank`);
        eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "sel-day", `K · ${key}: focus stays on the day list`);
      }
      eq(await page.$$eval("#sel-day option", (o) => o.length), 31, "K · the day list still has 31 options for May");
    });

    /* ---- L · the first-day tick ----------------------------------------------------- */
    await section("L", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, "2026-04-30");
      check(await untilVisible(page, "#genesis-line", true), "L · the first-day box shows on 30 April (nothing on record before it)");
      await page.check("#chk-genesis");
      eq(await page.$eval("#chk-genesis", (e) => e.checked), true, "L · ticked");
      await pick(page, "2026-04-29");
      eq(await page.$eval("#chk-genesis", (e) => e.checked), false, "L · picking another date unticks it");
      await pick(page, "2026-04-30");
      check(await untilVisible(page, "#genesis-line", true), "L · the box shows again on coming back");
      eq(await page.$eval("#chk-genesis", (e) => e.checked), false, "L · and is still unticked after coming back");
    });

    /* ---- M · a slow answer never repaints ---------------------------------------------- */
    await section("M", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await slow(page, "**/api/check", 3000, async () => {
        await setAmount(page, OPEN, "1300");
        await setAmount(page, "cash_sales", "100");
        await setAmount(page, CLOSE, "1450");
        await page.waitForTimeout(700);                    // the check for these figures is now in flight
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "7");
        await page.waitForTimeout(4500);                   // both delayed answers have landed
      });
      eq(await shownDate(page), d7, "M · the new date stays on screen");
      await assertBlank(page, "M (check in flight)");
      eq((await rowTitles(page)).length, 0, "M · the old figures' rows never appeared on the new date", JSON.stringify(await rowTitles(page)));
      eq(await hidden(page, "#reason-box"), true, "M · nor did the old reason box");

      // "Show saved figures" in flight (2026-10-07: the link is reached through Clear)
      await pick(page, d1);
      await Promise.all([checkFor(page, d1).catch(() => null), page.click("#btn-clear")]);
      check(await untilLink(page, true), "M · after Clear, 1 May shows the link");
      await slow(page, "**/api/day**", 2500, async () => {
        await page.evaluate(() => document.getElementById("checks-load").click());
        await page.waitForTimeout(300);
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "7");
        await page.waitForTimeout(3500);
      });
      eq(await shownDate(page), d7, "M · the date picked meanwhile stands");
      await assertBlank(page, "M (load in flight): nothing from the saved day was loaded");
      eq(await linkOn(page), false, "M · and 7 May (unsaved) has no link");

      // (2026-10-07) A date's own look-up in flight: 1 May is picked, and 4 May
      // is picked before 1 May's saved day arrives. 1 May's answer is let go.
      await slow(page, "**/api/day**", 2500, async () => {
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "1");
        await page.waitForTimeout(300);
        await page.selectOption("#sel-day", "4");
        await page.waitForTimeout(3500);
      });
      eq(await shownDate(page), d4, "M · the second date picked stands");
      await assertBlank(page, "M (look-up in flight): nothing of 1 May reached 4 May");
      eq((await rowTitles(page)).length, 0, "M · no rows on 4 May", JSON.stringify(await rowTitles(page)));
      eq(await linkOn(page), false, "M · and no link");

      // (2026-10-07) A figure typed on 1 May while its look-up is on its way is
      // the person's own start on the form: the saved figures are not put over it.
      await slow(page, "**/api/day**", 2500, async () => {
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "1");
        await page.waitForTimeout(300);
        await setAmount(page, "cash_sales", "77");
        await page.waitForTimeout(3500);
      });
      eq(await shownDate(page), d1, "M · 1 May is on screen");
      const typed = await blankReport(page);
      eq(JSON.stringify(typed.nonBlank), JSON.stringify(["in-cash_sales"]), "M · the saved figures were not put over the figure typed meanwhile");
      eq(await value(page, "#in-cash_sales"), "77.00", "M · which is still there");
      eq(await page.$eval("#chk-closed", (e) => e.checked), false, "M · still a Work day");
    });

    /* ---- N · Clear, Next day, scrolling --------------------------------------------------- */
    await section("N", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      await setAmount(page, "cash_sales", "100");
      await Promise.all([checkFor(page, d6).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      eq(await shownDate(page), d6, "N · Clear keeps the date");
      await assertBlank(page, "N (after Clear)");
      await page.fill("#in-cash_sales", "77");
      await Promise.all([checkFor(page, d6).catch(() => null), page.keyboard.press("Control+Alt+c")]);
      await page.waitForTimeout(400);
      eq(await shownDate(page), d6, "N · Ctrl+Alt+C keeps the date");
      await assertBlank(page, "N (after Ctrl+Alt+C)");
      await typeBalanced(page, "1300");
      let s = await clickSave(page);
      eq(s.status, 200, "N · 6 May is saved");
      await untilSavedShown(page);
      eq(await shownDate(page), d6, "N · Save stays on the day");
      eq(Number(await value(page, "#in-" + CLOSE)), 1300, "N · and the figures stay in the boxes");
      const [nres] = await Promise.all([
        page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: T }),
        page.click("#btn-next"),
      ]);
      eq(nres.status(), 200, "N · Next day is accepted for the saved day");
      await page.waitForTimeout(1200);
      eq(await shownDate(page), d7, "N · Next day lands on the following date");
      await assertBlank(page, "N (after Next day)");
      eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "in-" + OPEN, "N · with the cursor in the opening box");
      // the page does not scroll on a month change either
      await page.evaluate(() => window.scrollTo(0, 150));
      const y0 = await page.evaluate(() => window.scrollY);
      await pickVia(page, "month", 6);
      eq(await page.evaluate(() => window.scrollY), y0, "N · a month change does not scroll the page");

      // (2026-10-07) Next day onto a date that is in the books brings that day
      // up as saved, still with the cursor in the opening balance.
      await pick(page, d5);
      await asSaved(page, d5, "N · 5 May comes up as saved");
      const [nres2] = await Promise.all([
        page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: T }),
        checkFor(page, d6).catch(() => null),
        page.click("#btn-next"),
      ]);
      eq(nres2.status(), 200, "N · Next day is accepted for 5 May as saved");
      await page.waitForTimeout(700);
      eq(await shownDate(page), d6, "N · Next day lands on 6 May");
      await asSaved(page, d6, "N · which comes up as saved, figures and all");
      eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "in-" + OPEN, "N · with the cursor in the opening box");
      eq(await linkOn(page), false, "N · and no \"Show saved figures\"");
    });

    /* ---- O · in-flight guards --------------------------------------------------------------- */
    await section("O", async () => {
      await fresh();                           // MUTATE=1 only
      await pick(page, d6);
      // (2026-10-07) 6 May comes up as saved by itself; there is no link to press.
      eq(Number(await value(page, "#in-" + CLOSE)), 1300, "O · 6 May (saved) comes up with its figures");
      eq(await linkOn(page), false, "O · with no link to press");
      await page.waitForTimeout(500);
      let before = nexts.length;
      await slow(page, "**/api/next", 2500, async () => {
        await page.click("#btn-next");
        await page.waitForTimeout(300);
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "3");
        await page.waitForTimeout(3300);
      });
      check(nexts.length === before + 1, "O · Next day was really sent");
      eq(await shownDate(page), d3, "O · a date picked before Next day answered stands (no move to the next day)");
      eq(await dockSentence(page), null, "O · #dock-msg stays hidden");
      await assertBlank(page, "O (3 May)");

      // the same, with a refusal on its way (2026-10-07: 6 May comes up as
      // saved, so it is cleared first)
      await pick(page, d6);
      await Promise.all([checkFor(page, d6).catch(() => null), page.click("#btn-clear")]);
      await page.waitForTimeout(400);
      before = nexts.length;
      await slow(page, "**/api/next", 2500, async () => {
        await page.click("#btn-next");                      // the blank form is not what was saved: a 409
        await page.waitForTimeout(300);
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "3");
        await page.waitForTimeout(3300);
      });
      check(nexts.length === before + 1, "O · a refused Next day was sent");
      eq(await shownDate(page), d3, "O · the picked date stands after a refusal too");
      eq(await dockSentence(page), null, "O · and the refusal sentence is not shown for the new date");

      // Save with the check still on its way. Since 2026-10-06 Save is grey
      // until the check has answered, so the press is made from a green button
      // (a balanced, checked day) after a figure is changed with the check held
      // up: the press waits for that check, and the date changes meanwhile.
      await pick(page, d7);
      await setAmount(page, OPEN, "1300");
      await setAmount(page, CLOSE, "1300");
      await untilText(page, "#predicted", "The day balances.");
      await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: T });
      const nSaves = saves.length;
      await slow(page, "**/api/check", 2500, async () => {
        await setAmount(page, CLOSE, "1350");
        eq(await page.$eval("#btn-save", (b) => b.disabled), false, "O · Save is green when pressed, before the check answers");
        await page.evaluate(() => document.getElementById("btn-save").click());
        await page.waitForTimeout(300);
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "3");
        await page.waitForTimeout(3500);
      });
      eq(saves.length, nSaves, "O · no POST /api/save was sent for the date that was left");
      eq(await shownDate(page), d3, "O · and the date picked stands");
      eq(await dockSentence(page), null, "O · nothing is said under the buttons");
      eq(await bannerCount(page), 0, "O · and no banner");
      eq(await page.$eval("#btn-next", (b) => b.disabled), false, "O · Next day is usable again once its answer was ignored");

      // Save refused while another date is being picked: the refusal is held
      // back until the date has changed. A failed save is never kept quiet, so
      // the banner names the day it was about; nothing else of that day is shown.
      await pick(page, d7);
      await setAmount(page, OPEN, "1300");
      await setAmount(page, CLOSE, "1300");
      await untilText(page, "#predicted", "The day balances.");
      const held = saves.length;
      await page.route("**/api/save", async (route) => {
        await sleep(2500);
        await route.fulfill({ status: 409, contentType: "application/json",
          body: JSON.stringify({ ok: false, error: "The books changed while this was being saved.",
            findings: [{ level: 1, levelName: "Stop", code: "L1-C", field: CLOSE, title: "Closing Balance Not Entered", message: "held back on purpose" }] }) });
      });
      try {
        await page.evaluate(() => document.getElementById("btn-save").click());
        await page.waitForTimeout(600);
        await page.focus("#sel-day");
        await page.selectOption("#sel-day", "3");
        await untilText(page, "#banner-area", "was not saved");
      } finally { await page.unroute("**/api/save"); }
      check(saves.length === held + 1, "O · the save was really sent before the date changed");
      eq(await shownDate(page), d3, "O · the date picked while the save was on its way stands");
      eq(await page.$eval("#banner-area .banner span", (e) => e.textContent.trim()).catch(() => null), `${pretty(d7)} was not saved. The books changed while this was being saved.`,
         "O · a save refused after the date changed says so at the top, naming its day");
      eq((await rowTitles(page)).length, 0, "O · and none of that day's findings are put on the new date");
      eq(await hidden(page, "#dock-note"), true, "O · no explanation is opened for them");
      const late = await blankReport(page);
      check(late.nonBlank.length === 0 && late.marked.length === 0 && late.errs === 0 && late.outlines.length === 0 &&
            !late.reasonBoxes[0] && !late.reasonBoxes[1] && late.noteHidden && late.msgHidden && late.banners === 1,
            "O · the new date's form is still blank, with that one banner and nothing else", JSON.stringify(late));
      await pick(page, d5);
      eq(await bannerCount(page), 0, "O · the sentence goes on the next date change");
    });

    /* ---- Q · console, 1536 ----------------------------------------------------------------------- */
    check(errors.length === 0, "Q · no console or page errors at 1536", errors.slice(0, 3).join(" | "));
    await ctx.close();

    /* ---- P · 390 px --------------------------------------------------------------------------------- */
    await section("P", async () => {
      const ctx2 = await mkCtx({ width: 390, height: 844 }, 2);
      const p2 = await ctx2.newPage();
      const saves2 = [], nexts2 = [];
      listen(p2, errors2, saves2, nexts2);
      await Promise.all([checkFor(p2, today), p2.goto(BASE)]);
      await p2.waitForSelector("#in-" + OPEN);
      eq(await p2.$eval("#checks", (e) => e.classList.contains("open")), false, "P · at 390 the Checks sheet starts closed");

      // B at 390
      await pick(p2, d12);
      await typeBalanced(p2, "1300");
      let s = await clickSave(p2);
      eq(s.status, 200, "P/B · 12 May (11 May missing) is saved at 390");
      check(await untilText(p2, "#dock-msg", `${pretty(d12)} saved to the books.`), "P/B · #dock-msg says it (the panel is hidden here)");
      check(await untilVisible(p2, "#dock-status", true), "P/B · the pill shows the waiting-ledger check");
      await p2.click("#dock-status");
      check(await p2.waitForFunction(() => document.getElementById("checks").classList.contains("open"), null, { timeout: 5000 }).then(() => true).catch(() => false), "P/B · the pill opens the sheet");
      check((await rowTitles(p2)).includes(WAITING), "P/B · \"Ledger waiting on the day before\" is in the sheet", JSON.stringify(await rowTitles(p2)));

      // C at 390
      await pick(p2, d11);
      eq(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")), false, "P/C · after a date change the sheet is closed");
      await assertBlank(p2, "P/C (11 May)");
      eq((await rowTitles(p2)).length, 0, "P/C · the list has no rows");
      eq(await hidden(p2, "#dock-status"), true, "P/C · and the pill is hidden");
      eq(await linkOn(p2), false, "P/C · no link on an unsaved date");

      // D at 390 (2026-10-07: 12 May comes up as saved, over a figure typed on
      // 11 May; after Clear the link cannot be opened here with no rows, so
      // only its state is read)
      await setAmount(p2, "cash_sales", "5");
      await pick(p2, d12);
      await asSaved(p2, d12, "P/D · 12 May comes up as saved at 390");
      eq(await hidden(p2, "#checks-load"), true, "P/D · the link is hidden on a date change (DOM state)");
      check((await rowTitles(p2)).includes(WAITING), "P/D · the sheet holds \"Ledger waiting on the day before\" for the figures on screen", JSON.stringify(await rowTitles(p2)));
      eq(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")), false, "P/D · and stays closed");
      await Promise.all([checkFor(p2, d12).catch(() => null), p2.click("#btn-clear")]);
      await p2.waitForTimeout(400);
      await assertBlank(p2, "P/D (12 May, cleared)");
      eq(await hidden(p2, "#checks-load"), false, "P/D · after Clear the link is not hidden for the saved pending day (DOM state; the sheet cannot be opened without rows)");
      eq((await rowTitles(p2)).length, 0, "P/D · no rows for the blank pending day");
      await p2.evaluate(() => document.getElementById("checks-load").click());
      await p2.waitForTimeout(1500);
      eq(Number(await value(p2, "#in-" + CLOSE)), 1300, "P/D · pressing it loads the saved figures");

      // F at 390
      await pick(p2, d14);
      await Promise.all([checkFor(p2, d14).catch(() => null), p2.click(".daytype-toggle .opt-closed")]);
      s = await clickSave(p2);
      eq(s.status, 200, "P/F · 14 May is saved as an Off day at 390");
      check(await untilText(p2, "#dock-msg", `${pretty(d14)} saved to the books.`), "P/F · #dock-msg says it (the panel is hidden here)");
      await pick(p2, d15);
      eq(await p2.$eval("#chk-closed", (e) => e.checked), false, "P/F · picking 15 May: the Off day switch is off");
      await assertBlank(p2, "P/F (15 May)");
      // (2026-10-07) 14 May comes up as the saved Off day, over an opening
      // balance typed on 15 May.
      await fresh(p2);                         // MUTATE=1 only
      await setAmount(p2, OPEN, "1300");
      await pick(p2, d14);
      eq(await p2.$eval("#chk-closed", (e) => e.checked), true, "P/F · picking 14 May again: it comes up as an Off day, switch on");
      await asSaved(p2, d14, "P/F · with every box blank");
      eq(await hidden(p2, "#checks-load"), true, "P/F · the link is hidden on a date change (DOM state)");
      await Promise.all([checkFor(p2, d14).catch(() => null), p2.click("#btn-clear")]);
      await p2.waitForTimeout(400);
      await assertBlank(p2, "P/F (14 May, cleared: Work-day blank)");
      eq(await hidden(p2, "#checks-load"), false, "P/F · after Clear the link is not hidden for the saved Off day (DOM state)");
      // The sheet cannot be opened with no rows, so the key is the way to it here.
      await Promise.all([checkFor(p2, d14).catch(() => null), p2.keyboard.press("Control+Alt+z")]);
      await p2.waitForTimeout(500);
      eq(await p2.$eval("#chk-closed", (e) => e.checked), true, "P/F · Ctrl+Alt+Z brings the Off day back though the sheet is closed");
      eq(await hidden(p2, "#checks-load"), true, "P/F · and the link hides again");
      check(errors2.length === 0, "Q · no console or page errors at 390", errors2.slice(0, 3).join(" | "));
      await ctx2.close();
    });
  } finally {
    await browser.close();
  }

  console.log(`\n${pass} pass, ${fail} fail${MUTATE ? "  (MUTATE=1: the old onDateChange)" : ""}`);
  if (fail) { console.log("FAILED CHECKS:"); failed.forEach((f) => console.log("  - " + f)); }
  console.log(fail === 0 ? "ALL PASS" : `${fail} FAILED`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.log("FAIL  the script itself stopped: " + ((e && e.stack) || e)); process.exit(2); });
