# LDGR brand: design principles

Read this before changing, extending or adding to the LDGR brand: the logo, the start banner, the closing screen, the
form's header strip, the app icon, or anything new in the same voice (an installer, a printed guide, a document
cover).
- **What applies:** these are the rules the owner arrived at over the design session of 8–9 October 2026. Where the
  owner says something different later, the owner wins.
- **Where the rest is:** the exact sizes and colours are in `README.md`, and how it is wired in is in `WIRING.md`.
  Every draft and the full story are in `drafts/`; open `drafts/15-journey-page/ldgr-brand-journey.html` for the
  round-by-round account.

## 1. The idea
- **LDGR is an entry written into a ledger book** (Hannah's idea). The word is written on a patch of a real
  accounting ledger page, as a bookkeeper would write it.
- **The feel is analogue:**
  - off-white paper with a faint grain;
  - fine ruled lines, with double vertical rules at the edges;
  - a clerk's pen hand.
  It should look like a book on a desk, not a spreadsheet or a grid.

## 2. Lines and letters (the "Pacioli" rule)
Luca Pacioli, the father of double-entry bookkeeping, drew his capitals on a strict proportional grid. The owner's
rule follows from that.
- **The ruling comes from the letters.** The row pitch is set from the font's own measured proportions. In the
  current logo the pitch is half the cap height, so:
  - every letter's baseline sits on a rule;
  - the tall capitals reach the rule two rows up.
- **"Selectively" means geometry, never colour.** The lines line up with *some* letters' features and miss others.
  Do not colour or highlight line segments to point this out. (Green per-letter segments were tried and dropped.)
- **No line may ever read as a strikethrough.** A line through a word means a voided entry in bookkeeping.
  - Rules are faint and sit behind the ink.
  - A rule that would cut across the middle of the letters is either cut away around them or kept so faint that it
    reads as paper.
- **Rules are hairlines,** clearly lighter than the letters (about 3 : 1 or more). No heavy rules. No grid ticks or
  "brick wall" of vertical lines.
- **Horizontal rules are all the same length,** edge to edge. The patch is a cut piece of a page, with no tapering.
- **Two sets of vertical rules only:** one double rule near each end, mirrored, so the ends are symmetrical. No
  money columns, heading bands or margin colours.
- **The paper hugs the lettering:** the patch is only as tall as the word needs.
- **The letters cascade diagonally:** L highest, then D, G and R, each one row lower, like consecutive entries.

## 3. Type
- **The display face is Petit Formal Script, with "LDGR" in capitals.** It reads as a clerk's round hand, and its
  capitals stay legible for clinic staff. Avoid scripts whose capitals are ornate or collide.
- **The script lives only inside images:** logo, banner, closing, header strip and icon. **The form's own text font
  never changes** (Segoe UI for text, Consolas for figures). No font file ships with the app.
- **Open-licence fonts only** (SIL OFL or similar). Fonts that come with Windows or Office are licence-uncertain for
  a logo and were set aside.

## 4. Colour and surface
- **Only the app's own palette.** Nothing new is introduced.

  | Use | Colour |
  |---|---|
  | Letters | brand green `#1F6F5C` (`#175649` at header size) |
  | Paper | off-white, mean `#FDFCF9` |
  | Patch edge | the app's hairline `#E3E0D8` |
  | Screens behind the art | the app's page colour `#FAF9F6` |

- **G1 is the main colourway:** green letters on off-white textured paper, horizontal rules in green at about
  22–25 %, end rules at about 34–36 %.
- **G2 is the secondary colourway:** white letters on textured green. It is used only for "Urgent Care" in the
  header strip.
- **It must mesh with the app:**
  - no yellow or ivory paper (tried and dropped);
  - the start and closing screens use `#FAF9F6`, not white;
  - the header strip sits at 94.5 % opacity, because full strength was too contrasty and 85 % too faint.
- **The texture is felt, not seen:** fine grain only, never blotchy or dirty.
- **Corners are soft, never sharp:**

  | Piece | Corner radius |
  |---|---|
  | Logo | about 3.5 % of the width (16.5 pt on the 470 pt patch) |
  | Header strip | 4.5 px |
  | Icon tiles | about 20 % of the size, to match Windows 11 |

- **A shadow only where the banner sits on a page,** and then only the form's own soft card shadow.

## 5. Hierarchy and restraint
- **The program name dominates.** "Urgent Care" is a quieter caption and must never pull attention from "LDGR".
- **The header strip is one piece.** "LDGR" (G1) and "Urgent Care" (G2) share one double rule, green on the white
  side and white on the green side, with no gap between them.
  - "Urgent" sits above "Care".
  - The top of the U is 2/7 of the way down the D, and the bottom of "Care" is 4/9 of the way down from the top of
    the R; then the words were enlarged 2.75 %, centred.
  - Only the outer corners are rounded.
- **Say as little as possible:**
  - no "powered by SolRegia";
  - no "Starting LDGR…": the banner itself tells staff the program is loading;
  - text appears only when something is wrong, in the owner-approved sentences (`packaging/DESIGN.md` §4), in
    Segoe UI, under the banner.
  - The closing screen is just "Closing…" in the script.
  - The icon is just the L.
- **The start banner floats** centred on the desktop until the form is ready, like a classic splash. It has no
  window frame and no text.

## 6. Small sizes
- **Draw each size for its size; don't just scale the big one down.**
  - Icons are hand-tuned per size: no texture below 48 px, a heavier L, fewer rules at 16–24 px.
  - The header letters get a 0.45 px stroke in `#175649` so they hold up at 125 %.
- **Adjust line weights by eye at small sizes** (faint rules at about 1 px). Thin rules turn to grey fuzz;
  rules that vanish lose the ledger.
- **The ledger stays even when small.** A header wordmark stripped of its lines was rejected: "the ledger lines need
  to still go through the word … it still has to have that analogue look of the book".

## 7. Files and formats
- **Keep every asset as PNG** (`@1x`, `@1.25x`, `@1.5x`, `@2x`, plus `@3x` for the header) **and as SVG.**
- **Use SVG where nothing restricts the file type** (the form header). **Use the required format where something
  does:** PNG in the WinForms launcher, ICO for the exe and the favicon. In a browser, a PNG set goes in a `srcset`.
- **The editable masters are the VectorCraft documents in `source/`;** the font file is in `font/`.

## 8. Working on the brand with the owner
- **Judge everything where it will be seen:**
  - the owner's screen is 1536 × 864 CSS px at 125 % Windows scaling;
  - show art in the real header or the real window, not only on an artboard.
- **Show options side by side with a recommendation, and let the owner choose.**
  - The owner gives precise tweaks (fractions of a letter, percentages); apply them exactly.
  - Show a measurement image when it helps (guide lines drawn across the art).
- **Make previews pixel-exact.** Never stretch small art on a review page: magnify it with hard (nearest-neighbour)
  pixels, or the owner will see a blur that is not in the files.
- **Verify in proportion to the change:** direct screen grabs of a scratch copy plus the existing suites. No extra
  review rounds.
- **Keep the drafts** (`drafts/`) and record each decision where the next session will find it.

## 9. Tried and rejected: don't bring these back unasked
- **Rejected for the ruling:**
  - a middle rule crossing the letters (it read as a strikethrough);
  - heavy rules;
  - grid ticks;
  - a loud red margin;
  - tapered rules;
  - money columns.
- **Green highlight segments over each letter.**
- **Serif wordmarks:** Source Serif 4 and Piazzolla were "a bit too plain and vanilla".
- **Yellow or ivory paper.**
- **On the start screen:** a white background, a "powered by SolRegia" caption, and a "Starting LDGR…" line.
- **In the header:**
  - a wordmark without ledger lines;
  - the two patches with a gap between them;
  - "Urgent Care" as large as "LDGR";
  - full-strength and 85 % opacity.
