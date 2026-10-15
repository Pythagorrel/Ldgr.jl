# LDGR brand design session: shared brief (2026-10-08)

Every agent in this session reads this first. It is the single source of facts.

## What LDGR is

A small desktop bookkeeping app for an urgent care clinic in Guyana. Clinic staff
(non-technical, not accountants) type each day's cash figures into a form; LDGR
checks the day and writes a Daily Journal and ledgers for QuickBooks. It is
packaged as `LDGR.exe` (a maximised Windows window that hosts the form). It is
built by SolRegia (the developer, Jorrel, and Hannah). The look is calm, plain and
trustworthy: green and cream, lots of white space, no gimmicks.

## The four deliverables

1. **The full logo.** Hannah's idea: the word **LDGR**, integrated with an analog
   accounting ledger, the letters falling in between the ledger lines as though
   the word were an entry written into the ledger. Delivered as a PNG with a
   transparent background (plus an outlined SVG master). It must read on white
   `#FFFFFF` and on the cream page `#FAF9F6`.
2. **The startup screen.** Shown by `LDGR.exe` while the program starts (about
   3 seconds on a normal start; up to minutes on a slow first start). A banner,
   most likely white, showing the full logo with a sub-caption "powered by
   SolRegia". It also needs a quiet place for a one-line status message in the
   form's own font (Segoe UI), because these owner-approved lines can appear
   there: "Starting LDGR…", after 60 s "Still starting. Please wait.", and on
   failure longer sentences such as "LDGR could not start. Please contact the
   technician." plus a file path on a second line.
3. **The closing screen.** Shown while LDGR closes (a few seconds, at most 20 s).
   It just says closing ("Closing…") in the final logo font.
4. **The small brand image at the top left of the form.** Today it is a 38×38 px
   rounded square (radius 11 px) in accent green `#1F6F5C` with a white
   document icon, followed by the text "LDGR" (Segoe UI 17 px, weight 600,
   letter-spacing .06em, colour `#1C2521`) and a caption "Urgent Care" (13 px,
   `#5B6660`). The header bar is white-ish on the page, 18 px padding top and
   bottom, a 1 px `#E3E0D8` hairline under it. The new image must match the final
   logo and font. It must stay crisp and legible at small size (it is shown at
   CSS px size on a 125% Windows display, so export 2× and 3×).

## The font rule

ONE display font (possibly two weights) is chosen for the logo, the startup
screen and the closing screen only. The form's own font (Segoe UI / Inter for
text, Consolas for figures) does NOT change. The status line on the startup
screen stays in Segoe UI.

Because the startup and closing screens are drawn by a small Windows program and
the clinic PC will not have the display font installed, the plan is to render
the logo, the "powered by SolRegia" caption and the "Closing…" word into PNG
images, so no font file has to ship. So the font licence must allow use in a
logo and in raster images for a commercial product. Prefer fonts with clear open
licences (SIL OFL, Apache). Fonts that come with Windows or Microsoft Office are
allowed for exploration but must be flagged as licence-uncertain for a logo.

## Palette (fixed; do not invent colours)

| token | hex | use |
|---|---|---|
| ink | `#1C2521` | main text |
| ink-soft | `#5B6660` | secondary text |
| accent | `#1F6F5C` | brand green |
| accent-dk | `#175649` | darker green |
| band | `#E8F3EE` | pale green tint (classic green ledger paper!) |
| line | `#E3E0D8` | hairlines |
| line-soft | `#EFEDE7` | soft rules |
| page | `#FAF9F6` | cream page |
| card | `#FFFFFF` | white |
| danger | `#A63D40` | muted red (could be the red margin rule of a ledger) |
| warn | `#8A6212` | ochre |
| counted-line | `#D9C89A` | warm rule |

Translucent or darker versions of these are fine. Nothing else.

## Ledger vocabulary (for the logo idea)

A paper accounting ledger: pale green ruled sheet, evenly spaced horizontal rules,
a red (or dark) double vertical rule at the left margin, column rules for
Date | Particulars | Debit | Credit, and the accountant's single underline under
figures and **double underline under a total**. An entry is written on a row,
sitting on its rule. "Letters falling in between the ledger lines" can be read
two ways, and both are worth a concept: (a) the whole word sits as one entry on a
row, between two rules; (b) the letters cascade down successive rows like
consecutive entries.

## Hard constraints

- Plain, legible, calm. No gradients-for-show, no glow, no 3D, no clip-art.
- The logo must survive being small (header use) and large (startup screen).
- Transparent background on the logo PNG.
- Work only in the scratchpad `brand/` folder unless told otherwise.
- VectorCraft is ONE shared headless app with one active document. Only one agent
  may use it at a time; the orchestrator schedules this. Always start your work
  with `file.new` (your own document) and never close or edit documents you did
  not create.
- Nothing in this session touches the LDGR program files, the Records folder or
  `notify.toml`.

## Addendum (owner's decisions, later on 2026-10-08)

- **Fonts for the concept round:** Source Serif 4 and Piazzolla. Both are SIL OFL variable
  fonts, now installed for this Windows user, and VectorCraft lists every named weight:
  Source Serif 4 ExtraLight..Black (+ italics) and Piazzolla Thin..Black (+ italics).
  Source Serif 4 was previously only VectorCraft's own bundled Regular; the installed family
  now replaces it. Drawing weight: SemiBold to start with; Medium is allowed if SemiBold
  looks heavy.
- **The owner's direction for the ledger (verbatim):** "the ledger should scale with the size
  of the LDGR text to actually act as a backdrop and the dimensions of the letters should fit
  aesthetically into the lines - think the ratio of letters in the pacioli font selectively
  highlighted by the lines in the ledger background".
  - What that means: Luca Pacioli (the father of double-entry bookkeeping) also drew Roman
    capitals by construction (De Divina Proportione, 1509): each letter built on a square
    of height H, stems a fixed fraction of H, thin strokes a fixed fraction of the stem. So the
    ledger is NOT generic ruled paper with a word placed on it. It is the letters'
    construction grid, dressed as a ledger:
    - every measure is a multiple of the cap height H, so the whole logo scales as one unit;
    - the rule pitch is derived from the letters, so rules land exactly on the letters'
      landmarks (baseline, cap line, and the waist where R's bowl meets its leg / G's bar);
    - the rules that coincide with a landmark are the highlighted ones; the rest of the
      ruling is a quieter backdrop around the word.
- Pacioli is a proportion reference, not a font to find: Uizze has no Pacioli or Roman
  inscriptional font.

## Addendum 2 (owner's redirection, late on 2026-10-08) — supersedes earlier choices where they conflict

The owner looked at the plain-ledger header wordmark (W1, Source Serif 4 SemiBold on faint rules) and said,
verbatim: "I like W1 but don't you find the font a bit too plain and vanilla? I'd like some cursive - it fits
the analogue backdrop better. Also it should have the 'book' colour - like in this image I provided here. The
backdrop should be slightly textured to give it that book feel and the font could be smaller, the lines should
be uniform in length, and it can have the vertical lines that make it resemble an actual ledger book as in the
image".

What that changes (for the logo, the header wordmark, the startup banner and "Closing…" alike: one brand):
- **Font: cursive.** Source Serif 4 is out as the display font. A script that fits an analogue ledger (the
  clerks' round hand / copperplate / a calm pen script) is wanted. It must stay legible for clinic staff.
- **Paper: the "book colour".** The logo is no longer letters-and-rules on transparent: it sits on a patch of
  ledger paper. The owner's reference image is a two-page accounting ledger spread ("12 | 13"):
  - pale ivory / cream-yellow paper (roughly #F6F3DA–#F8F5E1), with a slightly lighter header strip at the top
    carrying the page numbers;
  - a column-heading band between two horizontal rules;
  - a body of evenly spaced thin horizontal rules (about 40 rows) in a light grey-green;
  - vertical rules in groups: at the far left a narrow column of tiny row numbers and a double rule, then a
    narrow date column and a wide "particulars" column, then several money columns, each made of 3–4 thin
    verticals close together (dollars / cents subdivisions), separated by double rules; a narrow column again
    at the far right;
  - all lines fine and uniform, the verticals a touch darker than the horizontals.
- **Texture:** the paper is slightly textured (subtle grain / fibre), enough to feel like a page, never dirty.
- **Letters smaller** relative to the ruling than in rounds 1-2 (where caps filled two rows).
- **Rules uniform in length:** no tapering. The ruling is a rectangular patch of page.
- **Vertical rules welcome**, as in the reference, so it reads as an actual ledger book.
- Still true: the owner's Pacioli idea, meaning the horizontal lines match only SOME letters' dimensions (geometry,
  not colour highlighting); no rule crosses a letter in a way that reads as a strikethrough; the form's own
  font (Segoe UI) does not change; "Urgent Care" stays live Segoe UI text beside the header wordmark.
- The palette rule is relaxed for the paper and its ruling only (the owner asked for the book colour); ink and
  brand green stay.
