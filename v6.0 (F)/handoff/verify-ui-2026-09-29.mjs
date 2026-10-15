/* verify-ui-2026-09-29.mjs — browser verification of the owner's simplification
   of 2026-09-29. Plain JavaScript, no build step, same style as
   verify-save-next.mjs (which covers the Save / Next day flow itself).

   WHAT CHANGED, and what this walks:
     1  the header reads "LDGR" with the caption "Urgent Care", and the window
        title is "LDGR" (it used to say "Daily Entry" and a longer caption);
        since 2026-10-09 the header is the image header.svg, alt "LDGR Urgent Care"
     2  the top banner "<date> saved to the books. Saving again will replace it."
        and its "Edit that day" button are gone: nothing at all is said at the
        top after a successful save. The Checks row "Day saved, ledger
        generated" (meta "Good to know") says it instead
     3  the full explanation of that row (See full explanation) is exactly:
        "A ledger has already been generated for <date>. Before importing into
        QuickBooks, confirm that no journal already exists for this date. If
        there is a QB journal already, delete that journal before importing a
        new one with updated numbers and/or accounts. If the numbers match,
        there is no need to change the QB records."
     4  the grey note #checks-regen ("Saving again will regenerate the ledgers
        with the current figures and accounts.") sits inside #checks, shows only
        for a Work day that already has a ledger, and is not counted in
        #checks-count
     5  there is no "replace the ledger file" tick box anywhere; every save sends
        force:true, so a re-save with a changed figure rewrites the daily ledger
        CSV, and "NOT been overwritten" never appears
     6  a saved Off day, like a Work day whose day before is missing (its
        ledger waits), is confirmed by the grey note #checks-saved ("This day
        has been saved. Saving again will rewrite it with the current
        figures."; on an Off day only "This day has been saved.", as it has no
        figures on screen), with #dock-msg empty while the Checks panel is visible. The
        line "<date> saved to the books." under the buttons is only for a window
        under 1100 px, where the panel is hidden (checked at 390 with an Off day)
     7  the refusal banners at the top are unchanged, word for word
     8  keyboard: Ctrl+S saves (also from inside a box mid-typing), does nothing
        when Save is greyed and opens no browser dialog; Ctrl+N moves to the
        next day, or refuses into #dock-msg; Ctrl+Alt+C clears and keeps the date;
        Ctrl+Alt+Z presses "Show saved figures" when it is showing (also from
        inside a box mid-typing, and at 390 with the Checks sheet closed) and
        does nothing at all when it is not, asking the server nothing; all four
        are swallowed by the form
     9  no console errors, no horizontal scrolling at 1536 and 390, no warning
        codes on screen, nothing floating over the page
    10  "Show saved figures", a quiet link in the Checks sidebar under the grey
        notes (it still shows when they are hidden), with the tooltip "Show saved
        figures (Ctrl+Alt+Z)" and aria-keyshortcuts "Control+Alt+Z". Since
        2026-10-07 it shows ONLY after Clear on a date that is in the books (an
        Off day and a day whose ledger waits included), and typing after Clear
        keeps it. It never shows on arriving at a date (a saved date comes up as
        saved by itself), after a figure is changed, or after Clear on a date
        that is not in the books; and it goes on a date change, Next day, a good
        load and a successful save, without coming back when the person returns
        to the date. It is not a check, so it is not in #checks-count, the narrow
        pill or the screen-reader line. Pressing it restores the figures (over
        anything typed since Clear), both reasons and the Off day switch, scrolls
        to the top and puts the cursor in the opening box on a Work day; no
        banner, no editing mode, no #btn-cancel-edit. A load that fails, or finds
        no day, says one plain sentence right under the link (never the top
        banner), taken down on the next date change, Clear or good load
    12  a date change clears the form like Clear, and a date already in the
        books then comes up as it was saved (updated 2026-10-06 and 2026-10-07;
        see below): nothing of the old day is left either way
    11  Esc closes an open full explanation like its X does (cursor back on its
        "See full explanation" link); with nothing open it does nothing and is
        not swallowed; on the 390px Checks sheet it still closes the sheet. The
        X has title "Close (Esc)" and aria-keyshortcuts "Escape"

   UPDATED 2026-10-06: a date change now clears the form. Picking another date
   (day, month or year list) gives exactly what Clear gives on that date: blank
   boxes, both reasons hidden and empty, Work day, first-day tick off, no open
   explanation, nothing under the buttons or the link, the narrow sheet closed,
   focus left on the list. The older rule "changing the date keeps the typed
   figures and the Off day setting" is reversed by the owner. So: the part 7
   "bounce" only changes date and each block re-types its figures; the Clear
   presses and the "put the Off day back" step that only emptied what a date
   change used to keep are gone; part 12 (new) walks the clearing itself, and
   the 390px part closes the open sheet with a date change.

   UPDATED 2026-10-07 (the owner's two requests of that day): a date that is
   already in the books comes up AS SAVED whenever the form lands on it (page
   load, any of the three date lists, Next day): a Work day with its figures
   and both reasons, an Off day with the switch on and every box blank. Only a
   date that is not in the books comes up blank. "Show saved figures" is no
   longer how a saved day comes back; it shows only after Clear on a saved
   date, and Ctrl+Alt+Z presses it. And a saved Off day is confirmed by the
   grey note #checks-saved, so #dock-msg says nothing after saving one on a
   wide window. So: part 6 checks the grey note for the Off day (and the 390px
   part checks the dock line where the panel is hidden); part 10 reaches the
   link through Clear on 7 May, 1 May, 2 May (Off day) and 5 May (ledger
   waits), checks that a changed figure, a date change (and coming back), Next
   day, a load and a save never leave it showing, and adds Ctrl+Alt+Z, the
   tooltip and aria-keyshortcuts; part 12 checks that a saved destination shows
   its own saved day (savedForm) where an unsaved one is blank (blankForm). The
   checks of what pressing the link does are unchanged.

   COUNTS: 271 checks before 2026-10-07 (256 at 1536, 15 at 390); 319 until the
   brand header (2026-10-09; the header is now the header.svg image, checked
   with 3 checks at each width instead of 2 and 1), 322 since (296 at 1536, 26
   at 390, in one run). The 319 passed on 2026-10-07, three runs in a row.

   MUTATION PROOF: MUTATE=1 serves app.js to the page with the 2026-10-07 link
   rules undone: "Show saved figures" shows on every date that is in the books,
   Clear or not (the Clear condition taken out of renderDayFacts), and
   Ctrl+Alt+Z is not a shortcut (its SHORTCUTS entry taken out). The real file
   is never edited. 29 checks must fail then, every one a check of the link or
   of Ctrl+Alt+Z, and nothing else (29 did on 2026-10-07).

   The viewport is 1536x730 at deviceScaleFactor 1.25: the owner's 1920x1080
   display at 125% Windows scaling with the app window maximized and Chrome at
   100% zoom. (The sidebar screenshot with the link is taken at 1536x794.) The
   last part re-opens the saved day at 390px wide, with the Checks sheet open.

   HOW TO RUN (never against the real Records folder):
     1. In a scratch folder:  npm init -y && npm i playwright-core@1   (drives
        the installed Chrome; no browser download), then copy this file there.
        Use a Chrome --user-data-dir inside the scratch folder only: this script
        launches a fresh, temporary profile, never the owner's.
     2. From your copy of v5.0, with LEDGER_ROOT set to an EMPTY scratch folder,
        LDGR_NO_BROWSER=1, LDGR_NO_DIGEST=1, and LDGR_NOTIFY_CONFIG set to a
        path inside the scratch folder that does not exist:
           julia --startup-file=no server.jl 8798
        (add -J sysimage/ldgr.dll after --startup-file=no when it is built).
        (A server started beside a working notify.toml would hand the owner a
        report built from the scratch books within seconds.) The start-up
        "Email" line must read "off (no notify.toml)". Nothing here contacts
        Resend or the internet.
        Warm the endpoints first (curl /api/config); Julia compiles each one on
        its first call, which takes seconds.
     3. From the scratch folder, with LEDGER_ROOT set to the SAME folder (the
        script empties the books when it starts, and refuses a path that
        mentions "Records"):
           node verify-ui-2026-09-29.mjs
        -> PASS/FAIL lines, a total, and screenshots in ./shots (OUT=<folder>
           puts them elsewhere; BASE=http://127.0.0.1:<port> for another port;
           MUTATE=1 for the mutation proof, which exits 0 when it is done)
        It takes about a minute (MUTATE=1 about a minute and a half).
     4. Stop the server BY PID (not by image name; the owner has Chrome and
        Julia open) and confirm nothing listens on 8798.

   Dates are chosen relative to /api/config's `today`, and the run starts from
   an empty set of books, so 1 May 2026 is the first day on record. */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE   = process.env.BASE || "http://127.0.0.1:8798";
const SHOTS  = path.resolve(process.env.OUT || "shots");
const MUTATE = !!process.env.MUTATE;
fs.mkdirSync(SHOTS, { recursive: true });

// MUTATE=1: the page gets app.js with the 2026-10-07 link rules undone (see the
// header). Both edits must find their text, or the proof would prove nothing.
async function mutate(ctx) {
  if (!MUTATE) return;
  await ctx.route("**/app.js*", async (route) => {
    const res = await route.fetch();
    let body = await res.text();
    const gate = /\$\("checks-load"\)\.hidden = !\(day && day\.inBooks && state\.clearedDate === currentDate\(\)\);/;
    const key  = /\n\s*\{ code: "KeyZ", alt: true,\s*button: "checks-load" \},/;
    if (!gate.test(body) || !key.test(body)) throw new Error("MUTATE: the link's Clear condition or its Ctrl+Alt+Z entry was not found in app.js");
    body = body.replace(gate, '$("checks-load").hidden = !(day && day.inBooks);').replace(key, "");
    await route.fulfill({ response: res, body });
  });
}

/* ---------------------------------------------------------------------- */
/* Reporting                                                               */
/* ---------------------------------------------------------------------- */
let pass = 0, fail = 0;
const check = (cond, label, extra) => {
  if (cond) { pass++; console.log(`PASS  ${label}`); }
  else      { fail++; console.log(`FAIL  ${label}${extra ? "  -- " + extra : ""}`); }
  return !!cond;
};
const eq = (got, want, label) => check(got === want, label, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
/* The header is the header.svg image: one <img> in .brand-logo, loaded, with its alt text (3 checks). */
async function headerChecks(pg, tag) {
  const n = await pg.locator(".brand-logo img").count();
  check(n === 1, tag + "the header has exactly one logo image", "found " + n);
  let loaded = false;
  try {
    await pg.waitForFunction(() => { const i = document.querySelector(".brand-logo img"); return !!i && i.complete && i.naturalWidth > 0; }, null, { timeout: 10000 });
    loaded = true;
  } catch (e) { /* reported below */ }
  check(loaded, tag + "the header logo image is fully loaded");
  eq(await pg.locator(".brand-logo img").first().getAttribute("alt"), "LDGR Urgent Care", tag + "the header logo image has the alt text LDGR Urgent Care");
}

/* ---------------------------------------------------------------------- */
/* Dates and the books                                                     */
/* ---------------------------------------------------------------------- */
const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
const pretty = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${MONTHS[m - 1]} ${y}`; };
const getJSON = async (p) => (await fetch(BASE + p)).json();

function emptyBooks() {
  const root = process.env.LEDGER_ROOT;
  if (!root) {
    console.log("FAIL  LEDGER_ROOT must be set to the server's scratch folder so the books can be emptied");
    process.exit(2);
  }
  if (/records/i.test(root)) {
    console.log("FAIL  refusing to empty a folder whose path mentions Records: " + root);
    process.exit(2);
  }
  for (const entry of fs.readdirSync(root)) fs.rmSync(path.join(root, entry), { recursive: true, force: true });
}

// The daily ledger CSV for one date, wherever the month folders put it.
function findDailyLedger(iso) {
  const root = process.env.LEDGER_ROOT;
  const want = `Daily Ledger ${iso}.csv`;
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { const r = walk(p); if (r) return r; }
      else if (e.name === want) return p;
    }
    return null;
  };
  return walk(root);
}
const readLedger = (iso) => { const p = findDailyLedger(iso); return p ? fs.readFileSync(p, "utf8") : null; };

/* ---------------------------------------------------------------------- */
/* Page helpers                                                            */
/* ---------------------------------------------------------------------- */
const text   = (page, sel) => page.$eval(sel, (e) => e.textContent.trim()).catch(() => null);
// The words a person can see: anything inside the element that is hidden is left out.
const shownText = (page, sel) => page.$eval(sel, (e) => {
  const c = e.cloneNode(true);
  c.querySelectorAll("[hidden]").forEach((n) => n.remove());
  return c.textContent.trim();
}).catch(() => null);
const hidden = (page, sel) => page.$eval(sel, (e) => e.hidden).catch(() => true);
const value  = (page, sel) => page.$eval(sel, (e) => e.value).catch(() => null);

const bannerCount    = (page) => page.$$eval("#banner-area .banner", (b) => b.length);
const bannerSentence = (page) => text(page, "#banner-area .banner span");
const dockSentence   = (page) => page.$eval("#dock-msg", (e) => (e.hidden ? null : e.textContent.trim())).catch(() => null);
const rowTitles      = (page) => page.$$eval("#checks-list li .check-title", (n) => n.map((x) => x.textContent.trim()));
const rowMeta        = (page, title) => page.$$eval("#checks-list li", (ls, t) => {
  const li = ls.find((l) => l.querySelector(".check-title").textContent.trim() === t);
  return li ? li.querySelector(".check-meta").textContent.trim() : null;
}, title);
const SAVED_TITLE = "Day saved, ledger generated";
const noteOn = (page) => page.$eval("#checks-regen", (e) => !e.hidden).catch(() => false);
const shownDate = (page) => page.evaluate(() => {
  const v = (id) => document.getElementById(id).value;
  return `${v("sel-year")}-${String(v("sel-month")).padStart(2, "0")}-${String(v("sel-day")).padStart(2, "0")}`;
});
const linkOn = (page) => page.$eval("#checks-load", (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
const untilLink = (page, on) => page.waitForFunction((v) => {
  const e = document.getElementById("checks-load");
  return (!e.hidden && e.getClientRects().length > 0) === v;
}, on, { timeout: 15000 }).then(() => true).catch(() => false);
const loadMsgText = (page) => page.$eval("#checks-load-msg", (e) => (e.hidden || !e.getClientRects().length ? null : e.textContent.trim())).catch(() => null);
const savedNoteOn = (page) => page.$eval("#checks-saved", (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
const blankBoxes  = (page) => page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input", (is) => is.every((i) => i.value === ""));
// Everything a key press could have changed, as one string.
const formSnap = (page) => page.evaluate(() => JSON.stringify({
  a: document.activeElement && document.activeElement.id, v: [...document.querySelectorAll("input, textarea")].map((i) => i.value + (i.checked ? "!" : "")),
  note: document.getElementById("dock-note").hidden, sheet: document.getElementById("checks").className,
  rows: document.getElementById("checks-list").textContent, ban: document.getElementById("banner-area").textContent,
  msg: document.getElementById("dock-msg").textContent, link: document.getElementById("checks-load").hidden,
  lmsg: document.getElementById("checks-load-msg").textContent, y: window.scrollY,
}));
const settle = (page) => page.waitForTimeout(700);        // lets a re-check land and renderDayFacts run
const narrow = (page) => page.$eval("#dock-status", (e) => e.getClientRects().length > 0).catch(() => false);

const checkFor = (page, iso) => page.waitForResponse(async (r) => {
  if (!r.url().includes("/api/check")) return false;
  try { return JSON.parse(r.request().postData() || "{}").date === iso; } catch { return false; }
}, { timeout: 40000 });

const untilText = (page, sel, needle) => page.waitForFunction(
  ([s, t]) => { const n = document.querySelector(s); return !!n && n.textContent.includes(t); },
  [sel, needle], { timeout: 40000 });

// After a save: the "Day saved" row is in the Checks panel, or the dock says so.
const untilSavedShown = (page) => page.waitForFunction(() => {
  const row = [...document.querySelectorAll("#checks-list .check-title")]
    .some((n) => n.textContent.trim() === "Day saved, ledger generated");
  const msg = document.getElementById("dock-msg");
  const note = document.getElementById("checks-saved");
  return row || (!!note && !note.hidden && note.getClientRects().length > 0) || (!msg.hidden && msg.textContent.includes("saved to the books"));
}, null, { timeout: 40000 });

// Picks a date. Picking the date already on screen is not a change (nothing is
// cleared and no check runs), so that is simply a no-op here.
async function setDate(page, iso) {
  if (await shownDate(page) === iso) return;
  const [y, m, d] = iso.split("-").map(Number);
  await page.selectOption("#sel-year", String(y));
  await page.selectOption("#sel-month", String(m));
  await Promise.all([checkFor(page, iso), page.selectOption("#sel-day", String(d))]);
}

async function setAmount(page, key, v) {
  await page.fill("#in-" + key, v);
  await page.$eval("#in-" + key, (e) => e.blur());
}

async function clickSave(page) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/save"), { timeout: 120000 }),
    page.click("#btn-save"),
  ]);
  return { status: res.status(), body: await res.json().catch(() => null) };
}

/* ---------------------------------------------------------------------- */
async function main() {
  emptyBooks();
  const cfg = await getJSON("/api/config");
  const today = cfg.today;
  const OPEN = cfg.openingKey, CLOSE = cfg.closingKey, DEP = cfg.depositKey;
  const d1 = "2026-05-01", d2 = "2026-05-02", d5 = "2026-05-05", d6 = "2026-05-06", d7 = "2026-05-07";
  console.log(`today=${today}  base=${BASE}  mutate=${MUTATE}  shots=${SHOTS}\n`);

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    /* The owner's maximized window at 100% zoom on a 1920x1080 display at 125%. */
    const ctx = await browser.newContext({ viewport: { width: 1536, height: 730 }, deviceScaleFactor: 1.25, acceptDownloads: false });
    await mutate(ctx);
    const page = await ctx.newPage();

    // A refused save or move answers 4xx on purpose, and Chrome logs each one as
    // a console error. Those are answers being tested, not defects.
    const errors = [];
    // /api/day is aborted on purpose in part 10, and /api/check in part 7 (the
    // first-day banner is reached through a check that never answers).
    const noise = (t) => /favicon/i.test(t) || (/api\/(next|save)/.test(t) && /\b(400|409)\b/.test(t)) || /api\/day/.test(t) ||
                         (/api\/check/.test(t) && /ERR_FAILED/.test(t));
    page.on("console", (m) => {
      if (m.type() !== "error") return;
      const where = (m.location() && m.location().url) || "";
      const line = `${m.text()} [${where}]`;
      if (!noise(line)) errors.push(line);
    });
    page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
    let dialogs = 0;
    page.on("dialog", (d) => { dialogs++; d.accept(); });      // the "mark as CLOSED?" question
    let downloads = 0;
    page.on("download", () => { downloads++; });
    const saves = [];                                          // every POST /api/save body
    let dayAsks = 0;                                           // every GET /api/day
    page.on("request", (r) => {
      if (r.url().includes("/api/save") && r.method() === "POST") {
        try { saves.push(JSON.parse(r.postData() || "{}")); } catch { saves.push({}); }
      }
      if (r.url().includes("/api/day")) dayAsks++;
    });

    await Promise.all([checkFor(page, today), page.goto(BASE)]);
    await page.waitForSelector("#in-" + OPEN);

    /* ---- 1 · the window, the header ----------------------------------- */
    const vp = await page.evaluate(() => ({ w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio, zoomless: document.documentElement.clientWidth }));
    check(vp.w === 1536 && vp.dpr === 1.25, "1 · viewport is the owner's maximized window (1536 wide at DPR 1.25)", JSON.stringify(vp));
    await headerChecks(page, "1 · ");
    eq(await page.title(), "LDGR", "1 · the window title says LDGR");
    check(!/Daily Entry/i.test(await page.evaluate(() => document.body.innerText)), "1 · \"Daily Entry\" is nowhere on the page");
    await page.locator(".topbar").screenshot({ path: path.join(SHOTS, "header.png") });

    /* ---- 5 · no ledger tick box anywhere ------------------------------ */
    const boxes = await page.$$eval("input[type=checkbox]", (bs) => bs.map((b) => b.id).sort());
    eq(boxes.join(" "), "chk-closed chk-genesis", "5 · the only tick boxes are Off day and first day: no ledger tick box");
    eq(await page.evaluate(() => /replace the ledger|keep the old file/i.test(document.body.textContent)), false,
       "5 · the words of the old tick box are gone from the page");
    eq(await page.$$eval("#force-line, #chk-force, #btn-cancel-edit", (n) => n.length), 0, "5 · no #force-line, #chk-force or #btn-cancel-edit");
    eq(await page.$$eval(".dock-actions button", (bs) => bs.map((b) => b.id).join(" ")), "btn-clear btn-save btn-next",
       "5 · the dock actions are Clear, Save, Next day");
    eq(await page.evaluate(() => [...document.querySelectorAll("button")].some((b) => /edit that day/i.test(b.textContent))), false,
       "5 · there is no Edit that day button");

    /* ---- 7 · the refusal banners, unchanged ---------------------------- */
    // Save is greyed whenever the day cannot be saved as it stands (since
    // 2026-10-06 that includes everything the server's last check found, and a
    // form no check has answered for yet), so these banners are only reachable
    // in the moment before a check lands and greys the button: the form is
    // built to survive that race, by waiting for a check of exactly what is on
    // screen. Each one is opened from a GREEN button: a checked, balanced day
    // whose closing balance is then changed while the check is held up; and a
    // form whose first check never arrived (the server could not be reached),
    // so the first-day box has not been asked for yet.
    const slow = async (ms, fn) => {
      await page.route("**/api/check", async (route) => { await new Promise((res) => setTimeout(res, ms)); await route.continue().catch(() => {}); });
      // Checks still waiting when fn ends are let through by the handler, which
      // stays in place a moment longer so none of them is left hanging.
      try { await fn(); await new Promise((res) => setTimeout(res, ms + 200)); }
      finally { await page.unroute("**/api/check"); }
    };
    // Off the date and back. Since 2026-10-06 each date change also blanks the
    // form, so the figures are typed AFTER it (typeDay), and forgets what the
    // last check said about the date.
    const bounce = async (iso) => {
      const [y, m, d] = iso.split("-").map(Number);
      await page.selectOption("#sel-day", String(d === 1 ? 2 : 1));
      await page.selectOption("#sel-day", String(d));
    };
    const typeDay = async (o, sales, dep, c) => {            // typed, never blurred: still mid-entry
      await page.fill("#in-" + OPEN, o);
      await page.fill("#in-cash_sales", sales);
      await page.fill("#in-" + DEP, dep);
      await page.fill("#in-" + CLOSE, c);
    };
    let before = saves.length;

    await setDate(page, d1);
    await typeDay("1000.00", "500.00", "300.00", "1200.00");   // balances
    await page.$eval("#in-" + CLOSE, (e) => e.blur());
    await untilText(page, "#predicted", "The day balances.");
    await page.waitForFunction(() => !document.getElementById("genesis-line").hidden, null, { timeout: 40000 });
    await page.check("#chk-genesis");
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    eq(await page.$eval("#btn-save", (e) => e.disabled), false, "7 · a balanced first day, ticked and checked: Save is green");
    await slow(2500, async () => {
      await page.fill("#in-" + CLOSE, "1250.00");          // 50 too much: needs a reason, check held up
      eq(await page.$eval("#btn-save", (e) => e.disabled), false, "7 · Save is still green in the moment before the check answers");
      await page.click("#btn-save");
      await untilText(page, "#banner-area .banner span", "Add a short reason");
    });
    eq(await bannerSentence(page), "Add a short reason before saving this day.", "7 · a difference with no reason: the reason banner, at the top");
    eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "txt-reason", "7 · the cursor goes to the reason box");
    eq(saves.length, before, "7 · …and nothing was posted");
    await page.waitForFunction(() => document.getElementById("btn-save").disabled, null, { timeout: 40000 });

    await page.route("**/api/check", (route) => route.abort());   // the server cannot be reached
    await bounce(d1);                                      // blanks the form; its first check never answers
    await typeDay("1000.00", "500.00", "300.00", "1200.00");
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    eq(await hidden(page, "#genesis-line"), true, "7 · with no check answered, the first-day box has not been asked for");
    await page.unroute("**/api/check");
    await page.click("#btn-save");
    await untilText(page, "#banner-area .banner span", "Tick the first-day box");
    eq(await bannerSentence(page), "Tick the first-day box before saving this day.", "7 · the first day with its box unticked: the first-day banner, at the top");
    eq(saves.length, before, "7 · …and nothing was posted");
    await page.waitForFunction(() => document.getElementById("btn-save").disabled, null, { timeout: 40000 });

    /* ---- 2, 3, 4, 5 · save the first day ------------------------------ */
    await page.check("#chk-genesis");
    let s = await clickSave(page);
    eq(s.status, 200, "2 · Save writes the first day");
    await untilSavedShown(page);
    eq(await bannerCount(page), 0, "2 · after the save there is no banner at the top");
    eq(await page.evaluate(() => document.getElementById("banner-area").textContent.trim()), "", "2 · the banner area is empty");
    eq(await shownDate(page), d1, "2 · Save stays on the day");
    eq(await value(page, "#in-" + CLOSE), "1200.00", "2 · the figures are still in the boxes");
    eq(await hidden(page, "#dock-msg"), true, "6 · a day with a ledger needs no line under the buttons (the panel says it)");
    check((await rowTitles(page)).includes(SAVED_TITLE), "3 · the Checks panel row is titled Day saved, ledger generated", JSON.stringify(await rowTitles(page)));
    eq(await rowMeta(page, SAVED_TITLE), "Good to know", "3 · with the meta Good to know");
    check(!(await rowTitles(page)).some((t) => /ledger already made/i.test(t)), "3 · the old title is gone");
    eq(saves.length, before + 1, "5 · one save was posted");
    eq(saves[saves.length - 1].force, true, "5 · and it asked for the ledger to be regenerated (force: true)");

    // the grey note
    eq(await noteOn(page), true, "4 · the grey note shows for a Work day that has a ledger");
    eq(await text(page, "#checks-regen"), "Saving again will regenerate the ledgers with the current figures and accounts.", "4 · with exactly the owner's words");
    eq(await page.$eval("#checks-regen", (e) => !!e.closest("#checks")), true, "4 · it sits inside the Checks panel");
    eq(await page.$eval("#checks-regen", (e) => !!e.closest("#checks-list")), false, "4 · but it is not one of the list rows");
    const count = await page.$eval("#checks-count", (e) => (e.hidden ? "" : e.textContent.trim()));
    const rowsN = await page.$$eval("#checks-list li", (l) => l.length);
    eq(count, rowsN ? String(rowsN) : "", "4 · #checks-count counts the rows only, not the note");
    eq(await page.$eval("#checks-regen", (e) => getComputedStyle(e).position), "static", "4 · the note is in the page flow, not floating");
    const greyOk = await page.$eval("#checks-regen", (e) => {
      const c = getComputedStyle(e);
      return { color: c.color, bg: c.backgroundColor };
    });
    console.log(`      (note colours: ${JSON.stringify(greyOk)})`);

    // screenshot of the saved-day state: sidebar row, grey note, dock
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.screenshot({ path: path.join(SHOTS, "saved-day-state.png"), fullPage: true });
    await page.locator("#dock").screenshot({ path: path.join(SHOTS, "saved-day-dock.png") });
    await page.locator("#checks").screenshot({ path: path.join(SHOTS, "saved-day-sidebar.png") });

    // the full explanation
    const savedLi = page.locator("#checks-list li", { has: page.locator(".check-title", { hasText: SAVED_TITLE }) });
    await savedLi.locator(".check-more").click();
    await page.waitForFunction(() => { const n = document.getElementById("dock-note"); return n && !n.hidden; }, null, { timeout: 40000 });
    const want = `A ledger has already been generated for ${pretty(d1)}. ` +
      "Before importing into QuickBooks, confirm that no journal already exists for this date. " +
      "If there is a QB journal already, delete that journal before importing a new one with updated numbers and/or accounts. " +
      "If the numbers match, there is no need to change the QB records.";
    eq(await text(page, "#dock-note .note-text"), want, "3 · the full explanation is exactly the owner's wording");
    check(!/NOT been overwritten|replace the ledger|tick/i.test(await text(page, "#dock-note")), "3 · and the old talk of a tick box is gone");
    await page.screenshot({ path: path.join(SHOTS, "full-explanation.png"), fullPage: false });
    await page.locator("#dock").screenshot({ path: path.join(SHOTS, "full-explanation-dock.png") });
    await page.click("#dock-note .note-close");

    /* ---- 7 · the red-marks banner (a box goes red inside the race) ------ */
    // The form holds the day just saved, checked and green. The press waits
    // for its own check, and the box goes red while that check is on its way.
    before = saves.length;
    let redBanner = null;
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    await slow(2500, async () => {
      // The click is made inside the page so the box cannot go red first.
      await page.evaluate(() => document.getElementById("btn-save").click());
      await page.fill("#in-cash_sales", "abc");            // goes red while the check is still on its way
      await untilText(page, "#banner-area .banner span", "Fix what is marked in red");
      redBanner = await bannerSentence(page);
    });
    eq(redBanner, "Fix what is marked in red before saving this day.", "7 · a box gone red: the red-marks banner, at the top");
    eq(saves.length, before, "7 · …and nothing was posted");
    await setAmount(page, "cash_sales", "500");
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });

    /* ---- 5 · a re-save with a changed figure regenerates the CSV ------- */
    const csv1 = readLedger(d1);
    check(!!csv1, "5 · the daily ledger CSV for 1 May exists", String(findDailyLedger(d1)));
    await setAmount(page, "cash_sales", "600");
    await setAmount(page, CLOSE, "1300");
    await untilText(page, "#predicted", "The day balances.");
    s = await clickSave(page);
    eq(s.status, 200, "5 · saving again is accepted with no tick box");
    await untilSavedShown(page);
    const csv2 = readLedger(d1);
    check(csv1 !== null && csv2 !== null && csv1 !== csv2, "5 · the daily ledger CSV was regenerated: its content changed");
    check(!!csv2 && csv2.includes("600"), "5 · and it holds the new figure (600)");
    check(!JSON.stringify(s.body).includes("NOT been overwritten"), "5 · the save's answer never says NOT been overwritten");
    eq(await page.evaluate(() => document.body.textContent.includes("NOT been overwritten")), false, "5 · nor does the page");
    eq(saves[saves.length - 1].force, true, "5 · the second save sent force: true too");
    eq(await bannerCount(page), 0, "2 · and still no banner at the top");

    /* ---- 4 · when the note shows ---------------------------------------- */
    await Promise.all([checkFor(page, d1), page.click(".daytype-toggle .opt-closed")]);
    eq(await noteOn(page), false, "4 · the note is gone when the day is marked Off");
    await Promise.all([checkFor(page, d1), page.click(".daytype-toggle .opt-trading")]);
    eq(await noteOn(page), true, "4 · and back when the day is a Work day again");
    await setDate(page, d2);
    eq(await noteOn(page), false, "4 · a Work day with no ledger yet (2 May) has no note");
    check(!(await rowTitles(page)).includes(SAVED_TITLE), "4 · nor a Day saved row");
    await setDate(page, d1);
    await page.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    eq(await noteOn(page), true, "4 · picking 1 May again brings the note back");

    /* ---- 6 · an Off day: confirmed by the grey note #checks-saved ------- */
    // Since 2026-10-07 the panel says it, so the dock does not say it again on
    // a wide window. The dock line is checked at 390, where the panel is hidden.
    await setDate(page, d2);
    await Promise.all([checkFor(page, d2), page.click(".daytype-toggle .opt-closed")]);
    const dlg = dialogs;
    s = await clickSave(page);
    eq(s.status, 200, "6 · an Off day is saved");
    await page.waitForFunction(() => { const n = document.getElementById("checks-saved"); return !!n && !n.hidden && n.getClientRects().length > 0; }, null, { timeout: 40000 });
    await settle(page);
    eq(dialogs, dlg + 1, "6 · after the form's own \"mark as CLOSED?\" question");
    eq(await shownText(page, "#checks-saved"), "This day has been saved.",
       "6 · the Off day is confirmed by the grey note #checks-saved, word for word (no figures, so no second sentence)");
    eq(await dockSentence(page), null, "6 · …so nothing is said under the buttons while the Checks panel is visible");
    eq(await bannerCount(page), 0, "6 · and nothing is said at the top");
    eq(await noteOn(page), false, "6 · the regenerate note is not shown for an Off day");
    eq(await page.$eval("#checks-saved", (e) => !!e.closest("#checks") && !e.closest("#checks-list")), true, "6 · the grey note sits in the Checks panel, outside the list");
    await page.locator("#checks").screenshot({ path: path.join(SHOTS, "off-day-save.png") });

    /* ---- 6 · a ledger that waits on a missing day ------------------------ */
    // 3 and 4 May are not in the books, so the day before 5 May is missing.
    // 2 May was left on Off day with its save. Picking 5 May starts blank on a
    // Work day (the date change clears the switch), with no Clear press needed.
    await setDate(page, d5);
    eq(await page.$eval("#chk-closed", (e) => e.checked), false, "6 · picking 5 May after an Off day leaves a Work day");
    eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input", (is) => is.every((i) => i.value === "")), true,
       "6 · …and empty boxes");
    eq(await hidden(page, "#dock-msg"), true, "6 · …and nothing under the buttons");
    await setAmount(page, OPEN, "1300");
    await setAmount(page, CLOSE, "1300");
    await untilText(page, "#predicted", "The day balances.");
    s = await clickSave(page);
    eq(s.status, 200, "6 · 5 May, with its day before missing, is saved");
    await page.waitForFunction(() => { const n = document.getElementById("checks-saved"); return !!n && !n.hidden && n.getClientRects().length > 0; }, null, { timeout: 40000 });
    eq(await dockSentence(page), null, "6 · a day whose ledger waits has no #dock-msg line while the Checks panel is visible");
    eq(await shownText(page, "#checks-saved"), "This day has been saved. Saving again will rewrite it with the current figures.", "6 · the grey note #checks-saved confirms it instead, in full");
    eq(await bannerCount(page), 0, "6 · and nothing is said at the top");
    eq(await noteOn(page), false, "6 · no note: it has no ledger to regenerate");
    check(!(await rowTitles(page)).includes(SAVED_TITLE), "6 · and no Day saved, ledger generated row (no ledger was made)");
    check(readLedger(d5) === null, "6 · no daily ledger file exists for 5 May");

    /* ---- 8 · keyboard shortcuts ----------------------------------------- */
    // A shortcut that reaches the page must be swallowed, so the browser's own
    // Save page / New window never opens. Recorded in the bubbling phase, after
    // the form's own listener has run.
    await page.evaluate(() => {
      window.__keys = [];
      window.addEventListener("keydown", (e) => window.__keys.push({ code: e.code, ctrl: e.ctrlKey, alt: e.altKey, prevented: e.defaultPrevented }));
    });
    const lastKey = () => page.evaluate(() => window.__keys[window.__keys.length - 1]);

    // Save greyed: a fresh blank day, nothing typed.
    await setDate(page, d6);
    eq(await page.$eval("#chk-closed", (e) => e.checked), false, "8 · 6 May opens as a Work day");
    await page.fill("#in-cash_sales", "abc");              // a red box greys Save
    const saveGreyed = await page.$eval("#btn-save", (b) => b.disabled);
    check(saveGreyed, "8 · Save is greyed while a box is red");
    before = saves.length;
    const dlg2 = dialogs, dl2 = downloads;
    await page.keyboard.press("Control+s");
    await page.waitForTimeout(700);
    eq(saves.length, before, "8 · Ctrl+S while Save is greyed posts nothing");
    eq(dialogs, dlg2, "8 · …opens no dialog");
    eq(downloads, dl2, "8 · …and starts no download");
    let k = await lastKey();
    check(k && k.code === "KeyS" && k.prevented, "8 · …and the browser's own Ctrl+S is still swallowed", JSON.stringify(k));

    await page.fill("#in-cash_sales", "");
    await page.$eval("#in-cash_sales", (e) => e.blur());

    // Ctrl+S from inside a box, mid-typing.
    const prior6 = await getJSON("/api/prior?date=" + d6);
    const open6 = prior6.hasPrior ? Number(prior6.expected) : 1300;
    await setAmount(page, OPEN, open6.toFixed(2));
    await setAmount(page, "cash_sales", "100");
    await page.click("#in-" + CLOSE);
    await page.keyboard.type((open6 + 100).toFixed(0));       // no blur: the cursor stays in the box
    // Since 2026-10-06 Save is grey until the check for the typed figure has
    // answered (the last answer still said the closing balance was blank), so
    // the person pauses for it, as anyone does before reaching for a shortcut.
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    eq(await page.evaluate(() => document.activeElement.id), "in-" + CLOSE, "8 · the cursor is inside the closing box");
    const [sres] = await Promise.all([
      page.waitForResponse((r) => r.url().includes("/api/save"), { timeout: 120000 }),
      page.keyboard.press("Control+s"),
    ]);
    eq(sres.status(), 200, "8 · Ctrl+S from inside a box mid-typing saves the day");
    eq(JSON.parse(sres.request().postData()).date, d6, "8 · …the day on screen");
    await untilSavedShown(page);
    eq(await value(page, "#in-" + CLOSE), (open6 + 100).toFixed(2), "8 · the typed figure was tidied and kept");
    eq(await shownDate(page), d6, "8 · and the form stays on the day");
    eq(dialogs, dlg2, "8 · no dialog opened");
    k = await lastKey();
    check(k && k.code === "KeyS" && k.prevented, "8 · Ctrl+S was swallowed by the form", JSON.stringify(k));

    // Ctrl+N on a saved day moves on.
    const settled = checkFor(page, d7).catch(() => null);
    const [nres] = await Promise.all([
      page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: 120000 }),
      page.keyboard.press("Control+n"),
    ]);
    eq(nres.status(), 200, "8 · Ctrl+N on a saved day is accepted");
    await settled;
    eq(await shownDate(page), d7, "8 · …and the form moves to the next day");
    k = await lastKey();
    check(k && k.code === "KeyN" && k.prevented, "8 · Ctrl+N was swallowed by the form", JSON.stringify(k));

    // Ctrl+N on an unsaved day is refused, into the dock.
    await setAmount(page, OPEN, "1400");
    const [rres] = await Promise.all([
      page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: 120000 }),
      page.keyboard.press("Control+n"),
    ]);
    eq(rres.status(), 409, "8 · Ctrl+N on an unsaved day is refused by the server");
    await untilText(page, "#dock-msg", "not been saved");
    check((await dockSentence(page) || "").includes("not been saved"), "8 · the refusal is in #dock-msg, beside the buttons", String(await dockSentence(page)));
    eq(await bannerCount(page), 0, "8 · and not only at the top of the page");
    eq(await shownDate(page), d7, "8 · the form stays on the day");

    // Ctrl+Alt+C clears and keeps the date.
    await page.click("#in-cash_sales");
    await page.keyboard.type("77");
    const [cres] = await Promise.all([
      checkFor(page, d7),
      page.keyboard.press("Control+Alt+c"),
    ]);
    eq(cres.status(), 200, "8 · Ctrl+Alt+C re-checks the day it cleared");
    eq(await shownDate(page), d7, "8 · Ctrl+Alt+C keeps the date");
    eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input",
                         (is) => is.every((i) => i.value === "")), true, "8 · …and empties every box");
    eq(await hidden(page, "#dock-msg"), true, "8 · …and takes the old refusal down");
    k = await lastKey();
    check(k && k.code === "KeyC" && k.alt && k.prevented, "8 · Ctrl+Alt+C was swallowed by the form", JSON.stringify(k));

    // Every save so far asked for a regenerated ledger.
    check(saves.length > 0 && saves.every((b) => b.force === true), "5 · every save the form sent had force: true", JSON.stringify(saves.map((b) => b.force)));

    /* ---- 10 · "Show saved figures" ---------------------------------------- */
    // Since 2026-10-07 a saved date comes up as saved by itself, so the link is
    // only the way back after Clear on a saved date (or Ctrl+Alt+Z). Every way
    // to it below goes through Clear.
    const LINK = "Show saved figures";
    const noEditing = async (label) => {
      eq(await bannerCount(page), 0, `10 · ${label}: no banner at the top`);
      eq(await page.$$eval("#btn-cancel-edit", (n) => n.length), 0, `10 · ${label}: no #btn-cancel-edit`);
      eq(await page.evaluate(() => /edit that day|cancel edit|editing/i.test(document.body.innerText) || /edit/i.test(document.body.className)),
         false, `10 · ${label}: no Edit that day, Cancel edit or editing mode`);
    };
    const boxesMatch = async (day, label) => {
      const bad = [];
      for (const [k, v] of Object.entries(day.amounts || {})) {
        const got = await value(page, "#in-" + k);
        if (got === null) continue;
        if (got === "" ? (v !== null && v !== "" && Number(v) !== 0) : Number(got) !== Number(v)) bad.push(`${k}: ${got} vs ${v}`);
      }
      eq(bad.join("; "), "", `10 · ${label}: every figure in the boxes is the saved figure`);
    };
    // Press the link with the page scrolled down first, so the return to the
    // top can be seen. Returns the scroll position before and the reply status
    // (-1 for a request that failed, 0 for none at all).
    const pressLink = async ({ scrolled = true } = {}) => {
      if (scrolled) await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      const y = await page.evaluate(() => window.scrollY);
      const isDay = (x) => x.url().includes("/api/day");
      const answered = Promise.race([
        page.waitForResponse(isDay, { timeout: 40000 }).then((r) => r.status()).catch(() => 0),
        page.waitForEvent("requestfailed", { predicate: isDay, timeout: 40000 }).then(() => -1).catch(() => 0),
      ]);
      await page.evaluate(() => document.getElementById("checks-load").click());
      const status = await answered;
      await page.waitForTimeout(1200);                    // the re-check and the smooth scroll
      return { y, status };
    };
    const clearDay = (iso) => Promise.all([checkFor(page, iso), page.click("#btn-clear")]);
    // A saved day's figures typed back by hand into the blank boxes.
    const typeBack = async (day) => {
      for (const [k, v] of Object.entries(day.amounts || {})) {
        if (v === null || v === "" || (Number(v) === 0 && k !== OPEN && k !== CLOSE)) continue;
        if (await value(page, "#in-" + k) === null) continue;
        await setAmount(page, k, String(v));
      }
    };

    // Part 8 ended with Ctrl+Alt+C on 7 May, which is not in the books yet.
    await setDate(page, d7);
    await settle(page);
    eq(await linkOn(page), false, "10 · Clear on a date that is not in the books (7 May) shows no link");
    let z = await formSnap(page), asks = dayAsks;
    await page.keyboard.press("Control+Alt+z");
    await page.waitForTimeout(700);
    eq(await formSnap(page), z, "8 · Ctrl+Alt+Z with no link showing changes nothing");
    eq(dayAsks, asks, "8 · …and asks the server nothing");
    k = await lastKey();
    check(k && k.code === "KeyZ" && k.alt && k.prevented, "8 · …and is still swallowed by the form", JSON.stringify(k));
    check(await page.$eval("#checks-load", (e) => e.tagName === "BUTTON" && e.textContent === "Show saved figures"),
          "10 · the link is a button reading exactly \"Show saved figures\"");
    eq(await page.$eval("#checks-load", (e) => e.title), "Show saved figures (Ctrl+Alt+Z)", "10 · its tooltip names the shortcut: \"Show saved figures (Ctrl+Alt+Z)\"");
    eq(await page.$eval("#checks-load", (e) => e.getAttribute("aria-keyshortcuts")), "Control+Alt+Z", "10 · and its aria-keyshortcuts is \"Control+Alt+Z\"");
    check(await page.$eval("#checks-load", (e) => e.previousElementSibling.previousElementSibling.id === "checks-regen" || e.previousElementSibling.id === "checks-regen"),
          "10 · it comes right after the grey note in the sidebar");
    check(await page.$eval("#checks-load", (e) => !!e.closest("#checks") && !e.closest("#checks-list")),
          "10 · inside #checks and outside the list");
    eq(await page.$eval("#checks-load", (e) => getComputedStyle(e).position), "static", "10 · it is in the page flow");

    // 7 May: a saved day with both reasons, so a load has reasons to restore.
    const RSN_OPEN = "Counted again in the morning", RSN_DAY = "Change given by mistake";
    await setAmount(page, OPEN, "1500");
    await setAmount(page, "cash_sales", "100");
    await setAmount(page, CLOSE, "1650");
    await page.waitForSelector("#txt-opening-reason", { state: "visible", timeout: 40000 });
    await page.fill("#txt-opening-reason", RSN_OPEN);
    await page.waitForSelector("#txt-reason", { state: "visible", timeout: 40000 });
    await page.fill("#txt-reason", RSN_DAY);
    await page.$eval("#txt-reason", (e) => e.blur());
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    eq(await linkOn(page), false, "10 · still no link while the date is unsaved and being typed");
    s = await clickSave(page);
    eq(s.status, 200, "10 · 7 May, with an opening reason and a day reason, is saved");
    await untilSavedShown(page);
    await settle(page);
    eq(await linkOn(page), false, "10 · hidden right after Save (7 May was cleared before it was typed, and the save ends that)");
    eq(await bannerCount(page), 0, "10 · and nothing at the top after that save");

    // A changed figure does not bring it (until 2026-10-07 it did): only Clear does.
    await Promise.all([checkFor(page, d7), setAmount(page, "cash_sales", "250")]);
    await page.fill("#txt-reason", "something else");
    await settle(page);
    eq(await linkOn(page), false, "10 · a changed figure on a saved date does not bring the link");
    await clearDay(d7);
    check(await untilLink(page, true), "10 · Clear on a saved date (7 May) shows the link");
    eq(await shownDate(page), d7, "10 · …Clear kept the date");
    eq(await blankBoxes(page), true, "10 · …and every box is blank: Clear does not put the saved day back by itself");
    eq(await page.evaluate(() => document.getElementById("txt-opening-reason").value + document.getElementById("txt-reason").value), "",
       "10 · …nor its reasons");
    eq(await text(page, "#checks-load"), LINK, "10 · with the same exact label");
    const rows10 = await page.$$eval("#checks-list li", (l) => l.length);
    const cnt10 = await page.$eval("#checks-count", (e) => (e.hidden ? "" : e.textContent.trim()));
    eq(cnt10, rows10 ? String(rows10) : "", "10 · #checks-count counts the rows only: the link is not counted");
    eq(await page.$$eval("#checks-list li", (ls) => ls.filter((l) => /saved figures/i.test(l.textContent)).length), 0, "10 · the link is not a row in the list");
    eq(await page.$eval("#checks-live", (e) => /saved figures/i.test(e.textContent)), false, "10 · nor in the screen-reader line");
    eq(await page.$eval("#dock-status", (e) => /saved figures/i.test(e.textContent)), false, "10 · nor in the narrow-screen pill");
    const geo = await page.evaluate(() => {
      const n = document.getElementById("checks-regen");
      return { noteBottom: n.getBoundingClientRect().bottom, noteShown: !n.hidden, linkTop: document.getElementById("checks-load").getBoundingClientRect().top };
    });
    check(!geo.noteShown || geo.linkTop >= geo.noteBottom - 1, "10 · the link sits below the grey note", JSON.stringify(geo));
    const linkStyle = await page.evaluate(() => {
      const c = getComputedStyle(document.getElementById("checks-load"));
      const m = document.createElement("button"); m.className = "check-more"; m.textContent = "x"; document.getElementById("checks").appendChild(m);
      const d = getComputedStyle(m);
      const out = { link: [c.color, c.textDecorationLine, c.backgroundColor, c.fontSize], more: [d.color, d.textDecorationLine, d.backgroundColor, d.fontSize] };
      m.remove(); return out;
    });
    check(linkStyle.link.join("|") === linkStyle.more.join("|"), "10 · it is styled like See full explanation (colour, underline, background, size)", JSON.stringify(linkStyle));
    await Promise.all([checkFor(page, d7), setAmount(page, "cash_sales", "300")]);
    await settle(page);
    eq(await linkOn(page), true, "10 · typing after Clear keeps the link");

    // Press it: figures, reasons and the switch are back; cursor, top, no banner.
    const day7 = (await getJSON("/api/day?date=" + d7)).day;
    check(!!day7 && day7.openingReason === RSN_OPEN && day7.reason === RSN_DAY, "10 · the books hold both reasons for 7 May", JSON.stringify(day7 && [day7.openingReason, day7.reason]));
    let pl = await pressLink();
    check(pl.y > 0, "10 · the page was scrolled down before the press", String(pl.y));
    eq(pl.status, 200, "10 · pressing it asks GET /api/day");
    await boxesMatch(day7, "after loading 7 May (over the 300.00 typed since Clear)");
    eq(await value(page, "#txt-opening-reason"), RSN_OPEN, "10 · the opening reason is restored");
    eq(await value(page, "#txt-reason"), RSN_DAY, "10 · the day reason is restored");
    eq(await page.$eval("#chk-closed", (e) => e.checked), false, "10 · the Work day switch is right");
    eq(await page.evaluate(() => window.scrollY), 0, "10 · the page has scrolled to the top");
    eq(await page.evaluate(() => document.activeElement.id), "in-" + OPEN, "10 · the cursor is in the opening balance box");
    eq(await linkOn(page), false, "10 · hidden right after loading");
    await noEditing("after loading");
    eq(await hidden(page, "#dock-msg"), true, "10 · nothing under the buttons after a load");
    eq(await shownDate(page), d7, "10 · the date is unchanged");
    eq(await page.$eval("#txt-opening-reason", (e) => e.offsetParent !== null), true, "10 · the reasons show at once, as the day was saved");
    await Promise.all([checkFor(page, d7), setAmount(page, "cash_sales", "300")]);
    await settle(page);
    eq(await linkOn(page), false, "10 · changing a figure after a load does not bring the link back");
    await clearDay(d7);
    check(await untilLink(page, true), "10 · Clear brings it back again");
    await Promise.all([checkFor(page, d7), setAmount(page, "cash_sales", "300")]);
    await settle(page);

    // Screenshot: the sidebar with the link at 1536x794 (DPR 1.25).
    await page.setViewportSize({ width: 1536, height: 794 });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(SHOTS, "link-sidebar-1536x794.png") });
    await page.locator("#checks").screenshot({ path: path.join(SHOTS, "link-sidebar-panel.png") });
    await page.setViewportSize({ width: 1536, height: 730 });

    // A failed load: the sentence sits under the link, not at the top.
    await page.route("**/api/day**", (route) => route.abort());
    await pressLink({ scrolled: false });
    eq(await loadMsgText(page), "LDGR has stopped. Unsaved figures will need to be re-entered. Close this window and open LDGR again.", "10 · a failed load says the api() sentence under the link");
    const under = await page.evaluate(() => {
      const a = document.getElementById("checks-load").getBoundingClientRect(), b = document.getElementById("checks-load-msg").getBoundingClientRect();
      return { linkBottom: a.bottom, msgTop: b.top, inChecks: !!document.getElementById("checks-load-msg").closest("#checks") };
    });
    check(under.inChecks && under.msgTop >= under.linkBottom - 1, "10 · the sentence is directly under the link, in the sidebar", JSON.stringify(under));
    eq(await bannerCount(page), 0, "10 · and the top banner stays empty");
    eq(await page.evaluate(() => document.getElementById("banner-area").textContent.trim()), "", "10 · the banner area is empty");
    eq(await value(page, "#in-cash_sales"), "300.00", "10 · a failed load leaves the typed figures alone");
    eq(await linkOn(page), true, "10 · the link stays for another try");
    await page.locator("#checks").screenshot({ path: path.join(SHOTS, "link-failed-load.png") });
    await page.unroute("**/api/day**");

    // A date change ends what Clear offered: the next date comes up as saved,
    // and so does 7 May when it is picked again, with no link either time.
    const day1 = (await getJSON("/api/day?date=" + d1)).day;
    await setDate(page, d1);
    await settle(page);
    eq(await loadMsgText(page), null, "10 · the sentence goes on the next date change");
    await boxesMatch(day1, "picking 1 May (saved) after Clear and 300.00 typed on 7 May");
    eq(await linkOn(page), false, "10 · a date change after Clear takes the link down: 1 May came up as saved, with none");
    await setDate(page, d7);
    await boxesMatch(day7, "back on 7 May");
    eq(await value(page, "#txt-reason"), RSN_DAY, "10 · back on 7 May its reason is back too, as saved");
    eq(await linkOn(page), false, "10 · …and the link is gone for good: Clear's offer ended with the date change");
    await setDate(page, d1);

    // A reply of no day: "<date> is not in the books."
    await page.route("**/api/day**", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: true, day: null }) }));
    await clearDay(d1);
    check(await untilLink(page, true), "10 · Clear on 1 May (saved) shows the link on a blank form");
    await pressLink({ scrolled: false });
    eq(await loadMsgText(page), `${pretty(d1)} is not in the books.`, "10 · a reply of no day says \"<date> is not in the books.\" under the link");
    eq(await bannerCount(page), 0, "10 · and not at the top");
    await clearDay(d1);
    await settle(page);
    eq(await loadMsgText(page), null, "10 · the sentence goes when the form is cleared");
    await pressLink({ scrolled: false });
    eq(await loadMsgText(page), `${pretty(d1)} is not in the books.`, "10 · and comes back on the next failed press");
    await page.unroute("**/api/day**");
    pl = await pressLink();
    eq(await loadMsgText(page), null, "10 · the sentence goes on a good load");
    await boxesMatch(day1, "after loading 1 May");
    eq(await linkOn(page), false, "10 · the link is hidden after that load");
    eq(await page.evaluate(() => document.activeElement.id), "in-" + OPEN, "10 · the cursor is in the opening box on 1 May too");
    await noEditing("after loading 1 May");

    // Ctrl+Alt+Z: nothing at all while the link is hidden (1 May is up as
    // saved), and a press of the link while it shows, even mid-typing.
    z = await formSnap(page); asks = dayAsks;
    await page.keyboard.press("Control+Alt+z");
    await page.waitForTimeout(700);
    eq(await formSnap(page), z, "8 · Ctrl+Alt+Z on a saved day that is already on screen (no link) changes nothing");
    eq(dayAsks, asks, "8 · …and asks the server nothing");
    await clearDay(d1);
    check(await untilLink(page, true), "8 · after Clear on 1 May the link shows again");
    await page.click("#in-cash_sales");
    await page.keyboard.type("55");                       // no blur: the cursor stays in the box
    const [zres] = await Promise.all([
      page.waitForResponse((x) => x.url().includes("/api/day"), { timeout: 15000 }).catch(() => null),
      page.keyboard.press("Control+Alt+z"),
    ]);
    eq(zres ? zres.status() : 0, 200, "8 · Ctrl+Alt+Z from inside a box mid-typing presses Show saved figures (GET /api/day)");
    await page.waitForTimeout(1200);
    await boxesMatch(day1, "after Ctrl+Alt+Z on 1 May (over the 55 typed)");
    eq(await linkOn(page), false, "8 · …the link is gone after it, as after a click");
    eq(await page.evaluate(() => document.activeElement.id), "in-" + OPEN, "8 · …and the cursor is in the opening balance, as after a click");
    k = await lastKey();
    check(k && k.code === "KeyZ" && k.alt && k.prevented, "8 · Ctrl+Alt+Z was swallowed by the form", JSON.stringify(k));

    // An Off day (2 May): it comes up switched to Off day by itself; after
    // Clear the link shows though the regenerate note is hidden.
    await setDate(page, d2);
    eq(await page.$eval("#chk-closed", (e) => e.checked), true, "10 · picking a saved Off day (2 May) brings it back with the Off day switch on");
    eq(await blankBoxes(page), true, "10 · …with every box blank (its balances were carried, not counted)");
    eq(await linkOn(page), false, "10 · …and no link: the saved day is already on screen");
    eq(await savedNoteOn(page), true, "10 · …the grey note #checks-saved says it is saved");
    await clearDay(d2);
    check(await untilLink(page, true), "10 · Clear on the saved Off day shows the link");
    eq(await page.$eval("#chk-closed", (e) => e.checked), false, "10 · …on a blank Work day");
    eq(await noteOn(page), false, "10 · …while the regenerate note is hidden (an Off day has no ledger)");
    pl = await pressLink();
    eq(await page.$eval("#chk-closed", (e) => e.checked), true, "10 · loading an Off day turns the Off day switch on");
    eq(await blankBoxes(page), true, "10 · …and leaves every box blank");
    eq(await page.evaluate(() => window.scrollY), 0, "10 · …at the top of the page");
    eq(await linkOn(page), false, "10 · hidden right after loading the Off day");
    await noEditing("after loading the Off day");
    await Promise.all([checkFor(page, d2), page.click(".daytype-toggle .opt-trading")]);
    await settle(page);
    eq(await linkOn(page), false, "10 · turning the Off day switch off does not bring the link back");
    await Promise.all([checkFor(page, d2), page.click(".daytype-toggle .opt-closed")]);
    await settle(page);
    eq(await linkOn(page), false, "10 · nor does turning it back on");

    // A day whose ledger waits (5 May): up as saved; after Clear, the link,
    // no regenerate note, no ledger row.
    const day5 = (await getJSON("/api/day?date=" + d5)).day;
    await setDate(page, d5);
    await boxesMatch(day5, "picking 5 May (its ledger waits)");
    eq(await linkOn(page), false, "10 · a saved day whose ledger waits (5 May) comes up as saved, with no link");
    eq(await savedNoteOn(page), true, "10 · …and its grey note #checks-saved");
    await clearDay(d5);
    check(await untilLink(page, true), "10 · Clear on 5 May shows the link");
    eq(await noteOn(page), false, "10 · …with the regenerate note hidden");
    check(!(await rowTitles(page)).includes(SAVED_TITLE), "10 · …and no Day saved, ledger generated row");
    pl = await pressLink();
    await boxesMatch(day5, "after loading 5 May");
    eq(await page.$eval("#chk-closed", (e) => e.checked), false, "10 · loading a Work day turns the Off day switch off");
    eq(await page.evaluate(() => document.activeElement.id), "in-" + OPEN, "10 · the cursor is in the opening box");
    eq(await linkOn(page), false, "10 · hidden right after loading 5 May");

    // A day with a ledger (1 May): after Clear, the note and the link, in that order.
    await setDate(page, d1);
    await page.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    await clearDay(d1);
    check(await untilLink(page, true), "10 · Clear on 1 May (ledger made) shows the link under the grey note");
    const both = await page.evaluate(() => ({ n: document.getElementById("checks-regen").getBoundingClientRect().bottom, l: document.getElementById("checks-load").getBoundingClientRect().top }));
    check(both.l >= both.n - 1, "10 · the link is below the grey note", JSON.stringify(both));

    // The saved figures typed back by hand keep the link; a save takes it down.
    await typeBack(day1);
    await untilText(page, "#predicted", "The day balances.");
    await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    eq(await linkOn(page), true, "10 · typing 1 May's figures back after Clear keeps the link");
    s = await clickSave(page);
    eq(s.status, 200, "10 · 1 May, typed back after Clear, is saved");
    await untilSavedShown(page);
    await settle(page);
    eq(await linkOn(page), false, "10 · a successful save takes the link down");

    // Next day after Clear: the offer goes with the date, and is not there on
    // coming back to it.
    await clearDay(d1);
    check(await untilLink(page, true), "10 · Clear on 1 May shows it once more");
    await typeBack(day1);
    await untilText(page, "#predicted", "The day balances.");
    await settle(page);
    const toD2 = checkFor(page, d2).catch(() => null);
    const [nx] = await Promise.all([
      page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: 120000 }),
      page.click("#btn-next"),
    ]);
    eq(nx.status(), 200, "10 · Next day from 1 May, cleared and typed back as saved, is accepted");
    await toD2;
    await page.waitForTimeout(1200);                      // Next day's smooth scroll to the top, before part 12 measures the scroll
    eq(await shownDate(page), d2, "10 · …and moves on to 2 May");
    eq(await linkOn(page), false, "10 · …where there is no link");
    await setDate(page, d1);
    await boxesMatch(day1, "back on 1 May after Next day");
    eq(await linkOn(page), false, "10 · back on 1 May the day is up as saved, and Clear's offer has ended");

    /* ---- 12 · a date change clears the form ------------------------------- */
    // Since 2026-10-07 a date that is in the books then comes up as it was
    // saved (savedForm) and any other date stays blank (blankForm). Either way
    // nothing of the old day is left on screen.
    let y12 = 0;                                            // scroll position just before a date change
    const mark12 = async () => { y12 = await page.evaluate(() => window.scrollY); };
    const blankForm = async (label) => {
      eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input", (is) => is.every((i) => i.value === "")), true, `12 · ${label}: every money box is empty`);
      eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input",
                           (is) => is.filter((i) => i.classList.contains("invalid") || [...i.classList].some((c) => /^lv\d/.test(c)) || [...i.parentElement.classList].some((c) => /^lv\d/.test(c))).length), 0,
         `12 · ${label}: no red marks or outlines`);
      eq(await page.$eval("#txt-opening-reason", (e) => e.offsetParent === null && e.value === ""), true, `12 · ${label}: the opening reason is hidden and empty`);
      eq(await page.$eval("#txt-reason", (e) => e.offsetParent === null && e.value === ""), true, `12 · ${label}: the day reason is hidden and empty`);
      eq(await page.$eval("#chk-closed", (e) => e.checked), false, `12 · ${label}: Work day`);
      eq(await page.$eval("#chk-genesis", (e) => e.checked), false, `12 · ${label}: the first-day tick is off`);
      eq(await hidden(page, "#predicted"), true, `12 · ${label}: no predicted line`);
      eq(await hidden(page, "#dock-note"), true, `12 · ${label}: no open explanation`);
      eq(await hidden(page, "#dock-msg"), true, `12 · ${label}: nothing under the buttons`);
      eq(await bannerCount(page), 0, `12 · ${label}: no top banner`);
      eq(await loadMsgText(page), null, `12 · ${label}: nothing under the link`);
      // A blank form can make the page shorter, and the browser then pulls the
      // scroll position up to the new end; that is the only move allowed.
      const [yNow, maxY] = await page.evaluate(() => [window.scrollY, document.documentElement.scrollHeight - window.innerHeight]);
      eq(yNow, Math.min(y12, Math.max(0, maxY)), `12 · ${label}: the page did not scroll (only the browser's own clamp to a shorter page)`);
    };
    // A saved date: that day's own figures, reasons and kind of day, and none
    // of the old day's; nothing open, nothing said, no link.
    const savedForm = async (day, label) => {
      const bad = [];
      for (const [k, v] of Object.entries(day.amounts || {})) {
        const got = await value(page, "#in-" + k);
        if (got === null) continue;
        const want = day.status === "closed" ? null : v;    // an Off day comes up with every box blank
        if (got === "" ? (want !== null && want !== "" && Number(want) !== 0) : Number(got) !== Number(want)) bad.push(`${k}: ${got} vs ${want}`);
      }
      eq(bad.join("; "), "", `12 · ${label}: every box holds that day's saved figure`);
      eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input", (is) => is.filter((i) => i.classList.contains("invalid")).length), 0,
         `12 · ${label}: no box is marked red`);
      eq(await value(page, "#txt-opening-reason"), day.openingReason || "", `12 · ${label}: the opening reason is that day's own`);
      eq(await value(page, "#txt-reason"), day.reason || "", `12 · ${label}: the day reason is that day's own`);
      eq(await page.$eval("#chk-closed", (e) => e.checked), day.status === "closed", `12 · ${label}: the kind of day is that day's own`);
      eq(await page.$eval("#chk-genesis", (e) => e.checked), false, `12 · ${label}: the first-day tick is off`);
      eq(await hidden(page, "#dock-note"), true, `12 · ${label}: no open explanation`);
      eq(await hidden(page, "#dock-msg"), true, `12 · ${label}: nothing under the buttons`);
      eq(await bannerCount(page), 0, `12 · ${label}: no top banner`);
      eq(await loadMsgText(page), null, `12 · ${label}: nothing under the link`);
      eq(await linkOn(page), false, `12 · ${label}: no Show saved figures link (the day is already on screen)`);
      const [yNow, maxY] = await page.evaluate(() => [window.scrollY, document.documentElement.scrollHeight - window.innerHeight]);
      eq(yNow, Math.min(y12, Math.max(0, maxY)), `12 · ${label}: the page did not scroll (only the browser's own clamp to a shorter page)`);
    };
    // 7 May holds both reasons: pick it (it comes up as saved), then step the
    // day list with the keyboard to 6 May, which is saved too.
    const day6 = (await getJSON("/api/day?date=" + d6)).day;
    await setDate(page, d7);
    eq(await page.$eval("#txt-reason", (e) => e.value), RSN_DAY, "12 · 7 May is loaded with its reason before the date change (picked: it comes up as saved)");
    eq(await linkOn(page), false, "12 · …with no link");
    await page.focus("#sel-day");
    await mark12();
    await Promise.all([checkFor(page, d6), page.keyboard.press("ArrowUp")]);
    eq(await shownDate(page), d6, "12 · ArrowUp on the day list moves to 6 May");
    await savedForm(day6, "a keyboard step to 6 May (saved)");
    eq(await page.evaluate(() => document.activeElement.id), "sel-day", "12 · focus stays on the day list");
    // A saved date with a ledger, with an explanation open and a typed figure.
    await setDate(page, d1);
    await page.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    await page.locator("#checks-list li", { has: page.locator(".check-title", { hasText: SAVED_TITLE }) }).locator(".check-more").click();
    await page.waitForFunction(() => !document.getElementById("dock-note").hidden, null, { timeout: 5000 });
    await setAmount(page, "cash_sales", "123");
    await page.waitForTimeout(1200);                       // let the explanation's own smooth scroll finish
    // Month list: 1 May -> 1 April (not in the books).
    await mark12();
    await Promise.all([checkFor(page, "2026-04-01"), page.selectOption("#sel-month", "4")]);
    await blankForm("the month list to 1 April");
    eq(await shownDate(page), "2026-04-01", "12 · the month list changed the date");
    await settle(page);
    eq(await rowTitles(page).then((t) => t.includes(SAVED_TITLE)), false, "12 · 1 April carries no Day saved row from 1 May");
    eq(await noteOn(page), false, "12 · …and no grey note");
    eq(await linkOn(page), false, "12 · a date not in the books never shows the link");
    // Year list: back to 2026-05-01 via the day... use year list round trip.
    await mark12();
    await Promise.all([checkFor(page, "2025-04-01"), page.selectOption("#sel-year", "2025")]);
    await blankForm("the year list to 1 April 2025");
    await Promise.all([checkFor(page, "2026-04-01"), page.selectOption("#sel-year", "2026")]);
    // The pending day (5 May): arriving shows it as saved, with its own rows
    // and nothing left from the old date.
    await setAmount(page, "cash_sales", "50");
    await mark12();
    await setDate(page, d5);
    await savedForm(day5, "5 May (its ledger waits)");
    const typed5 = Object.fromEntries(cfg.groups.flatMap((g) => g.categories.map((c) => [c.key, day5.amounts[c.key] ?? null])));
    const own5 = await (await fetch(BASE + "/api/check", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ date: d5, amounts: typed5, reason: day5.reason || "", openingReason: day5.openingReason || "" }) })).json();
    const rows5 = await rowTitles(page);
    eq(JSON.stringify([...rows5].sort()), JSON.stringify(own5.findings.map((f) => f.title).sort()),
       "12 · its rows are 5 May's own (what a check of its saved figures says), nothing left from the old date");
    // The reported scenario: save a pending day, then pick another date.
    await setAmount(page, OPEN, "1300");
    await setAmount(page, CLOSE, "1300");
    await untilText(page, "#predicted", "The day balances.");
    s = await clickSave(page);
    eq(s.status, 200, "12 · 5 May saved again (its ledger still waits)");
    await page.waitForFunction(() => { const n = document.getElementById("checks-saved"); return !!n && !n.hidden && n.getClientRects().length > 0; }, null, { timeout: 40000 });
    await mark12();
    await setDate(page, "2026-10-04");
    await blankForm("4 October after saving a pending day");
    eq(await hidden(page, "#dock-msg"), true, "12 · the pending day's confirmation is gone under the new date");

    // Back on 1 May (a ledger made) for the Esc part, as before.
    await setDate(page, d1);
    await page.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    await setAmount(page, "cash_sales", "999");

    /* ---- 11 · Esc ---------------------------------------------------------- */
    const key = () => page.evaluate(() => window.__keys[window.__keys.length - 1]);
    const savedLi1 = page.locator("#checks-list li", { has: page.locator(".check-title", { hasText: SAVED_TITLE }) });
    await savedLi1.locator(".check-more").click();
    await page.waitForFunction(() => { const n = document.getElementById("dock-note"); return n && !n.hidden; }, null, { timeout: 40000 });
    eq(await page.$eval("#dock-note .note-close", (e) => e.title), "Close (Esc)", "11 · the X has title \"Close (Esc)\"");
    eq(await page.$eval("#dock-note .note-close", (e) => e.getAttribute("aria-keyshortcuts")), "Escape", "11 · and aria-keyshortcuts \"Escape\"");
    eq(await page.$eval("#dock-note .note-close", (e) => e.getAttribute("aria-label")), "Close this explanation", "11 · its aria-label is unchanged");
    eq(await page.evaluate(() => document.activeElement.id), "dock-note", "11 · the cursor went to the open explanation");
    await page.keyboard.press("Escape");
    await page.waitForTimeout(300);
    eq(await hidden(page, "#dock-note"), true, "11 · Esc closes the open explanation");
    let ek = await key();
    check(ek && ek.code === "Escape" && ek.prevented, "11 · and that Esc was consumed (preventDefault)", JSON.stringify(ek));
    const back = await page.evaluate(() => { const a = document.activeElement; const li = a.closest("li"); return { cls: a.className, text: a.textContent, inSaved: !!li && li.textContent.includes("Day saved, ledger generated") }; });
    check(back.cls.includes("check-more") && back.inSaved, "11 · the cursor is back on that row's See full explanation link", JSON.stringify(back));
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => !document.getElementById("dock-note").hidden, null, { timeout: 5000 });
    await page.click("#dock-note .note-close");
    await page.waitForTimeout(300);
    const back2 = await page.evaluate(() => document.activeElement.className);
    check(back2.includes("check-more"), "11 · the X still returns the cursor to the link too", back2);
    // Esc with nothing open: nothing changes, and it is not swallowed.
    await page.click("#in-cash_sales");
    const snap = () => page.evaluate(() => JSON.stringify({
      a: document.activeElement.id, v: [...document.querySelectorAll("input")].map((i) => i.value + (i.checked ? "!" : "")),
      note: document.getElementById("dock-note").hidden, sheet: document.getElementById("checks").className,
      rows: document.getElementById("checks-list").textContent, ban: document.getElementById("banner-area").textContent,
      msg: document.getElementById("dock-msg").textContent, link: document.getElementById("checks-load").hidden, y: window.scrollY,
    }));
    const s0 = await snap();
    await page.keyboard.press("Escape");
    await page.waitForTimeout(300);
    eq(await snap(), s0, "11 · Esc with nothing open changes nothing");
    ek = await key();
    check(ek && ek.code === "Escape" && !ek.prevented, "11 · and is not swallowed (no preventDefault)", JSON.stringify(ek));
    await savedLi1.locator(".check-more").click();
    await page.waitForFunction(() => !document.getElementById("dock-note").hidden, null, { timeout: 5000 });
    await page.keyboard.press("Escape");
    await page.keyboard.press("Escape");
    await page.waitForTimeout(300);
    eq(await hidden(page, "#dock-note"), true, "11 · a second Esc after it closed does no harm");

    /* ---- 9 · layout, codes, console at 1536------------------------------ */
    await setDate(page, d1);
    await page.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    const scroll1536 = await page.evaluate(() => ({
      doc: document.documentElement.scrollWidth, win: document.documentElement.clientWidth,
      wide: [...document.querySelectorAll("body *")]
        .filter((e) => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
        .slice(0, 4).map((e) => e.tagName + (e.id ? "#" + e.id : "." + e.className)),
    }));
    check(scroll1536.doc <= scroll1536.win + 1, "9 · no horizontal scrolling at 1536", `${scroll1536.doc} > ${scroll1536.win}; ${scroll1536.wide.join(", ")}`);
    const floating = await page.evaluate(() => [...document.querySelectorAll("body *")]
      .filter((e) => ["fixed", "sticky"].includes(getComputedStyle(e).position))
      .map((e) => (e.id ? "#" + e.id : e.tagName) + ":" + getComputedStyle(e).position));
    eq(floating.join(" "), "#checks:sticky", "9 · nothing floats over the form except the Checks column's own sticky place");
    const codes = await page.evaluate(() => (document.body.innerText.match(/\bL[1-4]-[A-Z]\b/g) || []));
    eq(codes.join(" "), "", "9 · no warning code is visible");
    check(errors.length === 0, "9 · no console errors at 1536", errors.slice(0, 3).join(" | "));
    await ctx.close();

    /* ---- 9 · the same saved day at 390px --------------------------------- */
    const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
    await mutate(ctx2);
    const p2 = await ctx2.newPage();
    const errors2 = [];
    p2.on("console", (m) => {
      if (m.type() !== "error") return;
      const line = `${m.text()} [${(m.location() && m.location().url) || ""}]`;
      if (!noise(line)) errors2.push(line);
    });
    p2.on("pageerror", (e) => errors2.push("pageerror: " + e.message));
    await Promise.all([checkFor(p2, today), p2.goto(BASE)]);
    await p2.waitForSelector("#in-" + OPEN);
    await headerChecks(p2, "9 · at 390 ");
    await setDate(p2, d1);
    await p2.waitForFunction(() => !document.getElementById("checks-regen").hidden, null, { timeout: 40000 });
    eq(await narrow(p2), true, "9 · at 390 the Checks panel is behind the status pill");
    await p2.click("#dock-status");
    await p2.waitForFunction(() => document.getElementById("checks").classList.contains("open"), null, { timeout: 5000 });
    const seen = await p2.$eval("#checks-regen", (e) => !e.hidden && e.getClientRects().length > 0);
    eq(seen, true, "9 · opened, the sheet shows the grey note");
    check((await rowTitles(p2)).includes(SAVED_TITLE), "9 · and the Day saved, ledger generated row");
    eq(await bannerCount(p2), 0, "9 · no banner at the top at 390");
    const scroll390 = await p2.evaluate(() => ({
      doc: document.documentElement.scrollWidth, win: document.documentElement.clientWidth,
      wide: [...document.querySelectorAll("body *")]
        .filter((e) => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
        .slice(0, 4).map((e) => e.tagName + (e.id ? "#" + e.id : "." + e.className)),
    }));
    check(scroll390.doc <= scroll390.win + 1, "9 · no horizontal scrolling at 390", `${scroll390.doc} > ${scroll390.win}; ${scroll390.wide.join(", ")}`);
    await p2.locator("#checks").scrollIntoViewIfNeeded();
    await p2.screenshot({ path: path.join(SHOTS, "narrow-390.png"), fullPage: true });
    // 10/11 at 390: 1 May came up as saved, so the open sheet has no link until
    // Clear; then it shows there, and the pill and count leave it out; Esc
    // closes the sheet; and Ctrl+Alt+Z reaches the link with the sheet closed.
    eq(await linkOn(p2), false, "10 · at 390 a saved day that came up by itself has no link in the open sheet");
    await Promise.all([checkFor(p2, d1), p2.click("#btn-clear")]);
    if (!(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")))) await p2.click("#dock-status");
    await p2.waitForFunction(() => document.getElementById("checks").classList.contains("open"), null, { timeout: 5000 }).catch(() => {});
    check(await linkOn(p2), "10 · at 390, after Clear, the link shows in the open sheet");
    eq(await p2.$eval("#dock-status", (e) => /saved figures/i.test(e.textContent)), false, "10 · at 390 the pill does not mention it");
    const rowsN2 = await p2.$$eval("#checks-list li", (l) => l.length);
    eq(await p2.$eval("#checks-count", (e) => (e.hidden ? "" : e.textContent.trim())), rowsN2 ? String(rowsN2) : "", "10 · at 390 the count is rows only");
    await p2.screenshot({ path: path.join(SHOTS, "narrow-390-sheet-open.png") });
    await p2.locator("#checks").screenshot({ path: path.join(SHOTS, "narrow-390-sheet-panel.png") });
    await p2.keyboard.press("Escape");
    await p2.waitForTimeout(400);
    eq(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")), false, "11 · at 390 Esc still closes the Checks sheet");
    await p2.keyboard.press("Escape");
    eq(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")), false, "11 · Esc with nothing open at 390 changes nothing");
    const [z390] = await Promise.all([
      p2.waitForResponse((x) => x.url().includes("/api/day"), { timeout: 15000 }).catch(() => null),
      p2.keyboard.press("Control+Alt+z"),
    ]);
    eq(z390 ? z390.status() : 0, 200, "8 · at 390 Ctrl+Alt+Z presses the link inside the closed Checks sheet");
    await p2.waitForTimeout(1200);
    eq(await value(p2, "#in-" + CLOSE), Number(day1.amounts[CLOSE]).toFixed(2), "8 · …and 1 May's saved figures are back (its closing balance)");
    eq(await hidden(p2, "#checks-load"), true, "8 · …and the link is gone (hidden, not only out of sight in the closed sheet)");
    // A date change takes an open sheet down (it described the old day).
    await p2.click("#dock-status");
    check(await p2.waitForFunction(() => document.getElementById("checks").classList.contains("open"), null, { timeout: 5000 }).then(() => true).catch(() => false), "12 · at 390 the sheet can be opened again");
    await Promise.all([checkFor(p2, d2), p2.selectOption("#sel-day", "2")]);
    await p2.waitForTimeout(700);
    eq(await p2.evaluate(() => document.getElementById("checks").classList.contains("open")), false, "12 · at 390 picking another date closes the open Checks sheet");
    eq(await p2.evaluate(() => document.getElementById("sel-day").value), "2", "12 · …and the pick is kept");
    // 6 · 2 May came up as the saved Off day. Saved again where the panel is
    // hidden, it is confirmed under the buttons.
    eq(await p2.$eval("#chk-closed", (e) => e.checked), true, "6 · at 390 the saved Off day (2 May) came up switched to Off day");
    p2.on("dialog", (d) => d.accept());                    // the "mark as CLOSED?" question
    await p2.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
    const [o390] = await Promise.all([
      p2.waitForResponse((r) => r.url().includes("/api/save"), { timeout: 120000 }),
      p2.click("#btn-save"),
    ]);
    eq(o390.status(), 200, "6 · at 390 the Off day is saved again");
    await untilText(p2, "#dock-msg", "saved to the books");
    eq(await dockSentence(p2), `${pretty(d2)} saved to the books.`, "6 · at 390, where the Checks panel is hidden, the Off day is confirmed in #dock-msg");
    eq(await p2.$eval("#dock-msg", (e) => !!e.closest("#dock")), true, "6 · the message sits in the dock, beside the buttons");
    eq(await bannerCount(p2), 0, "6 · and nothing is said at the top at 390");
    await p2.locator("#dock").screenshot({ path: path.join(SHOTS, "off-day-save-390.png") });
    check(errors2.length === 0, "9 · no console errors at 390", errors2.slice(0, 3).join(" | "));
    await ctx2.close();
  } finally {
    await browser.close();
  }

  console.log(`\n${pass} pass, ${fail} fail${MUTATE ? "  (MUTATE=1: the link and Ctrl+Alt+Z checks are expected to fail)" : ""}`);
  console.log(fail === 0 ? "ALL PASS" : `${fail} FAILED`);
  process.exit(fail === 0 || MUTATE ? 0 : 1);
}

main().catch((e) => { console.log("FAIL  the script itself stopped: " + (e && e.stack || e)); process.exit(2); });
