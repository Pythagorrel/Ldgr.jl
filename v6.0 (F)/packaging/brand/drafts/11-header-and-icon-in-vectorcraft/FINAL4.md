# LDGR header and icon, final4 (VectorCraft is the source; final3 untouched)
## What came into VectorCraft
- header-ldgr.svg and header-urgentcare.svg opened as separate documents and came in whole, no warnings: paper texture as one embedded Image, a Clip Group with the rounded-rect clip (r 4.5), rules and verticals as compound paths, outlined letters as a compound path, the 1 px edge path. Nothing had to be rebuilt.
- Check: VectorCraft @3x of the unmodified LDGR patch vs final3's Chrome @3x: same size, mean per-channel difference 0.42/255 (edge anti-aliasing only).
- All 10 icon SVGs opened with no warnings and no rebuild. The pair (218x49) is a third document: file.place (link:false) of the two saved patch documents at x 0 and x 115 (7 px gap); inspect confirmed bounds 0..108 and 115..218.
## LDGR weight fix (only the letters changed; patch size, cascade, rules untouched)
- Letters: fill #1F6F5C -> #175649 (accent-dk) and a same-colour stroke #175649, 0.45 px, round join and cap.
- Urgent Care keeps its white 0.3 px stroke, unchanged.
- Judged at 125 % in the real header (preview/pair4-1.25.png): LDGR is clearly readable and holds its own beside Urgent Care; before (pair-1.25.png) it was faint. Ink metric rose about 30 % (0.40 px stroke) with the darker colour; 0.45 is the top of the suggested range.
## Files (final4/header, PNG RGBA transparent outside patches; px)
- header-ldgr@1x/1.25x/1.5x/2x/3x: 108x49, 135x61, 162x74, 216x98, 324x147
- header-urgentcare@...: 103x49, 129x61, 155x74, 206x98, 309x147
- header-pair@...: 218x49, 273x61, 327x74, 436x98, 654x147
- header-ldgr.svg, header-urgentcare.svg, header-pair.svg (outlined, viewBox = patch size, texture embedded); header-ldgr/urgentcare/pair.vectorcraft
- (1.25x and 1.5x heights round up to whole pixels: 61.25 -> 61, 73.5 -> 74)
## Files (final4/icon)
- ldgr-icon-N.vectorcraft and ldgr-N.png for N = 16 20 24 32 40 48 64 96 128 256 (each exactly NxN, scale 1)
- ldgr.ico (10 entries, PNG-compressed, 160,834 bytes; read back: 16..256, 32 bpp, 256 stored as 0), favicon.ico (16/32/48, 6,953 bytes)
- icon-sizes.png, icon-taskbar.png (final3's previews.py, composes PNGs only), MakeIco.ps1, previews.py
## Header markup (unchanged geometry; use the new 2x PNGs)
<h1 style="line-height:0;display:flex;gap:7px"><img src="header-ldgr@2x.png" width="108" height="49" alt="LDGR"><img src="header-urgentcare@2x.png" width="103" height="49" alt="Urgent Care"></h1>
- Preview: preview/pair4.html with header-ldgr4@2x.png, header-urgentcare4@2x.png; screenshots pair4-1.png, pair4-1.25.png, pair4-1.5.png.
## Icon comparison verdict
- VectorCraft's renders match final3's: mean diff 0.4 to 1.7 (of 255) from 40 px up, 3.1 to 3.8 at 20/24/32, 8.8 at 16 (corner/edge anti-aliasing). Side-by-side at 8x for 16-48: no visible difference.
- Crispness (mean edge gradient, new vs old): 16 78.7 vs 69.8, 20 71.8 vs 70.3, 24 63.0 vs 61.7, 32 52.8 vs 53.0, 40 45.9 vs 45.1, 48 38.6 vs 38.6, 64 and above equal within 2 %. None softer, so no adjustment was needed.
