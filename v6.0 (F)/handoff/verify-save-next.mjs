/* verify-save-next.mjs — browser verification of the Save / Next day split
   (2026-09-15). One button, "Save & next day", became two: #btn-save writes the
   day and stays on it, #btn-next asks POST /api/next and moves on only if the
   server says the day is in the books exactly as shown.

   UPDATED 2026-09-29 for the owner's simplification: the top banner
   "<date> saved to the books. Saving again will replace it." with its
   "Edit that day" button, the Cancel edit button and the "Replace the ledger
   file" tick box are gone. After a save there is NO banner at the top: the
   Checks panel row "Day saved, ledger generated" (meta "Good to know") and the
   grey note #checks-regen ("Saving again will regenerate the ledgers ...") say
   it. Saving always regenerates the ledger. The dock actions are Clear, Save,
   Next day. A day with no ledger file (an Off day, or a ledger waiting on a
   missing day) is confirmed in #dock-msg instead. The new behaviour is covered
   in more depth by verify-ui-2026-09-29.mjs.

   UPDATED 2026-10-06: a date change now clears the form. Picking another date
   in the day, month or year list does what Clear does on that date (blank
   boxes, no reasons, Work day, first-day tick off, Checks and dock messages
   gone). Before, the figures stayed and the Checks re-ran against them, so a
   saved day's "ledger waiting" row lingered under the next date. The Checks
   panel's "Show saved figures" link must then show for any saved date (ledger
   made, ledger waiting, Off day). Block (i) is new and covers it; (f) no longer
   needs its Clear click after changing the date.

   UPDATED 2026-10-07 for the owner's decision that a saved day comes up by
   itself. Whenever the form lands on a date (opening the page, picking a date,
   Next day) the server is asked for it (/api/day): a saved Work day comes up
   with its figures and reasons, a saved Off day with the switch on and every
   box blank, and any other date blank, as before. Typed figures still never
   follow to another date. "Show saved figures" shows only after Clear on a
   saved day, and Ctrl+Alt+Z presses it. After an Off day is saved on a wide
   window nothing is said under the buttons any more: the grey note
   #checks-saved ("This day has been saved. ...") says it in the Checks panel;
   below 1100px, where the panel is hidden, the line under the buttons still
   says it. (e) follows that, (i) is rewritten for the new contract, and (j) is
   new: Next day onto days that are already saved.

   WHAT IT WALKS, at 1440px and again at 390px, with the books emptied between
   the two passes so both see the same story:
     a  a fresh page: both buttons there, Save is the green primary, and
        Next day on an untouched blank day is refused with
        "… has not been saved yet. Save it before moving on." — under the
        buttons, in #dock-msg, and not in the banner at the top of the page
     b  a balancing first day (1 May 2026), first-day box ticked, Save — no
        top banner; the Checks row "Day saved, ledger generated" and the grey
        note instead; still on the date, figures still in the boxes
     c  Next day — the form moves to 2 May, blank, cursor in the opening box,
        and no Checks row about a balance nobody has reached
     d  2 May saved, then a figure changed: Next day is refused with
        "The figures on screen for … have not been saved.", Save again
        (no tick box: it always regenerates), then Next day moves on
     e  an Off day saved: the grey note "This day has been saved." in the
        Checks panel, and "<date> saved to the books." under the buttons only
        below 1100px (2026-10-07); left
     f  today saved: Next day says "Today is saved. There is no next day to
        enter yet." under the buttons, and stays
     g  a day that needs a reason: Save asks for the reason and posts nothing,
        Next day still refuses, then reason + Save + Next day moves on
     i  a date change (2026-10-06, 2026-10-07): typed figures, reasons and the
        Off day switch never follow; an unsaved date comes up blank; a saved
        one comes up as saved (ledger made, ledger waiting, Off day) with no
        link; Clear on a saved date offers "Show saved figures" (click, or
        Ctrl+Alt+Z), which brings it back; an unsaved date never offers it;
        Clear keeps the date; arrow keys clear too
     j  Next day onto saved days (2026-10-07): each comes up as saved, with
        the cursor in the opening balance, and Next day from it moves on
     h  layout: no horizontal scrolling with the saved state showing,
        nothing floating over the page, no console errors, no warning codes

   COUNTS: 185 checks at each width, all passing on 2026-10-07 (134 at each
   width before that day's change; 185 since the Off day's note was shortened
   to "This day has been saved.").

   HOW TO RUN (never against the real Records folder):
     1. In a scratch folder:  npm init -y && npm i playwright-core@1   (drives
        the installed Chrome; no browser download), then copy this file there.
     2. From your copy of v5.0, with LEDGER_ROOT set to an EMPTY scratch folder,
        LDGR_NO_BROWSER=1, LDGR_NO_DIGEST=1, and LDGR_NOTIFY_CONFIG set to a
        path inside the scratch folder that does not exist:
           julia --startup-file=no server.jl 8798
        (A server started beside a working notify.toml would hand the owner a
        report built from the scratch books within seconds.) The start-up
        "Email" line must read "off (no notify.toml)".
        Warm the endpoints with curl first; Julia compiles each one on its
        first call, which takes seconds.
     3. From the scratch folder, with LEDGER_ROOT set to the SAME folder (the
        script empties the books between the two passes):
           node verify-save-next.mjs
        (BASE=http://127.0.0.1:<port> for a server on another port)
        -> PASS/FAIL lines, a count per width, screenshots of the dock in ./shots
        (OUT=<folder> puts them elsewhere)
     4. Stop the server; confirm nothing listens on 8798.

   Dates are chosen relative to /api/config's `today`, and the run starts from
   an empty set of books, so 1 May 2026 is the first day on record. */

import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE  = process.env.BASE || "http://127.0.0.1:8798";
const SHOTS = path.resolve(process.env.OUT || "shots");
fs.mkdirSync(SHOTS, { recursive: true });

/* ---------------------------------------------------------------------- */
/* Reporting                                                               */
/* ---------------------------------------------------------------------- */
let width = 0;
const tally = new Map();          // width -> {pass, fail}
const score = () => tally.get(width) || (tally.set(width, { pass: 0, fail: 0 }), tally.get(width));

const check = (cond, label, extra) => {
  const s = score();
  if (cond) { s.pass++; console.log(`PASS  [${width}] ${label}`); }
  else      { s.fail++; console.log(`FAIL  [${width}] ${label}${extra ? "  -- " + extra : ""}`); }
  return !!cond;
};
const eq = (got, want, label) => check(got === want, label, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

/* ---------------------------------------------------------------------- */
/* Dates and the books                                                     */
/* ---------------------------------------------------------------------- */
const shift = (iso, n) => {
  const [y, m, d] = iso.split("-").map(Number);
  const t = new Date(y, m - 1, d + n, 12);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
};
const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];
const pretty = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${MONTHS[m - 1]} ${y}`; };
const getJSON = async (p) => (await fetch(BASE + p)).json();

/* Empty the scratch books between the two passes, so the second width walks
   exactly the same story as the first. Refuses anything that looks like the
   real Records folder. */
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

/* ---------------------------------------------------------------------- */
/* Page helpers                                                            */
/* ---------------------------------------------------------------------- */
const text   = (page, sel) => page.$eval(sel, (e) => e.textContent.trim()).catch(() => null);
const hidden = (page, sel) => page.$eval(sel, (e) => e.hidden).catch(() => true);
const value  = (page, sel) => page.$eval(sel, (e) => e.value).catch(() => null);

const bannerSentence = (page) => text(page, "#banner-area .banner span");
const bannerKind     = (page) => page.$eval("#banner-area .banner", (e) => e.className.replace("banner", "").trim()).catch(() => null);
const bannerButton   = (page) => text(page, "#banner-area .banner button");
// After a save the top of the page says nothing at all (2026-09-29).
const bannerCount    = (page) => page.$$eval("#banner-area .banner", (b) => b.length);
const rowTitles      = (page) => page.$$eval("#checks-list li .check-title", (n) => n.map((x) => x.textContent.trim()));
const rowMeta        = (page, title) => page.$$eval("#checks-list li", (ls, t) => {
  const li = ls.find((l) => l.querySelector(".check-title").textContent.trim() === t);
  return li ? li.querySelector(".check-meta").textContent.trim() : null;
}, title);
const SAVED_TITLE = "Day saved, ledger generated";
// Below 1100px the whole Checks panel is closed until the pill in the dock opens
// it, so "on" means the note is not hidden, and "on screen" opens the panel first.
const noteShown   = (page) => page.$eval("#checks-regen", (e) => !e.hidden).catch(() => false);
// The other grey note, for a saved day with no ledger file: an Off day, or a
// day whose ledger is waiting on the day before.
const savedNoteShown = (page) => page.$eval("#checks-saved", (e) => !e.hidden).catch(() => false);
const SAVED_NOTE = "This day has been saved. Saving again will rewrite it with the current figures.";
// An Off day has no figures on screen, so its note keeps only the first sentence (2026-10-07).
const SAVED_NOTE_OFF = "This day has been saved.";
// The words a person can see: anything inside the element that is hidden is left out.
const shownText = (page, sel) => page.$eval(sel, (e) => {
  const c = e.cloneNode(true);
  c.querySelectorAll("[hidden]").forEach((n) => n.remove());
  return c.textContent.trim();
}).catch(() => null);
async function noteOnScreen(page, sel = "#checks-regen") {
  const narrow = await page.$eval("#dock-status", (e) => e.getClientRects().length > 0);
  if (narrow) await page.click("#dock-status");
  const seen = await page.$eval(sel, (e) => !e.hidden && e.getClientRects().length > 0).catch(() => false);
  if (narrow) await page.click("#dock-status");
  return seen;
}
// Nothing the banner says should also be said at the top of the page.
const bannerHas      = (page, needle) =>
  page.$eval("#banner-area", (e, t) => e.textContent.includes(t), needle).catch(() => false);

/* What Next day answered, under the buttons (2026-09-15, later). The sentence
   is only there while the element is showing, so a stale one cannot pass. */
const dockSentence = (page) => page.$eval("#dock-msg", (e) => (e.hidden ? null : e.textContent.trim())).catch(() => null);
const dockKind     = (page) => page.$eval("#dock-msg", (e) => e.className.replace("dock-msg", "").trim()).catch(() => null);

const shownDate = (page) => page.evaluate(() => {
  const v = (id) => document.getElementById(id).value;
  return `${v("sel-year")}-${String(v("sel-month")).padStart(2, "0")}-${String(v("sel-day")).padStart(2, "0")}`;
});

// The check for one date, sent and answered: every date change and every reset
// asks for one, and waiting for the exact date keeps an older answer from
// satisfying the wait.
const checkFor = (page, iso) => page.waitForResponse(async (r) => {
  if (!r.url().includes("/api/check")) return false;
  try { return JSON.parse(r.request().postData() || "{}").date === iso; } catch { return false; }
}, { timeout: 40000 });

const untilText = (page, sel, needle) => page.waitForFunction(
  ([s, t]) => { const n = document.querySelector(s); return !!n && n.textContent.includes(t); },
  [sel, needle], { timeout: 40000 });

const untilShown = (page, sel) => page.waitForFunction(
  (s) => { const n = document.querySelector(s); return !!n && !n.hidden && n.getClientRects().length > 0; },
  sel, { timeout: 40000 });

// After a save has been answered and the form has re-checked: either the
// "Day saved" row is in the Checks panel or the dock says the day was saved.
const untilSavedShown = (page) => page.waitForFunction(() => {
  const row = [...document.querySelectorAll("#checks-list .check-title")]
    .some((n) => n.textContent.trim() === "Day saved, ledger generated");
  const msg = document.getElementById("dock-msg");
  const note = document.getElementById("checks-saved");
  return row || (!!note && !note.hidden && note.getClientRects().length > 0) || (!msg.hidden && msg.textContent.includes("saved to the books"));
}, null, { timeout: 40000 });

async function setDate(page, iso) {
  const [y, m, d] = iso.split("-").map(Number);
  await page.selectOption("#sel-year", String(y));
  await page.selectOption("#sel-month", String(m));
  await Promise.all([checkFor(page, iso), page.selectOption("#sel-day", String(d))]);
}

async function setAmount(page, key, v) {
  await page.fill("#in-" + key, v);
  await page.$eval("#in-" + key, (e) => e.blur());
}

/* Save. The click is paired with the POST it should make, except when the form
   is expected to stop first (a missing reason), where nothing is posted. */
async function clickSave(page) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/save"), { timeout: 120000 }),
    page.click("#btn-save"),
  ]);
  return { status: res.status(), body: await res.json().catch(() => null) };
}

async function clickNext(page) {
  const [res] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/next"), { timeout: 120000 }),
    page.click("#btn-next"),
  ]);
  return { status: res.status(), body: await res.json().catch(() => null) };
}

/* Next day, expecting the form to land on `iso`. Moving on resets the form,
   asks the server for that date as saved (/api/day, 2026-10-07) and then runs
   one check on what ends up on screen; that wait is registered BEFORE the
   click, because the answer can arrive while the first assertions run. */
async function clickNextTo(page, iso) {
  const settled = checkFor(page, iso).catch(() => null);
  const r = await clickNext(page);
  if (r.status === 200 && r.body && r.body.next === iso) await settled;
  return r;
}

/* ---------------------------------------------------------------------- */
/* One pass at one width                                                   */
/* ---------------------------------------------------------------------- */
async function pass(browser, w, h, cfg) {
  width = w;
  score();
  emptyBooks();

  const today = cfg.today;
  const OPEN = cfg.openingKey, CLOSE = cfg.closingKey, DEP = cfg.depositKey;
  const d1 = "2026-05-01", d2 = "2026-05-02", d3 = "2026-05-03", d4 = "2026-05-04", d5 = "2026-05-05";

  const ctx = await browser.newContext({ viewport: { width: w, height: h } });
  const page = await ctx.newPage();

  // A refused save or move answers 4xx on purpose, and Chrome logs every one of
  // those as a console error. Those are the answers being tested, not defects.
  const errors = [];
  // The URL is in the message's location, not in its text, so both are read.
  const noise = (t) => /favicon/i.test(t) ||
                       (/api\/(next|save)/.test(t) && /\b(400|409)\b/.test(t));
  page.on("console", (m) => {
    if (m.type() !== "error") return;
    const where = (m.location() && m.location().url) || "";
    const line = `${m.text()} [${where}]`;
    if (!noise(line)) errors.push(line);
  });
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
  page.on("dialog", (d) => d.accept());          // the "mark as CLOSED?" question

  let posts = 0;
  page.on("request", (r) => { if (r.url().includes("/api/save") && r.method() === "POST") posts++; });

  await Promise.all([checkFor(page, today), page.goto(BASE)]);
  await page.waitForSelector("#in-" + OPEN);

  /* ---- (a) the fresh page, and Next day on a blank day ---------------- */
  const ids = await page.$$eval(".dock-actions button", (bs) => bs.map((b) => b.id));
  eq(ids.join(" "), "btn-clear btn-save btn-next", "a · dock actions in order Clear, Save, Next day");
  eq(await page.$$eval("#btn-cancel-edit, #force-line, #chk-force", (n) => n.length), 0, "a · no Cancel edit button and no replace-the-ledger tick box");
  eq(await page.$eval("#checks-regen", (e) => e.hidden), true, "a · the grey note is not shown for a date with no ledger");
  eq(await text(page, "#btn-save"), "Save", "a · the primary button says Save");
  eq(await text(page, "#btn-next"), "Next day", "a · the second button says Next day");
  eq(await page.$eval("#btn-save", (e) => e.className), "btn-primary", "a · Save is the primary button");
  eq(await page.$eval("#btn-next", (e) => e.className), "btn-ghost", "a · Next day is a plain outline button");
  eq(await page.$$eval(".btn-primary", (b) => b.length), 1, "a · exactly one primary button on the page");
  eq(await page.$eval("#btn-save", (e) => getComputedStyle(e).backgroundColor), "rgb(31, 111, 92)", "a · Save is the green accent");
  eq(await page.$eval("#btn-next", (e) => e.disabled), false, "a · Next day is not greyed out just because the day is unsaved");

  let r = await clickNext(page);
  eq(r.status, 409, "a · Next day on a blank day is refused");
  eq(r.body.saved, false, "a · …because it was never saved");
  await untilText(page, "#dock-msg", "has not been saved yet");
  eq(await dockSentence(page), `${pretty(today)} has not been saved yet. Save it before moving on.`,
     "a · the message under the buttons is the server's sentence");
  eq(await dockKind(page), "warn", "a · shown as a warning, not an error");
  eq(await bannerHas(page, "has not been saved yet"), false,
     "a · and not at the top of the page, where the person cannot see it");
  eq(await bannerButton(page), null, "a · no extra button is offered");
  eq(await shownDate(page), today, "a · the form stays on the date");

  /* ---- (b) a balancing first day, saved --------------------------------*/
  await setDate(page, d1);
  eq(await hidden(page, "#dock-msg"), true, "b · the refusal goes once another date is picked");
  await setAmount(page, OPEN, "1000");
  await setAmount(page, "cash_sales", "500");
  await setAmount(page, DEP, "300");
  await setAmount(page, CLOSE, "1200");
  await untilText(page, "#predicted", "The day balances.");
  await untilShown(page, "#genesis-line");
  await page.check("#chk-genesis");
  let s = await clickSave(page);
  eq(s.status, 200, "b · Save writes the first day");
  await untilSavedShown(page);
  eq(await bannerCount(page), 0, "b · no banner at the top after a save");
  check((await rowTitles(page)).includes(SAVED_TITLE), "b · the Checks panel says Day saved, ledger generated", JSON.stringify(await rowTitles(page)));
  eq(await rowMeta(page, SAVED_TITLE), "Good to know", "b · as a Good to know row");
  eq(await noteShown(page), true, "b · the grey note about saving again is showing");
  eq(await noteOnScreen(page), true, "b · and can be seen (through the pill on a narrow screen)");
  eq(await text(page, "#checks-regen"), "Saving again will regenerate the ledgers with the current figures and accounts.", "b · with the owner's words");
  eq(await bannerHas(page, "Edit that day"), false, "b · no Edit that day button at the top");
  // Where the Checks panel is hidden (a narrow window) the dock says the day is saved.
  eq(await hidden(page, "#dock-msg"), width >= 1100, "b · a day whose ledger exists needs no line under the buttons unless the panel is hidden");
  eq(await hidden(page, "#dock-msg"), width >= 1100, "b · a day whose ledger exists needs no line under the buttons unless the panel is hidden");
  eq(await shownDate(page), d1, "b · Save stays on the day");
  eq(await value(page, "#in-" + OPEN), "1000.00", "b · the opening balance is still in its box");
  eq(await value(page, "#in-" + CLOSE), "1200.00", "b · the closing balance is still in its box");
  eq(await page.$$eval("#force-line, #chk-force", (n) => n.length), 0, "b · no replace-the-ledger-file tick box");

  await page.locator("#dock").screenshot({ path: path.join(SHOTS, `dock-saved-${w}.png`) });

  /* ---- (c) Next day moves on ----------------------------------------- */
  r = await clickNextTo(page, d2);
  eq(r.status, 200, "c · Next day is allowed once the day is saved");
  eq(r.body.next, d2, "c · the server names the day after");
  eq(await shownDate(page), d2, "c · the form moves to 2 May");
  eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input",
                       (is) => is.every((i) => i.value === "")), true, "c · every box is blank");
  eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "in-" + OPEN,
     "c · the cursor is in the opening balance box");
  eq(await page.$$eval("#checks-list li", (ls) => ls.map((l) => l.dataset.field || "")).then(
       (f) => f.filter((x) => x === OPEN || x === CLOSE).length), 0,
     "c · no Checks row about a balance nobody has reached");
  eq(await hidden(page, "#reason-box"), true, "c · no reason box yet");
  eq(await hidden(page, "#opening-reason-box"), true, "c · no opening reason box yet");

  /* ---- (d) figures changed after a save ------------------------------- */
  await setAmount(page, OPEN, "1200");
  await setAmount(page, "cash_sales", "400");
  await setAmount(page, CLOSE, "1600");
  await untilText(page, "#predicted", "The day balances.");
  s = await clickSave(page);
  eq(s.status, 200, "d · 2 May saved");
  await untilSavedShown(page);

  // Two boxes change together so the day still balances: the point being tested
  // is that what is on screen no longer matches the books, not the arithmetic.
  await setAmount(page, "cash_sales", "450");
  await setAmount(page, CLOSE, "1650");
  await untilText(page, "#predicted", "The day balances.");
  r = await clickNext(page);
  eq(r.status, 409, "d · Next day is refused while a changed figure is unsaved");
  eq(r.body.changed, true, "d · …because the day on screen differs from the books");
  await untilText(page, "#dock-msg", "have not been saved");
  eq(await dockSentence(page), `The figures on screen for ${pretty(d2)} have not been saved. Save them before moving on.`,
     "d · the message under the buttons is the server's sentence");
  eq(await bannerHas(page, "have not been saved"), false, "d · and not at the top of the page");
  eq(await shownDate(page), d2, "d · the form stays on the day");
  eq(await value(page, "#in-" + CLOSE), "1650.00", "d · the changed figure is left alone");

  s = await clickSave(page);
  eq(s.status, 200, "d · saving again is accepted, with no tick box to press");
  eq(await text(page, "#dock-msg").then((t) => !t || !t.includes("have not been saved")), true, "d · and the refusal goes once the day is saved");
  eq(await text(page, "#dock-msg").then((t) => !t || !t.includes("have not been saved")), true, "d · and the refusal goes once the day is saved");
  r = await clickNextTo(page, d3);
  eq(r.status, 200, "d · Next day then moves on");
  eq(await shownDate(page), d3, "d · the form is on 3 May");

  /* ---- (e) an Off day ------------------------------------------------- */
  await Promise.all([checkFor(page, d3), page.click(".daytype-toggle .opt-closed")]);
  eq(await page.$eval("#chk-closed", (e) => e.checked), true, "e · the day is marked Off");
  s = await clickSave(page);
  eq(s.status, 200, "e · an Off day is saved");
  eq(s.body.closed, true, "e · …as a closed day");
  // Since 2026-10-07 the Checks panel confirms a saved Off day with its grey
  // note, so the line under the buttons is added only where the panel is hidden.
  await untilSavedShown(page);
  if (width < 1100) await untilText(page, "#dock-msg", "saved to the books");
  eq(await savedNoteShown(page), true, "e · the grey note 'This day has been saved.' is showing for the Off day");
  eq(await noteOnScreen(page, "#checks-saved"), true, "e · and can be seen (through the pill on a narrow screen)");
  eq(await shownText(page, "#checks-saved"), SAVED_NOTE_OFF, "e · with the owner's words for an Off day (no figures, so no second sentence)");
  eq(await dockSentence(page), width >= 1100 ? null : `${pretty(d3)} saved to the books.`,
     "e · the Off day is confirmed under the buttons only where the panel is hidden (below 1100px)");
  eq(await dockKind(page), width >= 1100 ? "" : "info", "e · as information, where it is said");
  eq(await bannerCount(page), 0, "e · and there is no banner at the top");
  eq(await noteShown(page), false, "e · the regenerate note is not shown for an Off day (it has no ledger)");
  await page.locator("#dock").screenshot({ path: path.join(SHOTS, `dock-offday-${w}.png`) });
  r = await clickNextTo(page, d4);
  eq(r.status, 200, "e · Next day moves on from an Off day");
  eq(await shownDate(page), d4, "e · the form is on 4 May");
  eq(await page.$eval("#chk-closed", (e) => e.checked), false, "e · the new day starts as a work day");

  /* ---- (g) a day that needs a reason ---------------------------------- */
  // Run before (f) so the form is still on a past date. Since 2026-10-06 Save
  // is grey whenever the last check says the day cannot be saved, so the race
  // the form is built to survive needs a green button first: a balanced day,
  // checked. Then the check is delayed on purpose and the closing balance is
  // changed, so Save is pressed in the moment before the reason box appears.
  // The form waits for a check of exactly what is on screen, then asks for the
  // reason and posts nothing.
  const prior4 = await getJSON("/api/prior?date=" + d4);
  const open4  = prior4.hasPrior ? Number(prior4.expected) : 1650;
  await setAmount(page, OPEN, open4.toFixed(2));
  await setAmount(page, "cash_sales", "100");
  await Promise.all([checkFor(page, d4), setAmount(page, CLOSE, (open4 + 100).toFixed(2))]);
  await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
  eq(await page.$eval("#btn-save", (e) => e.disabled), false, "g · a balanced, checked day has a green Save");
  await page.route("**/api/check", async (route) => {
    await new Promise((res) => setTimeout(res, 1200));
    await route.continue();
  });
  await page.fill("#in-" + CLOSE, (open4 + 150).toFixed(2));   // now short: L2-A, reason box still to come
  const before = posts;
  eq(await page.$eval("#btn-save", (e) => e.disabled), false, "g · Save is still green in the moment before the check answers");
  await page.click("#btn-save");
  await untilText(page, "#banner-area .banner span", "Add a short reason");
  eq(await bannerSentence(page), "Add a short reason before saving this day.", "g · Save asks for the reason");
  eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "txt-reason",
     "g · the cursor is put in the reason box");
  eq(posts, before, "g · nothing was posted to the books");
  await page.unroute("**/api/check");

  r = await clickNext(page);
  eq(r.status, 409, "g · Next day is refused while the day is unsaved");
  await untilText(page, "#dock-msg", "has not been saved yet");
  eq(await dockSentence(page), `${pretty(d4)} has not been saved yet. Save it before moving on.`,
     "g · with the server's sentence under the buttons");
  eq(await bannerHas(page, "has not been saved yet"), false, "g · and not at the top of the page");
  eq(await bannerSentence(page), "Add a short reason before saving this day.",
     "g · the request for the reason is left where it was");

  await page.fill("#txt-reason", "Till was short after the card machine reprint.");
  await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 });
  s = await clickSave(page);
  eq(s.status, 200, "g · saved once the reason is typed");
  await untilSavedShown(page);
  eq(await bannerCount(page), 0, "g · the request for the reason goes once the day is saved");
  r = await clickNextTo(page, d5);
  eq(r.status, 200, "g · Next day then moves on");
  eq(await shownDate(page), d5, "g · the form is on 5 May");


  /* ---- (i) a date change (2026-10-06), a saved day comes up (2026-10-07) - */
  const BOXES = "#slot-opening input, #groups-activity input, #slot-closing input";
  const inputsBlank = () => page.$$eval(BOXES, (is) => is.every((i) => i.value === ""));
  const linkHidden  = () => hidden(page, "#checks-load");
  // Below 1100px the link sits in the Checks sheet, which stays closed; click it directly.
  const clickLink = async () => {
    const [res] = await Promise.all([
      page.waitForResponse((r) => r.url().includes("/api/day"), { timeout: 40000 }),
      page.$eval("#checks-load", (e) => e.click()),
    ]);
    return res.status();
  };
  const linkGone  = () => page.waitForFunction(() => document.getElementById("checks-load").hidden, null, { timeout: 40000 });
  // Since 2026-10-07 the link shows only after Clear on a saved day. A wait that
  // never ends is left to the check that follows it to report.
  const linkShows = () => page.waitForFunction(() => !document.getElementById("checks-load").hidden, null, { timeout: 40000 }).catch(() => null);
  const clearOn   = (iso) => Promise.all([checkFor(page, iso), page.click("#btn-clear")]);
  const offSwitch = () => page.$eval("#chk-closed", (e) => e.checked);
  const close4    = (open4 + 150).toFixed(2);            // 4 May as saved in (g)
  // Pick a date through the lists, one list at a time, and wait for the check
  // the new date asks for. Since 2026-10-07 that check comes once the server has
  // said whether the date is saved, on what is then on screen.
  const pick = async (iso) => {
    const [y, m, d] = iso.split("-").map(Number);
    const cur = (await shownDate(page)).split("-").map(Number);
    if (cur[0] !== y) await page.selectOption("#sel-year", String(y));
    if (cur[1] !== m) await page.selectOption("#sel-month", String(m));
    if (cur[2] !== d) await Promise.all([checkFor(page, iso), page.selectOption("#sel-day", String(d))]);
    else await checkFor(page, iso).catch(() => null);
    await page.waitForTimeout(200);
  };
  // A bit of everything: figures, a reason (the day does not balance), and then
  // the Off day switch on top.
  const fillEverything = async () => {
    await setAmount(page, OPEN, "500");
    await setAmount(page, "cash_sales", "250");
    await setAmount(page, CLOSE, "900");          // does not balance: opens the reason box
    await untilShown(page, "#reason-box");
    await page.fill("#txt-reason", "left over from yesterday");
  };

  // d1..d4 are saved (d3 is an Off day); d5 is not. Fill the form with a bit of
  // everything on an unsaved date, then pick another unsaved date.
  await pick("2026-05-10");
  await fillEverything();
  eq(await inputsBlank(), false, "i · (setup) the form holds typed figures and a reason");
  await page.click(".daytype-toggle .opt-closed");      // and the Off day switch is on
  eq(await offSwitch(), true, "i · (setup) the Off day switch is on");
  await pick("2026-05-11");
  eq(await shownDate(page), "2026-05-11", "i · the date moved to 11 May");
  eq(await inputsBlank(), true, "i · every money box is empty after a date change to a date not in the books");
  eq(await page.$$eval(BOXES, (is) => is.filter((i) => i.classList.contains("bad") || i.getAttribute("aria-invalid") === "true").length), 0,
     "i · no red marks on the boxes");
  eq(await hidden(page, "#reason-box"), true, "i · the End of day reason box is hidden");
  eq(await value(page, "#txt-reason"), "", "i · and empty");
  eq(await hidden(page, "#opening-reason-box"), true, "i · the opening reason box is hidden");
  eq(await offSwitch(), false, "i · Work day");
  eq(await bannerCount(page), 0, "i · no top banner");
  eq(await hidden(page, "#dock-msg"), true, "i · nothing under the buttons");
  eq(await hidden(page, "#dock-note"), true, "i · no open explanation");
  eq(await hidden(page, "#checks-load-msg"), true, "i · no sentence under the link");
  eq(await hidden(page, "#predicted"), true, "i · the predicted line is hidden");

  // The same on a saved date (2026-10-07): nothing typed follows, and 1 May
  // comes up by itself exactly as it was saved. Its ledger exists, so its row
  // and the grey note show, and there is no link: the day is already there.
  await fillEverything();
  await page.click(".daytype-toggle .opt-closed");
  eq(await offSwitch(), true, "i · (setup) everything typed again on 11 May, Off day switch on");
  await pick(d1);
  eq(await shownDate(page), d1, "i · the date moved to 1 May");
  eq(await offSwitch(), false, "i · 1 May comes up as the Work day it was saved as");
  eq(await value(page, "#in-" + OPEN), "1000.00", "i · with its own saved opening balance");
  eq(await value(page, "#in-cash_sales"), "500.00", "i · its own cash sales");
  eq(await value(page, "#in-" + DEP), "300.00", "i · its own deposits");
  eq(await value(page, "#in-" + CLOSE), "1200.00", "i · and its own closing balance");
  eq(await value(page, "#txt-reason"), "", "i · the reason typed for 11 May does not follow");
  eq(await hidden(page, "#reason-box"), true, "i · and 1 May balances: no reason box");
  await page.waitForFunction((t) => [...document.querySelectorAll("#checks-list .check-title")].some((n) => n.textContent.trim() === t),
                             SAVED_TITLE, { timeout: 40000 });
  eq(await noteShown(page), true, "i · a saved date with a ledger shows Day saved, ledger generated and the grey note");
  eq(await linkHidden(), true, "i · no Show saved figures link: the saved day is already on screen");
  await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 }).catch(() => null);
  eq(await page.$eval("#btn-save", (e) => e.disabled), false, "i · Save is green for the day as saved");

  // Clear on a saved date blanks the form and keeps the date. Only then is
  // "Show saved figures" offered, and it brings the day back.
  await clearOn(d1);
  await linkShows();
  eq(await shownDate(page), d1, "i · Clear on a saved day keeps the date");
  eq(await inputsBlank(), true, "i · and blanks the form");
  eq(await linkHidden(), false, "i · Show saved figures is offered once a saved day is cleared");
  eq(await clickLink(), 200, "i · the link loads the saved figures");
  await linkGone();
  eq(await inputsBlank(), false, "i · the saved figures are in the boxes");
  eq(await value(page, "#in-" + OPEN), "1000.00", "i · 1 May's opening balance came back");

  // Typed figures never follow a pick, even between two saved dates.
  await pick(d2);
  eq(await value(page, "#in-cash_sales"), "450.00", "i · 2 May comes up with its own saved cash sales");
  await setAmount(page, "cash_sales", "999");
  await pick(d1);
  eq(await value(page, "#in-cash_sales"), "500.00", "i · figures typed on 2 May do not follow to 1 May: its own are there");
  eq(await linkHidden(), true, "i · 1 May is on screen as saved: no link");

  // A saved Off day (3 May) comes up with the switch on and every box blank.
  // Cleared, it is a blank Work day; Ctrl+Alt+Z, the link's key, brings it
  // back, even below 1100px, where the link is in the closed Checks sheet.
  await pick(d3);
  eq(await offSwitch(), true, "i · picking a saved Off day turns the switch on by itself");
  eq(await inputsBlank(), true, "i · its boxes stay blank (an Off day's balances were carried, not counted)");
  eq(await noteShown(page), false, "i · no regenerate note for an Off day");
  eq(await savedNoteShown(page), true, "i · the grey note says the Off day has been saved");
  eq(await linkHidden(), true, "i · no link: the Off day is already on screen");
  await clearOn(d3);
  await linkShows();
  eq(await offSwitch(), false, "i · Clear on the Off day leaves a blank Work day");
  eq(await linkHidden(), false, "i · the link is offered for the cleared Off day");
  const [viaKey] = await Promise.all([
    page.waitForResponse((r) => r.url().includes("/api/day"), { timeout: 40000 }),
    page.keyboard.press("Control+Alt+KeyZ"),
  ]);
  eq(viaKey.status(), 200, "i · Ctrl+Alt+Z presses it and loads the Off day");
  await page.waitForFunction(() => document.getElementById("chk-closed").checked, null, { timeout: 40000 });
  await linkGone();
  eq(await linkHidden(), true, "i · the link goes once the Off day is loaded");
  await pick(d4);
  eq(await offSwitch(), false, "i · the Off day switch does not follow to the next date");

  // A pending day: a Work day saved with 6 and 7 May missing before it.
  const gap = "2026-05-08";
  await pick(gap);
  const pg = await getJSON("/api/prior?date=" + gap);
  const openG = pg.hasPrior ? Number(pg.expected) : 1000;
  await setAmount(page, OPEN, openG.toFixed(2));
  await setAmount(page, "cash_sales", "100");
  await setAmount(page, CLOSE, (openG + 100).toFixed(2));
  await untilText(page, "#predicted", "The day balances.");
  s = await clickSave(page);
  eq(s.status, 200, "i · (setup) a day after a gap is saved");
  await untilSavedShown(page);
  const waitingTitle = (await rowTitles(page)).find((t) => /waiting|day before/i.test(t)) || null;
  check(waitingTitle !== null, "i · (setup) its Checks row says the ledger is waiting on the day before", JSON.stringify(await rowTitles(page)));
  eq(await linkHidden(), true, "i · the form holds what was just saved: no link");
  await pick(d4);
  eq(await value(page, "#in-" + CLOSE), close4, "i · leaving the waiting day brings up 4 May as saved, not the waiting day's figures");
  eq((await rowTitles(page)).includes(waitingTitle), false, "i · the 'ledger waiting' row does not linger under another date");
  eq(await dockSentence(page), null, "i · nor does a 'saved to the books' sentence");
  await pick(gap);
  eq(await value(page, "#in-" + CLOSE), (openG + 100).toFixed(2), "i · coming back to the waiting day brings its saved figures up by itself");
  eq((await rowTitles(page)).includes(SAVED_TITLE), false, "i · a waiting day has no 'ledger generated' row");
  eq(await savedNoteShown(page), true, "i · the grey note says the waiting day has been saved");
  eq(await shownText(page, "#checks-saved"), SAVED_NOTE, "i · in full, since a Work day has figures to rewrite");
  eq(await linkHidden(), true, "i · and there is no link");
  await clearOn(gap);
  await linkShows();
  eq(await inputsBlank(), true, "i · Clear on the waiting day blanks the form");
  eq(await linkHidden(), false, "i · Show saved figures is offered for a cleared day whose ledger is waiting");
  eq(await clickLink(), 200, "i · and loads it");
  await linkGone();
  eq(await value(page, "#in-" + CLOSE), (openG + 100).toFixed(2), "i · the waiting day's closing balance came back");

  // A date that is not in the books never offers the link.
  await pick("2026-05-20");
  eq(await inputsBlank(), true, "i · a date not in the books is blank");
  eq(await linkHidden(), true, "i · and never offers Show saved figures");

  // Clear keeps the date; the arrow keys clear too and focus stays on the list.
  await setAmount(page, OPEN, "5");
  await clearOn("2026-05-20");
  await page.waitForTimeout(200);
  eq(await shownDate(page), "2026-05-20", "i · Clear keeps the date");
  eq(await inputsBlank(), true, "i · and blanks the form");
  eq(await linkHidden(), true, "i · Clear on a date not in the books offers no link either");
  await setAmount(page, OPEN, "5");
  await page.focus("#sel-day");
  await Promise.all([checkFor(page, "2026-05-21"), page.keyboard.press("ArrowDown")]);
  eq(await shownDate(page), "2026-05-21", "i · the arrow key moved the date");
  eq(await inputsBlank(), true, "i · and cleared the form");
  eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "sel-day", "i · focus stays on the list that was used");

  /* ---- (j) Next day onto saved days (2026-10-07) ------------------------ */
  // Next day lands on the day after as it is in the books: a saved Work day
  // with its figures and reasons, a saved Off day switched on. That is the day
  // as saved, so Next day from it is allowed at once.
  await pick(d1);
  r = await clickNextTo(page, d2);
  eq(r.status, 200, "j · Next day from 1 May, as it came up, is allowed");
  eq(await shownDate(page), d2, "j · the form moves to 2 May");
  eq(await value(page, "#in-" + OPEN), "1200.00", "j · 2 May comes up with its saved opening balance");
  eq(await value(page, "#in-cash_sales"), "450.00", "j · its saved cash sales");
  eq(await value(page, "#in-" + CLOSE), "1650.00", "j · and its saved closing balance");
  eq(await page.evaluate(() => document.activeElement && document.activeElement.id), "in-" + OPEN,
     "j · the cursor is in the opening balance box");
  await page.waitForFunction(() => !document.getElementById("btn-save").disabled, null, { timeout: 40000 }).catch(() => null);
  eq(await page.$eval("#btn-save", (e) => e.disabled), false, "j · Save is green for the day as saved");
  check((await rowTitles(page)).includes(SAVED_TITLE), "j · the Checks panel says Day saved, ledger generated", JSON.stringify(await rowTitles(page)));
  eq(await linkHidden(), true, "j · no Show saved figures link");
  eq(await hidden(page, "#dock-msg"), true, "j · nothing under the buttons");

  r = await clickNextTo(page, d3);
  eq(r.status, 200, "j · Next day from 2 May, untouched, is allowed at once");
  eq(await shownDate(page), d3, "j · the form moves to 3 May");
  eq(await offSwitch(), true, "j · 3 May comes up as the Off day it was saved as");
  eq(await inputsBlank(), true, "j · with every box blank");
  eq(await savedNoteShown(page), true, "j · and the grey note says it has been saved");

  r = await clickNextTo(page, d4);
  eq(r.status, 200, "j · Next day from the Off day is allowed");
  eq(await offSwitch(), false, "j · 4 May comes up as a Work day");
  eq(await value(page, "#in-" + CLOSE), close4, "j · with its saved closing balance");
  await untilShown(page, "#reason-box").catch(() => null);
  eq(await hidden(page, "#reason-box"), false, "j · its reason box shows straight away");
  eq(await value(page, "#txt-reason"), "Till was short after the card machine reprint.", "j · holding its saved reason");

  r = await clickNextTo(page, d5);
  eq(r.status, 200, "j · Next day from 4 May, with its reason, is allowed");
  eq(await shownDate(page), d5, "j · the form moves to 5 May");
  eq(await inputsBlank(), true, "j · 5 May is not saved: every box is blank");
  eq(await offSwitch(), false, "j · a Work day");
  eq(await savedNoteShown(page), false, "j · and no grey note says it is saved");

  /* ---- (f) today ------------------------------------------------------ */
  await setDate(page, today);     // a date change blanks the form: no Clear click needed (2026-10-06)
  eq(await page.$$eval("#slot-opening input, #groups-activity input, #slot-closing input",
                       (is) => is.every((i) => i.value === "")), true, "f · picking today leaves a blank form");
  const priorT = await getJSON("/api/prior?date=" + today);
  const openT  = priorT.hasPrior ? Number(priorT.expected) : 2000;
  await setAmount(page, OPEN, openT.toFixed(2));
  await setAmount(page, CLOSE, openT.toFixed(2));
  await untilText(page, "#predicted", "The day balances.");
  if (!(await hidden(page, "#genesis-line"))) await page.check("#chk-genesis");
  s = await clickSave(page);
  eq(s.status, 200, "f · today is saved");
  await untilSavedShown(page);
  r = await clickNext(page);
  eq(r.status, 200, "f · Next day is allowed");
  eq(r.body.next, null, "f · …but there is no next day yet");
  await untilText(page, "#dock-msg", "no next day");
  eq(await dockSentence(page), "Today is saved. There is no next day to enter yet.",
     "f · and says so plainly, under the buttons");
  eq(await dockKind(page), "info", "f · as information, not a warning");
  eq(await bannerHas(page, "no next day"), false, "f · and not at the top of the page");
  eq(await shownDate(page), today, "f · the form stays on today");

  /* ---- (h) layout, floating, console, codes --------------------------- */
  // The busiest the page gets now: the saved row and grey note in the panel, a
  // message under the buttons, and all three buttons. Nothing here is a top banner.
  eq(await page.$$eval(".dock-actions button", (bs) => bs.filter((b) => !b.hidden).length), 3,
     "h · three buttons are on screen: Clear, Save, Next day");
  eq(await bannerCount(page), 0, "h · no banner at the top");

  await page.locator("#dock").screenshot({ path: path.join(SHOTS, `dock-today-${w}.png`) });
  await page.screenshot({ path: path.join(SHOTS, `page-today-${w}.png`), fullPage: false });

  const scroll = await page.evaluate(() => ({
    doc: document.documentElement.scrollWidth,
    win: document.documentElement.clientWidth,
    wide: [...document.querySelectorAll("body *")]
      .filter((e) => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
      .slice(0, 4).map((e) => e.tagName + (e.id ? "#" + e.id : "." + e.className)),
  }));
  check(scroll.doc <= scroll.win + 1, "h · no horizontal scrolling in the saved state",
        `${scroll.doc} > ${scroll.win}; ${scroll.wide.join(", ")}`);

  const floating = await page.evaluate(() => [...document.querySelectorAll("body *")]
    .filter((e) => ["fixed", "sticky"].includes(getComputedStyle(e).position))
    .map((e) => (e.id ? "#" + e.id : e.tagName) + ":" + getComputedStyle(e).position));
  const allowed = w >= 1100 ? ["#checks:sticky"] : [];
  eq(floating.join(" "), allowed.join(" "), "h · nothing floats over the form");

  const codes = await page.evaluate(() => (document.body.innerText.match(/\bL[1-4]-[A-Z]\b/g) || []));
  eq(codes.join(" "), "", "h · no warning code is visible anywhere");
  check(errors.length === 0, "h · no console errors", errors.slice(0, 3).join(" | "));

  await ctx.close();
}

/* ---------------------------------------------------------------------- */
async function main() {
  const cfg = await getJSON("/api/config");
  console.log(`today=${cfg.today}  base=${BASE}  shots=${SHOTS}\n`);

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    await pass(browser, 1440, 950, cfg);
    console.log("");
    await pass(browser, 390, 844, cfg);
  } finally {
    await browser.close();
  }

  console.log("");
  let failed = 0;
  for (const [w, s] of tally) {
    failed += s.fail;
    console.log(`${w}px: ${s.pass} pass, ${s.fail} fail`);
  }
  console.log(failed === 0 ? "ALL PASS" : `${failed} FAILED`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => { console.log("FAIL  the script itself stopped: " + (e && e.stack || e)); process.exit(2); });
