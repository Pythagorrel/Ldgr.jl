# The daily report as HTML — design and build spec (2026-09-29)

The daily report email gets an HTML body beside the plain text it has today.
The plain text stays exactly as it is: same words, same order, same bytes. It
is the record, the fallback, and what 764 test checks pin. The HTML shows the
**same facts**, reorganised so the owner can see on a phone, in one glance,
whether anything needs attention.

The visual reference is `handoff/email-html-mock.html`. It is a hand-written
mock of a busy late report and not generated output. Match its markup and inline styles.

## Hard rules

1. **Inline styles on every element.** The one `<style>` block in `<head>` is
   progressive enhancement only: dark-mode colours for mail apps that honour
   `prefers-color-scheme` (Apple Mail, iOS Mail, Outlook for Mac) and the
   `x-apple-data-detectors` reset. If a mail app drops it, the email must look
   exactly like the light mock.
2. **One column, tables for layout, `max-width:600px`**, `role="presentation"`
   on every layout table, `cellpadding="0" cellspacing="0" border="0"`.
3. **No images, no web fonts, no links, no tracking.** Font stack:
   `-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif`.
   ✓ is the text character U+2713, never an image or emoji.
4. **Colour never carries meaning alone.** Every coloured pill or stripe sits
   beside words that say the same thing ("Shortage $1,000.00", "Balanced").
5. **The report's existing wording rules hold:** no warning codes, money via
   `Checks.money` (`$1,234.00`), dates via `_long`/`_short`, times via `_clock`,
   "Work day"/"Off day", never "trading"/"closed".
6. **Deterministic.** No clock, no randomness, no path other than
   `Layout.ROOT` (already in the text). Two builds from the same books are
   byte-identical; the idempotency design depends on it.
7. **Every dynamic string is HTML-escaped** (`&`, `<`, `>`, `"`, `'`): reasons,
   who, the `changed` parts, `problem`, `Layout.ROOT`, the subject in
   `<title>`, the preheader.
8. **No-break spaces** inside times (`5:30&nbsp;pm`) and between day and month
   (`29&nbsp;September`), so "pm" or a month never wraps onto a line of its own.
   Apply this at render time in HTML helpers only. `_clock`/`_long` stay unchanged.
9. **Nothing may be lost.** Every fact in the text body appears in the HTML.
   A `changed` part the HTML cannot parse is shown verbatim, never dropped.

## Palette

Light values are the form's tokens (`public/styles.css`). The dark values are
new and used only inside the `@media (prefers-color-scheme:dark)` block, via
the classes shown, each with `!important`.

| Role | Light (inline) | Dark (class) |
|---|---|---|
| page background | `#FAF9F6` | `.lp` `#121614` |
| card background / border | `#FFFFFF` / `#E3E0D8` | `.lc` `#1B211E` / `#2F3833` |
| ink | `#1C2521` | `.li` `#E4E9E6` |
| soft ink | `#5B6660` | `.ls` `#A2ACA6` |
| accent (green) | `#1F6F5C` | `.la` `#7CC8B0` |
| band (green tint) | `#E8F3EE` | `.lb` `#17322A` |
| danger text / tint | `#A63D40` / `#FBEDE9` | `.ld` `#F2A0A2` / `.ldb` `#3A2022` |
| warn text / tint | `#8A6212` / `#FDF4E3` | `.lw` `#E8BF6A` / `.lwb` `#372C15` |
| quiet tint (reason boxes, notes) | `#EFEDE7` | `.lq` `#252C28` |
| hairlines | `#EFEDE7` | `.lr` border `#2F3833` |
| card stripe danger / warn | `border-left:4px solid #A63D40` / `#8A6212` | `.lsd` / `.lsw` |

The `<head>` also carries `<meta name="color-scheme" content="light dark">`,
`<meta name="supported-color-schemes" content="light dark">`,
`<meta name="x-apple-disable-message-reformatting">`,
`<meta name="format-detection" content="telephone=no, date=no, address=no, email=no">`,
`<meta name="viewport" content="width=device-width, initial-scale=1">`, and
`<title>` = the escaped subject. `<html lang="en">`.

## Order of the body

1. **Preheader** (hidden; first thing after `<body>`), then the spacer div of
   `&#8199;&#847;` pairs, both exactly as in the mock. Content:
   - log unreadable → `THE CHANGE LOG COULD NOT BE READ PROPERLY, so this report may be missing entries. It is not a quiet day.`
   - otherwise quiet → the quiet sentence the text prints, or nothing when the
     text prints none;
   - otherwise → the summary line (below), then ` — ` and up to two
     difference facts in attention order, each like
     `Shortage of $1,000.00 on 29 September.` / `Surplus of …` /
     `Opening balance $500.00 less on 29 September.`
2. **Problem banner**, only when `problem` is non-empty, ABOVE the LDGR
   header. Same words as the text paragraph; `THE CHANGE LOG COULD NOT BE READ
   PROPERLY,` in bold danger colour; card with danger tint, 1px border
   `#E9C3BE`, 4px danger stripe (classes `ldb lsd`).
3. **Header**, as in the mock: `LDGR` + `Urgent Care`; eyebrow `Daily report`
   (`Corrected report` when `corrected`); `<h1>` = `_long(Date(to))`; soft
   lines: the covering phrase with a capital first letter and a full stop, and
   the "Includes everything saved up to …" line when there are rows.
4. **Notes box** (quiet tint), one `<p>` per paragraph: the `note` if
   non-empty, then the span paragraph if the text prints it.
5. **Summary card**:
   - not quiet → the counts, uncapped (unlike the subject's three), in the
     order entered, differences, changed, waiting, from the same counts as
     `_summary`; each item `white-space:nowrap` with its ` · ` separator
     inside it; differences in danger colour, changed and waiting in warn,
     entered in ink;
   - quiet with no rows → `✓` in accent + the text's quiet sentence;
   - quiet with rows (same-date corrections only) → the text's sentence, no ✓;
   - quiet and log unreadable → **no summary card at all** (never an all-clear).
6. **NEEDS ATTENTION** (section label in danger colour), only if non-empty,
   in this order:
   a. day cards (entered and gap days, newest first) that are **attention
      days**: the latest row has a real `day_diff` or `night_diff`, OR a
      released row under the day has one, OR a later edit is reportable (the
      same test `_later_edits` uses to print edits rather than "Changed
      again");
   b. change cards: every day in `changed`;
   c. the waiting card, if `Chain.waiting_ledgers()` is non-empty.
7. **DAYS ENTERED** (soft label): the entered days that are not attention
   days, as compact rows in ONE card: date bold, soft line "Entered by X at T."
   plus "Changed again by X at T." when the text prints it; right-hand pill
   `Balanced` (green) for a Work day, `Off day` (neutral) for an Off day.
8. **GAPS FILLED** (soft label): gap days that are not attention days, one
   card each (see the mock).
9. **Footer**: hairline, the text's footer sentence, then `Records folder: …`.

## Components

Copy the mock's markup for each.

- **Day card**: header row with date left and `Work day`/`Off day` right.
  Then a figures table, one row per difference, from the same facts as
  `_difference_lines`:
  - "During the day" and a pill: `Shortage $X` (danger) or `Surplus $X` (warn);
  - "Opening balance" and a pill `$X less` (danger) or `$X more` (warn), then
    a soft line `than the $Y the day before closed with.` (or `than the day
    before closed with.` when the text has no amount);
  - right under each difference, a reason box (quiet tint): `Reason:` in soft
    ink + the typed text, or `(none given)` in soft italic.
  Then `Entered by X at T.` in soft ink, then any reportable edit blocks,
  balance lines and released lines. The stripe is danger if any difference is a
  shortage or a `less`, otherwise warn. A gap day in attention also shows
  the "Entered on …, filling a gap: …" line under its header.
- **Edit block**: caption `Changed on <date> by <who> at <time>` (14px, 600),
  or with the text's ", with no figure different." when there are no parts.
  Then a table. Split `changed` on `"; "` exactly as `_edit_lines` does, and
  handle each part as follows:
  - figure `^(.+?) (\$[0-9,]+\.[0-9]{2}|\(not counted\)) -> (\$[0-9,]+\.[0-9]{2}|\(not counted\))$`
    → a 3-column row: label | `<s>before</s>` (soft ink, right-aligned) | after (bold);
  - `^Kind of day (.+) -> (.+)$` → a 3-column row labelled `Kind of day`, with
    the values shown as Work day/Off day;
  - `^(Reason|Night reason) "(.*)" -> "(.*)"$` → a stacked row (label, then a
    `BEFORE` line with the struck text and an `AFTER` line). Label `Reason`, or
    `Opening reason` for "Night reason". An empty value shows `(none)`;
  - anything else → a full-width row with the part verbatim (escaped).
  The `BEFORE`/`AFTER` column heads appear once per table, and only if it has
  at least one 3-column row.
- **Balance lines**: `It did not balance before: …` (soft, 13px), then
  `✓ It balances now.` (accent, bold).
- **Released lines**: `✓ The ledger for <date> was made.` (accent, 600).
  Any differences it carries follow as figure rows ("During that day",
  "Opening balance … than the $Y that <date> closed with.") with their
  reasons.
- **Change card**: warn stripe; header row date + kind; the text's soft lines
  ("It was first saved on …", "Its ledger had not been made yet — …", or
  the release-only sentence); edit blocks; then balance lines or the
  remaining differences (figure rows); then released lines.
- **Waiting card**: warn stripe; title `Ledgers still waiting`; one row per day
  (date bold, then the text's rest-of-sentence with a capital first letter);
  then the text's three-line explanation joined into one soft paragraph.

## Code shape

- **Keep the text byte-identical.** Move the grouping and counting at the top
  of `_digest` into `_plan(rows)`, which returns a NamedTuple. Where a text
  helper works out a fact while printing it (`_difference_lines`,
  `_edit_lines`, `_later_edits`, `_balance_lines`, `_was_line`,
  `_released_lines`, `_waiting_block`, the `_changed_block`/`_gap_block`
  preambles, the `_entered_block` headline), split it into a pure function
  that returns the fact and a printer that prints it. Both renderers then use
  the same facts. Prove byte-identity with a golden comparison at fixed times
  before and after the change, and with the full suite.
- New file **`EmailHtml.jl`**, `include`d inside `module Notify` after the text
  helpers (not a module of its own). Its entry point is
  `_html_body(plan, rows, problem, from, to; note, corrected, subject) -> String`.
- `_report(rows, problem, from, to; note, corrected) -> (subject, text, html)`.
  `_digest` keeps its signature and 2-tuple (it returns the first two), and so
  does `build_digest`. Add `build_report(from, to; note)` (3-tuple). The
  hand-over paths (step 4, `_send_now!`) and the warm-up use the 3-tuple.
- `_email(cfg, subject, body; scheduled_at, html = "")` and
  `_email_dict(from, to, subject, text, scheduled_at, html = "")`: add
  `"html" => _utf8(html)` only when `html` is non-empty.
- `_hash16`: append `"|" * html` to the canonical string **only when the
  email has an html key**, so an html-less email hashes as before.
- `[pending.email]`: write `html` when present; `_read_state` reads
  `get(m, "html", "")`. An old state file without it must read and replay
  byte-identically, as today.
- `Resend.jl` passes `html` through unchanged. Only its docstring changes.

## Size

Gmail clips a message over about 102 KB ("[Message clipped]"). Putting "Needs
attention" first means a clip only ever hides routine days. Keep the rows
compact. Budget: a one-day report under 30 KB; a 31-day late report of
balanced days under 100 KB.

## Revisions 2026-09-30

Six changes from the owner's first look at the sample set. **The mock
(`email-html-mock.html`) and the sections above predate them** and still show
the old header, summary card, sentences and footer. HTML only: the plain text
and the subject are byte-for-byte unchanged (checked against the 24 preview
scenarios and the 17 samples).

1. **Header.** One line replaces the brand line, the eyebrow, the big date and
   the "Covering …" line: `LDGR (Urgent Care) | Daily Report | 23-09-2026`
   (`Corrected Report` for a corrected one; the date is `Date(to)`, dd-mm-yyyy).
   LDGR is brand green, bold, 1px letter-spacing; the rest is soft ink, with
   "Daily Report" and the date in ink, semibold. 13px, no-wrap: 14px did not fit
   the corrected report at 360px. Under it, only when there are rows, the
   caption "Includes everything saved up to 16:40 on 23 September." The
   "Covering" line is gone everywhere, several-day reports included.
2. **No summary card.** The "1 day entered · 2 differences …" card is removed;
   the quiet-day card stays, and the hidden preheader still carries the counts.
3. **Section headings** are 14px. "Days entered" and "Gaps filled" are brand
   green (`la` in dark mode); "Needs attention" stays danger red.
4. **Day events as bullets.** "Entered by X at T." / "Changed again by Y at T."
   become table-row bullets (a narrow `&bull;` cell and a text cell, never
   `<ul>`) in time order: `15:40 – entered and saved by reception`, then
   `16:35 – updated by manager` (the last same-session update, the one the text
   reports). Soft ink, 13px/19px. On the compact rows they span the card's full
   width under the date and pill. The reported later edits (before → after
   tables) are unchanged apart from the clock.
5. **24-hour time in the HTML** (`_clock24`, `09:05`). Sentences ldgr wrote
   that arrive with "5:30 pm" (the notes, the several-day paragraph) go through
   `_times24`, a strict regex; it is never applied to a reason, a name or the
   change log's problem.
6. **Footer.** The send-time sentence and "Records folder: …" are replaced by
   "Powered by **SolRegia**", as the form's footer shows it, as text only (mail
   apps drop the inline sun icon), soft ink, 12px, centred, under the hairline.
   The plain text keeps its footer and the Records folder line.

## Second round, 2026-09-30

The owner reviewed the revised samples and settled a second round of changes:
a green title band, one day section (Days entered) with every day as one card
shape and its status in tags, the change-log warning moved after the days, a
Saved Days with Pending Ledgers section at the bottom, and the omissions listed
there. It supersedes everything above wherever the two differ, and it is
written up in full, with its own list of what the HTML deliberately no longer
shows, in [`email-html-round2.md`](email-html-round2.md). HTML only again: the
plain text and the subject are byte-for-byte unchanged (checked against the 24
preview scenarios and the samples).
