# Cursive specimen, cascade layout, colourway G1 (2026-10-08)
Layout per the owner: two mirrored double rules, no money columns, no heading band (not needed: the double rules + ruling
already read as a ledger), letters cascade one row (p) per letter, each baseline on its own rule, cap top on the rule two above.
Patch = half a row above L's cap top to half a row below the lowest ink. Ink behind-ordered: texture, rules, letters on top.
Fonts all "exact" (text.rescanFonts was needed first: the script fonts were installed after VectorCraft started).

## Measured (fractions of font size, from glyph outlines; word extents checked against VectorCraft outlines)
| font | cap L | tallest cap | x-height | d ascender | pitch p = tallest cap / 2 | caps touching the rule two above |
|---|---|---|---|---|---|---|
| Petit Formal Script | .786 | .786 | .588 | .836 | .393 | L D G R (all equal) |
| Dancing Script | .720 | .720 | .332 | .720 | .360 | L D G R (all equal) |
| Parisienne | .712 | .725 | .353 | .655 | .362 | G (L, R 3%, D 2% of a row short) |
| Italianno | .546 | .549 | .265 | .612 | .275 | D, G (L, R 1% short) |
| Rouge Script | .665 | .671 | .340 | .550 | .336 | G, L (D 7%, R 5% short) |
| Great Vibes | .791 | .822 | .357 | .629 | .411 | G only (others 8% short) |
| Alex Brush | .679 | .679 | .416 | .485 | .340 | L only (D 13%, G 11%, R 16% short) |
| Pinyon Script | .684 | .703 | .334 | .779 | .352 | G only (others 5-8% short) |
Ldgr: pitch uses the same caps; d pokes ABOVE the cap rule in Petit Formal (+.05 em), Italianno and Pinyon (d taller than L), so there the
d, not L, is the tallest letter; g and r fill one row only.
Sizes: logo word extent 380 pt wide (size 95-218 pt, p 34-73 pt); header cap height 16.0 pt (size 19.5-29 pt, p = 8.0 pt, patch 83-125 x 48-51 pt).

## Colourway G1 (primary) - final values
- Paper: textured PNG baked in, mean #FDFCF9 (R253 G252 B249), grain sigma about 8 levels, low-frequency blotch removed (it read as dirt on off-white).
- Hairline edge #E3E0D8 (1.5 pt logo, 1 pt header). Page behind: #FAF9F6.
- Horizontal rules #1F6F5C at 22% (logo, 1.25 pt) / 25% (header, 1 pt). Double verticals #1F6F5C at 34% (1 pt) / 36% (0.8 pt header).
- Double rule gap 4 pt logo, 3 pt header; inset from edge 0.35 p logo, 0.6 p header; word starts 0.7 p / 0.9 p after the double rule.
- Letters #1F6F5C (accent). accent-dk #175649 was tried: crisper on thin header strokes, marginally heavier at logo size. Either works; kept accent so
  the mark matches the form's green square; switch to #175649 if the header ever looks faint.
## Colourway G2 (alternative)
- Paper #1F6F5C baked texture, sigma about 6 levels; edge #175649; rules white at 22% / 25%, verticals white at 34% / 36%; letters #FFFFFF.
- Reads as a green cloth book, strong echo of the green square mark; at header size it is the more visible patch, but it is a dark block beside the
  light form. G1 sits quietly in the page. Recommendation: G1 for the header, G2 only if a bolder startup screen is wanted.

## Ranking, cascade LDGR
Header at real size (16 pt caps, 1.25x): 1 Dancing Script (sturdiest strokes, caps instantly L-D-G-R), 2 Petit Formal Script, 3 Italianno, 4 Rouge Script;
then Parisienne (G reads like a J/S at 20 px), Great Vibes (G and R crowd), Alex Brush, Pinyon (hairlines vanish, G is a stroke).
Logo: 1 Dancing Script, 2 Petit Formal Script (calmest, most clerk-like), 3 Italianno, 4 Rouge Script, 5 Parisienne, 6 Great Vibes, 7 Alex Brush, 8 Pinyon.
## LDGR or Ldgr
LDGR reads better in every font: the cascade of four capitals is the strongest diagonal and its letters are all clear. Ldgr cascades less evenly
(g and r are short, the word is narrow, so the patch gets very tall and big for a given width). Ldgr is best in Dancing Script and Rouge Script (open d, g).
Italianno's Ldgr is weakest (d leans, g detaches). Use LDGR for the mark.
## Honest notes
- Selective match is exact only in Petit Formal and Dancing; elsewhere the tallest cap kisses and the others fall 1-16% of a row short, which is the
  intended "only some letters" effect, not an error.
- Rules do cross lower parts of letters (cascade makes that unavoidable); they are faint and behind the ink. No letter touches a vertical rule.
- Spacing: ink-box gap 0.03 em between consecutive letters; no collisions seen, but G/R in Great Vibes and Alex Brush come close.
- Not done: step = p/2 variant board; the M1/M2 yellow-paper boards were superseded. Header in place: cascade-header-inplace.png (screens at 1.25 on the real gradient).
## Files
cascade-logo.png (8 fonts LDGR), cascade-logo-ldgr.png (top 4, Ldgr), cascade-header.png (2x), cascade-header-1.25x.png, cascade-header-inplace.png,
colourways.png (G1 | G2, logo and header size), paper-cascade.html (in-place page), *.vectorcraft (specimen = 8-font logo board, specimen-header-g1, specimen-ldgr-g1, colourways).
