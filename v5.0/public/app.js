/* =========================================================================
   app.js — the whole front end.

   RESPONSIBILITY, STATED PLAINLY: collect one day's figures, show what the
   server's checks say about them, and POST them. That is all. It never
   computes a ledger row, never decides a filename, never learns what an
   account is, and never decides how serious a warning is. Every one of those
   belongs to the server, and keeping them there is what makes this page
   replaceable without touching anything else.

   WHERE THE DATA LIVES: not here. Saving sends the day to the server, which
   checks it again and writes it straight to the books; a saved day is read
   back from the server when someone asks to edit it. This page holds no
   record it cannot re-fetch, so closing the tab loses nothing that was saved.

   THE TWO ACTIONS: Save (/api/save) writes the day and stays on it. Next day
   (/api/next) writes nothing; it asks the server whether the day on screen is
   already in the books, exactly as shown, and only then moves the form on to
   the date the server names. Whether the day may be left is the server's
   answer, never this page's guess.

   WHAT IS BUILT HERE: index.html is a fixed shell. The fields, the rows of the
   Checks panel and the dock's explanation row are made in this file with
   createElement and textContent only. Nothing the server sends is ever handed
   to innerHTML, so a label or a message containing "<" or a quote cannot
   break the page.
   ========================================================================= */

const MONTHS = ["January","February","March","April","May","June",
                "July","August","September","October","November","December"];

/* The four warning levels in plain words (Warnings Guide §2). Naming a level is
   presentation; WHICH level a warning has is decided by the server alone. */
const LEVEL_WORDS = { 1: "Must fix", 2: "Needs a reason", 3: "Good to know", 4: "Tip" };

const CLOSED_NOTE = "No ledger will be generated. The next working day carries this balance through.";

const state = {
  config:    null,        // groups + labels, from /api/config
  editing:   null,        // date string of a saved day loaded back with "Edit that day", or null
  today:     null,
  findings:  [],          // last findings from the server, so the list can re-render without a request
  day:       null,        // what the last check said about the date itself: {date, genesis, hasDailyLedger, inBooks}
  touched:   new Set(),   // drawer-count keys the person has left (blur) at least once for this form, or loaded with a saved day
  saveTried: false,       // Save pressed for this form
  checkedFor: null,       // the figures the findings on screen were checked against, as JSON
  selected:  null,        // finding whose full explanation is open in the dock, by findingKey()
  notice:    null,        // what the last save did, kept for the banner: {date, text}
  dockMsgDate: null,      // the date the message under the buttons is about, or null
};

const $  = (id) => document.getElementById(id);
const money = (n) => "$" + Number(n || 0).toLocaleString(undefined,
                       { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

/* createElement with a class and plain text. Text only ever goes in through
   textContent, which is what keeps server-provided words from becoming markup. */
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = text;
  return node;
}

function button(className, text, onClick) {
  const b = el("button", className, text);
  b.type = "button";
  if (onClick) b.addEventListener("click", onClick);
  return b;
}

/* ---------------------------------------------------------------------------
   Server calls. Everything that can fail returns through here so one error
   path handles the lot.

   A refusal throws, with the server's answer attached as err.data, so a caller
   can still show the findings that explain it.
--------------------------------------------------------------------------- */
async function api(path, opts = {}) {
  let res;
  try {
    res = await fetch(path, { headers: { "Content-Type": "application/json" }, ...opts });
  } catch {
    throw Object.assign(new Error("Could not reach the server. Is the terminal window still open?"),
                        { status: 0, data: null });
  }
  let data;
  try { data = await res.json(); }
  catch {
    throw Object.assign(new Error("The server sent back something unreadable."),
                        { status: res.status, data: null });
  }
  const refused = !data || data.ok === false;
  if (res.ok && !refused) return data;
  throw Object.assign(new Error((data && data.error) || "The server refused that."),
                      { status: res.status, data });
}

function banner(where, kind, text, actionLabel, actionFn) {
  const host = $(where);
  host.replaceChildren();
  if (!text) return;
  const div = el("div", "banner " + kind);
  div.appendChild(el("span", "", text));
  if (actionLabel) div.appendChild(button("btn-ghost mini", actionLabel, actionFn));
  host.appendChild(div);
}

/* The answer to Next day, shown in the dock right under the button that asked
   for it. The banner is at the top of the page, which is off screen when
   somebody is down at the buttons, so its sentence was being missed. The kinds
   are the banner's, so a refusal and a piece of information still look the
   same wherever they appear.

   The sentence is about one date, so the date it was shown for is remembered
   and the message is taken down as soon as that date stops being the one on
   screen, the form is reset, or the day is saved. Calling this with no text
   takes it down. */
function dockMessage(kind, text) {
  const msg = $("dock-msg");
  msg.classList.toggle("warn", !!text && kind === "warn");
  msg.classList.toggle("info", !!text && kind === "info");
  msg.textContent = text || "";
  msg.hidden = !text;
  state.dockMsgDate = text ? currentDate() : null;
}

/* ---------------------------------------------------------------------------
   Building the form from the server's category list

   The opening and closing balances go into their own slots in the Start of day
   and End of day cards, because that is when the drawer is counted. Every other
   group becomes a sub-card under "Today's numbers". Both balance keys come from the
   server, so this file still holds no category names of its own (Handover §4
   rule 4).
--------------------------------------------------------------------------- */
function buildGroups() {
  const cfg = state.config;
  const activityHost = $("groups-activity");
  const openingHost  = $("slot-opening");
  const closingHost  = $("slot-closing");

  activityHost.replaceChildren();
  openingHost.replaceChildren();
  closingHost.replaceChildren();

  cfg.groups.forEach(group => {
    const grid = el("div", "grid");

    group.categories.forEach(cat => {
      if (cat.key === cfg.openingKey)      openingHost.appendChild(makeField(cat, true));
      else if (cat.key === cfg.closingKey) closingHost.appendChild(makeField(cat, true));
      else                                 grid.appendChild(makeField(cat, false));
    });

    if (!grid.childElementCount) return;      // every field went to a balance slot

    const card = el("section", "subcard");
    card.dataset.group = group.id;
    card.appendChild(el("h3", "", group.title));
    if (group.hint) card.appendChild(el("p", "hint", group.hint));
    card.appendChild(grid);
    activityHost.appendChild(card);
  });
}

/* One labelled money box. `counted` marks the two drawer counts, which look
   like counted figures and wait to be reached before they are warned about
   (see isTodo). */
function makeField(cat, counted) {
  const field = el("div", counted ? "field counted" : "field");
  field.dataset.key = cat.key;

  const label = el("label", "", cat.label);
  label.htmlFor = "in-" + cat.key;

  const input = el("input");
  input.type = "text";
  input.id = "in-" + cat.key;
  input.dataset.key = cat.key;
  input.dataset.label = cat.label;
  input.inputMode = "decimal";
  input.autocomplete = "off";
  // "0.00" is only a hint where blank really does mean zero. A drawer count
  // left blank means "not counted", so a grey 0.00 there would look like a
  // zero that was already entered (README rule 4).
  if (!counted) input.placeholder = "0.00";

  const box = el("div", "money");
  box.append(el("span", "sym", "$"), input);

  const err = el("div", "err");
  err.id = "err-" + cat.key;

  field.append(label, box, err);

  input.addEventListener("input", () => {
    if (pageFocused === input) pageFocused = null;     // the person is typing here now
    validateAmount(input); refreshTotals(); scheduleCheck();
  });
  input.addEventListener("blur", () => {
    tidyAmount(input); refreshTotals();
    if (counted) leftDrawerCount(input);
    scheduleCheck();
  });
  return field;
}

/* A drawer count the person has been to and left blank gets its Must-fix row
   straight away rather than after the next check. A box the page put the
   cursor in by itself (after Next day) has not been visited, so moving on
   from it does not count. */
let pageFocused = null;
function leftDrawerCount(input) {
  // Switching to another window blurs the box without leaving it: the cursor
  // is still in it when the person comes back.
  if (document.activeElement === input) return;
  const byPage = pageFocused === input;
  pageFocused = null;
  if (byPage) return;
  state.touched.add(input.dataset.key);
  // A blank box changes its row now. So does a box whose figure the last check
  // has already seen, so a difference in it, and the reason box that goes with
  // it, appear the moment the box is left. Any other figure waits for the check
  // already scheduled; re-drawing the old answer would flash a warning for a
  // figure that has just been typed.
  if (input.value.trim() === "" || checkedIsCurrent()) redrawAfterPress();
}

// The findings on screen were checked against exactly the figures in the boxes.
const checkedIsCurrent = () =>
  !$("chk-closed").checked && state.checkedFor === JSON.stringify(readAmounts());

/* The box usually loses focus because the mouse went down on something else,
   often a row in the Checks panel. Re-drawing at that moment moves the rows
   under the pointer, so the mouse comes up on a different row and the click is
   lost. The re-draw therefore waits until the press is over; the click is
   handled first and the red row appears straight after. */
let pressing = false;
let redrawPending = false;
function redrawAfterPress() {
  redrawPending = true;
  if (!pressing) setTimeout(flushRedraw, 0);
}
function flushRedraw() {
  if (!redrawPending) return;
  redrawPending = false;
  renderChecks(state.findings);
}
function pressEnded() {
  pressing = false;
  setTimeout(flushRedraw, 0);          // after the click this press produces
}

/* ---------------------------------------------------------------------------
   Validation.

   This is for the person typing, not for the server's benefit — the server
   re-checks every one of these rules and its answer is the one that counts.
   The point here is that mistakes are visible the instant they are made
   instead of after a submission is rejected.
--------------------------------------------------------------------------- */
function validateAmount(input) {
  const raw = input.value.trim();
  const err = $("err-" + input.dataset.key);
  let msg = "";

  if (raw !== "") {
    if (raw.startsWith("-"))                       msg = "Amounts cannot be negative.";
    else if (!/^\d*\.?\d*$/.test(raw))             msg = "Numbers only — no letters or symbols.";
    else if (raw === ".")                          msg = "Enter a number.";
    else if (Number(raw) > 1e7)                    msg = "That looks too large — please check it.";
    else if (/\.\d{3,}$/.test(raw))                msg = "At most two decimal places.";
  }

  input.classList.toggle("invalid", msg !== "");
  input.classList.toggle("filled", msg === "" && raw !== "");
  err.textContent = msg;
  err.classList.toggle("show", msg !== "");
  updateButtons();
  return msg === "";
}

// Tidy on blur so the value the user leaves behind matches what gets sent.
function tidyAmount(input) {
  const raw = input.value.trim();
  if (raw === "" || input.classList.contains("invalid")) return;
  input.value = Number(raw).toFixed(2);
}

/* YYYY-MM-DD from local calendar numbers. Dates in this file are always built
   from their parts, never through toISOString(), which works in UTC and gives
   the previous day for local midnight anywhere east of UTC. */
function isoDate(y, m, d) {
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function currentDate() {
  const y = Number($("sel-year").value);
  const m = Number($("sel-month").value);
  const d = Number($("sel-day").value);
  if (!y || !m || !d) return null;
  return isoDate(y, m, d);
}

// What is wrong with the chosen date, if anything, without touching the page.
function dateProblem() {
  const iso = currentDate();
  if (!iso) return "Choose a full date.";
  if (iso > state.today) return "That day has not happened yet.";
  return "";
}

function validateDate() {
  const err = $("err-date");
  const msg = dateProblem();

  err.textContent = msg;
  err.classList.toggle("show", msg !== "");

  // An edit belongs to the date it was loaded for. Once another date is
  // picked, the banner has to say what saving would do to THAT date.
  if (state.editing && state.editing !== currentDate()) {
    state.editing = null;
    $("btn-cancel-edit").hidden = true;
  }
  // What the last check said about the date belongs to that date alone.
  if (state.day && state.day.date !== currentDate()) setDayFacts(null);
  // So does the answer Next day gave: it named a date, and another date is
  // now on screen. A figure being typed does not take it down — a day that was
  // never saved is still unsaved while it is being corrected.
  if (state.dockMsgDate && state.dockMsgDate !== currentDate()) dockMessage();

  resumeBanner();
  updateButtons();
  return msg === "";
}

// The first day on record is showing its box and the box is not ticked yet.
const needsGenesisTick = () => !$("genesis-line").hidden && !$("chk-genesis").checked;

function formValid() {
  // v4.0: a Level 2 difference cannot be saved until its reason is typed. The
  // server enforces this too and that copy is the one that counts; this exists
  // so the button greys out rather than the save failing (Warnings Guide §8).
  if (emptyReason()) return false;
  // The first day on record has nothing to check its opening balance against,
  // so it is accepted once, deliberately, by ticking its box. Same idea: the
  // server refuses the day without it, and the button greys out first.
  if (needsGenesisTick()) return false;
  if (dateProblem() !== "") return false;
  // A closed day sends no figures, so a half-typed figure now hidden behind the
  // Closed toggle must not stop it being saved.
  if ($("chk-closed").checked) return true;
  return !formInputs().some(i => i.classList.contains("invalid"));
}

/* Save is the one action the form can rule out for itself: a Level 2 with no
   reason, an unticked first day, a bad date or a red box. Next day is not.
   It is greyed out only while there is no usable date to ask about, and while
   a save or a move is already on its way; whether the day may be left is the
   server's answer (POST /api/next), not a guess made here. */
function updateButtons() {
  $("btn-save").disabled = !formValid();
  $("btn-next").disabled = saving || moving || dateProblem() !== "";
}

/* ---------------------------------------------------------------------------
   Date selects
--------------------------------------------------------------------------- */
function fillDateSelects(iso) {
  const ySel = $("sel-year"), mSel = $("sel-month"), dSel = $("sel-day");

  if (!ySel.options.length) {
    const thisYear = Number(state.today.slice(0, 4));
    for (let y = thisYear - 2; y <= thisYear; y++) {
      ySel.add(new Option(y, y));
    }
    MONTHS.forEach((name, i) => mSel.add(new Option(name, i + 1)));
    [ySel, mSel].forEach(s => s.addEventListener("change", () => {
      fillDays(); validateDate(); loadPrior(); scheduleCheck();
    }));
    dSel.addEventListener("change", () => { validateDate(); loadPrior(); scheduleCheck(); });
  }

  const target = iso || state.today;
  const [yy, mm, dd] = target.split("-").map(Number);
  ySel.value = yy;
  mSel.value = mm;
  fillDays(dd);
}

// Rebuild the day list for the chosen month, so 31 September is never offered
// in the first place. The server rejects impossible dates too; this just means
// nobody has to be told.
function fillDays(keep) {
  const dSel = $("sel-day");
  const y = Number($("sel-year").value);
  const m = Number($("sel-month").value);
  const n = new Date(y, m, 0).getDate();
  const want = keep || Number(dSel.value) || 1;
  dSel.replaceChildren();
  for (let d = 1; d <= n; d++) dSel.add(new Option(d, d));
  dSel.value = Math.min(want, n);
}

function prettyDate(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]} ${y}`;
}

/* There is no "day after" helper here any more. The server names the next date
   in its answer to Next day, and sends null when the day on screen is today, so
   the form cannot land on a date the books have not reached. The old local
   version of this sum was the source of a v4.0 bug: it read the result back
   with toISOString(), which is UTC, and east of UTC that is still yesterday. */

/* ---------------------------------------------------------------------------
   Reading and writing the form
--------------------------------------------------------------------------- */
const formInputs = () => Array.from(document.querySelectorAll(
  "#slot-opening input, #groups-activity input, #slot-closing input"));

function readAmounts() {
  const out = {};
  formInputs().forEach(i => {
    const raw = i.value.trim();
    // CHANGED IN v4.0. Blank still means zero for every posted category — no
    // taxi fares today, so nothing was spent. It does NOT mean zero for the two
    // cash-book balances: there, blank means the drawer was never counted, and
    // sending 0 would invent a balance nobody observed. `null` travels as JSON
    // null and the server turns it back into NOT_COUNTED, which raises L1-C.
    if (raw === "") {
      out[i.dataset.key] = isCashBook(i.dataset.key) ? null : 0;
    } else {
      out[i.dataset.key] = Number(raw);
    }
  });
  return out;
}

/* True for the opening/closing balance fields. The keys come from the server so
   this file still holds no category names of its own (Handover §4 rule 4). */
function isCashBook(key) {
  return key === state.config.openingKey || key === state.config.closingKey;
}

/* Put a day's figures in the boxes, or blank every box with null.
   CHANGED IN v4.0: a drawer count shows a counted 0 as 0.00, and only a
   missing value as blank. For those two boxes blank means "not counted", so
   showing a real $0.00 as blank turned it into a Stop when the day was saved
   again. Every other box still shows 0 as blank. */
function writeAmounts(amounts) {
  formInputs().forEach(i => {
    const v = amounts ? amounts[i.dataset.key] : null;
    const isNumber = v !== null && v !== undefined && v !== "" && isFinite(Number(v));
    if (isCashBook(i.dataset.key)) i.value = isNumber ? Number(v).toFixed(2) : "";
    else                           i.value = isNumber && Number(v) !== 0 ? Number(v).toFixed(2) : "";
    i.classList.remove("invalid");
    i.classList.toggle("filled", i.value !== "");
    const err = $("err-" + i.dataset.key);
    err.textContent = ""; err.classList.remove("show");
  });
  refreshTotals();
}

function refreshTotals() {
  const a = readAmounts();
  const sum = (cats) => cats.reduce((t, c) => t + (a[c.key] || 0), 0);
  const g = (id) => (state.config.groups.find(x => x.id === id) || { categories: [] }).categories;

  $("tot-cash").textContent = money(sum(g("cash")));
  $("tot-exp").textContent  = money(sum(g("expenses")));
  // "Banked" is the deposits figure, identified by the server rather than by a
  // name written into this file. Shown because it is the figure most often mistyped.
  $("tot-dep").textContent  = money(a[state.config.depositKey] || 0);
}

/* ---------------------------------------------------------------------------
   Loading or clearing the form — one way to do it.

   Every path that puts a new day in front of the person comes through here:
   startup, Next day, Clear, Cancel edit and Edit that day. Before this
   existed each of those reset a different part of the form, so a reason typed
   for one day was saved again with the next, an edited closed day reopened as
   a trading day, and the warnings on screen described figures that were no
   longer there.

   `day` is a saved day from /api/day. Without one the form is blank, on
   `date` if given and on today otherwise.
--------------------------------------------------------------------------- */
function resetForm(day = null, { date } = {}) {
  // Everything on screen described the old figures. Drop the pending check,
  // ignore any answer still on its way, and start the Checks panel from
  // nothing. This happens before the new figures go in, because an empty
  // Checks list also empties the reason boxes.
  clearTimeout(checkTimer);
  checkSeq++;
  pageFocused = null;
  state.touched.clear();
  state.saveTried = false;
  state.selected = null;
  state.checkedFor = null;
  renderChecks([]);
  $("predicted").hidden = true;
  dockMessage();                       // whatever Next day last answered was about the old day

  const closed = !!day && day.status === "closed";
  fillDateSelects(day ? day.date : (date || state.today));
  // A closed day's stored balances were carried through by the server, not
  // counted by anyone. Putting them in the boxes would pre-fill both drawer
  // counts the moment the day was switched back to trading (README rules 3
  // and 4), so a closed day comes back with every box blank.
  writeAmounts(day && !closed ? day.amounts : null);
  // A saved day's counts were entered when it was saved, so its warnings and
  // reasons show straight away rather than waiting for each box to be left.
  if (day && !closed) [state.config.openingKey, state.config.closingKey].forEach(k => state.touched.add(k));
  REASONS.forEach(r => { $(r.input).value = day ? (day[r.sent] || "") : ""; });
  $("chk-closed").checked = closed;
  // A tick is consent for one save of one day. It never carries over.
  $("chk-genesis").checked = false;
  $("chk-force").checked = false;

  setChecksSheet(false);
  applyClosedState();
  validateDate();
  refreshTotals();
  updateButtons();
  loadPrior();
  return runCheck();
}

/* ---------------------------------------------------------------------------
   v4.0 — warnings
   ---------------------------------------------------------------------------
   THIS FILE NEVER DECIDES A SEVERITY. It receives a level, a code, a short
   title and a message from the server and renders them. The rules live in
   Checks.jl and exist in exactly one place, which is the only way two copies
   of a rule stay in step (Handover §4 rule 5).

   Where they appear:
     * the Checks panel has one row per warning: the short title, the level as
       a plain word, and a "See full explanation" link. The code (L1-C and so
       on) is never shown; it is for the backend and the Warnings Guide, and
       stays on the row only as data-code;
     * the dock's explanation row, at the bottom of the form, shows the full
       message of one warning. It opens only when asked for with that link, or
       when a save is refused, never by itself: the boxes already carry the
       outlines, and the reason boxes already ask for a reason;
     * the box a warning is about gets an outline in its level's colour;
     * a warning that needs a reason gets a reason box in the card of the
       figure it is about, which names the warning (see REASONS).

   The one choice made here is about TIMING, not severity. A blank drawer
   count nobody has reached yet is left out of the Checks panel, so the page
   does not alarm on the first figure typed. It is still a Stop and the server
   still refuses the day; its row appears as soon as the box is left blank or
   Save is pressed. A difference in a drawer count, with its reason box, waits
   for the same moment, so nobody is asked for a reason while still typing the
   figure. So does the deficit line under the closing balance (showPredicted).
--------------------------------------------------------------------------- */

/* The two reason boxes. A day can have two differences that need a reason, and
   each is explained beside its own figure: an opening balance that doesn't
   match the last close in Start of day, anything else (a day that doesn't
   balance) in End of day. Each goes to the server as its own reason, and the
   server checks each warning against its own (Checks.reason_for). Which box a
   warning belongs to is read from its `field`, using the opening key the
   server sends, so this file still holds no category names. */
const REASONS = [
  { box: "opening-reason-box", input: "txt-opening-reason", lead: "opening-reason-lead", sent: "openingReason" },
  { box: "reason-box",         input: "txt-reason",         lead: "reason-lead",         sent: "reason" },
];
const reasonFor = (f) => REASONS[f.field === state.config.openingKey ? 0 : 1];

// Both reasons as the server expects them.
function readReasons() {
  const out = {};
  REASONS.forEach(r => { out[r.sent] = $(r.input).value.trim(); });
  return out;
}

// The first reason box on the page that is showing and still empty, or null.
const emptyReason = () =>
  REASONS.find(r => !$(r.box).hidden && $(r.input).value.trim() === "") || null;

/* Which warning is which, for the dock's explanation row. The code alone is not
   enough: "not counted" can be raised for the opening and the closing balance
   at once, and those are two different explanations. The message is left out
   on purpose, so an open explanation stays open while its figures change. */
const findingKey = (f) => f.code + "|" + (f.field || "");

// The person has been to this drawer count and left it, or has pressed Save.
const reached = (key) => state.touched.has(key) || state.saveTried;

// A Stop about a drawer count that is still blank, or a difference in one that
// needs a reason, when that box has not been reached. It is not shown until it
// has been.
function isTodo(f) {
  if (!f.field || !isCashBook(f.field) || reached(f.field)) return false;
  if (f.level === 2) return true;
  if (f.level !== 1) return false;
  const input = $("in-" + f.field);
  return !!input && input.value.trim() === "";
}

function setLevelClass(node, level) {
  node.classList.remove("lv1", "lv2", "lv3", "lv4");
  if (level) node.classList.add("lv" + level);
}

function renderChecks(findings) {
  findings = Array.isArray(findings) ? findings : [];
  state.findings = findings;

  // An open explanation stays open only while its warning is still there.
  if (state.selected && !findings.some(f => findingKey(f) === state.selected)) state.selected = null;

  const real  = findings.filter(f => !isTodo(f));
  const shown = (state.selected && real.find(f => findingKey(f) === state.selected)) || null;

  renderReasonBoxes(findings, real);
  renderCheckRows(real, shown);
  renderCheckSummary(real);
  renderFieldOutlines(real);
  renderDockNote(shown);
  updateButtons();
}

/* A Level 2 cannot be saved without a typed reason. Each reason box appears
   only when its warning is showing, so it never reads as routine paperwork.
   What was typed is cleared only once the warning itself has gone. A closed
   day has no figures to explain, so both boxes stay hidden then, keeping
   anything typed in case the day is switched back to trading. */
function renderReasonBoxes(findings, real) {
  const closed = $("chk-closed").checked;
  REASONS.forEach(r => {
    const mine = (list) => list.filter(f => f.level === 2 && reasonFor(f) === r);
    const need = mine(real);
    $(r.box).hidden = closed || need.length === 0;
    if (!closed && mine(findings).length === 0) $(r.input).value = "";
    // The box is the one prompt for its reason, so it says what the reason is
    // for, in the server's short title: "Opening doesn't match last close." or
    // "Day doesn't balance." A day can need a reason and still balance.
    const titles = [...new Set(need.map(f => f.title).filter(Boolean))];
    if (titles.length) $(r.lead).textContent = titles.map(t => t + ".").join(" ");
  });
}

/* Rows are updated in place, one element per warning, rather than rebuilt on
   every check. Re-checks arrive after every pause in typing, and a drawer count
   losing focus as the mouse goes down on a row re-draws the list at once; a
   rebuilt row would swallow that click, and lose a keyboard focus on it. */
const rowEls = new Map();            // row key -> its <li>
const rowFindings = new WeakMap();   // <li> -> the warning it shows now

function renderCheckRows(real, shown) {
  const labels = state.config.labels || {};
  const repeats = new Map();
  const rows = real.map(f => {
    const base = findingKey(f);
    const n = (repeats.get(base) || 0) + 1;       // the same warning twice still gets two rows
    repeats.set(base, n);
    const title = f.title || f.levelName || "";
    // A title that already names its box ("Closing Balance Not Entered") does
    // not need the box's name again on the line underneath.
    const box = labels[f.field] || "";
    return {
      key:   base + "|" + n,
      f,
      cls:   `check lv${f.level}` + (f === shown ? " selected" : ""),
      title,
      meta:  [LEVEL_WORDS[f.level] || f.levelName, title.includes(box) ? "" : box].filter(Boolean).join(" · "),
    };
  });

  const list = $("checks-list");
  const wanted = new Set(rows.map(r => r.key));
  for (const [key, li] of rowEls) {
    if (!wanted.has(key)) { li.remove(); rowEls.delete(key); }
  }

  const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };
  rows.forEach((r, i) => {
    let li = rowEls.get(r.key);
    if (!li) { li = makeCheckRow(); rowEls.set(r.key, li); }
    rowFindings.set(li, r.f);
    if (li.className !== r.cls) li.className = r.cls;
    li.dataset.code = r.f.code;
    if (r.f.field) li.dataset.field = r.f.field;
    else delete li.dataset.field;
    setText(li.querySelector(".check-title"), r.title);
    setText(li.querySelector(".check-meta"), r.meta);
    const more = li.querySelector(".check-more");
    const moreLabel = "See full explanation: " + r.title;
    if (more.getAttribute("aria-label") !== moreLabel) more.setAttribute("aria-label", moreLabel);
    if (list.children[i] !== li) list.insertBefore(li, list.children[i] || null);
  });
  while (list.children.length > rows.length) list.lastElementChild.remove();
}

function makeCheckRow() {
  const li = el("li");
  const icon = el("span", "check-icon");
  icon.setAttribute("aria-hidden", "true");
  const body = el("span", "check-body");
  body.append(el("span", "check-title"), el("span", "check-meta"));
  const btn = button("check-btn", null, () => onCheckClick(li));
  btn.append(icon, body);
  // Beside the row's button rather than inside it: a button cannot hold another.
  const more = button("check-more", "See full explanation", () => showExplanation(li));
  li.append(btn, more);
  return li;
}

let codesAnnounced = "";  // the set of codes last read out by screen readers
function renderCheckSummary(real) {
  const n = real.length;
  const worst = n ? Math.min(...real.map(f => f.level)) : 0;

  const count = $("checks-count");
  count.textContent = n ? String(n) : "";
  setLevelClass(count, worst);
  count.hidden = n === 0;

  $("checks-empty").hidden = n > 0;

  // The narrow-screen pill that opens the Checks panel as a sheet.
  const pill = $("dock-status");
  pill.textContent = n ? plural(n, "check") : "";
  setLevelClass(pill, worst);
  pill.hidden = n === 0;
  if (n === 0) setChecksSheet(false);          // nothing left to open it for

  // Screen readers hear when WHICH checks apply changes, not every re-check
  // while someone types.
  const codes = [...new Set(real.map(f => f.code))].sort().join(" ");
  if (codes !== codesAnnounced) {
    codesAnnounced = codes;
    const titles = [...new Set(real.map(f => f.title || f.levelName))];
    $("checks-live").textContent = n ? `${plural(n, "check")}: ${titles.join("; ")}`
                                     : "Nothing to fix so far";
  }
}

// Outline each box in the colour of the most serious warning about it.
function renderFieldOutlines(real) {
  document.querySelectorAll("#view-entry .field[data-key]").forEach(field => {
    const levels = real.filter(f => f.field === field.dataset.key).map(f => f.level);
    if (levels.length) field.dataset.level = String(Math.min(...levels));
    else delete field.dataset.level;
  });
}

/* The dock's explanation row: the whole message of one warning. ✕ only closes
   it: the row stays in the Checks panel, and a day that needs a reason still
   cannot be saved until one is typed (README rule 5). */
let noteShown = "";
function renderDockNote(f) {
  const note = $("dock-note");
  const signature = f ? JSON.stringify([findingKey(f), f.level, f.message]) : "";
  if (signature === noteShown) return;
  noteShown = signature;

  if (!f) {
    note.hidden = true;
    setLevelClass(note, 0);
    note.replaceChildren();
    return;
  }

  const icon = el("span", "note-icon");
  icon.setAttribute("aria-hidden", "true");
  const close = button("note-close", "×", closeExplanation);
  close.setAttribute("aria-label", "Close this explanation");

  setLevelClass(note, f.level);
  note.replaceChildren(icon, el("p", "note-text", f.message), close);
  note.hidden = false;
}

/* Clicking a row takes the person to the box it is about, using the `field`
   the server sends with each warning. A warning about the whole day has no box
   to go to, so its row opens its explanation instead. */
function onCheckClick(li) {
  const f = rowFindings.get(li);
  if (!f) return;
  const target = checkTarget(f);
  if (!target) { showExplanation(li); return; }
  setChecksSheet(false);
  target.scrollIntoView({ block: "center", behavior: "smooth" });
  target.focus({ preventScroll: true });
}

/* "See full explanation": open the warning's whole message in the dock at the
   bottom of the form and go there. The cursor goes to the explanation, so a
   screen reader reads it out, and ✕ brings it back to the link. */
let explainedFrom = null;
function showExplanation(li) {
  const f = rowFindings.get(li);
  if (!f) return;
  state.selected = findingKey(f);
  renderChecks(state.findings);
  setChecksSheet(false);
  explainedFrom = li.querySelector(".check-more");
  revealExplanation("center");
}

function revealExplanation(block) {
  if ($("dock-note").hidden) return;
  $("dock").scrollIntoView({ block, behavior: "smooth" });
  $("dock-note").focus({ preventScroll: true });
}

function closeExplanation() {
  const hadCursor = $("dock-note").contains(document.activeElement);
  state.selected = null;
  renderChecks(state.findings);
  if (!hadCursor) return;
  // Back to the link it was opened from. On a narrow screen that link has gone
  // with the closed Checks panel, so the pill that opens the panel is next best.
  const back = [explainedFrom, $("dock-status")].find(b => b && b.isConnected && b.getClientRects().length);
  if (back) back.focus({ preventScroll: true });
}

function checkTarget(f) {
  let t = null;
  if (f.field === "date")  t = $("sel-day");
  else if (f.field)        t = $("in-" + f.field);
  else if (f.level === 2)  t = $("txt-reason");
  // A box hidden behind the Closed toggle cannot be scrolled to or focused.
  return t && t.getClientRects().length ? t : null;
}

// Put the cursor in the first reason box that is showing and still empty.
function focusReason() {
  const r = emptyReason();
  if (!r) return;
  const box = $(r.input);
  box.scrollIntoView({ block: "center", behavior: "smooth" });
  box.focus({ preventScroll: true });
}

/* Run the checks without saving, so a difference is visible while the operator
   is still standing at the drawer rather than only when the day is saved. */
let checkTimer = null;
let checkSeq = 0;         // numbers each check, so a slow answer to an older one is ignored
function scheduleCheck() {
  clearTimeout(checkTimer);
  checkTimer = setTimeout(runCheck, 350);
}

async function runCheck() {
  clearTimeout(checkTimer);
  const seq = ++checkSeq;
  if (dateProblem() !== "") return;

  // v4.0: a closed day is checked as a closed day, so the server's closed-day
  // notice (what the next working day will open with) is shown, not nothing.
  const closed = $("chk-closed").checked;
  const body = closed
    ? { date: currentDate(), status: "closed" }
    : { date: currentDate(), amounts: readAmounts(), ...readReasons() };

  try {
    const res = await api("/api/check", { method: "POST", body: JSON.stringify(body) });
    if (seq !== checkSeq) return;       // the form changed while this was on its way
    state.checkedFor = closed ? null : JSON.stringify(body.amounts);
    renderChecks(res.findings);
    setDayFacts({ date: body.date, genesis: !!res.genesis,
                  hasDailyLedger: !!res.hasDailyLedger, inBooks: !!res.inBooks });
    if (closed) $("predicted").hidden = true;
    else        showPredicted(res.predicted, res.available, res.paidOut);
  } catch (e) {
    // A failed check must never block typing. The server re-checks on save.
  }
}

/* What the server says about the date itself, rather than its figures: whether
   it would be the first day on record, whether a ledger file was already made
   for it, and whether it is already in the books. Every check brings them, and
   they belong to the date that check was about. */
function setDayFacts(facts) {
  const before = state.day;
  const sameDate = !!facts && !!before && facts.date === before.date;
  // A tick is consent for one date. It never carries over to another.
  if (!sameDate) {
    $("chk-genesis").checked = false;
    $("chk-force").checked = false;
  }
  state.day = facts;
  renderDayFacts();
  // The banner is redrawn only when "is this date already saved?" gets a new
  // answer. Checks arrive after every pause in typing, and redrawing each time
  // would wipe a message Save has just put up (a refusal, a request for a
  // reason) while the person is still acting on it.
  if ((sameDate && before.inBooks) !== (!!facts && facts.inBooks)) resumeBanner();
}

/* Each tick box appears only when it applies to the date on screen. A closed
   day writes no ledger, so it has no ledger file to replace; its tick is kept
   in case the day is switched back to a work day. */
function renderDayFacts() {
  const day = state.day && state.day.date === currentDate() ? state.day : null;
  $("genesis-line").hidden = !(day && day.genesis);
  $("force-line").hidden   = !(day && day.hasDailyLedger) || $("chk-closed").checked;
  updateButtons();
}

/* The predicted closing balance, shown BESIDE the counted one and never in it.
   Filling the box would make the day balance by construction and the check
   would detect nothing, forever (Warnings Guide §8).

   A negative prediction is not a balance anyone could have left: more was paid
   out than there was to pay it with. That is said as a deficit, using the two
   totals the server sends with the prediction, never as a negative figure. It
   waits until the closing balance has been reached, so someone on their way to
   that box gets to enter it before a warning appears under it. */
function showPredicted(predicted, available, paidOut) {
  const box = $("predicted");
  if (predicted === null || predicted === undefined || isNaN(predicted)) { box.hidden = true; return; }
  // Under half a cent either way is zero, as in Checks.jl, so rounding noise
  // never shows as a deficit or as "-0.00".
  if (Math.abs(predicted) < 0.005) predicted = 0;
  if (predicted < 0) {
    if (!reached(state.config.closingKey) ||
        available === null || available === undefined || paidOut === null || paidOut === undefined) {
      box.hidden = true;
      return;
    }
    box.hidden = false;
    box.classList.add("off");
    box.textContent = "There's a deficit of " + money(paidOut - available) +
                      " between the total cash available (" + money(available) +
                      ") and total paid out (" + money(paidOut) + ").";
    return;
  }
  const counted = readAmounts()[state.config.closingKey];
  box.hidden = false;
  if (counted === null || counted === undefined) {
    box.classList.remove("off");
    box.textContent = "The figures predict " + money(predicted) + ". Input the actual amount of money left.";
  } else {
    const diff = Number(counted) - predicted;
    const off  = Math.abs(diff) >= 0.005;
    box.classList.toggle("off", off);
    box.textContent = off
      ? "Predicted " + money(predicted) + ", counted " + money(counted) + " — " +
        money(Math.abs(diff)) + (diff > 0 ? " more" : " less") + " than the figures account for."
      : "Predicted " + money(predicted) + " and that is what was counted. The day balances.";
  }
}

/* What the previous calendar day closed at. Shown, never pre-filled. */
let priorSeq = 0;
async function loadPrior() {
  const box = $("prior-hint");
  const seq = ++priorSeq;
  const iso = currentDate();
  if (!iso) { box.hidden = true; return; }
  try {
    const res = await api("/api/prior?date=" + encodeURIComponent(iso));
    if (seq !== priorSeq) return;       // another date was picked meanwhile
    box.hidden = false;
    box.classList.toggle("off", !res.genesis && !res.hasPrior);
    if (res.genesis) {
      box.textContent = "This would be the first day on record. Its opening balance cannot be checked against anything.";
    } else if (res.hasPrior) {
      box.textContent = prettyDate(res.priorDate) + " closed with " + money(res.expected) +
                        ". Count the drawer and enter what is there — do not copy this figure.";
    } else {
      box.textContent = "The day before this one has not been entered. This day will be saved, but its ledger will wait.";
    }
  } catch (e) {
    if (seq === priorSeq) box.hidden = true;
  }
}

/* ---------------------------------------------------------------------------
   The Checks panel on narrow screens
--------------------------------------------------------------------------- */

// Below 1100px the Checks panel is hidden until the status pill in the dock
// opens it, as the next block in the page just below the dock.
function setChecksSheet(open) {
  $("checks").classList.toggle("open", open);
  $("dock-status").setAttribute("aria-expanded", String(open));
}

// The dock is often at the bottom edge of the window when its pill is pressed,
// which would open the panel out of sight, so it is scrolled into view.
function toggleChecksSheet() {
  const open = !$("checks").classList.contains("open");
  setChecksSheet(open);
  if (open) $("checks").scrollIntoView({ block: "nearest", behavior: "smooth" });
}

function onKeydown(e) {
  if (e.key !== "Escape" || !$("checks").classList.contains("open")) return;
  const wasInside = $("checks").contains(document.activeElement);
  setChecksSheet(false);
  if (wasInside) $("dock-status").focus();
}

/* ---------------------------------------------------------------------------
   Saving a day, and moving on to the next one

   Two separate actions, and the order matters: Save writes the day and leaves
   the form on it, so the figures can still be seen beside the confirmation.
   Next day writes nothing at all — it asks the server whether this day is in
   the books exactly as shown, and moves on only if it is.
--------------------------------------------------------------------------- */
let saving = false;       // a second click while a save is on its way does nothing
let moving = false;       // ...and the same for Next day

/* Returns the date that was saved, or false. */
async function saveDay() {
  if (saving) return false;
  saving = true;
  updateButtons();
  try {
    // BUGFIX (v4.0): the check used to run only 350 ms after typing stopped,
    // so Save pressed straight after the last figure could send the day before
    // its reason box had appeared. Save now waits for a check of exactly what
    // is on screen before deciding anything.
    clearTimeout(checkTimer);
    state.saveTried = true;
    await runCheck();

    if (emptyReason()) {
      askForReason();
      return false;
    }
    if (needsGenesisTick()) {
      askForGenesis();
      return false;
    }
    if (!formValid()) {
      banner("banner-area", "warn", "Fix what is marked in red before saving this day.");
      return false;
    }

    // v4.0: a closed day sends no figures at all. The server carries the previous
    // balance through, because nobody counted the drawer on a day the clinic was
    // shut and a typed figure would be fiction.
    const date = currentDate();
    const closed = $("chk-closed").checked;
    if (closed && !confirm(
          "Mark " + prettyDate(date) + " as CLOSED?\n\n" +
          "No ledger will be generated for it, and the next working day will open " +
          "with the balance carried straight through.\n\n" +
          "If the clinic actually traded, this would erase the day's takings.")) {
      return false;
    }

    // Saving writes the day straight to the books. A tick goes with it only
    // while its box is showing, so one left behind a hidden box (an Off day
    // has no ledger file to replace) is never sent.
    const payload = closed
      ? { date, status: "closed" }
      : { date, amounts: readAmounts(), ...readReasons() };
    payload.allowGenesis = !$("genesis-line").hidden && $("chk-genesis").checked;
    payload.force        = !$("force-line").hidden && $("chk-force").checked;

    let res;
    try {
      res = await api("/api/save", { method: "POST", body: JSON.stringify(payload) });
    } catch (e) {
      // The server's refusal is the one that counts. It sends the findings that
      // explain it (a Stop, or a difference with no reason), so show those too.
      banner("banner-area", "error", e.message);
      if (e.data && Array.isArray(e.data.findings)) {
        // The banner is at the top of the page and the person is down at the
        // Save button, so a Must-fix warning's explanation opens in the dock,
        // right above the button that was just pressed.
        const stop = e.data.findings.find(f => f.level === 1);
        if (stop) { state.selected = findingKey(stop); explainedFrom = null; }
        renderChecks(e.data.findings);
        if (stop) {
          revealExplanation("nearest");
        } else if (e.data.needsReason) {
          focusReason();
        }
      } else if (e.data && e.data.needsGenesis) {
        // The server found this date has nothing on record before it, which the
        // last check had not said (the books changed meanwhile). Show the box.
        setDayFacts({ ...(state.day || {}), date, genesis: true });
        askForGenesis();
      }
      return false;
    }

    // The books have changed, so what the last check said about this date no
    // longer holds. The next check says it again.
    setDayFacts(null);
    state.editing = null;
    $("btn-cancel-edit").hidden = true;
    const saved = res.date || date;
    // Anything the bookkeeping code warned about while saving, such as a ledger
    // file left as it was, follows the confirmation.
    const warnings = (res.warnings || []).join(" ");
    state.notice = { date: saved, text: `${prettyDate(saved)} saved to the books.` + (warnings ? " " + warnings : "") };
    resumeBanner();
    // The day is in the books now, so a refusal of Next day that said it was
    // not saved has stopped being true.
    dockMessage();
    return saved;
  } finally {
    saving = false;
    updateButtons();
  }
}

/* A day that needs a reason was about to be saved without one: put the cursor
   in the first empty reason box, which says what the reason is for. Nothing is
   sent. */
function askForReason() {
  focusReason();
  banner("banner-area", "warn", "Add a short reason before saving this day.");
}

/* The first day on record was about to be saved without its box ticked: put
   the cursor on the box, which says what ticking it means. Nothing is sent. */
function askForGenesis() {
  const box = $("chk-genesis");
  box.scrollIntoView({ block: "center", behavior: "smooth" });
  box.focus({ preventScroll: true });
  banner("banner-area", "warn", "Tick the first-day box before saving this day.");
}

/* Save: write this day to the books and stay on it.

   The form stays where it is on purpose, so the figures are still there beside
   the confirmation. The check is then run again straight away, because the
   books have just changed underneath it: the date is now saved, a ledger file
   now exists for it, and the tick boxes and the banner have to say so. */
async function onSave() {
  const saved = await saveDay();
  if (!saved) return;
  await runCheck();
}

/* Next day: move the form on to the day after this one.

   This writes nothing. The server is asked whether this date is in the books
   with exactly the figures and reasons on screen, and its answer is the whole
   decision — a day that was never saved, or one whose figures have been
   changed since, comes back as a refusal and the form stays put. The page
   never presses Save by itself: what to do about the refusal is the person's
   choice, and the sentence under the buttons says what it is. */
async function onNextDay() {
  if (saving || moving) return;
  if (dateProblem() !== "") return;
  const date = currentDate();
  const closed = $("chk-closed").checked;
  const payload = closed
    ? { date, status: "closed" }
    : { date, amounts: readAmounts(), ...readReasons() };

  moving = true;
  updateButtons();
  let res;
  try {
    res = await api("/api/next", { method: "POST", body: JSON.stringify(payload) });
  } catch (e) {
    // The server's sentence, as it wrote it, under the button that was just
    // pressed rather than at the top of the page, which is off screen from
    // there. Nothing was saved and nothing moved.
    dockMessage("warn", e.message);
    return;
  } finally {
    moving = false;
    updateButtons();
  }

  // The day after today has not happened yet, so there is nowhere to go. Said
  // beside the button, for the same reason as the refusal above.
  if (!res.next) {
    dockMessage("info", "Today is saved. There is no next day to enter yet.");
    return;
  }

  resetForm(null, { date: res.next });
  window.scrollTo({ top: 0, behavior: "smooth" });
  // Ready for the next morning count. The page put the cursor here, so moving
  // on without typing does not count as leaving the box blank.
  const first = document.querySelector("#slot-opening input");
  if (first) { pageFocused = first; first.focus({ preventScroll: true }); }
}

/* ---------------------------------------------------------------------------
   Editing a day that is already in the books
--------------------------------------------------------------------------- */

/* "Edit that day": load the saved day back into the form exactly as it was
   saved, figures, counted balances, reason and all, so a mistake can be put
   right without typing the whole day again. Saving it replaces the day in the
   books. The balances are that date's own counts, loaded only because someone
   asked to edit that date; nothing is pre-filled for a day being entered. */
async function startEdit(iso) {
  let res;
  try {
    res = await api("/api/day?date=" + encodeURIComponent(iso));
  } catch (e) {
    banner("banner-area", "error", e.message);
    return;
  }
  if (!res.day) {
    banner("banner-area", "error", `${prettyDate(iso)} is not in the books, so there is nothing to edit.`);
    return;
  }
  state.editing = iso;
  state.notice = null;
  $("btn-cancel-edit").hidden = false;
  resetForm(res.day);
  banner("banner-area", "info", `Editing ${prettyDate(iso)}. Saving will replace it.`);
  window.scrollTo({ top: 0 });
}

/* The standing banner, most important first:
     1. while a saved day is being edited, the Editing banner stays put;
     2. the date on screen is already in the books, so saving will replace it.
        Right after that date was saved (saving today leaves the form on today)
        this is said together with the confirmation, rather than as a warning;
     3. what the last save did. */
function resumeBanner() {
  if (state.editing) return;
  const iso = currentDate();
  const day = dateProblem() === "" && state.day && state.day.date === iso ? state.day : null;
  const notice = state.notice;
  if (day && day.inBooks) {
    const justSaved = !!notice && notice.date === iso;
    banner("banner-area", justSaved ? "info" : "warn",
      (justSaved ? notice.text : `${prettyDate(iso)} is already saved.`) + " Saving again will replace it.",
      "Edit that day", () => startEdit(iso));
  } else if (notice) {
    banner("banner-area", "info", notice.text);
  } else {
    banner("banner-area", "");
  }
}

/* ---------------------------------------------------------------------------
   Boot
--------------------------------------------------------------------------- */

/* v4.0: hide the figure entry entirely when a day is marked closed. Nothing on
   a closed day is typed — the balance simply passes through — so leaving the
   fields on screen would invite somebody to fill them in. styles.css does the
   hiding through .is-closed; the reason boxes and the predicted line are also
   marked hidden here because formValid() and the checks read them. */
function applyClosedState() {
  const closed = $("chk-closed").checked;
  $("view-entry").classList.toggle("is-closed", closed);
  $("closed-note").textContent = closed ? CLOSED_NOTE : "";
  if (closed) {
    REASONS.forEach(r => { $(r.box).hidden = true; });
    $("predicted").hidden = true;
  }
  renderDayFacts();          // an Off day has no ledger file to replace; also updates the buttons
}

function wireEvents() {
  $("btn-save").onclick        = onSave;
  $("btn-next").onclick        = onNextDay;
  $("btn-clear").onclick       = () => resetForm(null, { date: currentDate() });     // keeps the chosen date
  $("btn-cancel-edit").onclick = () => { state.editing = null; $("btn-cancel-edit").hidden = true; resetForm(); };

  // v4.0 listeners
  $("chk-closed").addEventListener("change", () => { applyClosedState(); runCheck(); });
  REASONS.forEach(r => $(r.input).addEventListener("input", updateButtons));   // Save becomes available once each reason is typed
  $("chk-genesis").addEventListener("change", updateButtons); // ...and once the first day on record is accepted
  $("dock-status").addEventListener("click", toggleChecksSheet);
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("pointerdown", () => { pressing = true; }, true);
  document.addEventListener("pointerup", pressEnded, true);
  document.addEventListener("pointercancel", pressEnded, true);
}

async function boot() {
  try {
    state.config = await api("/api/config");
    state.today  = state.config.today;
  } catch (e) {
    const page = document.querySelector("main.page") || document.body;
    const div = el("div", "banner error");
    div.appendChild(el("span", "", "Could not reach the server. Is the terminal window still open?"));
    page.replaceChildren(div);
    return;
  }

  buildGroups();
  updateButtons();          // greyed out until there is a date
  resetForm();
  wireEvents();
}

boot();
