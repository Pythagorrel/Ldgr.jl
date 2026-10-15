# LDGR logo concepts: ledger grid from letter measurements (2026-10-08)

Files: A|B|C-serif.png and A|B|C-piazzolla.png (2400x1280, white), concepts.vectorcraft (6 artboards),
MEASUREMENTS.md, gen.js (generator), geom.json, svg/ (rule layers). H = 110 pt. All rules are filled rectangles, so copies scale exactly.

## Measurements (fractions of cap height H; details in MEASUREMENTS.md)
| | Source Serif 4 SemiBold | Piazzolla SemiBold |
|---|---|---|
| stem (L, D, R) | 0.197 H | 0.186 H |
| thinnest stroke (serif slab) | 0.071 H | 0.061 H |
| bowl arm / thin stroke | 0.077 H | 0.117 H (low contrast) |
| waist (R bowl stroke centre) | 0.498 H | 0.476 H |
| G bar top | 0.483 H | 0.511 H |
| G overshoot | 0.026 H each side | 0.017 / 0.014 H |
The weight really applies (L stem Regular -> SemiBold: 0.142 -> 0.197 H and 0.123 -> 0.185 H). `text.fonts` says "exact" for all.

## Grid derived (same recipe for both fonts)
- Pitch p = H/2 for both. p = H/3 puts rules at 0.333 H and 0.667 H, 0.14+ H away from the waist, so it was rejected.
  Waist error: Source Serif 4 0.002 H (R) / 0.017 H (G bar); Piazzolla 0.024 H (R) / 0.011 H (G bar). Both are inside 0.04 H.
- Landmark rules (baseline, waist, cap line): accent, weight = the thinnest serif edge (Serif 0.071 H = 7.8 pt, Piazzolla 0.061 H = 6.7 pt), centred on the landmark, drawn behind the letters. Piazzolla's bowl arm (0.117 H) was too heavy to be a rule, so I used its serif edge.
- Landmark length: word width + 0.6 H each side. Backdrop: 2 rows above the cap line, 2 below the baseline, accent at 30% opacity, half the landmark weight, each step out loses 0.5 H at each end.
- Columns: backdrop rows only, at the L, D, R stem-left edges (A, B) or the cell edges (C); each runs only as far as the tapered rows allow.
- Tracking: letters placed one by one by their ink; even ink gap 0.1 H (about half a stem: one full stem looked too loose for serifs). C: letters centred in cells of 1.0 H (Source Serif, widest letter 0.95 H) or 1.125 H (Piazzolla, R is 1.03 H).
- Margin: red double rule 0.5 H left of the L in A and B (0.6 x landmark weight, gap 1.5 x). Not in C.
- A and C: accent double underline "total" on the first row under the baseline (0.7 x landmark weight each).

## What I changed after looking
Nothing. I looked at all six and found no defect worth a second pass in the time; the points below are findings, not fixes.
- Rules land on the landmarks: the waist rule passes through R's bowl stroke and G's bar in Source Serif; in Piazzolla it sits visibly a little low on R's bowl (the 0.024 H).
- The backdrop stays quiet and reads as part of the word, mostly because the columns line up with the stems. The landmark rules are heavy (7.8 pt) and dominate; halving their weight is the first thing to try.
- 38 pt copies: the word survives in A and C (cap height about 12.7 pt); the backdrop turns to grey fuzz, the margin is a smudge. B at 38 pt is mush.

## Ranking
1. **C Source Serif 4**: calmest, rules sit on the stems, letters and cells feel built together; cleanest at 38 pt.
2. **C Piazzolla**: same structure, the wider cell suits its wider letters; waist is slightly low.
3. **A Source Serif 4**: the clearest "one entry" idea and the best waist fit; the red margin is loud.
4. **A Piazzolla**: as A, with the 0.024 H waist error and a sturdier, less formal feel.
5. **B Source Serif 4**: lively, but letters crowd each other's serifs (D over L's foot) and the staircase has the most clutter.
6. **B Piazzolla**: same, slightly worse; unreadable as a header image.

## What each loses at header size (38 pt total height)
- A: drop the margin, the total double underline (becomes one line), all backdrop rows and columns; keep three landmark rules or only the baseline.
- B: drop everything except the cascade itself with a baseline segment under each letter; the whole backdrop and margin go.
- C: drop backdrop rows, columns and total; keep the three landmark rules, or only baseline + cap line.
