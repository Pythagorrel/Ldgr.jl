/* smoke.mjs : black-box acceptance test of a running LDGR server (packaged or loose), over HTTP only.

   Needs Node 24 (built-in fetch); no dependencies.

     BASE         http://127.0.0.1:<port>          (required)
     LEDGER_ROOT  the server's books folder        (required; must be EMPTY and must not mention "Records")
     LOOSE=1      the server runs from loose source: HTML comments, an unminified app.js/styles.css and
                  public/prototype.html are allowed. Without it the package rules apply.

   The story uses dates in the past, relative to the server's own "today":
     day 0  first day on record (refused without the first-day tick, saved with allowGenesis)
     day 1  balanced
     day 2  opening differs from the last close AND closing does not balance (refused with no reasons, then
            with only one reason, then saved with both)
     day 3  Off day
     day 1  re-saved with a changed figure
     tomorrow  refused
   After every save the journal and the daily ledger are looked for under LEDGER_ROOT, ledger amounts must be
   plain two-decimal numbers, and "Change Log.csv" must gain one row. No response may be a 500.

   Prints PASS/FAIL lines and "smoke: N passed, M failed"; exit 1 on any failure (2 if it could not start). */

import fs from "fs";
import path from "path";

const BASE = (process.env.BASE || "").replace(/\/+$/, "");
const ROOT = process.env.LEDGER_ROOT || "";
const LOOSE = process.env.LOOSE === "1";

let passed = 0, failed = 0;
const check = (cond, label, extra) => {
  if (cond) { passed++; console.log(`PASS  ${label}`); }
  else { failed++; console.log(`FAIL  ${label}${extra !== undefined ? "  -- " + extra : ""}`); }
  return !!cond;
};
const eq = (got, want, label) =>
  check(got === want, label, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

if (!BASE) { console.log("FAIL  BASE must be set, e.g. http://127.0.0.1:8765"); process.exit(2); }
if (!ROOT) { console.log("FAIL  LEDGER_ROOT must be set to the server's scratch books folder"); process.exit(2); }
if (/records/i.test(ROOT)) { console.log("FAIL  refusing a LEDGER_ROOT that mentions Records: " + ROOT); process.exit(2); }
if (!fs.existsSync(ROOT) || !fs.statSync(ROOT).isDirectory()) {
  console.log("FAIL  LEDGER_ROOT is not a folder: " + ROOT); process.exit(2);
}
if (fs.readdirSync(ROOT).length !== 0) {
  console.log("FAIL  LEDGER_ROOT is not empty (the story needs empty books): " + ROOT); process.exit(2);
}

/* ---------------------------------------------------------------------- */
/* HTTP                                                                    */
/* ---------------------------------------------------------------------- */
const fives = [];                       // every request that answered 5xx
async function call(method, p, body) {
  const init = { method, headers: {} };
  if (body !== undefined) { init.body = JSON.stringify(body); init.headers["Content-Type"] = "application/json"; }
  const res = await fetch(BASE + p, init);
  const buf = Buffer.from(await res.arrayBuffer());
  const text = buf.toString("utf8");
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  if (res.status >= 500) fives.push(`${method} ${p} -> ${res.status}`);
  return { status: res.status, type: res.headers.get("content-type") || "", text, bytes: buf.length, json };
}
const get = (p) => call("GET", p);
const post = (p, b) => call("POST", p, b);

/* ---------------------------------------------------------------------- */
/* Books on disk                                                           */
/* ---------------------------------------------------------------------- */
function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, out); else out.push(f);
  }
  return out;
}
const findFile = (re) => walk(ROOT).filter((f) => re.test(path.basename(f)));
const monthTag = (iso) => `${iso.slice(5, 7)}-${iso.slice(0, 4)}`;
const journalFiles = (iso) => findFile(new RegExp(`^Daily Journal ${monthTag(iso)}\\.csv$`));
const ledgerFiles = (iso) => findFile(new RegExp(`^Daily Ledger ${iso}\\.csv$`));

/* A small CSV reader: quotes, doubled quotes, newlines inside quotes. */
function parseCSV(text) {
  const rows = []; let row = [], cell = "", q = false, i = 0;
  if (text.charCodeAt(0) === 0xFEFF) i = 1;
  for (; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; }
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); cell = ""; rows.push(row); row = [];
    } else cell += c;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => !(r.length === 1 && r[0] === ""));
}
const readCSV = (f) => parseCSV(fs.readFileSync(f, "utf8"));
const changeLogRows = () => {
  const f = path.join(ROOT, "Change Log.csv");
  return fs.existsSync(f) ? Math.max(0, readCSV(f).length - 1) : 0;
};
const journalRow = (iso) => {
  const fs_ = journalFiles(iso);
  if (fs_.length !== 1) return null;
  const rows = readCSV(fs_[0]);
  const head = rows[0];
  const r = rows.slice(1).find((x) => x[0] === iso);
  if (!r) return null;
  return Object.fromEntries(head.map((h, k) => [h, r[k]]));
};

/* ---------------------------------------------------------------------- */
/* Dates and figures                                                       */
/* ---------------------------------------------------------------------- */
const shift = (iso, n) => {
  const [y, m, d] = iso.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return t.toISOString().slice(0, 10);
};
const KEYS = ["cash_sales", "POS_Scotia", "POS_RBL", "POS_U", "doctor_fees", "medical_supply_costs",
              "miscellaneous_costs", "taxi_fare", "deposits", "Mr_Boyle", "opening_balance", "closing_balance"];
const figs = (o) => { const a = {}; for (const k of KEYS) a[k] = 0; return Object.assign(a, o); };
// opening + sales - doctor - deposits - Mr_Boyle = predicted closing
const day = (date, o, extra) => Object.assign({ date, amounts: figs(o), force: true }, extra || {});

/* ---------------------------------------------------------------------- */
async function main() {
  /* ---- the page and its files ---- */
  console.log("== the page and its files ==");
  const root = await get("/");
  eq(root.status, 200, "GET / is 200");
  check(/text\/html/i.test(root.type), "GET / is text/html", root.type);
  check(/<html/i.test(root.text) && /<\/html>/i.test(root.text), "GET / is an HTML document");
  if (LOOSE) check(true, "GET / comments not checked (LOOSE=1)");
  else check(!root.text.includes("<!--"), "GET / contains no '<!--' (comments stripped in the package)");
  check(/app\.js/.test(root.text) && /styles\.css/.test(root.text), "GET / refers to app.js and styles.css");
  check(/<title>\s*LDGR\s*<\/title>/i.test(root.text), "GET / has the title LDGR");

  const js = await get("/app.js");
  eq(js.status, 200, "GET /app.js is 200");
  check(/javascript/i.test(js.type), "GET /app.js is JavaScript", js.type);
  check(js.bytes > 20000, "GET /app.js is not empty", `${js.bytes} bytes`);
  const css = await get("/styles.css");
  eq(css.status, 200, "GET /styles.css is 200");
  check(/text\/css/i.test(css.type), "GET /styles.css is text/css", css.type);
  check(css.bytes > 2000, "GET /styles.css is not empty", `${css.bytes} bytes`);
  const nl = (s) => (s.match(/\n/g) || []).length;
  if (LOOSE) {
    check(true, "minification not checked (LOOSE=1)");
  } else {
    // Unminified, app.js has about one line in 35 bytes; minified, a handful in the whole file.
    check(nl(js.text) / js.bytes < 1 / 200, "app.js is minified (few newlines for its size)",
          `${nl(js.text)} newlines in ${js.bytes} bytes`);
    check(nl(css.text) / css.bytes < 1 / 200, "styles.css is minified (few newlines for its size)",
          `${nl(css.text)} newlines in ${css.bytes} bytes`);
    check(!/^\s*\/\/ /m.test(js.text), "app.js has no whole-line // comments");
    check(!/\/\*[\s\S]{40,}?\*\//.test(css.text), "styles.css has no long /* */ comments");
  }
  const proto = await get("/prototype.html");
  if (LOOSE) check(proto.status === 404 || proto.status === 200, "GET /prototype.html answers (LOOSE=1 serves the source folder)", proto.status);
  else eq(proto.status, 404, "GET /prototype.html is 404 (not shipped)");
  const fav = await get("/favicon.ico");
  check(fav.status === 404 || (fav.status === 200 && /image\/x-icon/i.test(fav.type)),
        "GET /favicon.ico is 404, or 200 image/x-icon", `${fav.status} ${fav.type}`);
  eq((await get("/nonexistent-file.txt")).status, 404, "GET /nonexistent-file.txt is 404");
  eq((await get("/..%2f..%2fwindows%2fwin.ini")).status, 404, "a path-traversal request is 404");
  eq((await call("DELETE", "/api/save")).status, 405, "DELETE /api/save is 405");

  /* ---- config ---- */
  console.log("\n== /api/config ==");
  const cfgRes = await get("/api/config");
  eq(cfgRes.status, 200, "GET /api/config is 200");
  const cfg = cfgRes.json || {};
  check(cfg.ok === true, "config ok");
  const cats = (cfg.groups || []).flatMap((g) => (g.categories || []).map((c) => c.key));
  check(cats.length >= 10, "config has categories", `${cats.length}`);
  for (const k of KEYS) check(cats.includes(k), `config lists category ${k}`);
  check(/^\d{4}-\d\d-\d\d$/.test(cfg.today || ""), "config has today", cfg.today);
  if (!cfg.today) { console.log(`\nsmoke: ${passed} passed, ${failed} failed`); process.exit(1); }

  const today = cfg.today;
  const D0 = shift(today, -12), D1 = shift(today, -11), D2 = shift(today, -10), D3 = shift(today, -9);
  const FUTURE = shift(today, 1);

  /* ---- bad requests ---- */
  console.log("\n== bad requests ==");
  eq((await get("/api/day")).status, 400, "GET /api/day without a date is 400");
  eq((await get("/api/prior?date=nonsense")).status, 400, "GET /api/prior with a bad date is 400");
  eq((await call("POST", "/api/check", undefined)).status, 400, "POST /api/check with no body is 400");
  eq((await post("/api/check", { amounts: figs({}) })).status, 400, "POST /api/check without a date is 400");
  eq((await post("/api/check", { date: D0, amounts: { bogus: 1 } })).status, 400, "an unknown category is 400");
  eq((await post("/api/check", { date: "1999-01-01", amounts: figs({}) })).status, 400, "a date before 2000 is 400");
  eq((await post("/api/check", { date: FUTURE, amounts: figs({}) })).status, 400, "/api/check of a future date is 400");

  /* ---- empty books ---- */
  console.log("\n== before anything is saved ==");
  const day0 = await get(`/api/day?date=${D0}`);
  eq(day0.status, 200, "GET /api/day on an empty book is 200");
  check(day0.json && day0.json.ok === true && day0.json.day === null, "GET /api/day: day is null");
  const prior0 = await get(`/api/prior?date=${D0}`);
  eq(prior0.status, 200, "GET /api/prior on an empty book is 200");
  check(prior0.json && prior0.json.genesis === true && prior0.json.hasPrior === false,
        "GET /api/prior: first day on record, no prior day");
  check(changeLogRows() === 0, "no change log rows yet");

  /* ---- day 0: the first day on record ---- */
  console.log(`\n== day 0 (${D0}): first day on record ==`);
  const d0 = day(D0, { opening_balance: 1000, cash_sales: 100, doctor_fees: 400, deposits: 100, Mr_Boyle: 100, closing_balance: 500 });
  const c0 = await post("/api/check", d0);
  eq(c0.status, 200, "check day 0 is 200");
  check(c0.json && c0.json.genesis === true && c0.json.inBooks === false && c0.json.blocked === false &&
        c0.json.needsReason === false, "check day 0: genesis, not in books, not blocked, no reason needed",
        c0.text.slice(0, 200));
  check(c0.json && c0.json.predicted === 500, "check day 0: predicted closing is 500", c0.json && c0.json.predicted);
  const s0a = await post("/api/save", d0);
  eq(s0a.status, 400, "save day 0 without allowGenesis is refused (400)");
  check(s0a.json && s0a.json.needsGenesis === true, "refusal says needsGenesis");
  check(journalFiles(D0).length === 0 && changeLogRows() === 0, "the refused save wrote nothing");
  const s0 = await post("/api/save", Object.assign({}, d0, { allowGenesis: true }));
  eq(s0.status, 200, "save day 0 with allowGenesis is 200");
  check(s0.json && s0.json.ok === true && s0.json.date === D0, "save day 0: ok and the right date");
  check(s0.json && s0.json.journal === "added" && s0.json.dailyLedger === "written",
        "save day 0: journal added, ledger written", s0.text.slice(0, 200));
  verifyBooks(D0, 1, 1);

  /* ---- day 1: balanced ---- */
  console.log(`\n== day 1 (${D1}): balanced ==`);
  const prior1 = await get(`/api/prior?date=${D1}`);
  check(prior1.json && prior1.json.hasPrior === true && prior1.json.priorDate === D0 && prior1.json.expected === 500,
        "prior of day 1 is day 0 closing 500", prior1.text.slice(0, 200));
  const d1 = day(D1, { opening_balance: 500, cash_sales: 200, closing_balance: 700 });
  const c1 = await post("/api/check", d1);
  check(c1.status === 200 && c1.json.blocked === false && c1.json.needsReason === false && c1.json.genesis === false,
        "check day 1: nothing to explain", c1.text.slice(0, 200));
  const s1 = await post("/api/save", d1);
  eq(s1.status, 200, "save day 1 is 200");
  check(s1.json && s1.json.journal === "added" && s1.json.dailyLedger === "written",
        "save day 1: journal added, ledger written", s1.text.slice(0, 200));
  verifyBooks(D1, 2, 2);
  const g1 = await get(`/api/day?date=${D1}`);
  check(g1.json && g1.json.day && g1.json.day.date === D1 && g1.json.day.amounts.cash_sales === 200 &&
        g1.json.day.amounts.closing_balance === 700 && g1.json.day.status === "trading",
        "GET /api/day returns day 1 as saved", g1.text.slice(0, 200));
  const n1 = await post("/api/next", d1);
  check(n1.status === 200 && n1.json.ok === true && n1.json.saved === true && n1.json.changed === false &&
        n1.json.next === D2, "POST /api/next on the saved day 1 is 200 and names day 2", n1.text.slice(0, 200));
  const n1b = await post("/api/next", Object.assign({}, d1, { amounts: figs({ opening_balance: 500, cash_sales: 999, closing_balance: 700 }) }));
  check(n1b.status === 409 && n1b.json.saved === true && n1b.json.changed === true,
        "POST /api/next with changed figures is 409 (changed)", n1b.text.slice(0, 200));
  const n2x = await post("/api/next", day(D2, { opening_balance: 700, closing_balance: 700 }));
  check(n2x.status === 409 && n2x.json.saved === false, "POST /api/next on an unsaved day is 409 (not saved)", n2x.text.slice(0, 200));

  /* ---- day 2: two differences ---- */
  console.log(`\n== day 2 (${D2}): opening differs and closing does not balance ==`);
  // opening 600 against last close 700; 600 + 100 - 100 = 600 predicted, counted 650
  const d2 = day(D2, { opening_balance: 600, cash_sales: 100, doctor_fees: 100, closing_balance: 650 });
  const c2 = await post("/api/check", d2);
  check(c2.status === 200 && c2.json.needsReason === true && c2.json.blocked === false,
        "check day 2: needs a reason, not blocked", c2.text.slice(0, 200));
  const lv2 = (c2.json.findings || []).filter((f) => f.level === 2);
  check(lv2.some((f) => f.field === "opening_balance"), "check day 2: a level 2 finding on the opening balance");
  check(lv2.some((f) => f.field !== "opening_balance"), "check day 2: a level 2 finding for the day");
  const jBefore = journalFiles(D2).length ? fs.readFileSync(journalFiles(D2)[0], "utf8") : "";
  const logBefore = changeLogRows();
  const lgBefore = ledgerFiles(D2).length;
  const r0 = await post("/api/save", d2);
  eq(r0.status, 400, "save day 2 with no reasons is refused (400)");
  check(r0.json && r0.json.ok === false && r0.json.needsReason === true && /reason/i.test(r0.json.error || ""),
        "refusal asks for the reasons", r0.text.slice(0, 200));
  const r1 = await post("/api/save", Object.assign({}, d2, { reason: "Counted twice, still 650." }));
  eq(r1.status, 400, "save day 2 with only the day reason is refused (400)");
  const r2 = await post("/api/save", Object.assign({}, d2, { openingReason: "Float topped up overnight." }));
  eq(r2.status, 400, "save day 2 with only the opening reason is refused (400)");
  const jAfter = journalFiles(D2).length ? fs.readFileSync(journalFiles(D2)[0], "utf8") : "";
  check(jAfter === jBefore, "the refused saves left the journal exactly as it was");
  eq(changeLogRows(), logBefore, "the refused saves added no change log row");
  eq(ledgerFiles(D2).length, lgBefore, "the refused saves wrote no daily ledger for day 2");
  const gd2 = await get(`/api/day?date=${D2}`);
  check(gd2.json && gd2.json.day === null, "day 2 is still not in the books");
  const s2 = await post("/api/save", Object.assign({}, d2, { reason: "Counted twice, still 650.", openingReason: "Float topped up overnight." }));
  eq(s2.status, 200, "save day 2 with both reasons is 200");
  check(s2.json && s2.json.ok === true && s2.json.journal === "added", "save day 2: journal added", s2.text.slice(0, 200));
  verifyBooks(D2, 3, 3);
  const jr2 = journalRow(D2);
  check(jr2 && jr2["Reason"] === "Counted twice, still 650." && jr2["Opening Reason"] === "Float topped up overnight.",
        "journal row for day 2 holds both reasons", JSON.stringify(jr2));
  const g2 = await get(`/api/day?date=${D2}`);
  check(g2.json && g2.json.day && g2.json.day.reason === "Counted twice, still 650." &&
        g2.json.day.openingReason === "Float topped up overnight.", "GET /api/day returns both reasons");

  /* ---- day 3: an Off day ---- */
  console.log(`\n== day 3 (${D3}): Off day ==`);
  const off = { date: D3, status: "closed", force: true };
  const c3 = await post("/api/check", off);
  check(c3.status === 200 && c3.json.blocked === false && c3.json.needsReason === false, "check Off day: nothing to explain", c3.text.slice(0, 200));
  const s3 = await post("/api/save", off);
  eq(s3.status, 200, "save Off day is 200");
  check(s3.json && s3.json.closed === true && s3.json.journal === "added", "save Off day: closed, journal added", s3.text.slice(0, 200));
  check(changeLogRows() === 4, "change log has 4 rows after the Off day", changeLogRows());
  check(ledgerFiles(D3).length === 0, "an Off day writes no daily ledger");
  const jr3 = journalRow(D3);
  check(jr3 && /closed/i.test(jr3["Status"] || ""), "journal row for the Off day says closed", JSON.stringify(jr3));
  const g3 = await get(`/api/day?date=${D3}`);
  check(g3.json && g3.json.day && g3.json.day.status === "closed", "GET /api/day returns the Off day as closed");

  /* ---- re-save day 1 with a changed figure ---- */
  console.log(`\n== day 1 again (${D1}): a figure changed ==`);
  const logN = changeLogRows();
  const ledgerPath = ledgerFiles(D1)[0];
  const ledgerBefore = fs.readFileSync(ledgerPath, "utf8");
  const d1b = day(D1, { opening_balance: 500, cash_sales: 250, closing_balance: 750 });
  const s1b = await post("/api/save", d1b);
  eq(s1b.status, 200, "re-save of day 1 is 200");
  check(s1b.json && s1b.json.ok === true && s1b.json.journal !== "added",
        "re-save: the journal row was replaced, not added", s1b.text.slice(0, 200));
  eq(changeLogRows(), logN + 1, "the re-save added one change log row");
  verifyBooks(D1, null, null);
  const g1b = await get(`/api/day?date=${D1}`);
  check(g1b.json && g1b.json.day && g1b.json.day.amounts.cash_sales === 250 && g1b.json.day.amounts.closing_balance === 750,
        "GET /api/day returns the changed figures");
  const ledgerAfter = fs.readFileSync(ledgerFiles(D1)[0], "utf8");
  check(ledgerAfter !== ledgerBefore && /250\.00/.test(ledgerAfter), "the daily ledger was regenerated with the new figure (250.00)");
  eq(journalFiles(D1).length, 1, "still exactly one journal file for the month");
  const rows = readCSV(journalFiles(D1)[0]).slice(1).filter((r) => r[0] === D1);
  eq(rows.length, 1, "the journal still has exactly one row for day 1");

  /* ---- a future date ---- */
  console.log("\n== a future date ==");
  const logF = changeLogRows();
  const sf = await post("/api/save", day(FUTURE, { opening_balance: 750, closing_balance: 750 }));
  eq(sf.status, 400, "save of tomorrow is refused (400)");
  check(sf.json && sf.json.ok === false && /future/i.test(sf.json.error || ""), "the refusal says it is in the future", sf.text.slice(0, 160));
  eq(changeLogRows(), logF, "the refused future save added no change log row");
  check(journalFiles(FUTURE).length === 0 || journalRow(FUTURE) === null, "nothing for tomorrow in the journal");

  /* ---- the end ---- */
  console.log("\n== the whole run ==");
  check(fives.length === 0, "no response was a 5xx", fives.join("; "));
  const names = walk(ROOT).map((f) => path.basename(f));
  check(names.includes("Change Log.csv"), "Change Log.csv exists");
  check(names.some((n) => /^Monthly Ledger .*\.csv$/.test(n)), "a Monthly Ledger exists");
  check(!walk(ROOT).some((f) => /\.jl$/i.test(f)), "no .jl file was written into the books");

  console.log(`\nsmoke: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

/* After a save: the journal row, the daily ledger (plain two-decimal amounts), the change log row count. */
function verifyBooks(iso, logRows, _unused) {
  const jf = journalFiles(iso);
  check(jf.length === 1, `[${iso}] exactly one journal file for the month`, jf.length);
  check(journalRow(iso) !== null, `[${iso}] the journal has a row for the date`);
  const lf = ledgerFiles(iso);
  if (!check(lf.length === 1, `[${iso}] the daily ledger file exists`, lf.length)) return;
  const rows = readCSV(lf[0]);
  const head = rows[0] || [];
  const di = head.indexOf("Debit"), ci = head.indexOf("Credit");
  check(di >= 0 && ci >= 0, `[${iso}] the daily ledger has Debit and Credit columns`, head.join("|"));
  const cells = rows.slice(1).flatMap((r) => [r[di], r[ci]]).filter((v) => v !== undefined && v !== "");
  check(cells.length > 0, `[${iso}] the daily ledger has amounts`);
  const bad = cells.filter((v) => !/^\d+\.\d{2}$/.test(v));
  check(bad.length === 0, `[${iso}] every ledger amount is plain digits with two decimals (no exponent)`, bad.slice(0, 5).join(" "));
  check(!/\d[eE][+-]?\d/.test(cells.join(" ")), `[${iso}] no exponent in any ledger amount`);
  const sum = (i) => rows.slice(1).reduce((a, r) => a + (parseFloat(r[i]) || 0), 0);
  check(Math.abs(sum(di) - sum(ci)) < 0.005, `[${iso}] ledger debits equal credits`, `${sum(di)} vs ${sum(ci)}`);
  if (logRows !== null) eq(changeLogRows(), logRows, `[${iso}] Change Log.csv has ${logRows} row(s)`);
}

main().catch((e) => { console.log("FAIL  the script itself stopped: " + (e && e.stack || e)); process.exit(2); });
