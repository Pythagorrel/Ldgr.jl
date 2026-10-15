# LDGR final brand, pass 1 (logo, startup, closing). 1 pt = 1 CSS px. All PNGs are RGBA, transparent where noted.
## Files (pixel size)
- ldgr-logo@1x/@1.25x/@1.5x/@2x.png: 471x238 / 588x297 / 706x357 / 941x475. Clean patch, no shadow, tight, transparent corners.
- ldgr-logo-2000w.png 2000x1010 (clean). ldgr-logo.svg 470.53x237.74 (outlined letters, texture embedded; corners transparent).
- startup-banner@1x/@1.25x/@1.5x/@2x.png: 519x286 / 648x357 / 778x429 / 1037x571. Patch + shadow + 24 px transparent padding
  (518.53x285.74 pt). This is also "the version with the shadow" (no separate ldgr-logo-shadow PNG).
- startup-preview.png, startup-preview-failure.png, closing-preview.png: 1920x1080 (1536x864 artboard at 1.25), bg #FAF9F6.
- closing@1x/@1.25x/@1.5x/@2x.png: 194x74 / 242x92 / 290x110 / 387x147. Transparent, 16 px padding (32 px at 2x).
- Sources: ldgr-logo.vectorcraft (clean), ldgr-logo-shadow.vectorcraft (banner), startup-preview[-failure].vectorcraft,
  closing-preview.vectorcraft (outlined text, no bg), tex-g1.png + tex.py (paper texture generator).
## Patch geometry (pt, origin = patch top-left; patch 470.53 x 237.74)
- Font Petit Formal Script 100.04 pt; baselines/left of L D G R: L (45.26,98.24) D (136.53,137.54) G (232.64,176.84) R (322.10,216.14).
  Pitch p = 39.3 (0.393 x size); each baseline on its own rule; identical to the specimen.
- Horizontal rules y = 19.65, 58.95, 98.24, 137.54, 176.84, 216.14, full width, 1.25 pt #1F6F5C at 22%.
- Vertical double rules x = 13.75, 17.75 and 452.78, 456.78 (mirrored), 1 pt #1F6F5C at 34%, y 0.5..237.24.
- Letters #1F6F5C. Paper texture: mean #FDFCF9 (253,252,249), grain sigma ~5 levels + faint horizontal fibres, 2048x1035 px, clipped to the rounded rect.
- Hairline edge #E3E0D8, 1.5 pt, inset 0.75 pt (rect 0.75..469.78, radius 15.75). No letter touches a vertical rule.
## Rounded corners
- Radius 16.5 pt (3.5% of 470.53 wide). Texture alpha is the rounded rectangle (4x supersampled), hairline follows it; outside is transparent.
## Shadow (screens only, banner/startup)
- Two layered VectorCraft drop shadows on a rounded rect under the patch, colour #1C2521, normal blend:
  (x0 y1 blur2 opacity 5%) and (x0 y8 blur14 opacity 9%). Approximates CSS 0 1px 2px .04 + 0 8px 24px -12px .10 (VectorCraft has no spread).
  In CSS for the launcher, use the form's own: box-shadow: 0 1px 2px rgba(28,37,33,.04), 0 8px 24px -12px rgba(28,37,33,.10).
## Startup screen (1536x864 CSS px, fill #FAF9F6)
- Patch (470.53x237.74) centred horizontally: left 532.74, top 244.11 (optical centre 42% = 362.98), bottom 481.85.
  Banner PNG (with 24 padding) is placed at left 508.74, top 220.11 at 518.53x285.74 pt.
- Status line: Segoe UI 14 px #5B6660 centred (x 768), "Starting LDGR…" (U+2026), baseline y 540 (cap top ~48 px below patch bottom).
- Failure: line 1 Segoe UI 15 px #1C2521 "LDGR could not start. Please contact the technician.", baseline y 540, centred;
  line 2 Segoe UI 13 px #5B6660 "C:\LDGR\logs\LDGR 2026-10-08.log", baseline y 564, centred. Patch unchanged.
## Closing screen
- "Closing…" Petit Formal Script 38 pt (cap height 29.9 px), #1F6F5C, plain. Ink box centred at x 768, y ~362.9 (same optical height as the patch).
- The ellipsis glyph in Petit Formal reads fine (three tight dots), so U+2026 is kept.
## Notes
- 1x banner/logo pixel sizes round up from fractional points (518.53 -> 519). For crisp edges, draw at 2x and let WebView2 downscale.
- SVG: the exporter wrote the embedded texture scale as 0.23 (0.5 pt too wide); patched to 0.2297 in ldgr-logo.svg. Rendered in headless Chrome and checked.
