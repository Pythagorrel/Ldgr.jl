# Cursive font research for LDGR (2026-10-08)

## Uizze
- `find_ui_materials` (kind font): "copperplate script", "handwritten cursive elegant" and (on retry, after a RATE_LIMITED error) "formal pen script calligraphy" all returned the same three: Geologica Global, Commissioner Humanist, Funnel Product (plus Recursive Interface once). None is a script/handwriting face (Geologica has a "cursive" axis but is a sans). "engraved script banknote Spencerian" returned the same three. No Uizze kit was downloaded: nothing fit.
- `find_ui_references` (web): "handwritten script wordmark on ruled paper" gave Bigpicture Company (https://uizze.com/packs/eafe33bf-6f53-4619-b279-686ad5869799, unrelated) and Handsome Frank (https://uizze.com/packs/19d4103a-9f4a-49f0-ad7d-af6588bab904, a monoline script logo, only loosely related). "vintage ledger bookkeeping brand" (retry) gave only a "closest" Dropbox Brand pack (https://uizze.com/packs/f6fbc2fb-ea5d-44cc-a37d-d7896005acbd), no ledger content.
- Verdict: Uizze has no usable script fonts; every candidate below is from the Google Fonts repository.

## Candidates (all downloaded to SP\brand\downloads\<dir>\, OFL.txt read: SIL OFL 1.1 confirmed for all 15)
| Windows family name | Styles | Licence | Source (google/fonts ofl/) | Installed |
|---|---|---|---|---|
| Pinyon Script | Regular | OFL 1.1 | pinyonscript | yes |
| Petit Formal Script | Regular | OFL 1.1 | petitformalscript | yes |
| Herr Von Muellerhoff | Regular | OFL 1.1 | herrvonmuellerhoff | yes |
| Italianno | Regular | OFL 1.1 | italianno | yes |
| Alex Brush | Regular | OFL 1.1 | alexbrush | yes |
| Parisienne | Regular | OFL 1.1 | parisienne | yes |
| Great Vibes | Regular | OFL 1.1 | greatvibes | yes |
| Allura | Regular | OFL 1.1 | allura | yes |
| Monsieur La Doulaise | Regular | OFL 1.1 | monsieurladoulaise | yes |
| Mrs Saint Delafield | Regular | OFL 1.1 | mrssaintdelafield | yes |
| Meddon | Regular | OFL 1.1 | meddon | yes |
| Corinthia | Regular, Bold (two files, one family) | OFL 1.1 | corinthia | yes |
| Imperial Script | Regular | OFL 1.1 | imperialscript | yes |
| Rouge Script | Regular | OFL 1.1 | rougescript | yes |
| Dancing Script | variable wght 400-700 (Windows GDI shows only Regular/Bold) | OFL 1.1 | dancingscript | yes |

No candidate 404ed. Windows reports every family with Regular/Bold/Italic flags (GDI synthesises them); the real styles are as listed. Dancing Script's installed file is the variable font; VectorCraft may list named weights.

Windows-bundled (present on this PC; licence-uncertain for a logo, comparison only, not recommended): Segoe Script, Lucida Handwriting, Edwardian Script ITC, French Script MT, Palace Script MT, Kunstler Script, Vladimir Script, Script MT Bold, Monotype Corsiva, Brush Script MT, Freestyle Script, Gabriola. Not installed or rendered; no OFL substitute is needed.

A quick render of "LDGR  Ldgr  Closing" in all 15 is in `quick-look.png` (judgements below come from it).

## Ranked shortlist (for the specimen)
1. **Petit Formal Script**: upright, round, even-weight engrosser's hand, the calmest and most "clerk". Caps L D G R are plain and clearly readable; lowercase is open. Best fit for a ledger entry.
2. **Dancing Script**: bouncy but plain pen script, the most legible of all, with sturdy caps (LDGR reads instantly) and weights for the header size. Less formal than a copperplate hand.
3. **Parisienne**: classic roundhand, moderate flourish. Caps L D G R are readable, G and R have small curls. Good ledger-clerk feel at medium weight.
4. **Italianno**: light, narrow Italian chancery. Caps are simple and clear; hairline strokes may thin out at header size and in 2x/3x exports (check).
5. **Rouge Script**: pen script with open, slightly rounded caps; legible, a little thin. Calm.
6. **Great Vibes**: formal copperplate; the caps are wide and ornate with long swashes (G and R busiest), but still recognisable. Strong "engrossed" look, riskier for legibility.
7. **Alex Brush**: heavier brushy pen; caps readable, though its brush quality drifts toward the style we want to avoid. Good for small sizes because of its weight.
8. **Pinyon Script**: true engraver's copperplate. Caps are elegant but the D and G are the more ornate; "Ldgr" in lower case is clean. Thin hairlines.

Rejected for caps legibility: Herr Von Muellerhoff, Mrs Saint Delafield (R and G collapse), Monsieur La Doulaise and Corinthia (huge looped caps overlap), Meddon (heavy flourish, collides), Imperial Script and Allura (caps merge/hairline). "LDGR" in capitals is hard in the Sudtipos faces; "Ldgr" is far more readable in every script, so the owner should compare it.
