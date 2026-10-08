/* =========================================================================
   app.js — the whole front end.

   RESPONSIBILITY, STATED PLAINLY: collect one day's figures, show what the
   server's checks say about them, and POST them. That is all. It never
   computes a ledger row, never decides a filename, never learns what an
   account is, and never decides how serious a warning is. Every one of those
   belongs to the server, and keeping them there is what makes this page
   replaceable without touching anything else.

   WHERE THE DATA LIVES: not here. Saving sends the day to the server, which
   checks it again and writes it straight to the books, and makes the day's
   ledger file again every time. This page holds no record it cannot re-fetch,
   so closing the tab loses nothing that was saved.

   THE TWO ACTIONS: Save (/api/save) writes the day and stays on it; that it
   worked is said by the Checks panel ("Day saved, ledger generated", or the
   grey note "This day has been saved."), and only when the panel is out of
   sight, or the server has something to add, by a line under the buttons. Next day
   (/api/next) writes nothing; it asks the server whether the day on screen is
   already in the books, exactly as shown, and only then moves the form on to
   the date the server names. Whether the day may be left is the server's
   answer, never this page's guess.

   A SAVED DAY COMES BACK BY ITSELF: whenever the form lands on a date (opening
   the page, picking a date, Next day), the server is asked for that date
   (/api/day). A date already in the books comes up as it was saved: its
   figures and reasons, or the Off day switch on for an Off day. Any other date
   comes up blank. The owner chose this on 2026-10-07. Clear still blanks the
   form and keeps the date; after Clear on a saved day, and only then, the quiet
   "Show saved figures" link under the Checks list (or Ctrl+Alt+Z) brings the
   day back. It is not a check and is never counted as one.

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
  today:     null,
  findings:  [],          // last findings from the server, so the list can re-render without a request
  day:       null,        // what the last check said about the date itself: {date, genesis, hasDailyLedger, inBooks}
  touched:   new Set(),   // drawer-count keys the person has left (blur) at least once for this form, or loaded with a saved day
  saveTried: false,       // Save pressed for this form
  checkedFor: null,       // the figures the findings on screen were checked against, as JSON
  checkAnswered: false,   // a check has answered (or failed) for this form since it was last reset
  selected:  null,        // finding whose full explanation is open in the dock, by findingKey()
  dockMsgDate: null,      // the date the message under the buttons is about, or null
  loadMsgDate: null,      // the date the sentence about a failed look-up is about, or null
  clearedDate: null,      // the date Clear blanked, for "Show saved figures"; null once anything else starts the form again or the day is saved
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

function banner(where, kind, text) {
  const host = $(where);
  host.replaceChildren();
  if (!text) return;
  const div = el("div", "banner " + kind);
  div.appendChild(el("span", "", text));
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
  setTimeout(() => { swallowClick = false; }, 0);   // likewise: the click comes first, if there is one
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

  // What the last check said about the date belongs to that date alone.
  if (state.day && state.day.date !== currentDate()) setDayFacts(null);
  // So does the answer Next day gave: it named a date, and another date is
  // now on screen. A figure being typed does not take it down — a day that was
  // never saved is still unsaved while it is being corrected.
  if (state.dockMsgDate && state.dockMsgDate !== currentDate()) dockMessage();
  // And the sentence about a failed look-up belongs to the date it was about.
  if (state.loadMsgDate && state.loadMsgDate !== currentDate()) loadMessage();

  clearBanner();
  updateButtons();
  return msg === "";
}

// The first day on record is showing its box and the box is not ticked yet. An
// Off day is never the starting point, so its box is greyed out and never needed.
const needsGenesisTick = () => !$("genesis-line").hidden && !$("chk-closed").checked &&
                               !$("chk-genesis").checked;

/* What the server's last check said stands in the way of a save: a Must fix,
   or a difference whose own reason box is still blank. Judged on every finding
   the server returned, not only the rows the panel is showing. A blank drawer
   count the person has not reached yet is still a Must fix, and a difference
   in a box the cursor is still in still needs its reason; the panel holds
   those rows back (isTodo), the button does not. */
function serverBlocks() {
  if ($("chk-closed").checked) return false;          // an Off day sends no figures
  // Nothing has been heard about this form yet (just reset, or just switched
  // back to a Work day): not saveable until the server has looked at it. A
  // check that could not be sent or answered counts as heard, so a server that
  // is down still gets reported by the save that follows.
  if (!state.checkAnswered) return true;
  return state.findings.some(f =>
    f.level === 1 ||
    (f.level === 2 && $(reasonFor(f).input).value.trim() === ""));
}

/* Save is green only while the day is in a state the server would save. The
   owner settled this on 2026-10-06: a green button that is refused when
   pressed, or that works on an empty form, says the wrong thing. The server
   still makes the decision that counts; this copy exists so the button greys
   out rather than the save failing (Warnings Guide §8). */
function formValid() {
  // v4.0: a Level 2 difference cannot be saved until its reason is typed.
  if (emptyReason()) return false;
  // The first day on record has nothing to check its opening balance against,
  // so it is accepted once, deliberately, by ticking its box. Same idea: the
  // server refuses the day without it, and the button greys out first.
  if (needsGenesisTick()) return false;
  if (dateProblem() !== "") return false;
  // Whatever the last check found: a Must fix (a blank drawer count, more cash
  // out than there was, and the rest), or a difference with no reason yet.
  if (serverBlocks()) return false;
  // A closed day sends no figures, so a half-typed figure now hidden behind the
  // Closed toggle must not stop it being saved.
  if ($("chk-closed").checked) return true;
  return !formInputs().some(i => i.classList.contains("invalid"));
}

/* Save is greyed out whenever the day cannot be saved as it stands: a Must fix
   or a difference with no reason in the server's last answer, an unticked
   first day, a bad date or a red box. Next day is not judged here. It is
   greyed out only while there is no usable date to ask about, and while a
   save or a move is already on its way; whether the day may be left is the
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
    [ySel, mSel].forEach(s => s.addEventListener("change", () => { fillDays(); onDateChange(); }));
    dSel.addEventListener("change", onDateChange);
  }

  const target = iso || state.today;
  // Already on that date (Clear, a load, or the person's own pick): the lists
  // are left alone, so one being stepped through with the arrow keys is not
  // rebuilt under the cursor.
  if (currentDate() !== target) {
    const [yy, mm, dd] = target.split("-").map(Number);
    ySel.value = yy;
    mSel.value = mm;
    fillDays(dd);
  }
  dateShown = currentDate();
}

/* Another date is another day. Picking one starts the form again on that date:
   the figures, both reasons, the Off day switch, the first-day tick, the Checks
   panel and anything said under the buttons all described the day that was on
   screen. (Until 2026-10-06 the figures were kept, so a saved day's figures and
   its checks stayed on screen under whatever date was picked next.) A date that
   is already in the books then comes up as it was saved; any other date stays
   blank, exactly as Clear leaves it (openDate). */
let dateShown = null;     // the date the form is on, to tell a real change of date
function onDateChange() {
  if (currentDate() === dateShown) return;
  openDate(currentDate());
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
   startup, Next day, Clear, picking another date, and a saved day coming up
   (openDate). Before this existed each of those reset a different part of the
   form, so a reason typed for one day was saved again with the next, an edited
   closed day reopened as a trading day, and the warnings on screen described
   figures that were no longer there.

   `day` is a saved day as /api/day returns it. Without one the form is blank,
   on `date` if given and on today otherwise. `check: false` leaves the check
   to the caller: openDate runs it once it knows whether the date is saved, so
   a blank form is not checked a moment before the saved day replaces it.
--------------------------------------------------------------------------- */
function resetForm(day = null, { date, check = true } = {}) {
  // Everything on screen described the old figures. Drop the pending check,
  // ignore any answer still on its way, and start the Checks panel from
  // nothing. This happens before the new figures go in, because an empty
  // Checks list also empties the reason boxes.
  clearTimeout(checkTimer);
  checkSeq++;
  formSeq++;                           // and a saved day, or a save's own check, still on its way is let go
  pageFocused = null;
  state.touched.clear();
  state.saveTried = false;
  state.selected = null;
  state.checkedFor = null;
  state.checkAnswered = false;         // Save stays grey until the check below answers
  state.clearedDate = null;            // Clear sets it again itself (onClear)
  renderChecks([]);
  $("predicted").hidden = true;
  dockMessage();                       // whatever Next day last answered was about the old day
  loadMessage();                       // and a failed look-up's sentence was about the old form

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

  setChecksSheet(false);
  applyClosedState();
  validateDate();
  refreshTotals();
  updateButtons();
  loadPrior();
  if (check) return runCheck();
}

/* Put the form on a date, as it is in the books. The form goes blank at once,
   so nothing typed for the old date can be saved under the new one while the
   server is asked. Then a date that is already in the books comes up as it was
   saved: a Work day with its figures and reasons, an Off day with the switch on
   and every box blank (resetForm says why). A date that is not in the books
   stays blank. Either way the check runs once, on what ends up on screen.

   The saved day is put in only if nothing has happened to the form meanwhile:
   another date, Clear or Next day start it again (resetForm), and a figure
   typed or the Off day switch moved is the person's own start on the form, which
   is kept. If the server cannot be asked, the form stays blank and says so in
   one sentence under the grey notes in the Checks panel (loadMessage).

   `cursor` is for Next day: back to the top, with the cursor in the opening
   balance, as the page put it there. */
let formSeq = 0;          // numbers each fresh start of the form (resetForm), so an answer meant for an earlier one is let go
async function openDate(date, { cursor = false } = {}) {
  resetForm(null, { date, check: false });
  const seq = formSeq;
  if (cursor) {
    window.scrollTo({ top: 0, behavior: "smooth" });
    const first = document.querySelector("#slot-opening input");
    if (first) { pageFocused = first; first.focus({ preventScroll: true }); }
  }
  const sigAtStart = formSig();
  let day = null;
  if (dateProblem() === "") {
    try {
      const res = await api("/api/day?date=" + encodeURIComponent(date));
      day = res.day || null;
    } catch (e) {
      if (seq === formSeq && currentDate() === date) {
        loadMessage(`Could not look up ${prettyDate(date)}. ${e.message}`);
      }
    }
  }
  // The form was started again meanwhile, and that start ran its own check.
  if (seq !== formSeq) return;
  if (day && currentDate() === date && formSig() === sigAtStart) showSaved(day);
  else runCheck();
}

/* Put a saved day on screen. On an Off day the boxes are hidden, so a cursor
   left in one is taken out first, as the page's own doing: the box was not
   visited, and its blank count must not be warned about early if the day is
   switched back to a Work day (isTodo). On a Work day a cursor the page put in
   the opening balance stays the page's. */
function showSaved(day) {
  const active = document.activeElement;
  if (day.status === "closed" && active && formInputs().includes(active)) {
    pageFocused = active;
    active.blur();
  }
  const byPage = pageFocused;
  resetForm(day);
  if (byPage && document.activeElement === byPage) pageFocused = byPage;
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
   does not alarm on the first figure typed. It is still a Stop: Save is grey
   while it stands (serverBlocks), and its row appears as soon as the box is
   left blank. A difference in a drawer count, with its reason box, waits for
   the same moment, so nobody is asked for a reason while still typing the
   figure; Save is grey until that reason is typed. So does the deficit line
   under the closing balance (showPredicted). A row held back this way also
   appears when a press of Save runs into it, which can only happen in the
   moment between the last keystroke and the check's answer (saveDay).
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
  close.title = "Close (Esc)";
  close.setAttribute("aria-keyshortcuts", "Escape");

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
    state.checkAnswered = true;
    renderChecks(res.findings);
    // "This day cannot be saved yet." answered a press that ran into a Must
    // fix. Once a check finds no Must fix, Save is green again and the sentence
    // would contradict it, so it goes.
    if (!state.findings.some(f => f.level === 1)) clearStopBanner();
    setDayFacts({ date: body.date, genesis: !!res.genesis,
                  hasDailyLedger: !!res.hasDailyLedger, inBooks: !!res.inBooks });
    if (closed) $("predicted").hidden = true;
    else        showPredicted(res.predicted, res.available, res.paidOut);
  } catch (e) {
    // A failed check must never block typing. The server re-checks on save.
    // The form has been heard about, even if nothing came back: Save follows
    // the last findings, and a press reports a server that cannot be reached.
    if (seq !== checkSeq) return;
    state.checkAnswered = true;
    updateButtons();
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
  if (!sameDate) $("chk-genesis").checked = false;
  state.day = facts;
  renderDayFacts();
  // The banner is taken down only when "is this date already saved?" gets a new
  // answer. Checks arrive after every pause in typing, and clearing it each
  // time would wipe a message Save has just put up (a refusal, a request for a
  // reason) while the person is still acting on it.
  if ((sameDate && before.inBooks) !== (!!facts && facts.inBooks)) clearBanner();
}

/* The first-day tick box and the grey notes in the Checks panel appear only when
   they apply to the date on screen. The first note says a save will make the
   day's ledger file again, so it shows only for a Work day that already has one.
   The second says the day is saved for every other saved day: one whose ledger
   waits on the day before, and an Off day, which has no ledger. On an Off day the first-day tick stays
   in view but greyed out and unticked: an Off day has no balance of its own, so
   it saves without becoming the starting point, and the first Work day after it
   is asked instead. Switched back to a Work day, the tick works again. */
function renderDayFacts() {
  const day = state.day && state.day.date === currentDate() ? state.day : null;
  $("genesis-line").hidden = !(day && day.genesis);
  const offDay = $("chk-closed").checked;
  $("chk-genesis").disabled = offDay;
  if (offDay) $("chk-genesis").checked = false;
  $("genesis-line").classList.toggle("is-off", offDay);
  $("checks-regen").hidden = !(day && day.hasDailyLedger) || offDay;
  // Any other saved day, Off day included: nothing else in the panel would say
  // it is saved. (An Off day whose date still has a ledger file from an earlier
  // Work day save has "Day saved, ledger generated" saying so.)
  $("checks-saved").hidden = !(day && day.inBooks && !day.hasDailyLedger);
  // An Off day has no figures on screen, so its note is only "This day has been
  // saved." (owner, 2026-10-07). Switched to a Work day, the whole note shows.
  $("checks-saved-more").hidden = offDay;
  // "Show saved figures" is only for a saved date that Clear has just blanked:
  // anywhere else the saved day is already on screen, or there is none.
  $("checks-load").hidden = !(day && day.inBooks && state.clearedDate === currentDate());
  updateButtons();
}

/* Clear: blank the form and keep the date. On a saved date the day can then be
   brought back with "Show saved figures"; the link shows as soon as the last
   check (or the one Clear runs) says the date is saved. */
function onClear() {
  resetForm(null, { date: currentDate() });
  state.clearedDate = currentDate();
  renderDayFacts();
}

/* The form as one string: Off day or not, and for a Work day the figures and
   both reasons. openDate and "Show saved figures" compare it before and after
   asking for a saved day, to tell whether the person has started on the form
   meanwhile. */
function formSig() {
  if ($("chk-closed").checked) return JSON.stringify({ closed: true });
  return JSON.stringify({ closed: false, amounts: readAmounts(), ...readReasons() });
}

/* The one sentence said when a date could not be looked up (openDate), or when
   "Show saved figures" did not work. It sits under the grey notes and the link
   in the Checks panel, never in the banner at the top. Below 1100 px it is only
   seen through the Checks pill, which shows only when there is a row (the same
   accepted narrow-window limit as the link itself).
   Like the dock message it is about one date, and is taken down with no text,
   when another date is chosen, when the form is reset, and when a save works. */
function loadMessage(text) {
  const msg = $("checks-load-msg");
  msg.textContent = text || "";
  msg.hidden = !text;
  state.loadMsgDate = text ? currentDate() : null;
}

/* "Show saved figures" (or Ctrl+Alt+Z), after Clear on a saved day: put the
   date on screen back as it is in the books. This replaces whatever has been
   typed since, and that is what was asked for by pressing it. Nothing is
   calculated here: the server's figures go in as sent, balances included, and
   the checks run on them like on any form. Then, as after Next day, the page
   goes to the top with the cursor in the opening balance (an Off day has no
   box to be in). */
let loadingSaved = false;
async function onLoadSaved() {
  if (loadingSaved || dateProblem() !== "") return;
  const date = currentDate();
  const seq = formSeq;
  const sigAtPress = formSig();
  loadingSaved = true;
  loadMessage();
  let res;
  try {
    res = await api("/api/day?date=" + encodeURIComponent(date));
  } catch (e) {
    if (currentDate() === date && formSeq === seq) loadMessage(e.message);
    return;
  } finally {
    loadingSaved = false;
  }
  // Another date was chosen, the form was started again, or the boxes were
  // changed, while this was on its way.
  if (currentDate() !== date || formSeq !== seq || formSig() !== sigAtPress) return;
  if (!res.day) { loadMessage(prettyDate(date) + " is not in the books."); return; }

  showSaved(res.day);
  window.scrollTo({ top: 0, behavior: "smooth" });
  const first = document.querySelector("#slot-opening input");
  if (first && !$("chk-closed").checked) { pageFocused = first; first.focus({ preventScroll: true }); }
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

/* Esc closes what is open, one thing at a time: a full explanation in the dock
   first, exactly as its ✕ does (which also returns the cursor to its link),
   otherwise the narrow-screen Checks sheet. The key's own action is suppressed
   only when it closed something. */
function onKeydown(e) {
  if (e.key !== "Escape") return;
  if (!$("dock-note").hidden) {
    e.preventDefault();
    closeExplanation();
    return;
  }
  if (!$("checks").classList.contains("open")) return;
  const wasInside = $("checks").contains(document.activeElement);
  setChecksSheet(false);
  if (wasInside) $("dock-status").focus();
}

/* ---------------------------------------------------------------------------
   Keyboard shortcuts

   Four, and only four: Ctrl+S saves, Ctrl+N goes to the next day, Ctrl+Alt+C
   clears the day, and Ctrl+Alt+Z presses "Show saved figures" after a Clear.
   Each acts exactly like pressing its button: a greyed-out Next day, or a link
   that is not showing, does nothing; a greyed-out Save answers the key as it
   answers a click, saying why it cannot save (pressGreySave). Otherwise the
   button is focused first so the box
   being typed in is left the way a mouse click would leave it (the amount is
   tidied, the "left the box" rule runs), then the button is clicked. On a
   narrow window the link sits in the closed Checks sheet; the key still
   reaches it there.
   The keys are matched on e.code, so the keyboard layout and AltGr do not
   change them. The browser's own meaning for these keys (Save page as, New
   window) is always suppressed. Nothing else is intercepted.
   In an ordinary Chrome tab Ctrl+N belongs to the browser and never reaches
   the page; in ldgr's --app window it does.
--------------------------------------------------------------------------- */
const SHORTCUTS = [
  { code: "KeyS", alt: false, button: "btn-save" },
  { code: "KeyN", alt: false, button: "btn-next" },
  { code: "KeyC", alt: true,  button: "btn-clear" },
  { code: "KeyZ", alt: true,  button: "checks-load" },
];

function onShortcut(e) {
  if (!e.ctrlKey || e.metaKey || e.shiftKey) return;
  // On Windows AltGr reports Ctrl and Alt together; that is a typed character
  // on some layouts, never Ctrl+Alt+C or Ctrl+Alt+Z.
  if (e.getModifierState && e.getModifierState("AltGraph")) return;
  const hit = SHORTCUTS.find(s => s.code === e.code && s.alt === e.altKey);
  if (!hit) return;
  e.preventDefault();
  if (e.repeat) return;
  const btn = $(hit.button);
  if (btn.disabled) {
    // A greyed-out Save still answers the key, as it answers a click: it says
    // why it is grey, or waits for the check of figures just typed. Nothing is
    // ever sent from here that the check refuses.
    if (hit.button === "btn-save") pressGreySave(false);
    return;
  }
  if (btn.hidden) return;             // "Show saved figures" only after Clear on a saved day
  btn.focus();
  btn.click();
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

/* Returns {date, warnings} for the day that was saved, or false. */
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
    const date = currentDate();
    const seq = formSeq;
    await runCheck();
    // Another date was picked, or the form was started again (Clear, or a saved
    // day coming up), while that check was on its way. The day Save was pressed
    // for is no longer on screen, so nothing is sent and nothing is said.
    if (currentDate() !== date || formSeq !== seq) return false;

    // Save was green when it was pressed, and the check it just waited for
    // says the day cannot be saved as it stands (the last figure typed made
    // the day impossible, or revealed a drawer count left blank, or left a
    // difference with no reason yet). The button greys out with that answer,
    // and this press is answered as a press on the grey button is.
    if (explainRefusal()) return false;

    // v4.0: a closed day sends no figures at all. The server carries the previous
    // balance through, because nobody counted the drawer on a day the clinic was
    // shut and a typed figure would be fiction.
    const closed = $("chk-closed").checked;
    if (closed && !confirm(
          "Mark " + prettyDate(date) + " as CLOSED?\n\n" +
          "No ledger will be generated for it, and the next working day will open " +
          "with the balance carried straight through.\n\n" +
          "If the clinic actually traded, this would erase the day's takings.")) {
      return false;
    }

    // Saving writes the day straight to the books. The first-day tick goes with
    // it only while its box is showing, so one left behind a hidden box is
    // never sent.
    const payload = closed
      ? { date, status: "closed" }
      : { date, amounts: readAmounts(), ...readReasons() };
    payload.allowGenesis = !$("genesis-line").hidden && $("chk-genesis").checked;
    // The owner decided on 2026-09-29 that saving always regenerates the day's
    // ledger file. The explanation of "Day saved, ledger generated" tells staff
    // how to keep QuickBooks free of a double import.
    payload.force = true;

    let res;
    try {
      res = await api("/api/save", { method: "POST", body: JSON.stringify(payload) });
    } catch (e) {
      // The server's refusal is the one that counts. It sends the findings that
      // explain it (a Stop, or a difference with no reason), so show those too.
      if (currentDate() !== date) {
        // Another date was picked while the save was on its way. A save that
        // failed is never kept quiet, but the sentence has to name its day,
        // because that day is no longer the one on screen; and its findings
        // describe figures that are not in the boxes any more.
        banner("banner-area", "error", `${prettyDate(date)} was not saved. ${e.message}`);
        return false;
      }
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
    // longer holds. The next check says it again. What is on screen is now what
    // is saved, so there is nothing for "Show saved figures" to bring back, and
    // a failed look-up of this date is old news. Only if the form Save was
    // pressed for is still the one on screen: a Clear or another date picked
    // while the save was on its way keeps its own link and sentence.
    if (formSeq === seq) { state.clearedDate = null; loadMessage(); }
    setDayFacts(null);
    // Anything the bookkeeping code warned about while saving follows the
    // confirmation, which onSave() words once the re-check has said whether the
    // Checks panel confirms the save itself.
    const warnings = (res.warnings || []).join(" ");
    // Any refusal banner was about the figures just sent.
    clearBanner();
    // The day is in the books now, so a refusal of Next day that said it was
    // not saved has stopped being true.
    dockMessage();
    return { date: res.date || date, warnings };
  } finally {
    saving = false;
    updateButtons();
  }
}

/* Why the day cannot be saved as it stands, said where the server would say
   it, in the server's order: a Must fix first ("This day cannot be saved yet."
   at the top, and the Must fix's own explanation in the dock, beside the
   button), then a difference with no reason (the cursor in its reason box),
   then the first-day box, then a box the form itself marked red. Nothing is
   sent. Returns true when there was something to say.

   Two presses end up here: a press on the green button whose own check found
   one of these (saveDay), and a press on the GREY button (pressGreySave), which
   cannot save and says why instead. Both count as "Save pressed", so a row the
   panel was holding back until its box was left is shown now. */
function explainRefusal() {
  state.saveTried = true;
  renderChecks(state.findings);
  const stop = state.findings.find(f => f.level === 1);
  if (stop && serverBlocks()) {
    banner("banner-area", "error", STOP_SENTENCE);
    state.selected = findingKey(stop); explainedFrom = null;
    renderChecks(state.findings);
    revealExplanation("nearest");
    return true;
  }
  if (emptyReason()) {
    askForReason();
    return true;
  }
  if (needsGenesisTick()) {
    askForGenesis();
    return true;
  }
  if (!formValid()) {
    banner("banner-area", "warn", "Fix what is marked in red before saving this day.");
    return true;
  }
  return false;
}

/* A press on the grey Save button: a real click (Chrome still reports the
   pointer going down on a disabled button, though never a click) or Ctrl+S.
   It can never save. What it does is what the press used to do before the
   button learned to grey out for the server's verdict: it shows why. A drawer
   count left blank that the panel was holding back gets its row, a difference
   gets its reason box, and the explanation opens beside the button.

   One case is let through to a real press: the figures have changed since the
   last check answered (or no check has answered yet), so the button is grey
   for an answer that is out of date. Typing the closing balance and pressing
   Ctrl+S at once is the normal keyboard flow, and it must not need a second
   press half a second later. saveDay waits for a check of exactly what is on
   screen before deciding, and never sends a day that check refuses. */
let swallowClick = false;   // the click that ends a press already answered on the way down
function pressGreySave(fromPointer) {
  if (dateProblem() !== "") return;                    // the date's own message is already on screen
  if ($("chk-closed").checked) {
    // An Off day is never grey for the server's verdict; only the first-day
    // box can grey it, and the press says so.
    if (needsGenesisTick()) setTimeout(explainRefusal, 0);
    return;
  }
  if (!state.checkAnswered || !checkedIsCurrent()) {
    // Leave the box the way a press on the green button would.
    const active = document.activeElement;
    if (active && active !== document.body && active.blur) active.blur();
    // A mouse press is answered as the pointer goes down. If the day is saved
    // before the button is released, Save is green by then and the release
    // would click it a second time, saving the day twice; that click is let
    // go. The flag is cleared after the press ends (pressEnded), so a later,
    // separate click is not lost.
    swallowClick = !!fromPointer;             // a key press ends in no click
    onSave();
    return;
  }
  // After the press itself: the browser takes the focus off the box as the
  // pointer goes down, and the cursor this puts in a reason box, or on the
  // explanation, has to be put there afterwards.
  setTimeout(explainRefusal, 0);
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
   now exists for it, and the Checks panel and the first-day box have to say so.

   The Checks panel is the confirmation ("Day saved, ledger generated", or the
   grey note "This day has been saved." for a day whose ledger waits on the day
   before and for an Off day), so a sentence is added under the buttons only
   where the panel cannot say it: a window too narrow for the panel, or when the
   server has a warning to pass on. */
async function onSave() {
  const saved = await saveDay();
  if (!saved) return;
  await runCheck();
  const day = state.day && state.day.date === saved.date ? state.day : null;
  // On a narrow window the Checks panel is hidden, so it cannot confirm the save.
  const panelShown = $("checks").offsetParent !== null;
  const panelSays = day && (day.hasDailyLedger || day.inBooks);
  if (currentDate() !== saved.date || (panelSays && !saved.warnings && panelShown)) return;
  dockMessage("info", `${prettyDate(saved.date)} saved to the books.` + (saved.warnings ? " " + saved.warnings : ""));
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
  const seq = formSeq;
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
    // there. Nothing was saved and nothing moved. It is about the date that was
    // asked about, so it is not shown once another date has been picked.
    if (currentDate() === date && formSeq === seq) dockMessage("warn", e.message);
    return;
  } finally {
    moving = false;
    updateButtons();
  }
  // Another date was picked, or the form was started again (a saved day coming
  // up after the press), while the answer was on its way: that stands, and the
  // answer about the old form is let go.
  if (currentDate() !== date || formSeq !== seq) return;

  // The day after today has not happened yet, so there is nowhere to go. Said
  // beside the button, for the same reason as the refusal above.
  if (!res.next) {
    dockMessage("info", "Today is saved. There is no next day to enter yet.");
    return;
  }

  // Ready for the next morning count, or the next day as it was saved. The page
  // puts the cursor in the opening balance, so moving on without typing does
  // not count as leaving the box blank.
  openDate(res.next, { cursor: true });
}

/* Takes the top banner down. A refusal (red marks, a missing reason, an unticked
   first-day box, a save error) is about the figures sent when it was raised, so
   it goes when the date changes, when the answer to "is this date saved?"
   changes, and when a save succeeds. Nothing stands there between times. */
function clearBanner() {
  banner("banner-area", "");
}

// The Must-fix refusal alone, whether a press ran into it here or the server
// sent it; the other banners (a reason, the first-day box) are taken down at
// the moments listed above, as before.
const STOP_SENTENCE = "This day cannot be saved yet.";
function clearStopBanner() {
  if ($("banner-area").textContent.trim() === STOP_SENTENCE) clearBanner();
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
  renderDayFacts();          // an Off day has no ledger, so no regenerate note; also updates the buttons
}

function wireEvents() {
  $("btn-save").onclick        = () => { if (swallowClick) { swallowClick = false; return; } onSave(); };
  // The second click of a double-click is not a second press: a saved day now
  // comes up in a few milliseconds, and the second click would move past it.
  $("btn-next").onclick        = (e) => { if (e.detail > 1) return; onNextDay(); };
  $("btn-clear").onclick       = onClear;          // keeps the chosen date, blank even when it is saved
  $("checks-load").onclick     = onLoadSaved;

  // v4.0 listeners
  // Switching the kind of day makes the last findings describe the other kind,
  // so Save waits for the check of this one; and a Must fix refusal was about
  // the other kind of day too.
  $("chk-closed").addEventListener("change", () => { state.checkAnswered = false; clearStopBanner(); applyClosedState(); runCheck(); });
  // A click on the greyed-out Save. The button cannot take the click, but the
  // pointer going down on it is still reported, so the press can be answered.
  document.addEventListener("pointerdown", (e) => {
    const btn = $("btn-save");
    if (e.target === btn && btn.disabled) pressGreySave(true);
  }, true);
  REASONS.forEach(r => $(r.input).addEventListener("input", updateButtons));   // Save becomes available once each reason is typed
  $("chk-genesis").addEventListener("change", updateButtons); // ...and once the first day on record is accepted
  $("dock-status").addEventListener("click", toggleChecksSheet);
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("keydown", onShortcut);
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
  openDate(state.today);    // today, as saved if it already is
  wireEvents();
}

boot();
