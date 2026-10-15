# LDGR header patches and app icon (pass 2). 1 pt = 1 CSS px. Made with Python (fontTools outlines + numpy texture) and rendered in headless Chrome; VectorCraft was not needed.
## Header files (header/), PNGs RGBA, transparent outside the patches
- header-ldgr@1x/@2x/@3x.png: 108x49 / 216x98 / 324x147. header-urgentcare@1x/2x/3x: 103x49 / 206x98 / 309x147.
- header-pair@1x/2x/3x: 218x49 / 436x98 / 654x147 (gap 7).
- header-ldgr.svg, header-urgentcare.svg, header-pair.svg: outlined text, texture embedded (PNG data URI), clipped to the curve. PNGs were rendered from these SVGs in Chrome.
- gen_header.py, common.py, cfg.json = sources ({"indent":8,"g2stroke":0.3}).
## Geometry
- Font Petit Formal Script 20.36 pt (cap 16, pitch 8). Rules 1 pt every 8 px, pixel aligned; verticals 1 pt at x=5,8 and W-9,W-6; radius 4.5, 1 pt edge following the curve.
- Patch 1: G1 (paper #FDFCF9 + grain, rules #1F6F5C 25%, verticals 36%, edge #E3E0D8), cascade L D G R, baselines 20.5/28.5/36.5/44.5.
- Patch 2: G2 (paper #1F6F5C + grain, edge #175649, rules/verticals white 25%/36%), white letters. "Urgent" baseline 20.5, "Care" baseline 44.5 (both on a rule, three rows apart so the g descender clears Care).
  Both words use the same size as LDGR. "Care" is indented 8 px (one pitch) to echo the cascade; "Urgent" fills the width between the double rules with equal 15 px side margins.
- Heights are identical (49 px) by construction. Width 103 is set by "Urgent".
## Header markup (checked in preview/pair.html; 2x PNGs, which Chrome scales to 1.25/1.5)
```html
<h1 style="line-height:0;display:flex;gap:7px">
  <img src="header-ldgr@2x.png" width="108" height="49" alt="LDGR">
  <img src="header-urgentcare@2x.png" width="103" height="49" alt="Urgent Care">
</h1>
```
The live "Urgent Care" text and the hairline are removed. Screenshots: preview/pair-1.png, pair-1.25.png, pair-1.5.png (and -crop files).
## Icon files (icon/)
- ldgr-{16,20,24,32,40,48,64,96,128,256}.png (square, RGBA) and ldgr-icon-N.svg; ldgr.ico (all 10, 158,952 bytes), favicon.ico (16/32/48). PNG-compressed entries, 0 for 256.
- MakeIco.ps1 (Windows PowerShell, same layout as WriteIco in MakeIcon.cs, but PNG for every size). gen_icon.py + tune.json = sources; previews.py.
- icon-sizes.png (1x on #F3F3F3 and #202020), icon-taskbar.png (24 and 32 among tiles, light and dark; 620x100).
- Corner radius 20% of size; edge hairline follows it. L is Petit Formal Script, centred, and kept between the inner vertical rule and the margin.
## Small-size tuning (each drawn at its exact size, pixel-aligned rules)
| size | texture | verticals | rules | L width | L colour / stroke |
|---|---|---|---|---|---|
| 256/128 | yes | double | all, 22% | 58% | #1F6F5C, none |
| 96/64 | yes | double | all, 24-25% | 60% | #1F6F5C, +0.15 / +0.3 px |
| 48 | yes | double | all, 24% | 59% | #1B6755, +0.45 px |
| 40 | none | double | all, 26% | 61% | #175649, +0.6 px |
| 32 | none | single | all, 28% | 70% | #175649, +0.75 px |
| 24 | none | single | baseline only, 35% | 68% | #175649, +0.9 px |
| 20 | none | single | baseline only, 35% | 62% | #175649, +0.95 px |
| 16 | none | none | baseline only, 38% | 76% | #175649, +1.0 px |
Edge hairline darkens at small sizes (#BCC7BF / #B8C4BC) so a pale tile does not vanish on the light taskbar.
## Changed after looking
- Header: G2 letters got a 0.3 px white stroke (Petit Formal's hairlines were thin at 1.25); "Care" indented.
- Icon: first pass had verticals cutting through the L at 16-40 and rules too strong. L width is now limited to the space inside the verticals; 16 drops the verticals (an 8 px gap was too small); rules lowered at small sizes.
## Honest verdicts
- Header at 1.25: "Urgent" and "Care" legible; hairlines are thin at 1x but readable.
- Icon: 32 and 24 read as a script L; 16 reads as an L but its foot is a heavy blob (stroke + baseline rule) and texture and ruling are gone.
