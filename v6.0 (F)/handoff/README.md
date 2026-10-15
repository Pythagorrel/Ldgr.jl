> **2026-09-15, later:** this file describes the 2026-09-14 UI handoff, which is finished. The current state, the ranked findings, the email design and the scenario scripts are in [`review-2026-09-15.md`](review-2026-09-15.md); the owner's decisions on its §6, the three-stream work split and every shared interface are in [`implementation-2026-09-15.md`](implementation-2026-09-15.md), which wins where the two disagree. `verify-ui-2026-09-15b.mjs` (the §5 scenarios), `verify-ui-2026-09-15.mjs` and `timing-probe.jl` are the verification scripts (`verification.md` below still scripts the removed Review flow). Start with `E:\Ldgr\CLAUDE.md`.

# Handoff — v4.0 entry form: wiring fixes and a simpler, refined UI

**Status:** **implemented and verified on 2026-09-14, not committed.** Don't run it again.
- The changes sit uncommitted on top of `main` at `1533dae` ("UI upgrades (unfinished)").
- Verified in the America/Guyana timezone only: the owner confirmed ldgr runs only in Guyana, entirely on the local machine.
- Changes made after this plan was written: the page loads no web fonts (nothing is fetched from the internet); the drawer counts have no `0.00` placeholder; on Review, Status is the second column and Edit/Remove stay pinned at the right.
- Later owner decisions that replace parts of decision 1 below (see `ui-contract.md`):
  - Nothing floats: the dock is the last block of the form, after the Evening count, and the watermark is a static line at the end of the page.
  - A warning's full explanation still lives in the dock, but it no longer opens by itself. Each row in the Checks panel has a "See full explanation" link that opens it; a refused save opens the Must-fix reason beside the Save button.
  - The reason box names the warnings that need the reason, and the dock has no "Write a reason" button.
- **2026-09-15: the Review and Saved screens are gone**, with the stepper. The owner judged them redundant because the checks already stop a bad save.
  - Save & next day writes each day straight to the books (`POST /api/save`), and `Staging.jl` is deleted.
  - The "first day on record" and "replace ledger file" tick boxes sit in the dock.
  - "Edit that day" loads a saved day back (`GET /api/day`).
  - Mentions of Review, "Save to the books", the Done screen, `/api/staged` or `/api/commit` in this folder describe the old flow.

## Background

Hannah (the designer) used Gemini to rework the entry form in commit `1533dae`. That commit added:
- three stages
- a fixed warnings rail on the right
- a sticky warnings bar
- a totals dock
- `public/prototype.html`, a dark Tailwind page, as visual direction

She ran out of time. Her handoff notes asked for:
- **Wiring:** check the HTML ⇄ backend wiring again, because Gemini may have broken something.
- **From the prototype:** its "floating sticky bottom dock, glass panel/blur treatment for banners and clearer card level accent borders".
- **Warnings:**
  - Make them "a little more visually distinct" and put them "on the side so they're easily noticed", without the current overlap.
  - "What I wanted was like a short phrase on the side and the detailed explanation below (it could even be added to the sticky thing until dismissed)."
- **Branding:** "a header and a watermark on the left corner with a 'powered by SolRegia'".

**The owner's direction:**
- Simplicity is the heart of the product.
- It must stay easy for a non-technical, non-accountant employee, with no learning curve and no extra features.
- The look should be more refined, modern and minimal, **in the same colour scheme**.
- Design lessons from the Uizze references are listed in `issues-and-design.md`.

**What the investigation found.** An earlier session read every file, ran the server on scratch data, and drove the current UI in Chrome. It found:
- 7 wiring bugs (W1–W7). The worst two: the very first save can never succeed from the form, and a failed commit hides the reason it failed.
- Several regressions from the Gemini commit.
- The layout problems Hannah described.

## Confirmed decisions

1. **Warnings.**
   - A "Checks" panel on the right lists a short phrase for each warning.
   - The full explanation of the most serious open warning shows in a slim row on the floating bottom dock, with a ✕ to close it.
   - Once closed, it stays hidden until a *different* warning appears.
2. **Card accents.**
   - Every card gets the same green accent bar (`--accent`) and a numbered stage chip: 1 Morning count, 2 Today's figures, 3 Evening count.
   - Warnings are the only other colour on the page.
3. **Drawer count not reached yet.** A blank drawer count first shows as a grey "Still to count" row. It turns into a red "Must fix" once the person leaves that box blank or presses Save.
4. **Execution.**
   - Three sub-agents on **Opus**, one per section, work in parallel.
   - Meanwhile the main session prepares verification.
   - When they finish, it reviews, verifies and fixes.

## Files in this folder

| File | Who reads it |
|---|---|
| `issues-and-design.md` | Everyone. The issues with their evidence, plus the design. |
| `ui-contract.md` | Agents B and C, and the main session. The exact IDs, classes and generated markup shared by `index.html`, `styles.css` and `app.js`. |
| `agent-a-backend.md` | Prompt for **Agent A**: Julia (`Checks.jl`, `server.jl`, one new test). |
| `agent-b-markup.md` | Prompt for **Agent B**: `index.html` and `styles.css`. |
| `agent-c-logic.md` | Prompt for **Agent C**: `app.js`. |
| `verification.md` | The main session. Environment, safe commands, test scripts, the flows to check and what each must show. |

## File ownership

No two agents edit the same file.

| Owner | Files |
|---|---|
| Agent A | `v4.0/Checks.jl`, `v4.0/server.jl`, `v4.0/tests/test_checks_titles.jl` (new), `v4.0/tests/TESTING.md` |
| Agent B | `v4.0/public/index.html`, `v4.0/public/styles.css` |
| Agent C | `v4.0/public/app.js` |
| Main session | No product files while the agents work; any file during the integration fixes. |

## Order of operations (main session)

1. **Read** this file, `issues-and-design.md`, `ui-contract.md` and `verification.md`.
2. **Launch the agents.**
   - Send three Agent tool calls in a single message, each with `subagent_type: "general-purpose"` and `model: "opus"`.
   - Each prompt is: "Read and follow `E:\Ldgr\v4.0\handoff\agent-<x>.md`. Your scratch folder is `<your scratchpad>\agent-<x>`."
   - They run in the background.
3. **While they work:**
   - Make sure nothing is listening on port 8765.
   - Set up the scratch tooling from `verification.md`: install `playwright-core`, then write `verify-ui.mjs` and `run-julia-tests.sh`.
4. **As each agent reports:** read its report and its diff (`git diff -- <its files>`), and check `git status` shows no changes outside the files it owns.
5. **When all three are done:**
   - Run the contract cross-check.
   - Re-run the Julia tests.
   - Start a fresh server with a scratch `LEDGER_ROOT`.
   - Run `verify-ui.mjs` in both timezones at all four widths.
   - Look at every screenshot.
6. **Fix what the checks turn up.**
   - Make small fixes yourself.
   - Send larger rework back to the agent that owns the file with `SendMessage`; each agent keeps its context.
   - Verify again after every round.
7. **Finish.**
   - Stop the server.
   - Report to the owner: what changed, the test results and the key screenshots.
   - Don't commit unless asked.

## Definition of done

- **Bugs:** W1–W7 are fixed, and every Gemini regression listed in `issues-and-design.md` is resolved.
- **Julia tests:**
  - `test_endtoend.jl` and `test_endtoend_edge.jl` report 0 FAIL.
  - `test_checks_titles.jl` passes.
  - The three `test_checks_*` scripts that only print their findings run without errors.
- **Browser:** `verify-ui.mjs` passes in America/Port_of_Spain (UTC−4) and Asia/Bangkok (UTC+7), at widths 1440, 1280, 1024 and 390. That means:
  - every flow passes
  - nothing overlaps
  - no horizontal scrolling
  - no console errors apart from the favicon 404
- **Visual review:** the screenshots have been checked against Hannah's notes and the design, and the page still reads as simple.
- **Safety:** nothing was written to the real `v4.0/Records/`, and nothing was committed.
