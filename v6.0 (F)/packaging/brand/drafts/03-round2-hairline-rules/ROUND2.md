# LDGR logo round 2: Source Serif 4 SemiBold only (scope cut by the owner's choice)

Files: V1|V2|V3-serif.png (artboards, 2400x1280), V*-serif-close.png (scale 4), V*-serif-logo.png (transparent, scale 2),
round2.vectorcraft (artboards 1, 3, 5 of 6 are empty Piazzolla boards, left untouched; the drawn ones are 0, 2, 4), gen2.js/geom2.json (geometry).
Font confirmed `text.fonts` = exact, SemiBold. H = 110 pt (size 165.66), letter ink gap 0.1 H, pitch p = H/2, letters #1C2521.

## Weights and clearances used (no deviation from the brief)
- Landmark rules 0.022 H = 2.42 pt, accent 100%. Backdrop rules 0.014 H = 1.54 pt, accent 35%. Weight ratio to the serif slab (0.071 H): 3.2:1.
- Cap rule's bottom edge on the cap height, baseline rule's top edge on the baseline, both continuous, behind the letters.
- Waist rule at B - H/2, knocked out with offsetPath 0.04 H (4.4 pt, round joins) of the united letter outlines, minusBack.
- Landmarks run 0.6 H past the word; backdrop 2 rows above the cap rule and 2 below the baseline rule at pitch H/2 from the rules' centres,
  each row 0.5 H shorter at both ends. No vertical rules except the margin.
- V1 margin: 2 hairlines of 0.014 H, gap 0.03 H, #A63D40 at 70%. Interpretation: 0.5 H left of the word (inside the 0.6 H lead-in), spanning the cap, waist and
  baseline rules, because nothing exists at 0.5 H left of the rules' own left end.
- V2: every rule 0.014 H at 35%; each letter's cap/baseline cell re-drawn 0.022 H solid. Cell = ink + 0.25 x gap each side (not 0.5 x gap, which
  would make neighbouring cells touch and remove the faint gaps the brief wants): visible faint gap 0.05 H. Waist faint, knocked out. No margin.
- V3: V1 without margin; both lower backdrop rows replaced by a double underline, 2 x 0.022 H, gap 0.05 H, centred one pitch below the baseline,
  word + 0.15 H each side. Upper backdrop kept.

## What I fixed after looking
- Measured the knock-out before rendering: the D-G gap (2.2 pt wide) left a sliver; deleted. Seven fragments remain per waist rule: left lead-in, L's open side, D counter (36 pt),
  G counter (25 pt), G-R gap (16 pt), R's right side. Counter pieces were kept deliberately (they read as the ruled line seen through the counter).
- Stacking: letters brought in front of all rules after the first look showed rules over the glyph edges.
- Scale-4 close-ups: no rule crosses ink, no specks, cap/baseline rules touch the letters (no gap, overlap only at G overshoot and R leg, 0.02 H).
  Clearance looks even (4.4 pt both sides of every stem). Not fixed: tiny nibs where the waist meets the G bar corners and the R bowl; they are the keep-out arc meeting the rule.
- A first selection mix-up (offsetting letters of the wrong artboard) was undone and redone; no effect on the output.

## Honest ranking of the 3 (Source Serif only)
1. V2 Highlighted cells: closest to the owner's "selectively highlighted by the lines"; quietest, rules never shout; but at 38 pt the highlights vanish.
2. V1 Between the lines: clearest "entry on a ruled row"; the margin is now discreet; the waist knock-out pieces read as dashes (busy at mid size).
3. V3 The total: the double underline is the strongest idea and reads at small sizes, but it is a different message (a sum, not an entry) and the two rules below look heavy.

## 38 pt header version of the top pick (V2)
Keep: the four letters, cap and baseline rules drawn once at about 0.03 H solid (1 px at 2x) as per-letter highlights, and the faint continuous cap/baseline rules.
Drop: the waist rule (it is a 0.3 pt dash line), all four backdrop rows, the extension lead-ins past the word beyond 0.3 H.
