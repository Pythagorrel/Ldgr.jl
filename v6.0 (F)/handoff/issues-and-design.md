# Issues found, and the agreed design

**How the issues were found:**
1. Read all of `public/`, plus `server.jl`, `Checks.jl`, `DayInput.jl`, `Chain.jl`, `Staging.jl`, `Journal.jl` and `main.jl`.
2. Ran `server.jl` on a scratch `LEDGER_ROOT`.
3. Drove the **current** UI (commit `1533dae`) in Chrome with Playwright, at 1440×900 with the browser set to UTC+7.

The screenshots from that run no longer exist, so what they showed is described in words below.

---

## 1. Issues

### 1A. Wiring bugs

#### W1 — The very first save can never succeed from the form

This bug is older than the Gemini commit.

**Problem.** `index.html` has a "first day on record" checkbox (`#genesis-line`, `#chk-genesis`), but `app.js` never un-hides it. So:
- `commit()` always sends `allowGenesis: false`;
- `process_day` in `main.jl` refuses a first-ever day without that flag.

**Seen in the browser.** With a fresh records folder, the checkbox stays hidden on Review and committing fails.

**Fix.**
- `handle_staged` in `server.jl` returns `genesis = Chain.is_genesis_date(rec.date)` for each staged day, next to `inJournal` and `hasDailyLedger`.
- `renderReview()` shows `#genesis-line` whenever any staged day has `genesis: true`.

#### W2 — A failed commit only says "The server refused that."

**Problem.**
- When any day fails, `POST /api/commit` replies with HTTP 200 and `{ok:false, results:[…], failures:n}`. That reply has no `error` field.
- `api()` throws on any `ok:false`, with the message `data.error || "The server refused that."`.
- As a result, the "Saved with problems" branch of `showDone()` — the part that lists what went wrong for each day — can never be reached.

**Seen in the browser.** After the W1 failure, that generic message was the only feedback.

**Fix.**
- Give `api()` an `allowFailure` option: when the HTTP status is 2xx, return the body even if it says `ok:false`.
- `commit()` uses that option, so `showDone()` lists each day's failure.

#### W3 — "Save & next day" does not move forward in timezones east of UTC

This bug is older than the Gemini commit.

**Problem.** `nextDate()` does four things in turn:
1. Builds the date with `new Date(iso+"T00:00:00")`, which is local midnight.
2. Adds one day.
3. Converts it with `.toISOString()`, which is UTC.
4. Cuts that string to its first 10 characters.

In UTC+7, local midnight is still the previous day in UTC, so the result is the date you started from. The form stays on the same date and then warns that the day was "already entered in this session".

**Seen in the browser.** At UTC+7, saving the 10th left the form on the 10th.

**Fix.**
- Build the next date from the local `getFullYear()`, `getMonth()` and `getDate()`.
- Still never go past `state.today`.

#### W4 — Reasons and statuses leak between days, and a counted zero is lost

**Problem.** Three separate faults:
- **Reason never cleared.** Save & next day, Clear, Cancel edit and Enter more days leave `#txt-reason` as it was. It is only cleared if a later check happens to find no difference.
- **Edit loses the reason and the Closed status.** `startEdit()` restores neither of these from the staged day, so a closed day reopens as a trading day.
- **Counted zero becomes blank.** `writeAmounts()` shows `0` as an empty box. For the two drawer counts, blank means "not counted", so re-saving a day whose drawer really held $0.00 now gives an L1-C Stop.

**Example.** Save a day with the reason "X". Go to Review, open another staged day whose reason is "Y", and save it. It is re-staged with "X".

**Fix.** Add one `resetForm(day?)` and use it on every path that loads or clears the form. It:
- sets or clears the figures, the reason and the Closed toggle together;
- shows a counted `0` as `0.00`, and only a missing value (`null`) as blank.

#### W5 — Warnings and hints go stale

**Problem.**
- **Nothing is re-checked.** `boot()`, `onNextDay()` and `startEdit()` never call `loadPrior()` or `scheduleCheck()`. The "previous day closed at…" hint is missing at startup, and the warnings on screen belong to the previous figures.
- **Warnings follow you to Review.** The fixed rail and the red sticky bar sit outside `#view-entry`, so they stay on screen over the Review page.

**Seen in the browser.** Two "L1-C STOP" cards and "2 issues must be fixed before saving" sat on top of the Review table.

**Fix.**
- `resetForm()` re-runs `loadPrior()` and the check.
- All warning UI lives inside `#view-entry`.

#### W6 — A day can be saved to the notepad without its reason

**Problem.**
- The check runs 350 ms after typing stops.
- Clicking Save right after typing the closing balance can send the day before the reason box appears.
- `handle_stage` only refuses Stops. The day is staged anyway and then fails at commit ("no reason was given").

**Fix.**
- `saveDay()` cancels the delay and waits for a fresh check before deciding.
- `handle_stage` also refuses a day that needs a reason when the reason is blank, answering `400 {ok:false, error, findings, needsReason:true}` (the same shape as its Stop refusal).

#### W7 — Closed days are dropped or not explained

**Problem.**
- **Dropped at Review.** `onReview()` only saves the day automatically when a figure is above 0, so a day marked Closed is silently not staged.
- **No explanation.** `runCheck()` returns early for closed days, so the server's closed-day notice never shows. That notice (L3-C) says "the next working day will open with $X, carried straight through".

**Fix.**
- In `onReview()`, count the Closed toggle as an entry.
- In `runCheck()`, POST `{date, status:"closed"}` and show what comes back.

### 1B. Regressions from the Gemini commit

- **Labels no longer escaped.** Category cards and fields are now built with `innerHTML` template strings, so group titles, hints and labels from `Config.jl` go into the page unescaped. They used to be set with `textContent`. A label containing `"` or `<` would break its field. Go back to `createElement` and `textContent`.
- **Styles deleted for classes `app.js` still uses.** On the Review page the "new" badge showed as bare text on a transparent background. Missing:
  - `.badge`, with `.new`, `.repl` and `.lock`
  - `.checkline`
  - `.result`, `.result.bad` and `.pathline` (Done screen)
  - `td.zero`, `tfoot td` and `td.act`
  - `.banner span { flex: 1 }`
- **Keyboard access lost.** The Trading/Closed checkbox has the `hidden` attribute, so it cannot be reached with the keyboard.
- **Invalid CSS.** `.opening-slot { border-top: 1fr dashed … }` — `1fr` is not a length, so the whole declaration is ignored.
- **Leftovers:**
  - an unused `isCashbook` variable
  - inline `style=` attributes in `index.html`
  - Google Fonts loaded with a CSS `@import`
- **Lost hint.** The server's Cash Book hint ("Count the drawer. Do not work these out from the figures above…") is no longer shown anywhere.
- **Wrong copy.** "Leave anything that did not happen blank — blank counts as zero" has been false for the two drawer counts since v4.0. For those, blank means "not counted".

### 1C. Layout and look (Hannah's notes)

- **The warnings rail covers the form.**
  - `.findings-rail` is `position: fixed; right: 24px; width: 300px`, over a centred 1080px column.
  - It only drops into the normal page flow below 1180px wide.
  - From 1180px up to about 1680px it covers the right side of the cards. At 1440px it sat on top of the Expenses and Banking inputs.
- **Two bottom bars collide.**
  - Mid-page, the sticky totals dock (`bottom: 20px`) sits on top of the fixed warnings bar (`bottom: 0`, about 49px tall).
  - No space is reserved under the page for either.
- **Warnings are hard to scan.** Each card shows the full paragraph plus jargon ("L2-A EXPLAIN"), and the four levels differ only by a thin left border.
- **It alarms too early.** The first figure typed triggers a check that shows a red Stop for the Closing Balance, before the person has even reached that field.
- **The accents are messy.**
  - The 4px coloured top border looks clipped on the rounded cards.
  - Stages 1 and 3 have badges; Stage 2 does not.
  - The colours (#107C41, #D13438, #4F6BED) are not in the palette.
  - The red Expenses bar competes with the red Stop warnings.
- **No branding.** There is no real header, just a centred title and stepper, and no SolRegia mark.

---

## 2. The design

### Principles

- **Order of the day.** One column of cards, in the order the day happens: 1 Morning count → 2 Today's figures → 3 Evening count.
- **One primary button.** Each screen has one solid green button; everything else stays quiet.
- **Only warnings are colourful.** They use plain words: "Must fix", "Needs a reason", "Good to know" and "Tip". The code stays in small grey text so it can still be traced to the Warnings Guide.
- **Same palette.** Translucent or darker versions of these colours are fine; new colours are not.

  | Token | Colour |
  |---|---|
  | `--ink` | #1C2521 |
  | `--ink-soft` | #5B6660 |
  | `--accent` | #1F6F5C |
  | `--accent-dk` | #175649 |
  | `--band` | #E8F3EE |
  | `--line` | #E3E0D8 |
  | `--line-soft` | #EFEDE7 |
  | `--page` | #FAF9F6 |
  | `--card` | #FFFFFF |
  | `--danger` | #A63D40 |
  | `--danger-bg` | #FBEDE9 |
  | `--warn` | #8A6212 |
  | `--warn-bg` | #FDF4E3 |

- **Fonts and tooling.** Inter for text, JetBrains Mono for figures, both with system-font fallbacks. No libraries and no build step.

### Layout at 1100px and wider

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ▣ Daily Entry                          ( 1 Enter days · 2 Review · 3 Saved ) │
│   Enter each day, check it, then save it to the books                       │
├───────────────────────────────────────────────┬──────────────────────────┤
│ ▬ 1  Morning count                             │ Checks                   │
│ Date [Sep ▾][14 ▾][2026 ▾]    (Trading | Closed)│ ▲ Day doesn't balance    │
│ Opening balance        $ [            ]        │   Needs a reason         │
│ ⓘ 13 Sep closed with $1,720.00 — count it      │ ◦ Matches one of your    │
│                                                │   figures · Tip          │
│ ▬ 2  Today's figures                           │                          │
│    Takings · Expenses · Banking  (sub-cards)   │ sticky in its own column │
│                                                │ — can never cover the    │
│ ▬ 3  Evening count                             │ form                     │
│ Closing balance        $ [            ]        │                          │
│ Reason (only when needed) [                  ] │                          │
└───────────────────────────────────────────────┴──────────────────────────┘
 ( ☼ Powered by SolRegia )   ╭───────────────────────────────────────────────╮
                             │ ▲ The drawer holds $100.00 less than …      ✕ │
                             │ Takings $500 · Expenses $100 · Banked $0      │
                             │      [Clear]  [Review & save]  [Save & next day] │
                             ╰───────────────────────────────────────────────╯
```

**Below 1100px:**
- The page becomes one column and the Checks panel is hidden.
- A status pill in the dock ("2 checks") opens the panel as a sheet just above the dock.

**Nothing ever sits behind the dock.** The page's bottom padding follows the dock's live height, through the CSS variable `--dock-h`, which `app.js` sets.

### The pieces

1. **Header**
   - Left: a small green logo tile, "Daily Entry", and one grey subtitle line ("Enter each day, check it, then save it to the books").
   - Right: the three-step stepper, drawn as a quiet pill.
   - A hairline divider underneath.

2. **Cards**
   - Solid white, 16px corner radius, hairline border.
   - Every card has the same 4px rounded green accent bar set inside its top edge, and a numbered stage chip tinted with `--band`.
   - "Today's figures" contains the three category sub-cards (Takings, Expenses, Banking). The sub-cards get no colours of their own.
   - The two drawer-count inputs keep a subtle "counted figure" look: the warm paper tint from the stylesheet before Gemini's changes (`background #fffdf5; border-color #d9c89a`).

3. **Checks panel**
   - **Position.** The right-hand column, with `position: sticky` inside its own grid column, so it can never overlap the form.
   - **Empty state.** "Nothing to fix so far".
   - **One row per warning from the server:**
     - a level icon;
     - the short title the server sends;
     - a meta line with the level word, plus " · field label" when the warning is about a particular field;
     - the code, in tiny grey text.
   - **Level styles.** Icon, word and colour all differ, because §8 of the Warnings Guide requires the four levels to look clearly different.

     | Level | Word | Colour | Icon |
     |---|---|---|---|
     | 1 | Must fix | `--danger` | stop octagon |
     | 2 | Needs a reason | `--warn` | warning triangle |
     | 3 | Good to know | `--accent` | info circle |
     | 4 | Tip | `--ink-soft` | lightbulb |

   - **Clicking a row** shows that warning's explanation in the dock, then scrolls to and focuses the field it is about. The server already sends `field`, but nothing uses it yet.
   - **To-do rows.** A Stop about a drawer count that is still blank shows as a grey row: "Still to count · Closing Balance", with a hollow circle icon. It turns into a normal red row once that box has been left blank (the input has lost focus) or Save has been pressed. Saving is refused either way.
   - **Field outline.** The input a warning is about gets a quiet outline in that level's colour (`.field[data-level]`).

4. **Floating dock**
   - A frosted-glass panel centred at the bottom of the screen, like the prototype's dock, about 880px wide at most.
   - **Main row:**
     - running totals: Takings, Expenses, Banked, Days saved;
     - actions: Clear; Cancel edit (only while editing); Review & save; and **Save & next day**, the one primary button.
   - **Explanation row**, above the main row:
     - It shows the full message of the most serious warning that is level 1 or 2, is not a to-do row, and has not been dismissed.
     - Level 3 and 4 warnings only appear here after their row in the Checks panel is clicked.
     - ✕ dismisses that warning's code until `resetForm()` runs. Changing figures does not bring it back, but a different warning still shows.
     - Level 2 warnings add a "Write a reason" button that scrolls to the reason box.
   - **The reason rule still holds.** Dismissing only hides the explanation: the row in the Checks panel stays, and Save stays disabled until a reason is typed.

5. **Glass banners**
   - Translucent white with `backdrop-filter: blur()`, a hairline border and a soft shadow.
   - Tinted by kind: info uses `--band`, warn uses `--warn-bg`, error uses `--danger-bg`.
   - A very faint green-and-cream wash on the page background (fixed radial gradients) makes the blur visible.
   - Glass is used only for banners, the dock, the Checks panel and the narrow-screen sheet. Form cards stay solid.

6. **Watermark**
   - A small outlined pill with a tiny sun mark: "Powered by **SolRegia**".
   - Low contrast, and not clickable.
   - When there is room beside the dock, it sits fixed at the bottom-left, level with the dock. Otherwise it becomes an ordinary footer line at the end of the page, above the space reserved for the dock.

7. **Review and Done screens**
   - Same header and card styling as the entry screen.
   - **Review table.** Sits inside a card, with badges: New, Replaces saved entry, Ledger file exists, and a new **Closed** badge.
   - **Checkbox rows.** "First day on record" (W1) and "Overwrite ledger files" appear as clear checkbox rows.
   - **Commit button.** It says "Save to the books".
   - **Done screen.** Lists each day; a day that failed shows the server's reason (W2).

### Uizze references

Only structural lessons were taken from these; no branding or layouts were copied.

| Reference | Lesson |
|---|---|
| Jeton — https://uizze.com/packs/1f32d914-6fdd-4692-b4fc-fcee2c414766 | A floating pill bar centred at the bottom, with small corner pills that never collide with it. Used for the dock and for where the watermark sits. |
| Inthememory — https://uizze.com/packs/8872694d-261d-4eb4-b355-fb39ee4c37ad | A rounded bar that can be closed: a tiny label, one line of text and ✕. Used for the dock's explanation row. |
| 10X HUB — https://uizze.com/packs/4acc13a0-c553-40d7-b78d-a9b6a4e94486 | An outlined "Built with…" badge in the corner. Used for the watermark's style. |
| N26 — https://uizze.com/packs/e9f07a27-bdd4-4f6a-8132-329d014aa5f4 | A deep teal primary colour used for one action only, and calm bordered info boxes. Confirms the existing green reads as modern when used sparingly. |
| Increase — https://uizze.com/packs/1ad4f49f-275a-4268-8ed1-677dc3c6e475 | Small status chips made of an icon plus a word, and a soft floating card with a hairline border. |
| Three — https://uizze.com/packs/57160546-4cf7-4d52-bb05-cd8b88e1fbf9 · Tally — https://uizze.com/packs/4e3aa524-b146-416c-907f-382c079ea80c | A minimal header (logo tile, name, one element on the right), plenty of white space, and one clear action. |

---

## 3. Backend changes (Agent A)

**`Checks.jl`**
- Add `finding_title(code) -> String`: a short, plain-language phrase for each Warnings Guide code, returning `""` for a code it doesn't know.
- `Finding`, `check_day`, and every existing message and level stay exactly as they are.

| Code | Title |
|---|---|
| L1-A | Negative amount |
| L1-B | More paid out than was in the drawer |
| L1-C | Drawer not counted |
| L1-D | Not a valid amount |
| L1-E | Date not allowed |
| L2-A | Day doesn't balance |
| L2-B | Opening doesn't match last close |
| L3-A | Ledger waiting on the day before |
| L3-B | Ledger already made for this day |
| L3-C | Marked as closed |
| L3-D | First day on record |
| L4-1 | Digits may be swapped |
| L4-2 | Matches one of your figures |
| L4-3 | Decimal point may be off |
| L4-4 | Card and cash may be mixed up |

**`server.jl`**
- `findings_json` adds `title` to each warning.
- `handle_staged` adds `genesis` to each staged day (W1).
- `handle_stage` refuses a day that needs a reason when the reason is blank (W6).

**New test: `tests/test_checks_titles.jl`**
- Checks that every code used in a `Finding("…"` call in `Checks.jl` has a non-empty title.
