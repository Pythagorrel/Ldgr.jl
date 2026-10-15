# Agent C — Front-end logic (`app.js`)

You are one of three sub-agents working **in parallel** on ldgr v4.0 (`E:\Ldgr\v4.0`). Your job is to fix the form's wiring bugs and drive the redesigned page.

At the same time:
- **Agent B** is rebuilding `index.html` and `styles.css` against the same contract.
- **Agent A** is changing the Julia backend.

The main session will integrate everything, run a real browser test and review it.

## Read first

1. `E:\Ldgr\CLAUDE.md` — especially the rules that must not be broken.
2. `E:\Ldgr\v4.0\handoff\issues-and-design.md` — all of §1 (W1–W7 and the regressions) and §2 (behaviour).
3. `E:\Ldgr\v4.0\handoff\ui-contract.md` — **your spec** for every ID, class and piece of generated markup.
4. The current `v4.0/public/app.js`, in full.
5. The request and response shapes in `v4.0/server.jl`: `handle_config`, `handle_staged`, `handle_stage`, `handle_prior`, `handle_check`, `handle_commit`.

**Agent A's server changes, and the fallbacks your code needs until they land:**

| Agent A adds | Your fallback if it's missing |
|---|---|
| `title` on every finding | `levelName` |
| `genesis` on every staged day | treat a finding with code `"L3-D"` as genesis |
| `400 {ok:false, error, findings, needsReason:true}` when a day that needs a reason is staged without one | none needed |

## You own (edit only this)

- `v4.0/public/app.js`

## Must not

- Edit `index.html`, `styles.css`, `prototype.html` or any Julia file.
- Decide a warning's severity. Show the server's `level`, `code`, `title` and `message` (Handover §4 rule 5). Turning a level into a plain word is presentation, and that is allowed.
- Hold category names. The form is built from `/api/config`.
- Pre-fill the opening or closing balance.
- Let a day with a level-2 warning be saved without a typed reason.
- Put server-provided text into the page with `innerHTML`. Use `createElement` and `textContent`.
- Add libraries or a build step.
- Commit.

## Keep, and adapt as needed

These existing functions stay: `api`, `banner`, `validateAmount`, `tidyAmount`, `currentDate`, `validateDate`, `formValid`, `updateButtons`, `fillDateSelects`, `fillDays`, `prettyDate`, `readAmounts`, `isCashBook`, `writeAmounts`, `refreshTotals`, `showPredicted`, `loadPrior`, `scheduleCheck`, `runCheck`, `saveDay`, `onNextDay`, `onReview`, `showReview`, `renderReview`, `startEdit`, `removeDay`, `backToEntry`, `commit`, `showDone`, `setStep`, `resumeBanner`, `loadStaged`, `applyClosedState`, `boot`.

Keep the file's explanatory comment style. Update any comment that no longer matches the code.

## State to add

```js
state.findings  = [];        // last findings from the server, so the list can re-render without a request
state.touched   = new Set(); // drawer-count keys the person has left (blur) at least once for this form
state.saveTried = false;     // Save & next day / Review & save pressed for this form
state.dismissed = new Set(); // finding codes hidden from the dock explanation row
state.selected  = null;      // code picked in the Checks panel, shown in the dock
state.notice    = null;      // banner to keep after a successful save: {kind, text, actionLabel, action}
```

## Tasks

### Wiring fixes

**W1 — first-day checkbox.**
- In `renderReview()`, show `#genesis-line` when any staged day has `genesis === true`. Before Agent A's change lands, fall back to: any finding with code `"L3-D"`. Otherwise hide it.
- Also add a `badge closed` ("closed") for `status === "closed"`.

**W2 — commit problems.**
- Change the signature to `api(path, opts = {}, { allowFailure = false } = {})`.
- When `allowFailure` is set and the HTTP status is 2xx, return the body even if `ok === false`.
- On any thrown error, attach the parsed body as `err.data` so callers can read `findings`.
- `commit()` uses `allowFailure: true`. The button shows "Saving…", then exactly "Save to the books".

**W3 — next date.** `nextDate(iso)` builds the next day from the local year, month and day (no `toISOString`) and never goes past `state.today`.

**W4 and W5 — `resetForm(day = null, { date } = {})`.** One function for every load or clear of the form.
- **If `day` is given** (a staged day):
  - date = `day.date`;
  - amounts = `day.amounts` — drawer counts show `""` for `null`/`undefined` and `Number(v).toFixed(2)` for any number, **including 0**; other keys show `""` for 0 as today;
  - `#txt-reason` = `day.reason || ""`;
  - `#chk-closed` = `day.status === "closed"`.
- **Otherwise:** date = the `date` option, or today; blank figures; empty reason; not closed.
- **Always, in this order:**
  1. Clear `touched`, `saveTried`, `dismissed` and `selected`.
  2. Remove `#checks.open`.
  3. `applyClosedState()`, without scheduling a check.
  4. `validateDate()`, `refreshTotals()`, `updateButtons()`.
  5. `loadPrior()`.
  6. Run the check **now** (cancel any pending timer).
- **Called from:**
  - `boot()` — after building the fields and loading staged days.
  - `onNextDay()` — after a successful save, with `{date: nextDate(from)}`.
  - Clear — `{date: currentDate()}`, which keeps the chosen date.
  - Cancel edit — today.
  - `startEdit(iso)` — with that staged day.
  - Enter more days (`#btn-restart`).

**W6 — save race.**
1. `saveDay()` cancels the timer, sets `state.saveTried = true` and `await runCheck()`.
2. If the reason box is showing and empty:
   - show the level-2 warning in the dock;
   - focus `#txt-reason`;
   - `banner("banner-area","warn","Add a short reason before saving this day.")`;
   - return `false` without posting.
3. If the server refuses with a 400, show its `error` in an error banner and render `err.data.findings` when present.

**W7 — closed days.**
- When `#chk-closed` is checked, `runCheck()` POSTs `{date, status:"closed"}` and renders what comes back (the server adds the L3-C closed-day notice), with `#predicted` hidden.
- In `onReview()`, a day marked Closed counts as an entry. Stage it through `saveDay()`, which keeps today's confirmation dialog.

**Banners.**
- After a successful save, set `state.notice` to the "<date> saved. N days ready to save. [Review them]" banner.
- `resumeBanner()` shows, in priority order:
  1. the duplicate-date warning from `validateDate()`;
  2. `state.notice`;
  3. the waiting-days message — at boot "N day(s) from an earlier session … waiting", later "N day(s) waiting to be saved to the books".
- Clear `state.notice` when returning from Review or after a commit.

### Rendering to the contract

**`buildGroups()`**
- Build every field with `createElement` and `textContent`, exactly as in contract §2 "Field".
- The opening and closing balance fields (from `config.openingKey` and `config.closingKey`) go into `#slot-opening` and `#slot-closing`, with class `field counted`.
- Every other group becomes a `section.subcard` in `#groups-activity`. Skip a group that ends up with no fields.
- If the config has a group containing the closing key and it has a `hint`, set `#evening-hint`'s text to that hint. This restores the server's "counted, not calculated" guidance.
- Keep the existing listeners:
  - `input`: validate, refresh totals, schedule a check.
  - `blur`: tidy the value, refresh totals, schedule a check.
- For the two drawer counts, also on `blur`: add the key to `state.touched` and re-render from `state.findings` straight away.

**`renderChecks(findings)`** (replaces `renderFindings`)
- Store the list in `state.findings`.
- **Classify each finding.** It is a *to-do* when all of these hold:
  - `level === 1`;
  - `field` is one of the two drawer-count keys;
  - that input's value is empty;
  - the key is not in `state.touched`;
  - `!state.saveTried`.
- **Rows.** Real rows first, in server order, then to-do rows, as in contract §2.
  - Title: `f.title || f.levelName`.
  - Meta: the level word ("Must fix", "Needs a reason", "Good to know", "Tip"), plus `" · " + config.labels[f.field]` when that label exists.
  - To-do rows: title "Still to count", meta = the field label, empty code.
- **Summary elements:**
  - `#checks-count` — the number of non-to-do rows, class `checks-count lvW` for the worst level present, hidden when 0.
  - `#checks-empty` — hidden whenever there are rows.
  - `#checks-live` — update only when the sorted set of codes changes (for example "2 checks: Day doesn't balance; Matches one of your figures").
  - `#dock-status` — text "1 check" / "N checks", class `dock-status lvW`, hidden when there are no non-to-do rows.
- **Field outlines.** For each field key, set `.field[data-level]` to the most serious non-to-do level of findings on that key; remove it otherwise.
- **Dock explanation row `#dock-note`**, in priority order:
  1. If `state.selected` is still present as a non-to-do finding, show that one (any level).
  2. Otherwise show the most serious non-to-do finding with `level <= 2` whose code is not in `state.dismissed`.
  3. Otherwise hide it.

  Contents:
  - class `dock-note lvN`, and `.note-text` = `f.message`;
  - add `.note-action` "Write a reason" when the level is 2 and `#txt-reason` is empty — it scrolls to and focuses `#txt-reason`;
  - `.note-close` adds the code to `state.dismissed`, clears `state.selected` if it matches, and re-renders.
- **Row click.**
  1. `state.selected = code` and remove it from `dismissed`, then re-render.
  2. Scroll the target into view with `scrollIntoView({block:"center", behavior:"smooth"})` and focus it with `focus({preventScroll:true})`. Targets:
     - the field `#in-<field>`;
     - `"date"` → `#sel-day`;
     - no field and level 2 → `#txt-reason`;
     - otherwise nothing.
  3. Close `#checks.open`.
- **Reason box.** It shows when any level-2 finding is present. Otherwise it is hidden and its value cleared, as today. While closed, it is always hidden.

**Narrow-screen sheet**
- `#dock-status` click toggles `#checks.open` and updates `aria-expanded`.
- Escape closes it.

**Dock height**
- A `ResizeObserver` on `#dock` sets `document.documentElement.style.setProperty("--dock-h", dock.offsetHeight + "px")`.
- Also recompute whenever the view changes (the dock is inside `#view-entry`, so it measures 0 on Review and Done).

**Views**
- A small `setView("entry"|"review"|"done")` helper may replace the repeated `.hidden` toggling. It calls `setStep` and updates `--dock-h`.

**Closed state**
- `applyClosedState()` toggles `.is-closed` on `#view-entry` instead of setting inline `style.display`.
- It sets `#closed-note` text: "No ledger will be generated. The next working day carries this balance through." — or empty when not closed.
- It hides `#reason-box` and `#predicted` while closed.

**Clean-up**
- Remove every reference to `findings-rail`, `findings-sticky`, `slot-closing-container` and the old `renderFindings`.

## Check your work

- `node --check E:/Ldgr/v4.0/public/app.js`.
- Read your code against each flow in `verification.md` §4, and against W1–W7.
- Optional smoke test:
  - Run your own server on port **8798** (never 8765) from a scratch copy of `v4.0`, with `LEDGER_ROOT` in your scratch folder: `julia --startup-file=no server.jl 8798`.
  - `index.html` may be half-edited by Agent B, so treat any visual result as unreliable. Only confirm there are no console errors on load and the requests look right.
  - Stop it when done.

## Report back (your final message)

- What changed, mapped to W1–W7 and the §1B regressions.
- Every assumption you made about the contract or the server responses, and every fallback you added.
- Known limitations, or anything you would like the main session to double-check in the browser.
