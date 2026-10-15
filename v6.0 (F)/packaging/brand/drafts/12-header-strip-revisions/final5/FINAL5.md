# LDGR header, final5: one continuous strip, 184x49 (final3/final4 untouched)
## Geometry (1 px = 1 CSS px)
- One rounded rect, r 4.5 on the four outer corners only; junction square. Both textures and all rules clipped to their own part.
- Off-white part x 0..101 (final4 LDGR G1, letters #175649 + 0.45 stroke, left double rule at 5/8 unchanged). Green part x 101..184 (G2 texture #1F6F5C, white).
- Shared double rule: left line x 99..100 #1F6F5C 36% (on off-white); right line x 102..103 white 36% (on green). 2 px gap, colour boundary at x 101 (middle of the gap).
- Right double rule of the green part at x 176 and 179 (W-9, W-6). Rules every 8 px at y 4,12..44, 1 px: #1F6F5C 25% left, white 25% right, same y across the junction.
- Edge hairline 1 px inside: #E3E0D8 round the off-white part, #175649 round the green part, open at x 101 (no line on the junction, butt ends meet).
## Urgent Care
- Petit Formal Script 13.6 px (x-height 0.588 = 8 px = one pitch; LDGR is 20.36 px), white, 0.3 px white stroke kept (letters look faint without it).
- "Urgent" baseline y 20.5, "Care" baseline y 36.5 (both on rules; lowercase sits between two rules, caps rise into the row above). g descender (to ~24.5) clears Care's C top (~25.8). Ink block 9.8..36.5, centre 23.2 vs strip centre 24.5.
- Urgent ink is 48.5 px wide, centred between the lines at x 103 and 176 (12 px margins each side). "Care" (31.2 px) is centred then placed with its left edge 7 px right of Urgent's left edge, a small cascade echo (true centre would be 8.65).
## Files (header/, PNG RGBA, transparent outside the strip)
- header@1x 184x49, @1.25x 230x61, @1.5x 276x74, @2x 368x98, @3x 552x147
- header.svg (outlined text, textures embedded, 184x49 viewBox), header.vectorcraft (opened from the SVG in VectorCraft; its @3x export is identical to the Chrome one), build.py (generator, env vars S, M, CARE_DX, BU, BC)
- Preview: ../preview/strip5.html, header5@2x.png, strip5-1.png, strip5-1.25.png, strip5-1.5.png
## Markup
<h1 style="line-height:0;margin:0"><img src="header5@2x.png" width="184" height="49" alt="LDGR Urgent Care"></h1>
## Checked
Junction seamless at 3x and at 1.25 (no seam, gap or doubled edge); shared rule reads as one pair in two colours; rules align; Urgent Care legible at 1.25 and clearly secondary.
