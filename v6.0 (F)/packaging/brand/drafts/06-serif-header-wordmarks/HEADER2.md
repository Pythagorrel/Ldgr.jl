# Header wordmark W1-W3 (plain ledger lines, no green segments, per the coordinator's later change)
All: Source Serif 4 SemiBold outlined, letters #1C2521 in front; every rule is #1F6F5C at 50% opacity, 1 px thick, on whole-pixel positions.
Built by gen.js from the outlined letters of ldgr-logo.svg (scaled by cap/110); SVGs transparent; PNGs w{1,2,3}@{1,2,3}x.png via VectorCraft.
- W1: cap 18, row pitch 9, 1 backdrop row each side. SVG 95x40. Cap/baseline rules run 0.6 H (10.8 px) past the word; backdrop rows 0.075 H past it.
- W2: cap 20, pitch 10, 1 row each side. SVG 105x44.
- W3: cap 16, pitch 8, 2 rows each side (second row 0.425 H inside the word ends). SVG 85x52 (under the 56 limit).
- Waist rule: cut from the logo's fragments, with extra trim so the gap to ink is at least 1.5 px; pieces under 3 px dropped (W1/W2/W3 each keep 4 pieces: two outer tails, two in the L-D and D-G gaps).
Rules sit just outside the cap top and baseline (as in the logo), so no rule touches ink except the G overshoot.
## What I changed after looking
- First built with 1.5-2 px solid green highlights; removed them all when the owner dropped them. Cap/baseline are NOT darker than the backdrop rows: at 1.0x the word did not float, so uniform 50%.
- 1.0x renders (header2-1x.png): rules stay crisp and visible, no grey fuzz. 1.25x/1.5x also fine (preview/header-w*-{1,1.25,1.5}.png).
- Honest caveats: the waist rule is barely perceptible at this size (only the L-D and D-G gaps and the tails show); it reads as "ruled page" mainly through the cap/baseline lines.
## Ranking
1. W1 - smallest block (40 px, close to today's 38), still clearly a ruled-page scrap.
2. W3 - closest to the full logo silhouette, but 52 px tall and the letters are the smallest (cap 16).
3. W2 - biggest letters, 44 px; one row each side looks a bit like underline/overline stripes.
## Pick: W1
<img src="header-w1.svg" width="95" height="40" alt="LDGR">  (copy w1.svg to the public folder under a name of your choice; keep CSS gap 12 px, hairline 1x26 px, align-items:center)
