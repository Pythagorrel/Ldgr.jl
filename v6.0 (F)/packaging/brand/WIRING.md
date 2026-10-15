# Wiring the new LDGR brand into the app: handoff brief

> **Done on 2026-10-09.** The owner then changed section 4: on a normal start the banner floats on the desktop as a
> borderless splash, and the window appears only when the form has loaded (or early, with the sentence under the
> banner, when start-up is slow or fails). See `README.md` ("Startup screen") and `packaging/DESIGN.md` section 3.
> The section 7.4 check must use GET (`curl -s -D - -o NUL …/header.svg`): the server answers HEAD with 405.

**Kick-off line for the owner to give a new Claude session:** "Wire in the brand assets: follow
`vFinal (6.0)/packaging/brand/WIRING.md`."

Read this whole file first, then `README.md` beside it (the specs) and the project's `CLAUDE.md` (the safety rules).
Everything here is decided; the design work is finished and approved by the owner. Your job is only to put the
finished files into the program, rebuild, and prove it works. Do not redesign anything. If something here cannot be
done as written, stop and ask the owner. Do not improvise a different look.

## 0. Ground rules
- **Work in `E:\Ldgr\vFinal (6.0)`.** `v5.0` stays untouched.
- **Do not commit or push.** No AI attribution anywhere in git.
- **Minimal change.** The owner's standing rule before packaging: touch only what this job needs. The form's own text
  font (Segoe UI / Consolas), its colours, its wording and its behaviour do not change. Warning timing, wording and
  placement are frozen.
- **Safety (from CLAUDE.md):** every server or test run uses a scratch `LEDGER_ROOT`, plus `LDGR_NO_DIGEST=1`,
  `LDGR_NOTIFY_CONFIG` pointing at a file that does not exist, and `LDGR_NO_BROWSER=1`. Never read or print
  `notify.toml`. Nothing may contact Resend.
- **Fonts:** the fonts installed on this PC during the design session stay installed. Do not remove them. The app
  ships no font: all display text is already baked into the images.
- **Back up before overwriting:** put a copy of every file you replace in `packaging\brand\replaced-<date>\`.

## 1. The format rule (owner's instruction)
Each asset is prepared both as PNG (at 1×, 1.25×, 1.5×, 2× and, for the header, 3×) and as SVG. **Use the better
format where no file-type restriction applies, and the format the place requires where one does.** SVG is better
where it can be used (vector, sharp at any Windows scale); PNG is the fallback.

| Surface | Renderer | Restriction? | Use |
|---|---|---|---|
| Form header (top left of the form) | WebView2 / Chromium | None in the browser. The server and the packaged build need two small additions (below). | **SVG**: `header.svg`. Fall back to the PNG `srcset` only if those additions are refused or fail. |
| Launcher start screen | WinForms / GDI+ (LDGR.exe, before the form loads) | **Yes:** GDI+ cannot draw SVG. | **PNG**: `startup-banner@<scale>.png` |
| Launcher closing screen | WinForms / GDI+ | **Yes:** GDI+ cannot draw SVG. | **PNG**: `closing@<scale>.png` |
| Exe, taskbar and shortcut icon | Windows (`csc /win32icon`) | **Yes:** must be `.ico`. | **ICO**: `icon/ldgr.ico` |
| Form favicon | WebView2 | It is `favicon.ico` today, and the window and taskbar take the exe's icon anyway. | **ICO**: `icon/favicon.ico` (unchanged mechanism) |

The SVGs for the launcher art (`startup-banner.svg`, `closing.svg`) and the icon SVGs (`icon/ldgr-icon-N.svg`) are
there for completeness and future use. They are not needed for this job.

## 2. Exe icon and favicon (do this first; it is the simplest)
1. Back up `packaging\icon\ldgr.ico` and `packaging\icon\favicon.ico`. Copy `packaging\brand\icon\ldgr.ico` and
   `packaging\brand\icon\favicon.ico` over them.
2. **Do NOT run `packaging\icon\MakeIcon.cs` again:** it draws the OLD document mark and would overwrite both
   files. Add one line to the top comment of `MakeIcon.cs` saying the icons now come from `packaging\brand\icon\`
   and this tool is retired. Do not change its code.
3. `build.jl` already picks these up: `launcher()` passes `ldgr.ico` to `/win32icon`, and `stage()` copies
   `favicon.ico` into the form. The desktop and Start-menu shortcuts made by `--install` take the exe's icon.

## 3. Form header
**Today:** `public/index.html` lines ~28-42 hold `<div class="brand">`, with a `.brand-mark` green square (inline SVG
icon) and `.brand-text` ("LDGR" `<h1>` plus "Urgent Care" `<p class="brand-sub">`).

**Change:**
1. Copy `packaging\brand\header\header.svg` to `public\header.svg`. The server serves `public\` by file name only,
   so no sub-folders.
2. Replace the inside of `<div class="brand">` with:
   ```html
   <h1 class="brand-logo"><img src="header.svg" width="163" height="49" alt="LDGR Urgent Care"></h1>
   ```
   Add to `styles.css` (near `.brand`): `.brand-logo { margin: 0; line-height: 0; }` and
   `.brand-logo img { display: block; }`. Leave the old `.brand-mark` / `.brand-text` / `.brand-sub` rules in place
   only if removing them risks anything; otherwise delete them as unused. Keep the narrow-screen (`@media`) rules
   working: the image is 163 px wide and fits at 390 px.
3. **`server.jl`:** add `".svg" => "image/svg+xml"` to `MIMES` (about line 66). Without it the file is served as
   `application/octet-stream` and the browser will not draw it.
4. **`packaging\build.jl` `stage()`:** it copies only `app.js`, `styles.css` (minified), `index.html` and
   `favicon.ico` into the packaged form. Add a copy of `public\header.svg` (and, if you use the PNG fallback,
   the five `header@*.png`) into `joinpath(src, "public")`. `LDGR.jl` then embeds every file in that folder into
   `PUBLIC_FILES` automatically.
5. **Fallback (only if step 3 or 4 is not possible):** copy the five `header@1x/1.25x/1.5x/2x/3x.png` into `public\`
   and use:
   ```html
   <h1 class="brand-logo"><img src="header@1x.png"
       srcset="header@1x.png 1x, header@1.25x.png 1.25x, header@1.5x.png 1.5x, header@2x.png 2x, header@3x.png 3x"
       width="163" height="49" alt="LDGR Urgent Care"></h1>
   ```
   (`.png` is already in `MIMES`.)
6. The strip's 94.5 % opacity is baked into the files. Do not add CSS opacity.

**Tests and docs that mention the old header (update them):**
- `handoff/verify-ui-2026-09-29.mjs`: lines ~348-349 assert `.brand-text h1` = "LDGR" and `.brand-sub` =
  "Urgent Care", and line ~1159 asserts the 390 px header says "LDGR". Change these to assert that
  `.brand-logo img` exists, is fully loaded (`naturalWidth > 0`) and has `alt` "LDGR Urgent Care", at both widths.
  Keep the check count honest in the file's header comment.
- `handoff/ui-contract.md` (the header markup around line 83) and `tests/TESTING.md` (around line 264): describe
  the image.

## 4. Launcher start screen (`packaging\launcher\LDGR.cs`, class `AppForm`, from about line 645)
**Today:**
- A `Label status` docked to fill, on `PageColour` `#FAF9F6`, in Segoe UI 16 and the accent green, says
  "Starting LDGR…".
- After 60 s it says "Still starting. Please wait." (line ~684).
- On failure, `ShowStatus(...)` puts other sentences there (lines ~693, 823, 855). Line 838 hides it when the page
  shows.

**The owner's design:**
- Window background stays `#FAF9F6`.
- **The banner image, centred.** In a 1536 × 864 client area its top-left is at (508.74, 220.11) CSS px, which puts
  the paper patch's optical centre at 42 % of the height. In general:
  - left = (clientWidth − bannerWidth) / 2;
  - patch centre y = 0.42 × clientHeight;
  - the banner image includes 24 px of transparent padding, so its top = 0.42 × clientHeight − 24·s − 118.87·s,
    where s = the scale.
  Check the result against `startup/startup-preview.png`.
- **A normal start shows no text at all.** Drop "Starting LDGR…" (owner: "the banner with the name of the program
  popping up after they double click should have them understand the program is loading up").
- **Status text appears only for the non-normal states, under the banner, centred.** The sentences stay exactly as
  they are today (owner-approved, `DESIGN.md` §4):
  - "Still starting. Please wait." after 60 s, and the 3-minute "taking too long" sentence: Segoe UI 14 px, `#5B6660`.
  - "could not start" (with the log path on a second line), "WebView2 missing", and any other `ShowStatus`
    sentence: first line Segoe UI 15 px, `#1C2521`; the path line Segoe UI 13 px, `#5B6660`.
  - Position: first baseline about 58 px below the bottom of the paper patch (y 540 in an 864-high window, so
    the cap top is about 48 px below the patch), a second line 24 px lower, wrapping at about 640 px. The banner
    never moves.
  - See `startup/startup-preview-failure.png`.
- **Pixel sizes:** px values are CSS px at 96 DPI. Multiply by s = DeviceDpi / 96. The manifest declares
  PerMonitorV2, and `Control.DeviceDpi` exists on .NET Framework 4.7+.
- **Which PNG:** pick the file for s: 1 → `@1x`, 1.25 → `@1.25x`, 1.5 → `@1.5x`, 2 → `@2x`. For any other scale,
  use the next larger file and draw it scaled down with `InterpolationMode.HighQualityBicubic`. Never scale a
  smaller file up. Draw at whole-pixel coordinates.
- **Where the PNGs live:** embed them in LDGR.exe as resources, so no loose image files ship and the user can't
  delete them.
  - In `build.jl` `launcher()`, add `/resource:<path>,<name>` for each `startup-banner@*.png` and `closing@*.png`
    from `packaging\brand\`.
  - Load them with `Assembly.GetManifestResourceStream(name)`.
  - If a resource is missing, fall back to the old centred text, so the window is never blank.
- **Implementation suggestion:**
  - Replace the docked `Label` with a small double-buffered `Panel` (or the form's own `OnPaint`) that draws the
    banner plus the optional status lines with `TextRenderer`.
  - Keep `ShowStatus(text)` as the single entry point and make it repaint.
  - Keep `status.Visible = false` (or its equivalent) when the page shows.
  - Re-layout on `Resize` and `DpiChanged`.
- **C# 5 only** (the in-box `csc` v4.0.30319): no `$"..."` strings, no `?.`, no expression-bodied members. Same
  references as today (`System.Windows.Forms`, `System.Drawing`).
- Everything else in `DESIGN.md` §3 stays: timers, mutex, stdin stop signal, shutdown handling and message boxes.

## 5. Launcher closing screen
**Today:** `BeginClose()` (line ~929) calls `ShowStatus("Closing LDGR…")`.

**The owner's design:**
- Show `closing@<scale>.png` instead of that text, on `#FAF9F6`, with no other text.
- Centre it horizontally; its ink centre sits at the same optical height as the startup patch (y = 0.42 ×
  clientHeight).
- Same scale and file choice as §4.
- The page (WebView2) must be hidden or covered while it shows, as today.
- If the resource is missing, fall back to the text "Closing LDGR…".

## 6. Documents to update
- **`packaging/DESIGN.md`:**
  - §3 items 2 and 6: the banner and closing image replace the text.
  - §4 wording table: "Window, starting" → banner only, no text; "Window, closing" → closing image. The other
    sentences are unchanged.
- **`packaging/README.md`:** note that the icon and launcher art come from `packaging\brand\`, embedded as resources.
- **`packaging/brand/README.md`:** change "NOT wired in yet" to what is now wired, and where.
- **`E:\Ldgr\CLAUDE.md`:** replace the "brand assets … NOT wired in" bullet with a short record of this work, in
  the style of the other entries (what changed, the tests and their counts).

## 7. Build and verify
1. **Julia suites on the changed source** (only `server.jl` changes, by one `MIMES` entry): run every suite with
   unchanged counts, especially `tests/test_endpoints.jl` and `tests/test_app_mode.jl`. Run them from a scratch copy,
   as `CLAUDE.md` and `handoff/verification.md` describe.
2. **Loose-source browser suites:** `packaging/verify/run-browser-suites.sh` against the loose source, with the
   updated `verify-ui` assertions. All five suites pass.
3. **Build:** `julia --startup-file=no packaging\build.jl all` from `vFinal (6.0)` (needs esbuild; see
   `packaging/README.md`). Raise `packaging\VERSION` only if the owner says so (ask).
4. **Packaged checks:**
   - `smoke.mjs` and the five browser suites against `dist\LDGR` (`packaging/verify/README.md`);
   - `packaging\launcher\test\run-tests.ps1` (54 checks with the fake Julia), still all passing;
   - confirm `header.svg` is served from the packaged image with `Content-Type: image/svg+xml`, as
     `curl -sI http://127.0.0.1:<port>/header.svg` shows.
5. **Visual proof for the owner.** `LDGR.exe` ignores any inherited `LEDGER_ROOT` and `LDGR_NOTIFY_CONFIG`
   (`LDGR.cs` ~line 258) and always uses `<its folder>\Records` and `<its folder>\settings\notify.toml`. So:
   - copy `dist\LDGR` to a scratch folder and run the copy;
   - confirm the copy has no `settings\notify.toml` before starting it (then email is off);
   - never run it from a folder that holds real books.
   `LDGR_TEST_NOACTIVATE=1` starts the window minimised, so run without it for screenshots. Screenshots of the
   real `LDGR.exe`:
   - the start screen;
   - the form with the new header at 125 %;
   - the closing screen;
   - the taskbar icon.
   Compare them side by side with `startup/startup-preview.png`, `closing/closing-preview.png`,
   `header/header-preview-125.png` and `icon/icon-taskbar.png`. Also check the start screen at 100 % and 150 %
   scaling if you can (the scale choice in §4).
6. **Not yet verified anywhere:** real OS key presses and a PC without Julia (from `CLAUDE.md`). Not part of this
   job; leave them as they are.

## 8. Done when
- The exe, taskbar and shortcut show the new L icon.
- The form shows the header strip (SVG, or the PNG fallback with the reason recorded).
- The start screen shows the banner with no text on a normal start, and the status sentences only in the slow and
  failure states.
- Closing shows the closing image.
- Every suite passes with its count recorded.
- The docs in §6 are updated.
- Nothing is committed.
- Report to the owner in plain words: what changed, which format each surface uses and why, the test counts, and
  the screenshots.
