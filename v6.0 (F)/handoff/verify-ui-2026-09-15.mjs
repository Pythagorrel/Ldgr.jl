/* verify-ui-2026-09-15.mjs — browser verification of the 2026-09-15 front-end changes
   (Saving… state, reason kept under a Stop and a refused save, Off-day question,
   overnight `today` refresh, 390px). Written by the front-end sub agent; passed
   against the real combined server on 2026-09-15.

   HOW TO RUN (never against the real Records folder):
     1. In a scratch folder:  npm init -y && npm i playwright-core@1   (uses the
        installed Chrome; no browser download), then copy this file there.
     2. From E:\Ldgr\v4.0, with LEDGER_ROOT set to an EMPTY scratch folder,
        LDGR_NO_BROWSER=1, LDGR_NO_DIGEST=1, and LDGR_NOTIFY_CONFIG set to a
        path inside the scratch folder that does not exist:
           julia --startup-file=no server.jl 8798
        (A server started beside a working notify.toml would hand the owner a
        report built from the scratch books within seconds.) The start-up
        "Email" line must read "off (no notify.toml)".
        Wait for "Ready." (warm-up takes ~9 s after the ~7 s package load).
     3. node verify-ui-2026-09-15.mjs      -> PASS/FAIL lines, "ALL PASS", screenshots in ./shots
     4. Stop the server; confirm nothing listens on 8798.
   Dates are chosen relative to /api/config's `today`, so the root must be fresh
   (the first flow is the first day on record). */
/* Verification for the front-end changes in v4.0/public/app.js.
   Runs against a server on 127.0.0.1:8798 with a scratch LEDGER_ROOT. */
import { chromium } from "playwright-core";
import fs from "fs";
import path from "path";

const BASE = "http://127.0.0.1:8798";
const SHOTS = path.resolve("shots");
fs.mkdirSync(SHOTS, { recursive: true });

let fails = 0;
const ok  = (m) => console.log("PASS  " + m);
const bad = (m, extra) => { fails++; console.log("FAIL  " + m + (extra ? "  -- " + extra : "")); };
const check = (cond, m, extra) => cond ? ok(m) : bad(m, extra);

const shift = (iso, n) => {
  const [y, m, d] = iso.split("-").map(Number);
  const t = new Date(y, m - 1, d + n, 12);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
};

const errors = [];
// The refusal in flow 3 is provoked on purpose, so its 400 is not a defect.
let expectRefusal = false;
const isNoise = (t) => /favicon/i.test(t) ||
  (expectRefusal && /api\/save/.test(t) && /400/.test(t));
const noteConsole = (tag) => (m) => {
  if (m.type() !== "error") return;
  const where = (m.location() && m.location().url) || "";
  const line = `${tag}: ${m.text()} [${where}]`;
  if (!isNoise(line)) errors.push(line);
};

async function setDate(page, iso) {
  const [y, m, d] = iso.split("-").map(Number);
  await page.selectOption("#sel-year", String(y));
  await page.selectOption("#sel-month", String(m));
  await page.selectOption("#sel-day", String(d));
  await page.waitForTimeout(50);
}

async function setAmount(page, key, value) {
  const sel = "#in-" + key;
  await page.fill(sel, value);
  await page.$eval(sel, (e) => e.blur());
}

const waitChecked = (page) => page.waitForResponse(
  (r) => r.url().includes("/api/check"), { timeout: 15000 });

// Wait until the page satisfies a predicate (checks arrive after every pause).
const until = (page, fn, arg) => page.waitForFunction(fn, arg, { timeout: 20000 });

async function main() {
  const cfg = await (await fetch(BASE + "/api/config")).json();
  const today = cfg.today;
  const d3 = shift(today, -3), d2 = shift(today, -2), d1 = shift(today, -1);
  console.log(`today=${today}  using ${d3}, ${d2}, ${d1}\n`);

  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  const page = await ctx.newPage();
  page.on("console", noteConsole("console"));
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));

  await page.goto(BASE + "/index.html", { waitUntil: "networkidle" });

  /* ---------------------------------------------------------------- 1 */
  console.log("--- 1. First day on record, and the Saving… state");
  await setDate(page, d3);
  await setAmount(page, "opening_balance", "1270");
  await setAmount(page, "cash_sales", "98400");
  await setAmount(page, "doctor_fees", "22400");
  await setAmount(page, "deposits", "75000");
  await setAmount(page, "closing_balance", "2270");
  await until(page, () => !document.getElementById("genesis-line").hidden);
  await page.check("#chk-genesis");
  await until(page, () => !document.getElementById("btn-next").disabled);

  const labelBefore = await page.textContent("#btn-next");
  check(labelBefore.trim() === "Save & next day", "button starts with its own label from index.html", labelBefore);

  await page.route("**/api/save", async (route) => {
    await new Promise((r) => setTimeout(r, 1500));   // hold the save so its busy state can be read
    await route.continue();
  });

  const savePosted = page.waitForRequest((r) => r.url().includes("/api/save"));
  const saveAnswered = page.waitForResponse((r) => r.url().includes("/api/save"));
  page.click("#btn-next");                       // deliberately not awaited
  await savePosted;
  const busy = await page.evaluate(() => {
    const b = document.getElementById("btn-next");
    return { text: b.textContent, disabled: b.disabled, aria: b.getAttribute("aria-busy") };
  });
  check(busy.text.trim() === "Saving…", "button reads Saving… while the save is in flight", busy.text);
  check(busy.disabled === true, "button is disabled while the save is in flight");
  check(busy.aria === "true", "button carries aria-busy while the save is in flight", String(busy.aria));
  await page.screenshot({ path: path.join(SHOTS, "01-saving-state.png"), fullPage: false });
  // a second click while it is on its way must do nothing
  await page.click("#btn-next", { force: true }).catch(() => {});
  await saveAnswered;
  await page.unroute("**/api/save");

  await until(page, (d) => document.getElementById("sel-day").value === String(Number(d.split("-")[2])), d2);
  const after = await page.evaluate(() => ({
    date: [document.getElementById("sel-year").value,
           document.getElementById("sel-month").value,
           document.getElementById("sel-day").value].join("/"),
    text: document.getElementById("btn-next").textContent.trim(),
    aria: document.getElementById("btn-next").getAttribute("aria-busy"),
  }));
  const want = [Number(d2.split("-")[0]), Number(d2.split("-")[1]), Number(d2.split("-")[2])].join("/");
  check(after.date === want, `the form moved on to ${d2}`, after.date);
  check(after.text === "Save & next day", "the button got its label back", after.text);
  check(after.aria === null, "aria-busy is gone once the save is over", String(after.aria));

  /* ---------------------------------------------------------------- 2 */
  console.log("\n--- 2. A typed reason survives a Stop");
  await setAmount(page, "opening_balance", "2270");
  await setAmount(page, "cash_sales", "98400");
  await setAmount(page, "doctor_fees", "22400");
  await setAmount(page, "deposits", "75000");
  await setAmount(page, "closing_balance", "3000");
  await until(page, () => !document.getElementById("reason-box").hidden);
  ok("the day doesn't balance, so its reason box is showing");

  const REASON = "Small notes left in the safe overnight";
  await page.fill("#txt-reason", REASON);
  await page.$eval("#txt-reason", (e) => e.blur());
  await page.screenshot({ path: path.join(SHOTS, "02-reason-typed.png") });

  // clear the closing box and leave it: "Closing Balance Not Entered" hides the difference
  await page.fill("#in-closing_balance", "");
  await page.$eval("#in-closing_balance", (e) => e.blur());
  // the box only hides once the server's own Stop has come back
  await until(page, () => document.getElementById("reason-box").hidden);
  await page.waitForTimeout(800);                 // let any later re-draw land too
  let kept = await page.inputValue("#txt-reason");
  check(kept === REASON, "the reason is still there while the Stop hides its warning", JSON.stringify(kept));
  await page.screenshot({ path: path.join(SHOTS, "03-reason-kept-under-stop.png") });

  await setAmount(page, "closing_balance", "3000");
  await until(page, () => !document.getElementById("reason-box").hidden);
  kept = await page.inputValue("#txt-reason");
  check(kept === REASON, "the reason is still there once the difference comes back", JSON.stringify(kept));

  await setAmount(page, "closing_balance", "3270");
  await until(page, () => document.getElementById("reason-box").hidden);
  await page.waitForTimeout(300);
  kept = await page.inputValue("#txt-reason");
  check(kept === "", "the reason is cleared once the day really balances", JSON.stringify(kept));

  /* ---------------------------------------------------------------- 3 */
  console.log("\n--- 3. A refused save keeps the reason");
  await setAmount(page, "closing_balance", "3000");
  await until(page, () => !document.getElementById("reason-box").hidden);
  await page.fill("#txt-reason", REASON);
  await page.$eval("#txt-reason", (e) => e.blur());
  await setAmount(page, "deposits", "900000");        // more paid out than came in: a Must-fix
  await until(page, () => Array.from(document.querySelectorAll("#checks-list .check"))
                               .some((li) => li.classList.contains("lv1")));
  await until(page, () => !document.getElementById("btn-next").disabled);
  expectRefusal = true;
  const refusal = page.waitForResponse((r) => r.url().includes("/api/save"));
  await page.click("#btn-next");
  await refusal;
  await page.waitForTimeout(300);
  expectRefusal = false;
  await until(page, () => /banner/.test(document.getElementById("banner-area").innerHTML));
  const bannerText = (await page.textContent("#banner-area")).trim();
  check(/cannot be saved/i.test(bannerText), "the banner says the day cannot be saved", bannerText);
  kept = await page.inputValue("#txt-reason");
  check(kept === REASON, "a refused save leaves the typed reason alone", JSON.stringify(kept));
  await page.screenshot({ path: path.join(SHOTS, "04-refused-save-reason-kept.png") });

  // put the day right and save it, so the Off day has the day before on record
  await setAmount(page, "deposits", "75000");
  await setAmount(page, "closing_balance", "3270");
  await until(page, () => document.getElementById("reason-box").hidden &&
                          !document.getElementById("btn-next").disabled);
  await page.click("#btn-next");
  await until(page, (d) => document.getElementById("sel-day").value === String(Number(d.split("-")[2])), d1);
  ok(`${d2} saved, the form moved on to ${d1}`);

  /* ---------------------------------------------------------------- 4 */
  console.log("\n--- 4. Off day");
  let dialogText = null;
  page.on("dialog", (d) => { dialogText = d.message(); d.accept(); });
  await page.click("label.daytype-toggle");
  await until(page, () => document.getElementById("chk-closed").checked);
  await until(page, () => !document.getElementById("btn-next").disabled);
  await page.click("#btn-next");
  await until(page, () => window.__dlg !== undefined || true);
  await page.waitForTimeout(100);
  check(dialogText !== null, "a question is asked before an Off day is saved");
  if (dialogText) {
    check(/Off day/.test(dialogText), "the question says Off day", JSON.stringify(dialogText));
    check(!/CLOSED/.test(dialogText), "the question never shouts CLOSED", JSON.stringify(dialogText));
    check(!/ledger/i.test(dialogText), "the question does not mention a ledger", JSON.stringify(dialogText));
    check(!/erase/i.test(dialogText), "the question does not threaten to erase the takings", JSON.stringify(dialogText));
    check(/work day/.test(dialogText) && !/working day/.test(dialogText),
          "the question says work day, not working day", JSON.stringify(dialogText));
    console.log("      dialog: " + JSON.stringify(dialogText));
  }
  await until(page, (d) => document.getElementById("sel-day").value === String(Number(d.split("-")[2])), today);
  ok(`the Off day saved and the form moved on to ${today}`);
  const note = await page.evaluate(() => {
    const n = document.getElementById("closed-note");
    return n ? n.textContent : "";
  });
  check(!/working day/.test(note), "the Off day note on screen says work day, not working day", JSON.stringify(note));

  /* ---------------------------------------------------------------- 5 */
  console.log("\n--- 5. Today refreshes while the window stays open");
  let cfgToday = today, checkToday = null;
  await page.route("**/api/config", async (route) => {
    const body = { ...cfg, today: cfgToday };
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) });
  });
  await page.route("**/api/prior**", (route) => route.fulfill({
    status: 200, contentType: "application/json",
    body: JSON.stringify({ ok: true, genesis: false, hasPrior: false }) }));
  await page.route("**/api/check", (route) => route.fulfill({
    status: 200, contentType: "application/json",
    body: JSON.stringify({ ok: true, findings: [], predicted: null, available: null, paidOut: null,
                           needsReason: false, blocked: false, genesis: false,
                           hasDailyLedger: false, inBooks: false,
                           ...(checkToday ? { today: checkToday } : {}) }) }));

  // (b) the window is looked at again the next morning — here, the next year
  cfgToday = "2027-01-02";
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await until(page, () => Array.from(document.getElementById("sel-year").options)
                               .some((o) => o.value === "2027"));
  ok("coming back to the window adds the new year to the list");
  await setDate(page, "2027-01-02");
  await page.waitForTimeout(300);
  let dateErr = await page.evaluate(() => {
    const e = document.getElementById("err-date");
    return { text: e.textContent, shown: e.classList.contains("show") };
  });
  check(!dateErr.shown && dateErr.text === "", "the new date is no longer 'has not happened yet'", JSON.stringify(dateErr));

  // (a) the same, carried on every check response
  checkToday = "2028-03-05";
  await setAmount(page, "cash_sales", "1");
  await until(page, () => Array.from(document.getElementById("sel-year").options)
                               .some((o) => o.value === "2028"));
  ok("a check response that carries a later today is taken up too");
  await setDate(page, "2028-03-05");
  await page.waitForTimeout(300);
  dateErr = await page.evaluate(() => {
    const e = document.getElementById("err-date");
    return { text: e.textContent, shown: e.classList.contains("show") };
  });
  check(!dateErr.shown && dateErr.text === "", "that date is accepted as well", JSON.stringify(dateErr));
  await page.screenshot({ path: path.join(SHOTS, "05-today-refreshed.png") });

  // back to a date the real server will accept before the stubs come off, so
  // the page never sends a check for a date that is still in its future
  await setDate(page, today);
  await page.waitForTimeout(800);
  await page.unroute("**/api/config");
  await page.unroute("**/api/prior**");
  await page.unroute("**/api/check");
  await page.waitForTimeout(400);

  /* ---------------------------------------------------------------- 6 */
  console.log("\n--- 6. Narrow screen (390px)");
  const narrow = await ctx.newPage();
  narrow.on("console", noteConsole("console(390)"));
  narrow.on("pageerror", (e) => errors.push("pageerror(390): " + e.message));
  await narrow.setViewportSize({ width: 390, height: 780 });
  await narrow.goto(BASE + "/index.html", { waitUntil: "networkidle" });
  await setDate(narrow, today);
  await setAmount(narrow, "opening_balance", "10");
  await narrow.waitForTimeout(600);
  const narrowLabel = (await narrow.textContent("#btn-next")).trim();
  check(narrowLabel === "Save & next day", "the Save button reads normally at 390px", narrowLabel);
  const noHScroll = await narrow.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1);
  check(noHScroll, "no sideways scrolling at 390px");
  await narrow.screenshot({ path: path.join(SHOTS, "06-narrow-390.png"), fullPage: true });
  await narrow.close();

  /* ---------------------------------------------------------------- */
  console.log("");
  check(errors.length === 0, "no console errors beyond the favicon", errors.join(" | "));

  await browser.close();
  console.log(`\n${fails === 0 ? "ALL PASS" : fails + " FAILED"}`);
  process.exit(fails === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(2); });
