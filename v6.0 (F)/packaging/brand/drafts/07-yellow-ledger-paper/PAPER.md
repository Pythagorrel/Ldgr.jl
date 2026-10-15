# Ledger paper patch (placeholder word: Segoe Script "LDGR", ink #1C2521)
Files: paper-header.vectorcraft (140x40 pt), paper-logo.vectorcraft (600x300 pt), p-header@1x/1.25x/2x.png (on #FAF9F6),
p-logo.png (on #FFFFFF), header-in-page.png (real header, 1.25x), make-grain.ps1 (run with Windows PowerShell 5.1: pwsh 7 lacks System.Drawing),
grain-512.png (header), grain-1024.png (logo), gen.js (prints the rule paths). Placed texture is EMBEDDED (link:false).
## Chosen look (variant A)
- Paper #F6F3DA, edge: inset hairline #DDD8B8 (1 pt header, 1.5 pt logo). No shadow; the hairline is enough.
- Logo only: column-heading band y 15-45 filled #FAF8E8 (between the first two rules).
- Horizontals #C3CBB5, full width, equal length. Header 1 pt, pitch 10, at y 5.5/15.5/25.5/35.5. Logo 1.25 pt, pitch 30, y 15..285.
- Verticals #B5AE93, full height. Header 0.8 pt, logo 1 pt.
- Column x as fraction of patch width: HEADER left double .075/.100 (gap 3.5 pt); money group double .800/.820, thin .89, .94.
  LOGO left double .060/.0667; money group 1 double .690/.697, thin .745, .800; group 2 double .855/.862, thin .905, .950.
  Particulars zone: header x .14-.79 (19-110 pt); logo x .07-.68 (42-410 pt). Date column and row-number column left out.
- Texture: grain PNG (mid-grey 128, sigma ~12 fine noise + faint low-frequency blotch + horizontal fibre streaks, tileable), placed over
  the paper, clipped by a patch-sized rectangle (object.clippingMask.make), blend overlay (transparency.set blend:"overlay") at 50 %.
  Survives export; felt, not seen; the header stays clean (no grey cast). Order: fill, (band), texture, horizontals, verticals, word.
## Tried and rejected
- #F2EDC6 with texture 75 %: reads dirty/mustard, like a highlighter. #F8F5E1: nearly vanishes on #FAF9F6 (only the rules show it).
- Texture at 40 % is almost invisible at 1x; 50 % is the minimum that reads on the 2x export.
- pwsh 7 cannot load System.Drawing; real VectorCraft has no noise effect, hence the PNG.
## Dropping the word on
- Baseline on a rule: header baseline y 25.5 (third rule), left edge x ~26 (past the left double rule at 14). Logo baseline y 195 (rule 7), left edge x ~86.
- Placeholder cap height about 15 pt header / 70 pt logo (hand ~ 2 rows high). Keep the word's right end left of the first money-group double rule
  (header x 112, logo x 414) so no vertical crosses a letter; the placeholder, scaled to 307 pt wide, ends at about 393 in the logo, 70 pt wide, ending x ~97 in the header
  (room left in the header: about 15 pt).
- Retune pitch to the font: change the `ys` in gen.js (and verticals if the word is wider), regenerate, redraw the two paths.
