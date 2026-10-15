# Agent B — Markup and look (`index.html` + `styles.css`)

You are one of three sub-agents working **in parallel** on ldgr v4.0 (`E:\Ldgr\v4.0`). Your job is to rebuild the entry form's structure and styling.

At the same time:
- **Agent C** is rewriting `app.js` against the same contract.
- **Agent A** is changing the Julia backend.

The main session will integrate everything, test it in a real browser and review it.

## Read first
1. `E:\Ldgr\CLAUDE.md`, especially the "UI principle" section.
2. `E:\Ldgr\v4.0\handoff\issues-and-design.md` — all of section 2 "The design", plus 1B and 1C for what is wrong today.
3. `E:\Ldgr\v4.0\handoff\ui-contract.md` — **your spec.** Follow it exactly.
4. The current `v4.0/public/index.html` and `v4.0/public/styles.css` (the colour tokens), and `v4.0/public/app.js`, only to see which classes it emits today.
5. `v4.0/public/prototype.html` — the designer's reference. Borrow the **floating bottom dock, the glass/blur panels and the thick rounded accent bar**. Do not borrow its dark palette, gradients or Tailwind.

## You own (edit only these)
- `v4.0/public/index.html`
- `v4.0/public/styles.css`

## Must not
- Edit `app.js`, `prototype.html` or any Julia file.
- Rename or drop anything in the contract. If you need an extra wrapper or class, add it and list it in your report.
- Add libraries, frameworks, Tailwind, a build step, images on disk or subfolders under `public/`. The server serves `public/` by file name only; inline SVG is fine.
- Use inline `style=` attributes or add colours outside the palette.
- Commit.

## Who uses this

Non-technical, non-accountant clinic staff who enter one day at a time. The owner's rule: **simplicity is the product's appeal.**
- Calm, spacious and obvious.
- One solid green button per screen.
- Plain words.
- No decoration that competes with the figures or the warnings.

The look should feel refined, modern and minimal, not like a template.

## Design requirements

- **Palette.** Keep these exact values. You may add translucent versions, darker shades, shadows and radii, but no new hues.

  | Token | Value |
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

- **Type.** Inter for text and JetBrains Mono for money inputs and totals, loaded with `<link>` in `index.html`. Use a system fallback stack, keep the scale small and consistent, and give tabular figures to amounts.

- **Page background.** `--page` plus a *very* faint fixed green/cream radial wash, so the glass blur actually shows.

- **Header.**
  - A small green logo tile, then "Daily Entry" with the one-line subtitle.
  - The stepper as a quiet segmented pill on the right, with `.active` and `.done` states.
  - A hairline divider underneath.
  - Stacks cleanly at 390px.

- **Cards.**
  - White, a hairline `--line` border, 16px radius and a soft shadow.
  - A **4px rounded `--accent` bar set inside the top edge of every stage card** (the same green on all three).
  - A numbered `.stage-chip` in a `--band` tint, and an `h2`.
  - `.subcard` sections inside "Today's figures" are lighter (no bar), separated by spacing or hairlines.
  - Two-column `.grid` of fields, dropping to one column when narrow.

- **Fields.**
  - Label above the input. `.money` has a `$` prefix, right-aligned mono figures and a comfortable height (≥ 40px).
  - `.field.counted` inputs get the subtle warm "counted figure" tint (`background #fffdf5; border-color #d9c89a`).
  - Define styles for `.invalid`, `.filled` and `.err.show`, plus the `.field[data-level]` outline in each level colour.

- **Trading/Closed toggle.** A small segmented control (`.daytype-toggle` with `.opt-trading` / `.opt-closed`), driven by the visually hidden `#chk-closed` checkbox via `:checked + label`. It must be focusable, with a visible focus ring. When checked, "Closed" is highlighted in a muted palette colour (not alarming red).

- **Hint lines and reason box.**
  - `.hintline`: a small note with an info mark.
  - `.hintline.off`: `--warn-bg` tint.
  - `.reasonbox`: a calm warn-tinted callout inside the Evening card.
  - `.closed-note`: muted text, hidden when empty.

- **Checks panel `#checks`.**
  - Glass surface; heading "Checks" plus the `.checks-count` pill.
  - `.checks-empty` is a calm line with a small check mark.
  - `.check-btn` rows:
    - A full-width button with an icon, a title (medium weight) and a meta line (small, `--ink-soft`); the code sits right-aligned in tiny mono grey.
    - A hover state, a `.selected` state (tinted background plus a left accent in the level colour) and a focus ring.
  - Level styles and CSS-only icons, per the contract table: stop octagon, warning triangle, info circle, lightbulb; `.todo` is a hollow circle in grey.
  - **The four levels must be distinguishable without colour** (icon plus word).

- **Dock `#dock`.**
  - Fixed, centred at the bottom, about 880px wide at most, 16px from the screen edges, glass (translucent white, `backdrop-filter: blur(14px) saturate(140%)`, hairline border, soft large shadow) and a rounded 18–20px radius.
  - **`.dock-main`:** `dl.totals` (small uppercase `dt`, mono `dd`) plus `.dock-actions`. Wraps gracefully at narrow widths; at 390px the totals take one or two compact rows and the buttons stay tappable.
  - **`#dock-note`:** a slim row above `.dock-main`, tinted by `lvN`, containing the icon, a `.note-text` of up to about 3 lines, an optional `.note-action` (small ghost button) and a `.note-close` ×.
  - **`#dock-status`:** a pill tinted by `lvN`. Visible only below 1100px, and only while it doesn't carry the `hidden` attribute.

- **Buttons.**
  - `.btn-primary`: solid `--accent`, hover `--accent-dk`.
  - `.btn-ghost`: white with a hairline border.
  - `.btn-quiet`: text only.
  - `.btn-danger`: white with `--danger` text.
  - `.mini`.
  - `:disabled` looks clearly inactive.

- **Banners.** `.banner.info|warn|error` are glass tinted with `--band`, `--warn-bg` and `--danger-bg`. `span { flex: 1 }` and the action button sits on the right.

- **Review screen.**
  - `.page-intro` is a simple heading and subline (no big tinted band).
  - `.table-card .table-scroll`: horizontal scroll, sticky header, sticky first column, `td.zero` muted, bold `tfoot td` with a top rule, and `td.act` buttons spaced.
  - Badges: `.badge.new` (band/accent), `.badge.repl` (warn), `.badge.lock` (danger), `.badge.closed` (neutral grey).
  - `.checkline` is a clear checkbox row.
  - `.actions` are right-aligned.

- **Done screen.**
  - `.result` card, with an `h4`, a muted `ul` and `.pathline` in mono.
  - `.result.bad` uses a `--danger-bg` tint with a `--danger` border.

- **Watermark `.watermark`.**
  - A small outlined pill: a tiny sun SVG, then "Powered by **SolRegia**".
  - `--ink-soft` at reduced opacity and not clickable (`pointer-events: none`).
  - Fixed at bottom-left, vertically level with the dock, **only at widths where it cannot touch the dock**. Otherwise it is a static centred line at the end of `.page`.

- **Layout.**
  - `.page` has a max width of about 1180px, centred, with side padding ≥ 16px, and `padding-bottom: calc(var(--dock-h, 0px) + 32px)`.
  - `.entry-grid` has two columns (form, then Checks at about 300px) at 1100px and up, and one column below.
  - `#checks` is `position: sticky` (top about 24px) with `max-height: calc(100vh - var(--dock-h, 0px) - 72px)` and scrolls.
  - Below 1100px, `#checks` is hidden unless `.open`; then it becomes a fixed glass sheet above the dock (see contract §3).

- **Accessibility.**
  - Text contrast meets WCAG AA.
  - A visible `:focus-visible` style everywhere.
  - Hit targets are 40px or more.
  - `.sr-only`.
  - `prefers-reduced-motion` removes transitions.
  - `[hidden]` and `.hidden` rules as in the contract.

Optional: if the `frontend-design` or `anti-ui-slop` skill is available you may load it for general guidance, but these docs and the owner's simplicity rule take precedence.

## Check your work visually (no server needed)

`app.js` and the backend are changing under you, so test with **static fixture pages** instead of the live app.

1. **Fixtures.**
   - In `<your scratch folder>`, create fixture HTML files that copy your `index.html` markup.
   - Pre-fill the generated markup exactly as in contract §2, and set `--dock-h` by hand on `:root` (for example `140px`).
   - Link the real stylesheet by absolute `file:///E:/Ldgr/v4.0/public/styles.css`.
   - Build these fixtures:
     - `entry.html` — three sub-cards with realistic fields, and both `.counted` fields. Checks list with one row of each level, one `.todo` row and one `.selected` row. `#checks-count` visible. `#dock-note` visible (lv2 with `.note-action`). One `.banner.info`, `#prior-hint`, `#predicted.hintline.off`, `#reason-box` visible, one `.field[data-level="2"]`, one `input.invalid` with `.err.show`.
     - `entry-empty.html` — no rows, `#checks-empty` visible, dock note hidden.
     - `entry-closed.html` — `#view-entry.is-closed` with `#chk-closed` checked and a `.closed-note`.
     - `entry-narrow-open.html` — `#checks.open` and `#dock-status` visible (screenshot it at 390 and 1024).
     - `review.html` — `#view-entry` hidden and `#view-review` visible, with a three-row table (badges, `td.zero`, `tfoot`, `td.act`) and both checklines visible.
     - `done.html` — one `.result` and one `.result.bad`, with `.pathline`.
2. **Screenshots.**
   - Install `playwright-core` in your scratch folder (`npm init -y && npm i playwright-core@1`), launch with `chromium.launch({ channel: "chrome" })` (local Chrome, no download).
   - Screenshot every fixture at 1440×900, 1280×800, 1024×768 and 390×844: the viewport, and the viewport scrolled to the bottom.
3. **Checks.**
   - **Look at the screenshots yourself** and fix clipping, overlap, cramped spacing, weak contrast or anything that feels busy.
   - Also assert in the script:
     - `#checks` does not intersect any `.card` at 1100px and wider;
     - the watermark does not intersect `#dock` at any width;
     - with the page scrolled to the bottom, the last card's bottom edge is above `#dock`'s top;
     - `document.documentElement.scrollWidth <= innerWidth` (no horizontal scroll).

## Report back (your final message)
- The structure and styling decisions, in a few lines each.
- Any class or wrapper you added beyond the contract.
- Contract points you found ambiguous, and what you chose.
- Screenshot file paths, grouped by fixture and width.
- The overlap-assertion results.
