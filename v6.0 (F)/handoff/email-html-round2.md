# The HTML daily report: the owner's second-round design (2026-09-30)

The developer reviewed all 17 sample emails one by one. This file is the
complete, settled result, and it supersedes `email-html-design.md` wherever
the two differ. It changes **the HTML body only**. The plain-text body and the
subject stay byte-identical to today's, apart from the Work day/Off day fix
already made.

## Whole-email structure (top to bottom)

1. **Hidden preheader**: kept, first after `<body>`. The difference wording
   follows the new tags: "CB Shortage ($2,000.00) on 24 September".
2. **Title band**: `LDGR | Daily Report | 23-09-2026`, or `LDGR | Corrected
   Report | dd-mm-yyyy` for a corrected report.
   - White text on a full-width green band (accent `#1F6F5C`), the very first
     visible thing, with rounded corners matching the cards.
   - "(Urgent Care)" is gone.
   - The date is the report date, `Date(to)`, as dd-mm-yyyy with single dashes.
   - The text is as LARGE AS FITS ON ONE ROW: re-measure as in the previous
     round (Segoe UI and Arial, 5% margin, worst-case date, separately for
     each wording), with an inline size for 360 px, media-query steps for
     375/390/412/430/600 and a step down below 360. Cap it at 28px.
   - "LDGR" is bold. The "|" separators are a pale green (`#B9D9CE`; no
     rgba), and "Daily Report" and the date are semibold, all on the band.
   - Dark mode keeps the band green (`#1F6F5C`, or `#175649`) with white text.
3. **Caption**: "Includes everything saved up to 16:40 on 23 September.", soft
   ink, current size, shown only when there are rows.
4. **Notes**, if any: plain soft text in parentheses, aligned with the
   caption, with no grey box. For example: "(This replaces the report sent at
   17:30, which was prepared before the last entry of that day could be
   sent.)" The same goes for the follow-up, possible-repeat, first-report and
   clock notes. The **late** and **several-days** notes are dropped from the
   HTML.
5. **DAYS ENTERED**: the only day section. It holds every entered day, gap day,
   revised day, kind-of-day change and pending day, newest date first. Its
   heading is green at 14px, as now. There is no "NEEDS ATTENTION" and no
   "GAPS FILLED" heading any more.
6. **Change-log warning** (only when the log could not be read): the red
   notice, same look and words, placed right AFTER Days entered.
7. **SAVED DAYS WITH PENDING LEDGERS**: a section heading in the same green
   style, then one card listing each waiting day. This is always the last
   section ("at the bottom by convention").
8. **Footer**: "Powered by **SolRegia**", as now.

The quiet-day card ("✓ Nothing was entered or changed today, and every
recorded day has its ledger.", and the same-date-corrections sentence) stays as
it is, in place of Days entered. Nothing is shown when the log is unreadable.

## The day card (every day, every kind)

It's a two-column table, shaped like sample 01's row:

- **Left column:** the date, then the event bullets.
  - The date is "24 September 2026" in sample 01's style: 15px, semibold, ink.
  - A suffix in title case can follow the date: "(Previous Gap Day)",
    "(Awaiting Gap Day)" or "(Previously Not Balanced)".
  - The bullets wrap INSIDE the left column.
- **Right column:** the status tag(s), top-aligned, `white-space:nowrap`,
  stacked one above another when there are several. NOTHING else goes in or
  under the right column. The explanation must never bleed into it.
- **Full-width row below** (colspan 2), only when the day has a reported
  edit: the change table(s).
- **Not shown any more:** a "Work day" label, the "During the day" and
  "Opening balance" captions, the "than the $X the day before closed with"
  line, any separator line inside the card, and the coloured left stripe.
  Colour now lives in the tags.
- The cards are separated by the existing 12px spacer, so several days never
  run together. Every change table sits visibly inside its own card.

### Status tags (pills)

| Situation | Tag(s) |
|---|---|
| Entered, balanced | `Balanced` (green) |
| Off day | `Off day` (neutral) |
| Closing count differs (`day_diff`) | `CB Shortage ($2,000.00)` (red) / `CB Surplus $1,000.00` (amber) |
| Opening differs from last close (`night_diff`) | `OB Shortage ($2,000.00)` (red: opening LESS than last close) / `OB Surplus $1,000.00` (amber: MORE) |
| Both differences | both tags, stacked, OB above CB |
| Reported edit, balanced before and after | `Numbers revised` (amber) |
| Reported edit that cleared a difference | `Balanced` (green), and the date suffix `(Previously Not Balanced)` |
| Reported edit, day still or newly unbalanced | `Numbers revised` (amber) only |
| Kind of day changed (either way) | `Work status update` (amber) only |
| The day's ledger is pending (waiting on a missing day before it) | `Ledger pending` (amber) IN PLACE OF `Balanced` / `Numbers revised` (the owner: "tag should say ledger pending"), kept beside `Off day` or the CB/OB tags; plus the date suffix `(Awaiting Gap Day)` |
| A gap day (it filled a gap) | its balance tag(s) as above, and the date suffix `(Previous Gap Day)` |

- Amounts use `Checks.money`. A shortage is in parentheses (the accounting
  negative). A surplus is plain.
- Colours are the palette's: red `#A63D40` on `#FBEDE9`, amber `#8A6212` on
  `#FDF4E3`, green `#1F6F5C` on `#E8F3EE`, neutral `#5B6660` on `#EFEDE7`.
- Precedence, when several rows apply: Work status update overrides everything
  for that day. Otherwise a reported edit decides between Balanced (cleared) and
  Numbers revised. Otherwise the balance tags apply. A day whose ledger is
  pending shows Ledger pending instead of Balanced or Numbers revised, keeping
  only Off day or the CB/OB tags beside it.

### Event bullets

Bullets are table rows (a narrow "•" cell plus a text cell), soft ink, 13px,
19px line height, en dash "–", 24-hour times, with dd-mm-yyyy dates where a date
is shown.

- **Day entered in this report:** `16:50 – entered and saved by reception`
  - with one difference: `… with explanation: Paid the lab courier from the drawer`;
  - with both: `… with explanations: OB – Change fund moved to the safe overnight; CB – Paid the lab courier from the drawer`;
  - with a difference but an empty reason: `…, no explanation given`.
- **Same-session update** (not reported): `16:35 – updated by manager`. Show
  the last one, as the text's "Changed again" line does.
- **Revised day not entered in this report:** first
  `First saved on 23-09-2026 at 16:50`, plus ` with explanation: …` /
  ` with explanations: …` when the day had a difference then. That
  explanation is the reason in force before the first reported edit: the
  "before" side of its reason part, else the reason on the rows before it. Then
  one bullet per reported edit: `Changed on 24-09-2026 by manager at 10:05`.
- **Day entered in this report and then edited after its session** (the
  next-morning case): `18:10 – entered and saved by reception`, then
  `Changed on 24-09-2026 by manager at 09:20`.
- **A gap day releasing ledgers:** keep one more line after its bullets,
  `✓ Ledger made for 23 September 2026` (accent). If a released day carries
  a difference, show it on that line's own small tag row in the same CB/OB
  wording, and its explanation as `explanation: …`.

### Change table (the full-width row under a card with a reported edit)

- The columns are as now: label | BEFORE (struck through, soft ink) | AFTER
  (bold).
- With several reported edits, use one table per edit, each with a small
  caption line ("Changed on 24-09-2026 at 10:05", soft, 12px) when there's more
  than one.
- Rows:
  - **Figure rows**, as now (the label from the change log; "(not counted)"
    stays as written).
  - **A difference row** whenever the edit changed a difference
    (`was_day_diff` → `day_diff`, `was_night_diff` → `night_diff`):
    - the label is `CB Shortage` if both sides are shortage or zero,
      `CB Surplus` if both are surplus or zero, else `CB Difference`, and the
      same with OB;
    - the values are a shortage in parentheses, a surplus plain, and zero as
      `$0.00`.
    - Examples: cleared, `CB Shortage | ($2,000.00) | $0.00`; new,
      `CB Shortage | $0.00 | ($1,000.00)`.
  - **Explanation row** (the label is "Explanation", not "Reason"; "Night
    reason" → "OB explanation"; a stacked before/after as now):
    - drop it when the explanation was CLEARED (after empty), because the
      first-save bullet already shows it;
    - keep it when the explanation was changed or added (before "(none)").
  - **Kind of day changed:** the table holds ONLY the row
    `Day type | Work day | Off day`, with no figure, difference or explanation
    rows.

### Saved Days with Pending Ledgers (the last section)

A card with one row per waiting day:
- The date, bold, on its own line.
- Under it, the caption, unchanged from the text: "Saved, but its ledger cannot be made until 22 September 2026 is entered.", or the rare
  "Saved, but its ledger has not been made yet. The day before it is already on record.".
  There must be a real line break between the date and the caption, never
  "23 September 2026Saved, …".
- At the very bottom of the card, soft and 12px: "This list clears
  automatically as gap dates are filled in."
- The old three-line explanation is gone.

## Facts the HTML deliberately no longer shows

The plain text keeps all of them:
- the last-close amount ("than the $20,000.00 the day before closed with");
- the late and several-days notes;
- a cleared explanation's table row (the old explanation is shown in the
  first-save bullet instead);
- the figures of a day whose kind changed;
- the Records folder line;
- every intermediate "Changed again" save but the last.

The parity test must list exactly these as intended omissions, and keep
checking everything else.

## Implementation notes

- **Draft fidelity:** Gmail's draft store dropped `background:` shorthands.
  Set every fill with BOTH a `bgcolor="#…"` attribute on the `<td>` AND
  `background-color:#…`, never the `background` shorthand: the band, the
  cards, the pills (put the pill fill on a `<span>` with `background-color`,
  and on a wrapping td where practical) and the quiet card. Check one draft
  afterwards to see whether the fills survive. White text must never end up
  on no fill: if the band's fill doesn't survive in the draft store, say so.
- Keep: escaping, no-break spaces in times and dates, 24-hour times,
  determinism, the fallback, the per-report live cache, html in the pending
  table and in the hash, and the size budget.
