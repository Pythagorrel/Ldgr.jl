/* verify-save-gate-2026-10-06.mjs — browser verification of the owner's decision
   of 2026-10-06: the Save button follows the server's verdict. Plain
   JavaScript, no build step, same style as verify-date-change-2026-10-06.mjs.

   THE CONTRACT (the owner's words: "a blank form is not a valid save state"):
     R1  While the server's latest check for the figures on screen holds a Must
         fix, Save is greyed out, whether or not the Checks panel is showing the
         row yet (a blank drawer count nobody has reached is still a Must fix).
         A click or Ctrl+S on the grey button sends nothing, but it does say
         why: the held-back row appears, the server's sentence goes to the top
         and the explanation opens in the dock, beside the button (part M).
     R2  While a difference applies and its own reason is blank, Save is greyed
         out, even while the cursor is still in the box with the difference and
         the reason box is held back. Once the reason is typed, Save is green.
     R3  Notices (a gap, a day already saved, an Off day, a day after on record)
         never grey Save and never stop a save. The first-day tick still does.
     R4  Save is green only once the server has looked at the figures: a form
         that has just been reset starts grey. That includes a saved day coming
         up by itself (2026-10-07): picking its date blanks the form at once,
         grey while the server is asked for the day, and the saved figures then
         stay grey until their own check answers. The one moment a press can run
         into a Must fix is the half-second before a check answers; the form
         then greys Save and gives the server's own answer in the dock, beside
         the button, and takes it down once a check finds the day clean.
     R5  A press that runs into a difference in that moment asks for the reason
         and sends nothing. When the check itself cannot reach the server, Save
         follows the last answer and the press is answered by the server. A
         press on the grey button while the figures have changed since the last
         answer (the closing balance typed and Ctrl+S at once) waits for the
         check and then saves, so the fast keyboard flow needs one press.
     R6  The rows keep their timing: a held-back row appears when its box is
         left, including when the thing clicked is the grey Save button.

   LETTERS in the labels (A..N) are the parts:
     A blank forms  B a balance not entered  C expenses over cash  D two Must
     fix  E a difference held back  F a saved day edited  G the race  H Off day
     and a dead server  I notices  J the first-day tick  K 390 px  L console
     M a press on the grey button says why  N grey until the server has looked

   UPDATED 2026-10-07: a saved day now comes up with its figures by itself when
   its date is picked, and "Show saved figures" shows only after Clear on a
   saved day. F and I no longer press the link after picking 3 June; N still
   presses it, after Clear, and also picks a saved date while the server is
   slow to answer (R4).

   MUTATION PROOF:  MUTATE=1 serves app.js with the server's verdict taken out
   of formValid() (the form as it was before 2026-10-06). The real file is never
   edited. The "greyed out" checks (A to F, and those of G, H, K, M and N) fail
   then, and nothing else does: 133 checks, 108 pass, 25 fail on 2026-10-06;
   138 checks, 111 pass, 27 fail on 2026-10-07 (the two new ones are N's grey
   while a saved day is looked up and while its check is on its way). Without
   MUTATE all 138 pass.

   HOW TO RUN (never against the real Records folder):
     1. A scratch server: LEDGER_ROOT=<scratch>, LDGR_NO_BROWSER=1,
        LDGR_NO_DIGEST=1, LDGR_NOTIFY_CONFIG=<a file that does not exist>,
        julia --startup-file=no server.jl <port>
     2. npm i playwright-core@1 in a scratch folder, copy this file there, then
        BASE=http://127.0.0.1:<port> LEDGER_ROOT=<the same scratch> OUT=<shots> \
          node verify-save-gate-2026-10-06.mjs          (add MUTATE=1 for the proof)
     The script empties the books when it starts and refuses a path that
     mentions "Records". Dates are in June 2026; 1 June is seeded by the API
     as the first day on record. */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE   = process.env.BASE || "http://127.0.0.1:8771";
const SHOTS  = path.resolve(process.env.OUT || "shots");
const MUTATE = !!process.env.MUTATE;
const T      = MUTATE ? 6000 : 25000;
fs.mkdirSync(SHOTS, { recursive: true });

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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const getJSON = async (p) => (await fetch(BASE + p)).json();
const post = (p, body) => fetch(BASE + p, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

function emptyBooks() {
  const root = process.env.LEDGER_ROOT;
  if (!root) { console.log("FAIL  LEDGER_ROOT must be set to the server's scratch folder"); process.exit(2); }
  if (/records/i.test(root)) { console.log("FAIL  refusing to empty a folder whose path mentions Records: " + root); process.exit(2); }
  for (const entry of fs.readdirSync(root)) fs.rmSync(path.join(root, entry), { recursive: true, force: true });
}

/* ---------------------------------------------------------------------- */
const OPEN = "opening_balance", CLOSE = "closing_balance";
const amounts = (o) => ({ cash_sales: 0, POS_Scotia: 0, POS_RBL: 0, POS_U: 0, doctor_fees: 0, medical_supply_costs: 0,
                          miscellaneous_costs: 0, taxi_fare: 0, deposits: 0, Mr_Boyle: 0, opening_balance: null, closing_balance: null, ...o });
const seed = (date, o, extra = {}) => post("/api/save", { date, amounts: amounts(o), reason: "", openingReason: "", allowGenesis: true, force: true, ...extra });

const disabled = (page) => page.$eval("#btn-save", (b) => b.disabled);
const rowTitles = (page) => page.$$eval("#checks-list li .check-title", (n) => n.map((x) => x.textContent.trim()));
const hidden = (page, sel) => page.$eval(sel, (e) => e.hidden).catch(() => true);
const bannerText = (page) => page.$eval("#banner-area", (e) => e.textContent.trim());
const noteText = (page) => page.$eval("#dock-note", (e) => (e.hidden ? "" : e.textContent.trim()));
const activeId = (page) => page.evaluate(() => (document.activeElement && document.activeElement.id) || "");
const untilDisabled = (page, want, ms = T) => page.waitForFunction((v) => document.getElementById("btn-save").disabled === v, want, { timeout: ms }).then(() => true).catch(() => false);
const untilRow = (page, title, on = true, ms = T) => page.waitForFunction(([t, v]) =>
  [...document.querySelectorAll("#checks-list .check-title")].some((n) => n.textContent.trim() === t) === v,
  [title, on], { timeout: ms }).then(() => true).catch(() => false);
const untilText = (page, sel, needle, ms = T) => page.waitForFunction(
  ([s, t]) => { const n = document.querySelector(s); return !!n && !n.hidden && n.textContent.includes(t); },
  [sel, needle], { timeout: ms }).then(() => true).catch(() => false);
const checkFor = (page, iso) => page.waitForResponse((r) => {
  if (!r.url().includes("/api/check")) return false;
  try { return JSON.parse(r.request().postData() || "{}").date === iso; } catch { return false; }
}, { timeout: T });
// The check for exactly the figures on screen has answered and been drawn.
const settled = async (page) => {
  await page.waitForFunction(() => {
    const amounts = {};
    document.querySelectorAll("#slot-opening input, #groups-activity input, #slot-closing input").forEach((i) => {
      const raw = i.value.trim();
      const cash = i.dataset.key === "opening_balance" || i.dataset.key === "closing_balance";
      amounts[i.dataset.key] = raw === "" ? (cash ? null : 0) : Number(raw);
    });
    return window.__ldgrCheckedFor === JSON.stringify(amounts);
  }, null, { timeout: T }).catch(() => {});
  await sleep(150);
};

async function pick(page, iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const cur = await page.evaluate(() => `${document.getElementById("sel-year").value}-${String(document.getElementById("sel-month").value).padStart(2, "0")}-${String(document.getElementById("sel-day").value).padStart(2, "0")}`);
  if (cur === iso) return;
  const w = checkFor(page, iso).catch(() => null);
  const [cy, cm] = cur.split("-").map(Number);
  if (y !== cy) { await page.focus("#sel-year"); await page.selectOption("#sel-year", String(y)); }
  if (m !== cm) { await page.focus("#sel-month"); await page.selectOption("#sel-month", String(m)); }
  if (Number(await page.$eval("#sel-day", (e) => e.value)) !== d) { await page.focus("#sel-day"); await page.selectOption("#sel-day", String(d)); }
  await w; await sleep(150);
}
// Real typing into a box; the cursor stays in it.
async function type(page, key, text) {
  await page.click("#in-" + key);
  await page.keyboard.press("Control+A");
  if (text === "") await page.keyboard.press("Backspace"); else await page.keyboard.type(text);
}
// Type and leave the box with Tab, then wait for the check of what is on screen.
async function typeLeave(page, key, text) { await type(page, key, text); await page.keyboard.press("Tab"); await settled(page); }
// A real mouse click at the centre of Save, whether or not it is greyed out.
async function clickSave(page) {
  const b = await page.$("#btn-save"); await b.scrollIntoViewIfNeeded();
  const bb = await b.boundingBox();
  const under = await page.evaluate(([x, y]) => { const e = document.elementFromPoint(x, y); return e && e.id; }, [bb.x + bb.width / 2, bb.y + bb.height / 2]);
  if (under !== "btn-save") throw new Error("the click would land on " + under);
  await page.mouse.click(bb.x + bb.width / 2, bb.y + bb.height / 2);
  await sleep(600);
}
const ctrlS = async (page) => { await page.keyboard.press("Control+s"); await sleep(600); };
const inBooks = async (iso) => (await getJSON("/api/day?date=" + iso)).day;

/* ---------------------------------------------------------------------- */
(async () => {
  emptyBooks();
  const seeded = await seed("2026-06-01", { cash_sales: 1000, opening_balance: 0, closing_balance: 1000 });
  eq(seeded.status, 200, "set-up · 1 June is the first day on record, closing 1,000");

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const errors = [], errors2 = [];
  try {
    const mkCtx = async (viewport, dsf) => {
      const ctx = await browser.newContext({ viewport, deviceScaleFactor: dsf, acceptDownloads: false });
      await ctx.route("**/app.js*", async (route) => {
        const res = await route.fetch();
        let body = await res.text();
        // The suite reads what the last answered check was for.
        // v6.0: the packaged app serves app.js minified (esbuild keeps top-level and
        // property names, renames locals), so the same assignment is found by a
        // pattern there. Neither found: stop, rather than wait 25 s at every step.
        const plain = "state.checkedFor = closed ? null : JSON.stringify(body.amounts);";
        const minified = /state\.checkedFor=\w+\?null:JSON\.stringify\(\w+\.amounts\)/;
        if (body.includes(plain)) body = body.replace(plain, plain + " window.__ldgrCheckedFor = state.checkedFor;");
        else if (minified.test(body)) body = body.replace(minified, "$&,window.__ldgrCheckedFor=state.checkedFor");
        else throw new Error("the checkedFor hook did not apply: app.js has changed");
        if (MUTATE) {
          // The OLD behaviour: the button never read the server's verdict.
          body = body.replace("if (serverBlocks()) return false;", "/* mutated: no server verdict */");
          if (!body.includes("mutated")) throw new Error("the mutation did not apply");
        }
        await route.fulfill({ response: res, body, headers: { ...res.headers(), "content-type": "application/javascript" } });
      });
      return ctx;
    };
    const ctx = await mkCtx({ width: 1536, height: 730 }, 1.25);
    const page = await ctx.newPage();
    const saves = [];
    page.on("response", async (r) => { if (r.url().includes("/api/save")) saves.push({ status: r.status(), date: JSON.parse(r.request().postData() || "{}").date }); });
    page.on("console", (m) => { if (m.type() === "error" && !/favicon|\b400\b|ERR_FAILED/.test(m.text())) errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
    await page.goto(BASE); await sleep(800);

    /* ---- A · blank forms --------------------------------------------- */
    await section("A · blank forms", async () => {
      eq(await disabled(page), true, "A · a fresh page on today's date has Save greyed out");
      await pick(page, "2026-06-02"); await settled(page);
      eq(await disabled(page), true, "A · a blank form on a past date has Save greyed out");
      eq((await rowTitles(page)).length, 0, "A · with no row in the Checks panel (the blank counts are held back)");
      const n = saves.length;
      await clickSave(page); eq(saves.length, n, "A · a click on the grey button sends nothing");
      eq(await untilRow(page, "Opening Balance Not Entered"), true, "A · but it says why: the held-back rows appear");
      eq(await bannerText(page), "This day cannot be saved yet.", "A · the server's sentence at the top");
      eq(await activeId(page), "dock-note", "A · and the explanation in the dock, with the cursor on it");
      await ctrlS(page);     eq(saves.length, n, "A · Ctrl+S sends nothing either");
      await page.click("#btn-clear"); await settled(page);
      eq(await disabled(page), true, "A · Clear leaves Save greyed out");
      const look = await page.$eval("#btn-save", (b) => { const c = getComputedStyle(b); return { opacity: c.opacity, cursor: c.cursor }; });
      check(Number(look.opacity) < 1 && look.cursor === "not-allowed", "A · the greyed button really looks greyed out", JSON.stringify(look));
    });

    /* ---- B · a balance not entered ------------------------------------- */
    await section("B · a balance not entered", async () => {
      await typeLeave(page, "cash_sales", "500");
      eq(await disabled(page), true, "B · takings typed, neither balance visited: greyed out");
      eq((await rowTitles(page)).length, 0, "B · still no row: the blank counts are held back from the panel");
      await typeLeave(page, OPEN, "1000");
      eq(await disabled(page), true, "B · opening typed, closing never visited: greyed out");
      await page.click("#in-" + CLOSE); await page.keyboard.press("Tab"); await settled(page);
      eq(await untilRow(page, "Closing Balance Not Entered"), true, "B · the closing box left blank: its row appears");
      eq(await disabled(page), true, "B · and Save is greyed out");
      const n = saves.length;
      await clickSave(page); eq(saves.length, n, "B · a click sends nothing");
      await type(page, CLOSE, "1500"); await settled(page);
      eq(await disabled(page), false, "B · the closing typed and the day balances: Save is green, cursor still in the box");
      await type(page, CLOSE, ""); await settled(page);
      eq(await disabled(page), true, "B · deleted again: greyed out");
      await typeLeave(page, CLOSE, "1500");
      eq(await disabled(page), false, "B · typed and left: green");
      await clickSave(page);
      eq(saves.length, n + 1, "B · a click on the green button saves");
      eq(saves[saves.length - 1].status, 200, "B · …and the server accepts (200)");
      check(!!(await inBooks("2026-06-02")), "B · 2 June is in the books");
      await page.screenshot({ path: path.join(SHOTS, "B-saved.png") });
    });

    /* ---- C · expenses over cash ---------------------------------------- */
    await section("C · expenses over cash", async () => {
      await pick(page, "2026-06-03"); await settled(page);
      await typeLeave(page, OPEN, "1500");
      await typeLeave(page, "cash_sales", "200");
      await typeLeave(page, CLOSE, "1700");
      eq(await disabled(page), false, "C · a balanced day: green");
      await type(page, "taxi_fare", "5000"); await settled(page);
      eq(await untilRow(page, "Expenses exceed total cash"), true, "C · taxi 5,000: the Must fix row shows");
      eq(await disabled(page), true, "C · and Save is greyed out, cursor still in the box");
      await page.keyboard.press("Tab"); await settled(page);
      eq(await disabled(page), true, "C · still greyed out after leaving the box");
      const n = saves.length;
      await clickSave(page); eq(saves.length, n, "C · a click sends nothing");
      await ctrlS(page);     eq(saves.length, n, "C · Ctrl+S sends nothing");
      eq(await bannerText(page), "This day cannot be saved yet.", "C · the press is answered with the server's sentence");
      check((await noteText(page)).includes("Expenses, deposits and Mr. Boyle"), "C · and the Must fix's explanation in the dock", await noteText(page));
      await typeLeave(page, "taxi_fare", "");
      eq(await untilRow(page, "Expenses exceed total cash", false), true, "C · put right: the row goes");
      eq(await disabled(page), false, "C · and Save is green again");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "C · the save goes through (200)");
    });

    /* ---- D · two Must fix at once -------------------------------------- */
    await section("D · two Must fix at once", async () => {
      await pick(page, "2026-06-04"); await settled(page);
      await typeLeave(page, OPEN, "1700");
      await typeLeave(page, "taxi_fare", "5000");             // closing never visited: L1-C + L1-B
      eq(await disabled(page), true, "D · a blank closing and expenses over cash: greyed out");
      await typeLeave(page, "taxi_fare", "");
      eq(await disabled(page), true, "D · one of the two put right: still greyed out (the closing is still blank)");
      const n = saves.length;
      await clickSave(page); eq(saves.length, n, "D · a click sends nothing");
      await typeLeave(page, CLOSE, "1700");
      eq(await disabled(page), false, "D · both put right: green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "D · and it saves");
    });

    /* ---- E · a difference held back ------------------------------------ */
    await section("E · a difference held back", async () => {
      await pick(page, "2026-06-05"); await settled(page);
      await typeLeave(page, OPEN, "1700");
      await typeLeave(page, "cash_sales", "500");
      await type(page, CLOSE, "2000"); await settled(page);      // 200 short, cursor still in the box
      eq(await hidden(page, "#reason-box"), true, "E · the reason box is held back while the cursor is in the closing box");
      eq((await rowTitles(page)).includes("Day doesn't balance"), false, "E · and so is the row");
      eq(await disabled(page), true, "E · but Save is greyed out");
      const n = saves.length;
      await clickSave(page);
      eq(saves.length, n, "E · a click on the grey button sends nothing");
      eq(await hidden(page, "#reason-box"), false, "E · the click left the box, so the reason box appears (R6)");
      eq(await untilRow(page, "Day doesn't balance"), true, "E · with its row");
      await page.fill("#txt-reason", "   "); await sleep(200);
      eq(await disabled(page), true, "E · spaces are not a reason: still greyed out");
      await page.fill("#txt-reason", "200 short, reported"); await sleep(200);
      eq(await disabled(page), false, "E · a reason typed: green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "E · the save goes through");
      const day = await inBooks("2026-06-05");
      eq(day && day.reason, "200 short, reported", "E · with the reason stored");

      // L2-B with the opening typed last (prior close 2,000).
      await pick(page, "2026-06-06"); await settled(page);
      await typeLeave(page, "cash_sales", "100");
      await typeLeave(page, CLOSE, "2200");
      await type(page, OPEN, "2100"); await settled(page);        // 100 more than last close, cursor in the box
      eq(await hidden(page, "#opening-reason-box"), true, "E · opening typed last: its reason box is held back");
      eq(await disabled(page), true, "E · and Save is greyed out");
      await page.keyboard.press("Tab"); await settled(page);
      eq(await hidden(page, "#opening-reason-box"), false, "E · leaving the box brings the reason box up");
      await page.fill("#txt-opening-reason", "float added"); await sleep(200);
      eq(await disabled(page), false, "E · the opening reason typed: green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "E · saved with the opening reason");
    });

    /* ---- F · a saved day edited into a Must fix ------------------------ */
    await section("F · a saved day edited into a Must fix", async () => {
      await pick(page, "2026-06-03"); await settled(page);       // a saved day comes up by itself (2026-10-07)
      eq(await page.$eval("#in-" + CLOSE, (e) => e.value), "1700.00", "F · picking 3 June brings its saved figures back");
      eq(await disabled(page), false, "F · the saved day as it stands: green");
      const was = JSON.stringify(await inBooks("2026-06-03"));
      await typeLeave(page, "deposits", "9000");
      eq(await untilRow(page, "Expenses exceed total cash"), true, "F · deposits 9,000: the Must fix row");
      eq(await disabled(page), true, "F · Save greyed out");
      const n = saves.length;
      await clickSave(page); eq(saves.length, n, "F · a click sends nothing");
      eq(JSON.stringify(await inBooks("2026-06-03")), was, "F · the saved row is untouched");
      await typeLeave(page, "deposits", "");
      eq(await disabled(page), false, "F · put right: green");
    });

    /* ---- G · the race ---------------------------------------------------- */
    await section("G · the race (a press in the moment before the check answers)", async () => {
      await pick(page, "2026-06-07"); await settled(page);
      await typeLeave(page, OPEN, "2200");
      await typeLeave(page, "cash_sales", "300");
      await typeLeave(page, CLOSE, "2500");
      eq(await disabled(page), false, "G · a balanced, checked day: green");
      await page.route("**/api/check", async (route) => { await sleep(1500); await route.continue().catch(() => {}); });
      await page.fill("#in-deposits", "9000");                  // expenses over cash, check held up
      eq(await disabled(page), false, "G · Save is still green before the check answers");
      const n = saves.length;
      await clickSave(page); await sleep(2200);
      eq(saves.length, n, "G · the press waited for its check and sent nothing");
      eq(await bannerText(page), "This day cannot be saved yet.", "G · the server's own sentence, at the top");
      check((await noteText(page)).includes("Expenses, deposits and Mr. Boyle"), "G · and the explanation opens in the dock", await noteText(page));
      eq(await activeId(page), "dock-note", "G · with the cursor on it, beside the button");
      eq(await disabled(page), true, "G · Save is greyed out now");
      await page.unroute("**/api/check");
      await typeLeave(page, "deposits", "");
      eq(await disabled(page), false, "G · put right: green");
      eq(await bannerText(page), "", "G · and the sentence is taken down");
      // The same moment with a difference instead of a Must fix.
      await page.route("**/api/check", async (route) => { await sleep(1500); await route.continue().catch(() => {}); });
      await page.fill("#in-" + CLOSE, "2600");                  // 100 over, check held up
      await clickSave(page); await sleep(2200);
      eq(saves.length, n, "G · a difference in that moment: nothing sent");
      eq(await bannerText(page), "Add a short reason before saving this day.", "G · the reason is asked for");
      eq(await activeId(page), "txt-reason", "G · cursor in the reason box");
      eq(await disabled(page), true, "G · Save greyed out until it is typed");
      await page.unroute("**/api/check");
      await page.fill("#txt-reason", "100 over"); await sleep(200);
      eq(await disabled(page), false, "G · reason typed: green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "G · and it saves");
    });

    /* ---- H · Off day, and a server that cannot be reached ---------------- */
    await section("H · Off day, and a server that cannot be reached", async () => {
      await pick(page, "2026-06-08"); await settled(page);
      eq(await disabled(page), true, "H · a blank Work day: greyed out");
      await page.click("label[for=chk-closed]"); await sleep(400);
      eq(await disabled(page), false, "H · switched to Off day: green at once (an Off day sends no figures)");
      await page.click("label[for=chk-closed]"); await settled(page);
      eq(await disabled(page), true, "H · back to Work day: greyed out again");
      await typeLeave(page, OPEN, "2600");
      await typeLeave(page, CLOSE, "2600");
      eq(await disabled(page), false, "H · a balanced day: green");
      await page.route("**/api/check", (route) => route.abort());
      await typeLeave(page, "cash_sales", "400");               // now 400 over, but no check can answer
      eq(await disabled(page), false, "H · the check cannot reach the server: Save follows the last answer (green)");
      const n = saves.length;
      await clickSave(page);
      eq(saves.length, n + 1, "H · the press sends the day");
      eq(saves[saves.length - 1].status, 400, "H · and the server refuses it (400)");
      eq(await hidden(page, "#reason-box"), false, "H · the refusal brings up the reason box");
      eq(await disabled(page), true, "H · and Save is greyed out");
      await page.unroute("**/api/check");
      await page.fill("#txt-reason", "400 over"); await sleep(200);
      await typeLeave(page, CLOSE, "3000");                     // balances again; the reason box goes
      eq(await disabled(page), false, "H · balanced again: green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "H · saved");
    });

    /* ---- I · notices never grey Save ------------------------------------- */
    await section("I · notices never grey Save", async () => {
      await pick(page, "2026-06-10"); await settled(page);        // 9 June missing: a gap
      await typeLeave(page, OPEN, "3000");
      await typeLeave(page, CLOSE, "3000");
      eq(await untilRow(page, "Ledger waiting on the day before"), true, "I · a gap: the notice shows");
      eq(await disabled(page), false, "I · and Save is green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "I · saved with its ledger waiting");
      await pick(page, "2026-06-09"); await settled(page);        // filling the gap: day after on record
      await typeLeave(page, OPEN, "3000");
      await typeLeave(page, CLOSE, "3000");
      eq(await untilRow(page, "Day after already on record"), true, "I · filling the gap: the notice shows");
      eq(await disabled(page), false, "I · Save green");
      await clickSave(page);
      eq(saves[saves.length - 1] && saves[saves.length - 1].status, 200, "I · saved");
      await pick(page, "2026-06-03"); await settled(page);        // comes up with its saved figures
      eq(await untilRow(page, "Day saved, ledger generated"), true, "I · a saved day loaded back: the notice shows");
      eq(await disabled(page), false, "I · Save green for a re-save");
      await pick(page, "2026-06-11"); await settled(page);
      await page.click("label[for=chk-closed]"); await sleep(400);
      eq(await untilRow(page, "Marked as closed"), true, "I · an Off day: the notice shows");
      eq(await disabled(page), false, "I · Save green");
    });

    /* ---- J · the first-day tick ------------------------------------------ */
    await section("J · the first-day tick", async () => {
      await pick(page, "2026-05-30"); await settled(page);        // before 1 June: a first day again
      await typeLeave(page, OPEN, "100");
      await typeLeave(page, CLOSE, "100");
      eq(await hidden(page, "#genesis-line"), false, "J · the first-day box is asked for");
      eq(await disabled(page), true, "J · unticked: greyed out");
      await page.check("#chk-genesis"); await sleep(200);
      eq(await disabled(page), false, "J · ticked: green");
      await page.uncheck("#chk-genesis"); await sleep(200);
      eq(await disabled(page), true, "J · unticked again: greyed out");
    });

    /* ---- M · a press on the grey button says why ------------------------ */
    // The grey button cannot save, but a press on it (click or Ctrl+S) still
    // does what the press used to do: it shows the held-back row and the
    // explanation beside the button. Keyboard and mouse behave the same.
    await section("M · a press on the grey button says why", async () => {
      // A drawer count never visited: nothing on screen says why Save is grey
      // until it is pressed (the box is empty, and that is all).
      await pick(page, "2026-06-13"); await settled(page);
      await typeLeave(page, "cash_sales", "200");
      await typeLeave(page, CLOSE, "200");
      eq(await disabled(page), true, "M · opening skipped: Save grey");
      eq((await rowTitles(page)).filter((t) => /Not Entered/.test(t)).length, 0, "M · and no Must fix row (the blank count is held back)");
      const n = saves.length;
      await clickSave(page);
      eq(saves.length, n, "M · a click on the grey button sends nothing");
      eq(await untilRow(page, "Opening Balance Not Entered"), true, "M · but it brings the held-back row up");
      eq(await bannerText(page), "This day cannot be saved yet.", "M · with the server's sentence at the top");
      check((await noteText(page)).includes("\"Opening Balance\" has not been filled in"), "M · and the explanation in the dock", await noteText(page));
      eq(await activeId(page), "dock-note", "M · cursor on the explanation, beside the button");
      await typeLeave(page, OPEN, "0");                                               // put right (first close was 0? no: prior close)
      // Ctrl+S on a grey button: the same, from the keyboard.
      await pick(page, "2026-06-14"); await settled(page);
      await typeLeave(page, OPEN, "3000");
      await typeLeave(page, "cash_sales", "500");
      await type(page, CLOSE, "3200"); await settled(page);                          // 300 short, cursor in the box, held back
      eq(await disabled(page), true, "M · a held-back difference: grey");
      await ctrlS(page);
      eq(saves.length, n, "M · Ctrl+S sends nothing");
      eq(await hidden(page, "#reason-box"), false, "M · but the reason box appears");
      eq(await activeId(page), "txt-reason", "M · with the cursor in it");
      eq(await bannerText(page), "Add a short reason before saving this day.", "M · and the reason banner at the top");
      // The fast keyboard flow: the closing typed and Ctrl+S at once, before
      // the check has answered. The button is grey for an answer that is out of
      // date, so the press waits for the check and then saves.
      await page.fill("#txt-reason", ""); await typeLeave(page, CLOSE, ""); await settled(page);  // blank again: grey for L1-C
      eq(await disabled(page), true, "M · the closing blank again: grey");
      await type(page, CLOSE, "3500");                                                // balances; no wait
      await page.keyboard.press("Control+s"); await sleep(1500);
      eq(saves.length, n + 1, "M · Ctrl+S straight after typing the closing balance saves the day");
      eq(saves[saves.length - 1].status, 200, "M · …accepted (200)");
      eq(await page.$eval("#in-" + CLOSE, (e) => e.value), "3500.00", "M · the figure was tidied and kept");
      // The same with an ordinary mouse click, held for 150 ms: the press is
      // answered as the pointer goes down, so the day is saved before the
      // button is released and Save is green by then; the release must not
      // save it a second time.
      await pick(page, "2026-06-15"); await settled(page);
      await typeLeave(page, OPEN, "3500");
      await typeLeave(page, "cash_sales", "100");
      await type(page, CLOSE, "3600");                                                // balances; no wait
      const b = await page.$("#btn-save"); await b.scrollIntoViewIfNeeded(); const bb = await b.boundingBox();
      await page.mouse.move(bb.x + bb.width / 2, bb.y + bb.height / 2);
      await page.mouse.down(); await sleep(150); await page.mouse.up(); await sleep(1500);
      eq(saves.length, n + 2, "M · a held click straight after typing the closing balance saves the day once");
      eq(saves[saves.length - 1].status, 200, "M · …accepted (200)");
      await clickSave(page);
      eq(saves.length, n + 3, "M · and the next ordinary click still saves (the swallowed click was this press's own)");
    });

    /* ---- N · grey until the server has looked (R4) ----------------------- */
    await section("N · grey until the server has looked", async () => {
      // A balanced saved day loaded back while the check is held up: grey
      // during the wait, green once it answers. The same for Off day -> Work
      // day on a balanced day. (Since 2026-10-07 picking 14 June brings it up
      // by itself; the link shows after Clear, which is what it is for now.)
      await pick(page, "2026-06-14"); await page.click("#btn-clear"); await settled(page);
      await page.route("**/api/check", async (route) => { await sleep(1500); await route.continue().catch(() => {}); });
      await page.click("#checks-load"); await sleep(400);
      eq(await page.$eval("#in-" + CLOSE, (e) => e.value), "3500.00", "N · Show saved figures put the day back");
      eq(await disabled(page), true, "N · Save is grey while its check is on its way");
      await sleep(2000);
      eq(await disabled(page), false, "N · and green once it has answered");
      await page.click("label[for=chk-closed]"); await sleep(200);
      eq(await disabled(page), false, "N · Off day: green at once");
      await page.click("label[for=chk-closed]"); await sleep(400);
      eq(await disabled(page), true, "N · back to Work day: grey while the check is on its way");
      await sleep(2000);
      eq(await disabled(page), false, "N · green once it has answered");
      await page.unroute("**/api/check");
      // A saved day coming up by itself (2026-10-07), with the server slow to
      // answer both questions: the form is blank and grey while the day is
      // looked up, and the saved figures stay grey until their check answers.
      await pick(page, "2026-06-13"); await settled(page);          // not saved
      const slow = async (route) => { await sleep(2000); await route.continue().catch(() => {}); };
      await page.route("**/api/day*", slow);
      await page.route("**/api/check", slow);
      await page.focus("#sel-day"); await page.selectOption("#sel-day", "15"); await sleep(400);
      eq(await page.$eval("#in-" + CLOSE, (e) => e.value), "", "N · 15 June picked: the form is blank while the server is asked for the day");
      eq(await disabled(page), true, "N · and Save is grey");
      await sleep(2400);
      eq(await page.$eval("#in-" + CLOSE, (e) => e.value), "3600.00", "N · then 15 June comes up with its saved figures");
      eq(await disabled(page), true, "N · Save is still grey while their check is on its way");
      await sleep(2400);
      eq(await disabled(page), false, "N · and green once it has answered");
      await page.unroute("**/api/day*"); await page.unroute("**/api/check");
    });

    /* ---- L · console (1536) ---------------------------------------------- */
    check(errors.length === 0, "L · no console errors at 1536", errors.slice(0, 3).join(" | "));
    await ctx.close();

    /* ---- K · 390 px ------------------------------------------------------ */
    await section("K · 390 px", async () => {
      const ctx2 = await mkCtx({ width: 390, height: 800 }, 3);
      const p2 = await ctx2.newPage();
      const saves2 = [];
      p2.on("response", async (r) => { if (r.url().includes("/api/save")) saves2.push(r.status()); });
      p2.on("console", (m) => { if (m.type() === "error" && !/favicon|\b400\b/.test(m.text())) errors2.push(m.text()); });
      p2.on("pageerror", (e) => errors2.push("pageerror: " + e.message));
      await p2.goto(BASE); await sleep(800);
      await pick(p2, "2026-06-12"); await settled(p2);
      eq(await disabled(p2), true, "K · a blank form at 390 px: greyed out");
      await typeLeave(p2, OPEN, "3000");
      await typeLeave(p2, "taxi_fare", "9000");
      eq(await disabled(p2), true, "K · expenses over cash with the closing blank: greyed out");
      await clickSave(p2); eq(saves2.length, 0, "K · a click sends nothing");
      await typeLeave(p2, "taxi_fare", "");
      await typeLeave(p2, CLOSE, "3000");
      eq(await disabled(p2), false, "K · put right: green");
      await clickSave(p2);
      eq(saves2[saves2.length - 1], 200, "K · and it saves");
      check(errors2.length === 0, "L · no console errors at 390", errors2.slice(0, 3).join(" | "));
      await ctx2.close();
    });
  } finally {
    await browser.close();
  }

  console.log(`\n${pass} passed, ${fail} failed${MUTATE ? "  (MUTATE=1: the 'greyed out' checks are expected to fail)" : ""}`);
  if (failed.length) console.log(failed.map((f) => "  - " + f).join("\n"));
  process.exit(fail && !MUTATE ? 1 : 0);
})();
