# LDGR brand finals (V2 "Highlighted cells", Source Serif 4 SemiBold). 1 pt = 1 CSS px.
Colours: ink #1C2521, ink-soft #5B6660, accent #1F6F5C, cream #FAF9F6, white #FFFFFF. Document: ldgr-brand.vectorcraft (10 named artboards).

## Master logo (art 615.11 x 388.96 = rules + 0.25 H pad; H = 110 pt cap height)
- ldgr-logo.svg (viewBox 0 0 615.11 388.96, outlined, transparent); ldgr-logo-2000w/1040w/520w.png = 2000x1265, 1040x658, 520x329.
- Letters #1C2521 in front; per-letter cap/baseline cells solid accent 0.022 H; all other rules 0.014 H accent at 35% (backdrop rows, faint cap/baseline rules).
- Waist rule: 6 plain rectangles (x 320-395.9, 426-492.5, 522.7-559.1, 625.4-649.6, 705.3-721.7, 794-880.1 in the 1200-wide design space), measured from the outlined letters at +-4.4 pt (0.04 H) both across and vertically; none < 0.08 H. No nibs.

## Startup (startup-banner.svg, @1x 552x376, @1.25x 690x470, @1.5x 828x564, @2x 1104x752, transparent)
- Logo scaled to 520 px wide (84.538 %) at x 16, y 16. Caption "powered by SolRegia" 16 px, centred on x 276: "powered by" Italic #5B6660, "SolRegia" SemiBold #1C2521, ink gap 4.4 px. Baseline y 354.29 (cap top 22 px under the lowest rule at y 321.57).
- startup-preview.png / startup-preview-failure.png: 1920x1080 (artboard 1536x864 at 1.25). Banner top-left at (492, 182.5), so word centre = 42 % of height (y 363). Caption baseline y 536.8. Status baselines: "Starting LDGR..." Segoe UI 14 #5B6660 centred, y 592.8 (56 below the caption baseline). Failure: line 1 Segoe UI 15 #1C2521 y 592.8, line 2 (path) Segoe UI 13 #5B6660 y 616.8 (24 below). Nothing moves; there is room for more lines down to y ~700.
- Launcher: draw the banner PNG so its top is 182.5 css px (word centre at 0.42 of window height; scale all by DPI), centred horizontally; status line baseline = banner top + 410.8 css px (caption baseline + 56). Status text is live Segoe UI.

## Closing (transparent PNGs @1x/@1.25x/@1.5x/@2x; 16 px padding)
- closing-c1: "Closing..." Source Serif 4 Regular 44 px #5B6660. @1x 212x76, @1.25x 265x95, @1.5x 318x114, @2x 424x152.
- closing-c2: SemiBold 44 px #1C2521, H = 29.48 px. Faint cap/baseline rules 0.014 H at 35 % accent, 0.6 H beyond the ink; solid highlights 0.022 H spanning ink +0.05 H; no backdrop or waist. @1x 252x76, @1.25x 315x95, @1.5x 378x114, @2x 504x152.
- closing-c1-preview.png / closing-c2-preview.png: 1920x1080 white. Word centred, cap-height midpoint at y 362.9 of 864 (42 %), baseline y 377.6. To place in the launcher: image centre at 42 % height (the images are not vertically symmetric about the cap line: baseline is 49.0 px below the top in c2; place by the previews).

## Form header (cream #FAF9F6 page)
- header-h1.svg + header-h1-38/-76/-114.png (38/76/114 px square, transparent outside): rounded square r 11 #1F6F5C; "L" SemiBold 24.1 px (cap 16 px), cream, baseline y 27, ink x 12.77-25.2 (centred at 19); cream bars 16.46 x 1.5 at y 9.5-11 and 27-28.5 (L ink +2 px each side). Placed where the square is now; keep the live Segoe "LDGR"/"Urgent Care" text beside it, or drop "LDGR" (the L alone does not say LDGR).
- header-h2.svg + header-h2@1x/@2x/@3x.png (92x30, 184x60, 276x90, transparent): "LDGR" SemiBold 33.13 px (cap 22 px), letter ink gap 3.0 px, ink spans x 2.0-90.0; accent bars 1.5 px at y 2.5-4 (cap line y 4) and 26-27.5 (baseline y 26), each letter ink +0.5 px, 2.0 px apart. Replaces the square and the Segoe "LDGR"; align image baseline (y 26 of 30) with the caption's text line; "Urgent Care" stays live Segoe UI beside/below.

## Changed from the brief, and why
- Banner artboard is 376 px tall, not 374: so @1.25x is a whole 470 px.
- Waist clearance is applied to a band thickened by 4.4 pt above and below (true 0.04 H clearance, so the G bar and R bowl are not touched); this gives 6 fragments.
- H2 letter gap is 3.0 px (logo: 2.2 px at this size) so the bar gaps reach 2 px.
- Closing size was unspecified: 44 px for both. The C2 highlights are 0.65 px thick as specified, so they are faint at 1x.
- SVGs: VectorCraft writes off-artboard objects of the same document into every SVG; those were stripped, leaving only the art in the viewBox.
- Status texts in the previews are live-font mockups only (rendered, not shipped).
