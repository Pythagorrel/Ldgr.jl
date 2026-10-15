# LDGR brand finals (plain ledger lines, Source Serif 4 SemiBold). 1 pt = 1 CSS px.
Colours: ink #1C2521, ink-soft #5B6660, accent #1F6F5C, cream #FAF9F6, white #FFFFFF. Document: ldgr-brand.vectorcraft (10 named artboards).

## Master logo (art 615.11 x 388.96 = rules + 0.25 H pad; H = 110 pt cap height)
- ldgr-logo.svg (viewBox 0 0 615.11 388.96, outlined, transparent); ldgr-logo-2000w/1040w/520w.png = 2000x1265, 1040x658, 520x329.
- Letters #1C2521 in front; every rule 0.014 H, accent #1F6F5C at 35% (backdrop rows, cap/baseline rules, waist). No solid highlight segments.
- Waist rule: 6 plain rectangles (x 320-395.9, 426-492.5, 522.7-559.1, 625.4-649.6, 705.3-721.7, 794-880.1 in the 1200-wide design space), measured from the outlined letters at +-4.4 pt (0.04 H) both across and vertically; none < 0.08 H. No nibs.

## Startup (startup-banner.svg, @1x 552x376, @1.25x 690x470, @1.5x 828x564, @2x 1104x752, transparent)
- Logo scaled to 520 px wide (84.538 %) at x 16, y 16. Caption "powered by SolRegia" 16 px, centred on x 276: "powered by" Italic #5B6660, "SolRegia" SemiBold #1C2521, ink gap 4.4 px. Baseline y 354.29 (cap top 22 px under the lowest rule at y 321.57).
- startup-preview.png / startup-preview-failure.png: 1920x1080 (artboard 1536x864 at 1.25). Banner top-left at (492, 182.5), so word centre = 42 % of height (y 363). Caption baseline y 536.8. Status baselines: "Starting LDGR..." Segoe UI 14 #5B6660 centred, y 592.8 (56 below the caption baseline). Failure: line 1 Segoe UI 15 #1C2521 y 592.8, line 2 (path) Segoe UI 13 #5B6660 y 616.8 (24 below). Nothing moves; there is room for more lines down to y ~700.
- Launcher: draw the banner PNG so its top is 182.5 css px (word centre at 0.42 of window height; scale all by DPI), centred horizontally; status line baseline = banner top + 410.8 css px (caption baseline + 56). Status text is live Segoe UI.

## Closing (transparent PNGs @1x/@1.25x/@1.5x/@2x; 16 px padding)
- closing-c1: "Closing..." Source Serif 4 Regular 44 px #5B6660. @1x 212x76, @1.25x 265x95, @1.5x 318x114, @2x 424x152.
- closing-c1-preview.png: 1920x1080 white. Word centred, cap-height midpoint at y 362.9 of 864 (42 %), baseline y 377.6. To place in the launcher: image centre at 42 % height (the images are not vertically symmetric about the cap line: baseline is 49.0 px below the top in c2; place by the previews).

## Form header options (plain ledger lines, no green segments; header2 set, not part of ldgr-brand.vectorcraft)
All: Source Serif 4 SemiBold outlined, letters #1C2521 in front; every rule #1F6F5C at 50% opacity, 1 px thick, on whole-pixel positions. Files: w1/w2/w3.svg (transparent) and w{1,2,3}@1x/@2x/@3x.png.
- W1 (recommended): cap 18, row pitch 9, 1 backdrop row each side. SVG 95x40; PNG 95x40, 190x80, 285x120. Cap/baseline rules run 0.6 H (10.8 px) past the word; backdrop rows 0.075 H past it.
- W2: cap 20, pitch 10, 1 row each side. SVG 105x44; PNG 105x44, 210x88, 315x132.
- W3: cap 16, pitch 8, 2 rows each side (second row 0.425 H inside the word ends). SVG 85x52; PNG 85x52, 170x104, 255x156.
- Waist rule: cut from the logo's fragments with at least 1.5 px to the ink; pieces under 3 px dropped (4 pieces each: two outer tails, two in the L-D and D-G gaps). Barely perceptible at this size.
- Use: <img src="w1.svg" width="95" height="40" alt="LDGR">, CSS gap 12 px, hairline 1x26 px, align-items:center; "Urgent Care" stays live Segoe UI.
- Ranking from the header study: W1 (smallest block, closest to today's 38 px), W3 (closest to the logo silhouette, smallest letters), W2 (biggest letters, reads a little like over/underline).

## Changed from the brief, and why
- Banner artboard is 376 px tall, not 374: so @1.25x is a whole 470 px.
- Waist clearance is applied to a band thickened by 4.4 pt above and below (true 0.04 H clearance, so the G bar and R bowl are not touched); this gives 6 fragments.
- H2 letter gap is 3.0 px (logo: 2.2 px at this size) so the bar gaps reach 2 px.
- Closing size was unspecified: 44 px.
- SVGs: VectorCraft writes off-artboard objects of the same document into every SVG; those were stripped, leaving only the art in the viewBox.
- Status texts in the previews are live-font mockups only (rendered, not shipped).
- Plain-lines version: the four solid-accent highlight paths (logo, banner, both startup previews) were deleted from the document; the 35% rules are untouched. Closing-c1 files are copied unchanged from final/. closing-c2 and the header-h1/h2 rounded-square files are not part of this set.
