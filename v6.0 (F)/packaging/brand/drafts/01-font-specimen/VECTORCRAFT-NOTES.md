# VectorCraft notes (from the specimen board, 2026-10-08)

Headless, points, y down, origin = artboard 1 top-left. Every call below worked.

- New doc: `file.new {width,height,name}`; resize later: `artboard.setProps {index:0,height:5020}`.
- Text: `text.create {x,y,text,size,font,style,color}` (x,y = left baseline). `style` must match `text.fontList {family}`
  exactly ("SemiBold" vs "Semibold", "Display Semibold", "Light" for Perpetua Titling MT). A wrong style silently
  substitutes: always run `text.fonts` and check every row says status "exact".
- Tracking: `text.setStyle {ids:[...], tracking:120}` (1/1000 em); one call for many objects.
- Many shapes in ONE object: `draw_path {d:"M..H..V..Z M...", fill, stroke, strokeWidth}`. Multi-subpath `d`
  gave 33 filled rectangles, 132 rules and 66 margin lines in 3 calls instead of 231. Generate `d` with a script.
- Stroke-only path: `fill:"none"`. No-stroke fill: `stroke:"none"`.
- Colour with opacity: `transparency.set {id, opacity:35}` (0..100) on the object (used on the rules path).
- Delete objects: `layer.delete {ids:[...]}` (there is no `edit.delete`). Select: `select.all`, `select.set {ids}`.
- Outline text: select it, then `type.createOutlines {}`; returns one Group id per text (ids are NOT the old text ids,
  they skip numbers). `text.fonts` only lists live text, so check fonts before outlining.
- Artboards: `artboard.new/setProps/fitToArt/duplicate`; export one with `export {artboard:n}`.
- Export: `export {format:"png", path, scale:1|2, options:{background:"#ffffff"}}`; save: `save_file {path}`.
  A tall board (1400x5020 pt) exports fine at 2x (2800x10040).

## Real glyph bounds (placing a baseline exactly)
`inspect_document` reports a text object's LAYOUT box (ascent..descent), not the ink. To get ink metrics:
1. `text.create` a single "L" at size 100 at a known baseline B in each font.
2. select all, `type.createOutlines`, `inspect_document depth:1`.
3. Cap height at size 100 = group `bounds.height`; baseline error = (bounds.y + height) - B
   (about 0 for most fonts; Segoe Print +2.8, Copperplate Gothic Light +3.1, Ink Free -1.6).
4. Real size = target_cap*100/height; real baseline y = rule_y - error*size/100. Then `layer.delete` the outlines.
   (Use "L": it has no overshoot. G and R overshoot a little.)

## Surprises
- Perpetua Titling MT has only Light and Bold; "Regular" resolves to Light with status "substitute".
- Brief's rule gap (26 pt) gives a 21 pt cap height, too small to judge fonts; the board uses 34 pt gaps and 27 pt caps
  in 140 pt strips (150 pt pitch).
- Do not delete ids by guessing: outline ids interleave with other ids; take them from the command's result.
