# UI contract — `index.html`, `styles.css`, `app.js` and the server

**Change of 2026-10-07 (a saved day comes up by itself):** whenever the form
lands on a date (page load, any of the three date lists, Next day), `openDate`
blanks it at once and asks `GET /api/day`. A saved Work day then comes up with
its figures and both reasons, a saved Off day with `#chk-closed` on and every
box blank, and any other date stays blank, exactly as Clear leaves it. The
check runs once, on what ends up on screen. The answer is dropped if the form
was started again meanwhile (`formSeq`), the date changed, or a figure was
typed or the switch moved. A look-up that fails leaves the form blank and says
"Could not look up <d Month yyyy>. <sentence>" in `#checks-load-msg`.
`#checks-load` ("Show saved figures") now shows only after **Clear** on a saved
date (`state.clearedDate`), and **Ctrl+Alt+Z** presses it. `#checks-saved` now
also shows for a saved Off day, so on a wide window an Off day's save puts
nothing in `#dock-msg`. `state.known` is gone. The owner's words: "Just have
the days load with their saved figures as long as there are figures saved",
and, after Clear, "the 'show saved figures' link should then populate on the
checks sidebar ... Tie it to a ctrl+alt+z shortcut." Verified in a browser by
[`verify-saved-day-loads-2026-10-07.mjs`](verify-saved-day-loads-2026-10-07.mjs)
and the four older scripts, updated; the passages below marked
**(2026-10-07)** were rewritten for it. Passages that still name `#force-line`,
`#btn-cancel-edit`, "Edit that day" or a standing banner after a save describe
things removed on 2026-09-29; they were not rewritten here.

**Change of 2026-10-06 (Save follows the server's verdict):** `#btn-save` is
greyed out whenever the server's latest check for the figures on screen holds a
Must-fix, or a difference whose own reason is blank, whether or not the panel
is showing that row yet (`serverBlocks` in `app.js`). A blank form starts grey
and stays grey until the check has answered. The owner's words: a blank form
is not a valid save state. The rows keep their timing. **A press on the grey
button still answers** (`pressGreySave`: Chrome reports the pointer going down
on a disabled button, and Ctrl+S is handled): it never sends, but it shows why,
in the server's order (`explainRefusal`: the held-back Must-fix row and "This
day cannot be saved yet." with the explanation in the dock; or the reason box
with the cursor in it; or the first-day box; or the red box), exactly as the
press did before the button learned to grey out. A press while the figures
have changed since the last answer waits for the check and then saves (the
closing balance typed and Ctrl+S at once). Verified in a browser by
[`verify-save-gate-2026-10-06.mjs`](verify-save-gate-2026-10-06.mjs); the
passages below marked **(2026-10-06)** were rewritten for it.

**Change of 2026-09-15 (later):** the single "Save & next day" button is gone.
Save and Next day are two separate actions in the dock (§1, §3, §4), and
`POST /api/next` is the new endpoint Next day asks. Verified in a browser by
[`verify-save-next.mjs`](verify-save-next.mjs).

Updated 2026-09-15 (evening) to the form as it stands after the work in
[`implementation-2026-09-15.md`](implementation-2026-09-15.md) §6. It replaces the
version written when two agents worked on the markup and the logic at the same
time; the earlier one still described the Morning/Evening count cards, the
Review screen, to-do rows, `.check-code` and `#evening-hint`, none of which
exist any more.

**What this file is for.** The three files in `public/` share one set of ids,
classes and data attributes, and `app.js` shares a second set of names with
`server.jl`. Nothing else connects them. Rename anything listed here and you
must change every side in the same commit — and this file with them.

**Rules that hold for every change**

- `app.js` puts text on the page through `textContent` only, never `innerHTML`,
  so a label or message from the server containing `<` cannot become markup.
- `app.js` holds **no category names**. Every key comes from `/api/config`
  (`openingKey`, `closingKey`, `depositKey`, the group lists).
- The browser **never decides a severity**. It renders the level, title, field
  and message the server sent. The only judgement it makes is *when* to show a
  warning about a box nobody has reached yet (see `isTodo`).
- **Warning codes are never shown.** `data-code` carries the code for tests and
  for debugging; no code appears in any visible string.
- No inline `style=` attributes. `server.jl` serves `public/` by file name only,
  so no subfolders. `prototype.html` is a designer's reference and is not served.

---

## 1. Static markup (`index.html`)

`*` marks ids `app.js` reads or writes. Wording that is not marked *(free)* is
either read by `app.js` or was settled with the owner; do not reword it here
without changing both.

```html
<header class="topbar">
  <div class="brand">
    <span class="brand-mark"><!-- inline svg, green tile --></span>
    <div class="brand-text">
      <h1>Daily Entry</h1>
      <p class="brand-sub">Enter one day at a time and save it.</p>
    </div>
  </div>
</header>

<main class="page">
  <section id="view-entry">                                 <!-- * .is-closed -->
    <div id="banner-area"></div>                            <!-- * -->
    <p id="checks-live" class="sr-only" aria-live="polite"></p>  <!-- * see §3.3 #1 -->

    <div class="entry-grid">
      <div class="entry-main">

        <section class="card stage" id="card-morning">
          <div class="stage-head">
            <span class="stage-chip">1</span>
            <h2>Start of day</h2>
            <div class="daytype">
              <input type="checkbox" id="chk-closed" class="daytype-input">  <!-- * visually hidden, still focusable -->
              <label for="chk-closed" class="daytype-toggle">
                <span class="opt opt-trading" aria-hidden="true">Work day</span>
                <span class="opt opt-closed">Off day</span>
              </label>
            </div>
          </div>
          <div class="date-row">
            <div class="field"><label for="sel-month">Month</label><select id="sel-month"></select></div>  <!-- * -->
            <div class="field"><label for="sel-day">Day</label><select id="sel-day"></select></div>        <!-- * -->
            <div class="field"><label for="sel-year">Year</label><select id="sel-year"></select></div>     <!-- * -->
          </div>
          <div class="err" id="err-date"></div>                     <!-- * gets .show -->
          <p class="closed-note" id="closed-note"></p>              <!-- * empty unless Off day -->
          <div id="slot-opening" class="hide-when-closed"></div>    <!-- * -->
          <p id="prior-hint" class="hintline hide-when-closed" hidden></p>   <!-- * .off -->
          <div id="opening-reason-box" class="reasonbox hide-when-closed" hidden>   <!-- * -->
            <label for="txt-opening-reason"><b id="opening-reason-lead">Opening doesn't match last close.</b> Say briefly why before saving.</label>
            <input type="text" id="txt-opening-reason" maxlength="400">   <!-- * -->
          </div>
        </section>

        <section class="card stage hide-when-closed" id="card-figures">
          <div class="stage-head"><span class="stage-chip">2</span><h2>Today's numbers</h2></div>
          <p class="hint">(Leave anything that didn't happen blank)</p>   <!-- (free) -->
          <div id="groups-activity"></div>                          <!-- * -->
        </section>

        <section class="card stage hide-when-closed" id="card-evening">
          <div class="stage-head"><span class="stage-chip">3</span><h2>End of day</h2></div>
          <div id="slot-closing"></div>                             <!-- * -->
          <p id="predicted" class="hintline" hidden></p>            <!-- * .off -->
          <div id="reason-box" class="reasonbox" hidden>            <!-- * -->
            <label for="txt-reason"><b id="reason-lead">This day doesn't balance.</b> Say briefly why before saving.</label>
            <input type="text" id="txt-reason" maxlength="400">     <!-- * -->
          </div>
        </section>

        <div id="dock" class="dock">                                <!-- * last block of the form -->
          <div id="dock-note" class="dock-note" tabindex="-1" hidden></div>   <!-- * -->
          <label class="checkline" id="genesis-line" hidden>        <!-- * -->
            <input type="checkbox" id="chk-genesis">                <!-- * -->
            <span>This is the <b>first day on record</b>. Accept its opening balance as the starting point.</span>
          </label>
          <label class="checkline" id="force-line" hidden>          <!-- * -->
            <input type="checkbox" id="chk-force">                  <!-- * -->
            <span>This day's file has already been made. Tick this to make it again with the corrected figures.
              <span class="muted">(Only leave this unticked if the old file was already sent to the accountant.)</span></span>
          </label>
          <div class="dock-main">
            <button id="dock-status" class="dock-status" type="button"
                    aria-controls="checks" aria-expanded="false" hidden></button>   <!-- * narrow screens only -->
            <dl class="totals">
              <div><dt>Takings</dt><dd id="tot-cash">$0.00</dd></div>     <!-- * -->
              <div><dt>Expenses</dt><dd id="tot-exp">$0.00</dd></div>     <!-- * -->
              <div><dt>Banked</dt><dd id="tot-dep">$0.00</dd></div>       <!-- * -->
            </dl>
            <div class="dock-actions">
              <button class="btn-quiet"   id="btn-clear"       type="button">Clear</button>               <!-- * -->
              <button class="btn-ghost"   id="btn-cancel-edit" type="button" hidden>Cancel edit</button>  <!-- * -->
              <button class="btn-primary" id="btn-save"        type="button">Save</button>                <!-- * writes the day, stays on it -->
              <button class="btn-ghost"   id="btn-next"        type="button">Next day</button>            <!-- * writes nothing, asks /api/next -->
            </div>
          </div>
          <p id="dock-msg" class="dock-msg" role="status" hidden></p>   <!-- * what Next day answered; .warn / .info -->
        </div>
      </div>

      <aside id="checks" class="checks" aria-labelledby="checks-heading">   <!-- * .open -->
        <div class="checks-head">
          <h2 id="checks-heading">Checks</h2>
          <span id="checks-count" class="checks-count" hidden></span>   <!-- * -->
        </div>
        <p id="checks-empty" class="checks-empty">Nothing to fix so far</p>   <!-- * -->
        <ul id="checks-list" class="checks-list"></ul>                  <!-- * -->
        <p id="checks-regen" class="checks-note" hidden>Saving again will regenerate the ledgers with the current figures and accounts.</p>   <!-- * -->
        <p id="checks-saved" class="checks-note" hidden>This day has been saved.<span id="checks-saved-more"> Saving again will rewrite it with the current figures.</span></p>    <!-- * -->
        <button id="checks-load" class="checks-load" type="button" title="Show saved figures (Ctrl+Alt+Z)"
                aria-keyshortcuts="Control+Alt+Z" hidden>Show saved figures</button>   <!-- * -->
        <p id="checks-load-msg" class="checks-load-msg" role="status" hidden></p>   <!-- * -->
      </aside>
    </div>
  </section>

  <footer class="watermark"><!-- tiny sun svg --> Powered by <b>SolRegia</b></footer>
</main>
```

Notes on the shell:

- **`#checks-live` is a direct child of `#view-entry`**, not of `#checks`
  (review §3.3 #1). Below 1100 px `#checks` is `display:none` until the pill
  opens it, and a live region inside a hidden element is never announced.
- **Save and Next day are two actions, in that order** (2026-09-15). `#btn-save`
  is the only `.btn-primary` on the page — the one obvious main action — and
  writes the day to the books without leaving it. `#btn-next` is a `.btn-ghost`
  beside it and writes nothing at all; it asks `POST /api/next` whether the day
  on screen is in the books exactly as shown, and moves the form on only if the
  server says so. Neither label is built in `app.js`; both are in the markup.
- **`#dock-msg` is the last child of `#dock`**, under the four buttons
  (2026-09-15, later). It carries what `POST /api/next` answered — the server's
  refusal, or "Today is saved. There is no next day to enter yet." — because
  the banner is at the top of the page and off screen from the buttons. Text
  goes in through `textContent`; the element is in the page flow and floats
  over nothing. It holds no other message: a refused **Save**, a request for a
  reason and the standing banners are all unchanged and still in `#banner-area`.
  The one exception is the save confirmation "<date> saved to the books.",
  which goes here only where the Checks panel cannot say it: below 1100 px,
  where `#checks` is hidden, or when the save brought `warnings`.
  **(2026-10-07)** An Off day is no longer one of those cases: `#checks-saved`
  confirms its save on a wide window.
- The four buttons wrap rather than shrink. Below 720 px `.dock-actions` is
  `display: contents`, so they wrap inside `.dock-main` with `#btn-save` and
  `#btn-next` stretching to fill the row they land on; at 390 px the row wraps
  without any horizontal scrolling.
- **The grey notes and the link in the Checks panel are not checks**
  **(2026-10-07)**. None of them is a row, and none is counted in
  `#checks-count`, the pill or `#checks-live`. `renderDayFacts` sets them from
  the last check's `hasDailyLedger` and `inBooks`:
  - `#checks-regen`: a Work day that has a ledger file.
  - `#checks-saved`: a saved day with no ledger file (`inBooks` and not
    `hasDailyLedger`), whatever the kind of day: a Work day whose ledger waits
    on the day before, or an Off day. On an Off day `#checks-saved-more` (the
    second sentence) is hidden, so the note reads "This day has been saved."
  - `#checks-load` ("Show saved figures"): only while the date is `inBooks` and
    `state.clearedDate` is the date on screen, that is after **Clear** on a
    saved day. `resetForm` and a successful save set `clearedDate` back to
    null, so another date, a Next day that moves on, pressing the link and a
    save hide it; typing does not. Pressing it (`onLoadSaved`) asks
    `GET /api/day`, drops the answer if the date, `formSeq` or the form
    changed meanwhile, puts the day in (`showSaved`), scrolls to the top and
    puts the cursor in the opening balance on a Work day. Two quick presses
    ask once (`loadingSaved`).
  - `#checks-load-msg`: the one sentence for a date that could not be looked up
    (`openDate`: "Could not look up <d Month yyyy>. <sentence>") or a press of
    the link that failed (the server's sentence, or "<d Month yyyy> is not in
    the books."). It sits right under the link, never in the banner, and goes
    on a date change, a reset (Clear included), a good load and a successful
    save. With the link hidden, `.checks-load[hidden] + .checks-load-msg` gives
    it the notes' own spacing.
- **Keyboard shortcuts** (`SHORTCUTS` and `onShortcut` in `app.js`), matched on
  `e.code` with AltGr ignored, and `preventDefault` always: Ctrl+S `#btn-save`,
  Ctrl+N `#btn-next`, Ctrl+Alt+C `#btn-clear` and **(2026-10-07)** Ctrl+Alt+Z
  `#checks-load`. The target is focused and then clicked, as a mouse would. A
  disabled button does nothing, except that Ctrl+S on a grey Save runs
  `pressGreySave`; a hidden link does nothing, and below 1100 px the key still
  reaches the link inside the closed Checks sheet. Each button, and the link,
  has a `title` naming its keys and `aria-keyshortcuts`.
- `#chk-closed` is visually hidden but focusable; the label beside it is what
  people see and click. Only `.opt-trading` is `aria-hidden`, which makes the
  checkbox's accessible name "Off day" — a double negative when it is
  unchecked. Still open (review §3.3 #5): give `#chk-closed` an `aria-label`.
- The cash-book group the server sends (`title` "Cash Book — counted, not
  calculated", with a hint) is **dead**: `buildGroups` drops a group whose
  fields all went into the balance slots. Either the server stops sending it or
  the owner asks for a one-line counting instruction back (review §3.3 #5).

---

## 2. Markup `app.js` builds

### Category sub-card — one per `/api/config` group, inside `#groups-activity`

```html
<section class="subcard" data-group="cash">
  <h3>Cash &amp; Card Takings</h3>                      <!-- group.title -->
  <p class="hint">(Money taken in over the counter…)</p><!-- group.hint, if any -->
  <div class="grid"> …fields… </div>
</section>
```

### Field

```html
<div class="field" data-key="cash_sales">             <!-- the two balances: class="field counted" -->
  <label for="in-cash_sales">Cash Sales</label>
  <div class="money">
    <span class="sym">$</span>
    <input type="text" id="in-cash_sales" data-key="cash_sales" data-label="Cash Sales"
           inputmode="decimal" autocomplete="off" placeholder="0.00">
  </div>
  <div class="err" id="err-cash_sales"></div>         <!-- .show while it has a message -->
</div>
```

- The opening-balance field goes in `#slot-opening`, the closing-balance field
  in `#slot-closing`; both keys come from `/api/config`. They get `.counted`
  and **no placeholder**: blank there means "not counted", and a grey `0.00`
  would read as a zero somebody had entered.
- `input.invalid` — the browser's own validation failed. `input.filled` — the
  box has a value.
- **What a box accepts** (review §3.2 #8): `$`, spaces (including non-breaking
  ones) and commas are stripped before anything is validated, sent or tidied,
  so `1,500`, `1 500` and `$1500` are all accepted. A leading `-` survives the
  strip so "Amounts cannot be negative." is still the message for it. On blur a
  valid box is rewritten as `1500.00`.
- **Warning outline:** `app.js` sets `data-level="1|2|3|4"` on the `.field` to
  the most serious level of any *shown* warning about that key, and removes the
  attribute when there is none.

### Checks row — in `#checks-list`

```html
<li class="check lv2 selected" data-code="L2-A" data-field="closing_balance">
  <button type="button" class="check-btn">
    <span class="check-icon" aria-hidden="true"></span>
    <span class="check-body">
      <span class="check-title">Day doesn't balance</span>
      <span class="check-meta">Needs a reason · Closing Balance</span>
    </span>
  </button>
  <button type="button" class="check-more" aria-label="See full explanation: Day doesn't balance">See full explanation</button>
</li>
```

- **Level words:** 1 "Must fix", 2 "Needs a reason", 3 "Good to know", 4 "Tip".
  A finding with no `title` falls back to its level word, never to the server's
  own name for the level.
- **`.check-meta`** is the level word, plus ` · ` and the box's label from
  `config.labels[field]` when the title does not already name that box. A
  `field` that is not a journal key (`"date"`) has no label, so the meta is the
  level word alone.
- **`.check-more`** is a sibling of `.check-btn`, because a button cannot hold
  another. It opens the whole message in `#dock-note` and moves the cursor there.
- Clicking `.check-btn` goes to the box the warning is about: `field === "date"`
  goes to `#sel-day`, another field to `#in-<field>`, and a warning with no box
  (or a box hidden on an Off day) opens its explanation instead.
- Rows are **updated in place**, keyed by `code|field|n`, never rebuilt, so a
  row cannot move out from under a click or lose keyboard focus.
- There are no to-do rows and no `.check-code` element any more. A warning
  about a balance nobody has reached is simply left out of the list until the
  box has been left or Save pressed (`isTodo`). **(2026-10-06)** It greys Save
  out while it is held back, and the press that reveals it is a press on the
  grey button, which sends nothing.

### Explanation row in the dock

```html
<div id="dock-note" class="dock-note lv2" tabindex="-1">
  <span class="note-icon" aria-hidden="true"></span>
  <p class="note-text">…the finding's whole message…</p>
  <button type="button" class="note-close" aria-label="Close this explanation">×</button>
</div>
```

It never opens by itself. It opens from "See full explanation", from clicking a
row that has no box, and when a press of Save runs into a Must-fix — so the
reason sits beside the button that was just pressed. **(2026-10-06)** At every
settled moment a Must-fix keeps Save greyed out, and a press on the grey button
opens the explanation the same way, without sending anything. `×` and
**Escape** close it and put the cursor back where it came from.

### Count, empty state and live region

- `#checks-count`: the number of shown rows, class `checks-count lvW` for the
  worst level present, `hidden` at zero.
- `#checks-empty`: hidden whenever there is at least one row.
- `#checks-live`: one short sentence, rewritten only when the **set of codes**
  changes, not on every keystroke, and reset whenever the form is reset or the
  date changes.

### Dock status pill (narrow screens)

```html
<button id="dock-status" class="dock-status lv2" type="button" aria-controls="checks" aria-expanded="true">2 checks</button>
```

`hidden` at zero rows. Clicking it toggles `#checks.open` and scrolls the panel
into view, because the panel opens **below** the dock. Escape closes it.

### Banner

```html
<div class="banner info|warn|error"><span>text</span>[<button class="btn-ghost mini">Edit that day</button>]</div>
```

There are two kinds of message and `app.js` keeps them apart (review §3.2 #6):

- a **standing** one, true until the date or the books change: "Editing 9
  September 2026. Saving will replace it.", "9 September 2026 is already saved.
  Saving again will replace it." + **Edit that day**, or what the last save did;
- a **transient** one, true only while its cause lasts: "Add a short reason
  before saving this day.", "Tick the first-day box before saving this day.",
  "Fix what is marked in red before saving this day.", "Could not check this
  day just now. Try Save again.", and a refusal of **Save**. A refusal of
  **Next day** is not a banner at all: it goes under the buttons, in
  `#dock-msg` (§4).

Each transient message is stored with the condition that keeps it true and is
dropped as soon as that condition fails, which puts the standing message back.
The banner is redrawn only when what it should say changes.

---

## 3. What `app.js` sets on the page

| Name | Meaning |
|---|---|
| `#view-entry.is-closed` | the day is marked Off; CSS hides `.hide-when-closed` inside it |
| `#checks.open` | the narrow-screen Checks panel is open, below the dock |
| `.field[data-level]` | worst shown level for that box |
| `li.check.lvN`, `li.selected` | a row's level; the row whose explanation is open |
| `li[data-code]`, `li[data-field]` | the finding's code (never displayed) and field |
| `#dock-note.lvN` | the level of the open explanation |
| `#dock-msg.warn`, `#dock-msg.info` | what Next day answered, under the buttons: the server's refusal (`warn`) or "no next day yet" (`info`); also a save's confirmation (`info`) where the Checks panel cannot say it (§1 notes). Hidden when empty |
| `#checks-regen[hidden]`, `#checks-saved[hidden]`, `#checks-load[hidden]` | **(2026-10-07)** which grey note, if any, and whether "Show saved figures" shows (§1 notes) |
| `#checks-load-msg` | the sentence about a failed look-up or load, with `state.loadMsgDate` the date it is about. Hidden when empty |
| `#prior-hint.off`, `#predicted.off` | the hint is something to note, rather than plain information |
| `input.invalid`, `input.filled` | the browser's own validation; the box has a value |
| `#btn-save[disabled]` | **(2026-10-06)** the day cannot be saved as it stands: the server's latest check holds a Must-fix or a difference whose own reason is blank (shown row or not), no check has answered yet for this form, an empty reason box, an unticked first-day box, a bad date, or a red box. Not greyed while a save is in flight; a second press then is dropped (`saving`) |
| `#btn-next[disabled]` | there is no usable date to ask about, or a save or a move is in flight. **Never** because the day looks unsaved: that is the server's answer, not the page's guess |

**Timing rules `app.js` owns** (nothing here decides a severity):

- A Must-fix about a balance that is still blank, and a difference in a balance,
  are held back until that box has been left once or Save has been pressed.
  **(2026-10-06)** Held back from the panel only: Save is grey meanwhile, and
  the press that reveals them is a press on the grey button. So
  is the whole `#predicted` line — including the positive case, as of the
  owner's decision 5 of 2026-09-15: the figure the day's arithmetic expects is
  not put in front of somebody who is on their way to count the cash.
- **Changing the date starts the form again** (2026-10-06, the owner's
  reversal of decision 7, which kept the figures). `onDateChange` does nothing
  when the date is unchanged (`dateShown`); otherwise it calls `openDate`,
  whose `resetForm` drops the figures, both reasons, the switch, the first-day
  tick, `touched`, `saveTried`, `checkedFor`, `selected`, the banner, the
  announced codes, an open explanation, `#dock-msg` and `#checks-load-msg`.
  **(2026-10-07)** Then a saved date comes up as saved (`showSaved`). A Work
  day's two balance keys count as visited, because its counts were entered
  when it was saved, so its warnings show at once. An Off day's boxes stay
  blank (README rules 3 and 4), and a cursor left in a money box is taken out
  as the page's doing, so that box is not counted as left blank. A date not in
  the books stays blank, and the check runs on it once the look-up has
  answered. `checkedFor` is `[date, amounts]`, so one date's answer can never
  be reused for another.
- **(2026-10-07) Nothing done during a look-up is overwritten.** `resetForm`
  bumps `formSeq`. `openDate` and `onLoadSaved` put a saved day in only if
  `formSeq`, the date and `formSig()` are what they were when they asked; so
  a figure typed, the switch moved, Clear, Next day or another date picked
  meanwhile wins. `saveDay` sends nothing, and says nothing, if `formSeq`
  moved during its pre-save check.
- A tick box is consent for one save of one date. Both are cleared whenever the
  form is reset or another date is picked, and a tick is sent only while its box
  is showing.
- `#dock-msg` is about one date too. `app.js` remembers it as
  `state.dockMsgDate` and takes the message down when the form is reset, when
  another date is picked, and when a save succeeds. Typing a figure does **not**
  take it down: "has not been saved yet" stays true until the day is saved.
- **(2026-10-07)** `Clear` (`onClear`) never asks. It starts the form again,
  blank, on the same date, and then sets `state.clearedDate` to that date, so
  on a saved date "Show saved figures" shows as soon as the last check for
  that date, or the one Clear runs, says `inBooks`.
  Clear does not look the date up: after Clear a saved day stays blank until
  the link (or Ctrl+Alt+Z) is pressed.

---

## 4. The server interface

All JSON. The browser never decides severity; every finding is
`{code, level, levelName, title, field|null, message}`.

| Endpoint | The form uses |
|---|---|
| `GET /api/config` | `today`, `groups[].{id,title,hint,categories[].{key,label}}`, `openingKey`, `closingKey`, `depositKey`, `labels`. Also asked for again on `focus`/`visibilitychange`, so a window left open overnight picks up the new date. |
| `GET /api/prior?date=` | `genesis`, `hasPrior`, `priorDate`, `expected` — shown under the opening balance, **never** pre-filled. Hidden entirely when `genesis`, because the tick box and the Checks row already say it (review §3.4 #5). |
| `GET /api/day?date=` | `day` = `{date, amounts, status, reason, openingReason}` or `null`. **(2026-10-07)** Asked by `openDate` every time the form lands on a date, and by "Show saved figures" after Clear. An Off day's stored amounts are never put in the boxes. |
| `POST /api/check` | `findings`, `today`, `predicted`, `available`, `paidOut`, `genesis`, `hasDailyLedger`, `inBooks`. (`needsReason` and `blocked` are sent and not used: the form reads the findings, and since 2026-10-06 greys Save from them.) Writes nothing. |
| `POST /api/save` | the only writer — see below. Sent by **Save**, which stays on the day afterwards. |
| `POST /api/next` | asked by **Next day**. Writes nothing — see below. |

**`POST /api/save` — 200 body** (implementation §3.3), and what the form does
with each field:

| Field | The form |
|---|---|
| `date`, `closed` | `date` is the day the banner names |
| `journal` `"added"`/`"replaced"` | not used |
| `dailyLedger` | decides the words after the save, never the log text: `"skipped"` → "The file for this day was left as it was."; `"removed"` → "The file made when this was a work day was removed."; `"held"` → "The day before this one hasn't been entered yet; its paperwork finishes as soon as that day is entered."; anything else adds nothing |
| `released` | "The file for 10 September 2026 was finished too." (several dates joined with "and") |
| `held` | "10 September 2026 still needs a reason: open it and save it again.", with **Edit that day** for the first one |
| `nextDayStale` | "Now open 10 September and save it again.", with **Edit that day** |
| `notified` | ignored on purpose (decision 3: the form stays silent about email) |
| `warnings` | joined into one string and added after "<date> saved to the books." in `#dock-msg`; a save that brings any is confirmed there even where the Checks panel would say it |

**Saving a day** (2026-09-15; the confirmation as it stands **(2026-10-07)**):
Save posts the payload and **stays on the date**, with the figures still in the
boxes. `app.js` then runs `/api/check` again straight away, because the books
have changed under it. Nothing appears at the top of the page. The Checks
panel is the confirmation: the row "Day saved, ledger generated" and
`#checks-regen` for a Work day with a ledger, or `#checks-saved` for any other
saved day (a Work day whose ledger waits, an Off day). `"<date> saved to the
books."` goes in `#dock-msg` only below 1100 px, where the panel is hidden, or
when the save brought `warnings`. A successful save also takes down "Show saved
figures" and `#checks-load-msg`. Nothing is cleared and nothing moves; only
**Next day** moves the form.

**Refusals** are 400 with `ok:false` and:

- `findings` containing a Must-fix → banner "This day cannot be saved yet.", and
  the first Must-fix message opens in the dock. **(2026-10-06)** The same
  answer is given, without a request, when the pre-save check finds a Must-fix
  that the button had not yet heard about, and when the grey button is pressed.
  The banner goes as soon as a check finds no Must-fix, and when the day is
  switched to an Off day;
- `findings` + `needsReason` → the server's sentence in the banner and the
  cursor in the first empty reason box;
- `needsGenesis` → the first-day tick box is shown and asked for.

**`POST /api/next` — Next day** (2026-09-15). The same body as `/api/save`
(`{date, status:"closed"}` for an Off day, otherwise `{date, amounts, reason,
openingReason}`; the two tick boxes are not sent, because nothing is written).
One answer shape either way:

```json
{ "ok": true, "saved": true, "changed": false, "date": "2026-05-01", "next": "2026-05-02", "error": null }
```

| Field | The form |
|---|---|
| `next` | the date to move to. **(2026-10-07)** `openDate(next, {cursor: true})`: the form goes blank at once, the page scrolls to the top, the cursor goes in the opening balance (as `pageFocused`, so leaving it does not count as a blank count), and then the day comes up as saved if it is in the books |
| `next: null` | the day on screen is today, so there is nowhere to go: `#dock-msg` **info** `"Today is saved. There is no next day to enter yet."`, and the form stays |
| `saved`, `changed`, `date` | not used: the server's `error` sentence is what the person reads |

Both answers appear in **`#dock-msg`**, under the buttons, rather than in the
banner at the top of the page (2026-09-15, later): the person who pressed Next
day is at the bottom of the form, where the top of the page is off screen.

**Refusals are 409**, and the form shows the server's sentence, word for word,
as a **warn** message in `#dock-msg` and stays on the day. No extra button is
offered and nothing is pressed for the person:

- never saved (`saved:false`) → "14 September 2026 has not been saved yet. Save
  it before moving on.";
- saved, but a figure or a reason on screen differs (`changed:true`) → "The
  figures on screen for 14 September 2026 have not been saved. Save them before
  moving on."

A date in the future is a 400, as it is for `/api/save`; `#btn-next` is disabled
while `dateProblem()` is non-empty, so the form does not ask.

**Known fault (2026-10-07, not fixed when this was written).** `onNextDay`
lets go of its answer only when the date has changed, not when the form was
started again (`formSeq`, as `saveDay` does). A Next day pressed while a saved
day is still being looked up sends the blank form and is refused; if the saved
day comes up first, that refusal ("The figures on screen for <date> have not
been saved. Save them before moving on.") is left in `#dock-msg` beside the
saved figures. It takes a second press within the moment the look-up takes.
`verify-saved-day-loads-2026-10-07.mjs` part H fails on it, once at each width.

**The Off-day Stop** (implementation §3.7): `L1-F`/`L1-G` arrive with
`field: "date"`, so the row points at the date selects. While any Must-fix row
is showing, Save **skips** the Off-day confirmation dialog and the first-day
tick prompt, and lets the server's refusal be the answer; asking a question that
cannot change the outcome would be one detour before the real message.

---

## 5. Styling rules both sides rely on

- `[hidden] { display: none !important; }` — author `display` rules would
  otherwise beat the attribute. `app.js` toggles visibility with `hidden`.
- `.sr-only`, `#view-entry.is-closed .hide-when-closed { display: none; }`,
  `.closed-note:empty { display: none; }`.
- `:root { color-scheme: light; }` — the page has one light palette, and without
  this a machine in dark mode draws the selects, tick boxes and scrollbars in
  dark UA colours on the cream cards.
- **Nothing floats over the form.** The dock, the banners and the watermark are
  all in the page flow; the only `position: fixed` element is the decorative
  `body::before` wash, which is `pointer-events: none`. The Checks column is
  `position: sticky` inside its own column, which covers nothing.
- **Breakpoint 1100 px.** At or above: two columns, the form plus a 300 px
  Checks column, `#checks` sticky with its own `overflow`, `#dock-status`
  `display:none`. Below: one column, `#checks` hidden until `.open`, then shown
  as the next block after the dock; `#dock-status` shows.
- **Level colours** — text and icon on a tint, each shape different so the four
  levels are told apart without colour:

  | Class | Colour | Tint | Icon |
  |---|---|---|---|
  | `.lv1` | `--danger` | `--danger-bg` | stop octagon |
  | `.lv2` | `--warn` | `--warn-bg` | warning triangle |
  | `.lv3` | `--accent` | `--band` | info circle |
  | `.lv4` | `--ink-soft` | `--line-soft` | lightbulb |

- **Palette:** the thirteen colours at the top of `:root` are fixed; everything
  else in `styles.css` is a darker or translucent version of one of them, plus
  the warm counted-figure tint. System colours are used in one place only, the
  `forced-colors` block, where the Work day / Off day toggle is drawn with
  `Highlight`/`HighlightText` so the two halves can still be told apart.
- **Focus:** `:focus-visible` everywhere, plus `#dock-note:focus`, because that
  row is given the cursor by `app.js` rather than by the person and so never
  matches `:focus-visible`.
- **Motion:** short transitions only, all switched off by
  `prefers-reduced-motion: reduce`. The six `scrollIntoView` calls in `app.js`
  read the same preference through the `SMOOTH()` helper, which CSS cannot
  reach.

---

## 6. Verification

`handoff/verify-ui-2026-09-15b.mjs` walks the end-user scenarios of review §5.2
at 1440 px and 390 px against a server on 8798 with an empty scratch
`LEDGER_ROOT`, and asserts the words in §5.1 as updated by the implementation
document. Its header says how to run it. Flows that need stream B's new save
fields (`nextDayStale`, `held`, `"removed"`) are marked `INTEGRATION` and are
skipped unless it is run with `--integration`. It describes the form before
2026-09-29.

**(2026-10-07)** The scripts that match the form as it stands are
[`verify-save-next.mjs`](verify-save-next.mjs),
[`verify-ui-2026-09-29.mjs`](verify-ui-2026-09-29.mjs),
[`verify-date-change-2026-10-06.mjs`](verify-date-change-2026-10-06.mjs),
[`verify-save-gate-2026-10-06.mjs`](verify-save-gate-2026-10-06.mjs) and
[`verify-saved-day-loads-2026-10-07.mjs`](verify-saved-day-loads-2026-10-07.mjs).
`tests/TESTING.md` says what each covers and gives its count.
