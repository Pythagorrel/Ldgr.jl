# LDGR brand assets (designed 2026-10-08/09)

The logo, the startup and closing screens, the form's header image and the app icon. They were designed in a
VectorCraft + Uizze session with the owner. **None of it is wired into the app yet.** The launcher, the form and
the exe icon still use the old look, and nothing in `vFinal (6.0)` reads this folder. **To wire it in, follow
[`WIRING.md`](WIRING.md).**

**Formats:** every asset is here as both PNG and SVG. The rule is to use the better format (SVG) where no file-type
restriction applies, and the required one where it does: PNG in the WinForms launcher, ICO for the exe icon.
`WIRING.md` §1 has the table.

Units: 1 pt = 1 CSS px. Every PNG is RGBA and transparent outside its artwork. `@Nx` files are for Windows display
scales (100/125/150/200 %). The owner's screen is 125 %.

## The design in one paragraph
The word "LDGR" is written in **Petit Formal Script** (a clerk's round hand). It is in brand green `#1F6F5C`,
cascading diagonally down the rows of a patch of off-white, lightly textured ledger paper with rounded corners.
- **Rules:** pale-green horizontal rules, with a mirrored double vertical rule at each end.
- **Row pitch:** taken from the letters, so each letter's baseline sits on its own rule and its cap top on the rule
  two above. This is the owner's "Pacioli" idea: the lines match only some of the letters' dimensions.
- **The form's own font is unchanged** (Segoe UI and Consolas). The script appears only in these images, so no font
  ships with the app.

## Files

| Folder | Files | Size at 1x | Use |
|---|---|---|---|
| `logo/` | `ldgr-logo@1x/@1.25x/@1.5x/@2x.png`, `ldgr-logo-2000w.png`, `ldgr-logo.svg` | 471 × 238 | Clean logo, no shadow. 2000w for documents and print. |
| `startup/` | `startup-banner@1x/@1.25x/@1.5x/@2x.png`, `startup-banner.svg` | 519 × 286 | Logo plus soft card shadow plus 24 px transparent padding. This is what the launcher draws (PNG). The SVG is 3.9 MB, mostly the embedded paper grain. |
| `startup/` | `startup-preview.png`, `startup-preview-failure.png` | 1920 × 1080 | How the screen should look (normal start, and a failed start). |
| `closing/` | `closing@1x/@1.25x/@1.5x/@2x.png`, `closing.svg`, `closing-preview.png` | 194 × 74 | "Closing…" in Petit Formal Script, `#1F6F5C`. |
| `header/` | `header@1x/@1.25x/@1.5x/@2x/@3x.png`, `header.svg`, `header-preview-125.png` | 163 × 49 | Form header strip: "LDGR" plus "Urgent / Care". |
| `icon/` | `ldgr.ico` (16-256), `favicon.ico` (16/32/48), `ldgr-N.png` × 10, `ldgr-icon-N.svg` × 10, `icon-sizes.png`, `icon-taskbar.png`, `MakeIco.ps1` | — | App and taskbar icon: the script "L" on the paper. Approved by the owner. |
| `font/` | `PetitFormalScript-Regular.ttf`, `OFL.txt` | — | Needed only to edit the art. SIL Open Font License 1.1. |
| `source/` | `.vectorcraft` documents, `tex.py` + `tex-g1.png` (paper grain), `header-build.py` | — | Editable sources. `header-build.py` is a record only: it relies on scratch helpers that are not kept. |

## Logo geometry (`ldgr-logo`, patch 470.53 × 237.74 pt)
- **Patch:** corner radius 16.5. Edge hairline `#E3E0D8`, 1.5 pt.
- **Paper:** mean `#FDFCF9` with fine grain and faint fibres (`tex-g1.png`), clipped to the rounded rectangle.
- **Lettering:** Petit Formal Script 100.04 pt, letters `#1F6F5C`. Row pitch p = 39.3 (0.393 × size).
  - Baselines (x, y): L (45.26, 98.24), D (136.53, 137.54), G (232.64, 176.84), R (322.10, 216.14).
- **Horizontal rules:** y = 19.65, 58.95, 98.24, 137.54, 176.84, 216.14. Full width, 1.25 pt, `#1F6F5C` at 22 %.
- **Vertical double rules:** x = 13.75/17.75 and 452.78/456.78, 1 pt, `#1F6F5C` at 34 %.
- **Shadow** (banner only): the form's card shadow, `0 1px 2px rgba(28,37,33,.04), 0 8px 24px -12px rgba(28,37,33,.10)`.

## Startup screen (LDGR.exe while Julia starts)
- **Window background:** `#FAF9F6`, the form's page colour. This is already the launcher's `PageColour`.
- **Banner:** draw `startup-banner@<scale>.png` centred horizontally. In a 1536 × 864 window its top-left is at
  (508.74, 220.11), which puts the patch's optical centre at 42 % of the height. Scale the position with the window.
- **Normal start shows no text.** The owner said: "the banner with the name of the program popping up after they
  double click should have them understand the program is loading up". "Starting LDGR…" is dropped.
- **Status line:** only for the slow and failure states (owner-approved wording in `packaging/DESIGN.md` §4).
  - "Still starting. Please wait." after 60 s, and the 3-minute message: Segoe UI 14 px `#5B6660`, centred,
    baseline at y 540 of 864 (about 48 px below the patch).
  - "LDGR could not start. Please contact the technician.": Segoe UI 15 px `#1C2521`, baseline 540. The log path
    goes on a second line, Segoe UI 13 px `#5B6660`, baseline 564. The banner never moves.

## Closing screen
- Background `#FAF9F6`.
- Draw `closing@<scale>.png` centred horizontally, its ink centred at the same optical height as the startup patch
  (42 %). This replaces the Segoe UI text "Closing LDGR…".

## Form header
- **What changes:** one image replaces the whole `.brand` block in `public/index.html`: the green square mark,
  "LDGR" and "Urgent Care".
  ```html
  <h1 style="line-height:0;margin:0"><img src="header@1x.png"
      srcset="header@1x.png 1x, header@1.25x.png 1.25x, header@1.5x.png 1.5x, header@2x.png 2x, header@3x.png 3x"
      width="163" height="49" alt="LDGR Urgent Care"></h1>
  ```
  Use the `srcset`: it makes the browser pick the file drawn for the screen's exact scaling. Shrinking the 2× file
  instead looks slightly soft at 125 %.
- **Opacity:** the whole strip is drawn at 94.5 % opacity, at the owner's request (less contrast against the page).
  It is baked into the PNGs and the SVG, so no CSS opacity is needed.
- **The strip:**
  - LDGR section: G1, green on off-white. The letters are `#175649` with a 0.45 px stroke, so they hold their own
    at small size.
  - "Urgent Care" section: G2, white on `#1F6F5C`.
  - The two share one double rule at x 99-100 / 102-103 (green on white | white on green). Only the outer corners
    are rounded (4.5).
  - Horizontal rules: 8 px pitch across both sections.
- **"Urgent Care" size:** set by the owner's proportions. The top of the U is 2/7 of the way down the D; the bottom
  of "Care" is 4/9 of the way down from the top of the R; then the words are enlarged 2.75 %, centred. That gives
  9.715 px Petit Formal Script, white, 0.3 px white stroke, centred.
- **For wiring:** the form uses `header.svg`. That needs two small additions:
  - `server.jl` serves no `.svg` type yet;
  - `build.jl` `stage()` copies only four form files.
  The PNG `srcset` is the fallback. See `WIRING.md` §3.

## App icon
- `icon/ldgr.ico` and `icon/favicon.ico` are drop-in replacements for `packaging/icon/ldgr.ico` and `favicon.ico`,
  which `packaging/build.jl` uses for the exe (`/win32icon`) and for the form.
- **Do not re-run `packaging/icon/MakeIcon.cs` afterwards:** it redraws the old document mark over them.
- **Small sizes are hand-tuned:**
  - below 48 px: no texture, a darker L (`#175649`) with a 0.75-1 px stroke;
  - 20-32 px: single verticals;
  - 16-24 px: only the baseline rule;
  - 16 px: no verticals.
