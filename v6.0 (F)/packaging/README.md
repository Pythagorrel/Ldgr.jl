# Packaging LDGR 6.0

How the clinic's copy of LDGR is built, installed, updated and looked after. The contract between the parts (folder layout, how Julia is started, the `LDGR-READY` line, the window's behaviour, the staff-facing wording) is in [`DESIGN.md`](DESIGN.md). This file is the how-to.

## What the clinic gets

One folder, `C:\LDGR` by default. No administrator rights are needed, and nothing else on the PC is changed apart from two shortcuts.

| Path | What it is | Who changes it |
|---|---|---|
| `LDGR.exe` | The window. Staff double-click it, and closing it stops LDGR. | A new build |
| `runtime\ldgr.dll` | **The whole program, compiled**: every `.jl` file (account names included), the form's HTML, JavaScript and CSS (minified), and the four packages | A new build (`Apply update`) |
| `runtime\julia\` | Julia 1.10.12, the official build, unchanged apart from three parts that are not needed: `sys.dll`, `include\` and `share\doc` | A Julia upgrade |
| `runtime\depot\artifacts\…` | OpenSSL, for HTTPS to Resend | A package upgrade |
| `runtime\env\Project.toml` | The five package names and ids | Never |
| `runtime\webview2\` | Microsoft's WebView2 SDK DLLs | Never |
| `runtime\VERSION.txt`, `runtime\THIRD-PARTY-NOTICES.txt` | Version, and the licences of everything SolRegia did not write | A new build |
| `settings\notify.toml` | Email settings, placed by hand. Holds the Resend key. | The technician |
| `settings\README.txt` | What the settings mean | |
| `Records\` | **The books.** Created at the first start. | LDGR only |
| `logs\` | One log a day, kept 60 days | LDGR only |
| `backups\` | Earlier `ldgr.dll` copies, kept by `Apply update` | `Apply update` |
| `tools\` | `Debug LDGR`, `Julia console`, `Apply update`, `Create shortcuts` | |

### What is compiled, and what is left out of the compiled program

The owner asked that as little of the source as possible be readable on the clinic's PC (Hannah's request, 8 October). So every file of LDGR's own code is compiled into `runtime\ldgr.dll`, and nothing of it ships as text. LDGR's docstrings are removed from the image, and comments are never compiled. The form's files are minified and stored inside the image, not on disk.

**Compiled into `runtime\ldgr.dll`:** `AuditLog.jl`, `Chain.jl`, `Changes.jl`, `Checks.jl`, `Config.jl`, `DayInput.jl`, `EmailHtml.jl`, `getdate.jl`, `Journal.jl`, `Layout.jl`, `Ledger.jl`, `main.jl`, `Notify.jl`, `Report.jl`, `Resend.jl`, `server.jl`, `public\index.html`, `public\app.js` and `public\styles.css`.

**Shipped beside it, on purpose:**

| File | Why it is not compiled in |
|---|---|
| `settings\notify.toml` | It is settings, not code, and it differs per PC. It holds that PC's Resend key, which must never be inside a file we copy between PCs, and the technician has to be able to edit it on site (changes apply within a minute). |
| `Records\`, `logs\` | Data written by LDGR. |
| `runtime\julia\` | Julia's own runtime, which is open source and not ours. Its `share\julia\base` and `stdlib` folders hold Julia's source, not LDGR's. |
| OpenSSL and WebView2 DLLs | Third-party binaries, loaded at run time. |
| `LDGR.exe` | Compiled C#. Its source (`packaging\launcher\LDGR.cs`) does not ship. |

**Not shipped at all** (developer-only): `tests\`, `handoff\`, `resend-work\`, `sysimage\`, `packaging\`, `public\prototype.html`, `sample_day.csv`, `notify.example.toml` (the setup checklist, which stays with SolRegia), `ldgr.bat`, `README.md`, `Project.toml`/`Manifest.toml` (the image carries the pinned versions) and the repository's MIT `LICENSE`.

**What compiling does and does not hide.** Nobody can open LDGR's source on the clinic's PC, because there is none there. But the image is not encrypted. Anyone with technical skill can still:
- read the text strings the program uses (messages, account names);
- open the form's minified JavaScript, either through `tools\Debug LDGR` (DevTools) or by asking the running program for `/app.js`;
- with Julia knowledge, inspect the compiled program's structure from `tools\Julia console`.

That is the practical limit. Stripping more (Julia's `--strip-ir`) would stop Julia from compiling anything at run time, and is not safe for this program.

## Building

On the developer's PC, from `vFinal (6.0)`:

```
julia --startup-file=no packaging\build.jl all
```

| Step | What it does | Time |
|---|---|---|
| `stage` | Copies the program's 16 `.jl` files into a package called `LDGR` (`packaging\LDGR\src\LDGR.jl` wraps them). Minifies the form with esbuild. Adds LDGR to a copy of the pinned environment (offline) and checks that no package version moved. | 1 min |
| `image` | `PackageCompiler.create_sysimage([:LDGR, :HTTP, :JSON3, :DataFrames, :CSV]; cpu_target = default_app_cpu_target())`, watching `packaging\precompile_app.jl` drive a full day's entry. The result runs on any 64-bit Intel/AMD processor. | 15-25 min |
| `assemble` | `dist\LDGR\`: copies Julia (without `sys.dll`, `include`, `share\doc`), the image, the OpenSSL artifact, the WebView2 DLLs, the notices (`notices.jl`), `settings\README.txt` and `tools\`. Compiles `LDGR.exe` with the in-box C# compiler. Zips the result. | 3-5 min |

**Outputs, in `vFinal (6.0)\dist\`:**
- `LDGR\`: the folder that becomes `C:\LDGR`.
- `LDGR-<version>.zip`: the whole folder, for a new installation.
- `LDGR-update-<version>.zip`: only `ldgr.dll` and `VERSION.txt`, for `Apply update`.

**Needs:**
- Julia 1.10.12 with PackageCompiler in its default environment.
- `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.
- esbuild 0.28.2: `npm i esbuild@0.28.2` in `%TEMP%\ldgrb\node`, or set `LDGR_ESBUILD`.

Intermediate files go in `LDGR_BUILD_DIR` (default `%TEMP%\ldgrb`). Every child process runs with email fenced off and scratch books.

**The version** is `packaging\VERSION`. Raise it for every build that leaves this PC.

## Installing (at the clinic)

Before the visit, check:
- the PC runs 64-bit Windows 10 or 11;
- it has 4 GB of RAM or more (8 GB is comfortable) and about 2 GB free;
- its date, time and time zone (America/Guyana) are right;
- what antivirus it runs;
- whether Smart App Control is on (Windows Security > App & browser control): if it is, unsigned programs may not run;
- that Microsoft Edge WebView2 Runtime is installed (it is on every up-to-date Windows 11). Carry Microsoft's offline WebView2 installer on the USB stick.

At the clinic:

1. Copy `LDGR-<version>.zip` from the USB stick and extract it to `C:\` so that `C:\LDGR\LDGR.exe` exists. A zip downloaded from the internet carries a "mark of the web" that makes Windows warn. A copy from a USB stick does not.
2. Put the PC's own `notify.toml` in `C:\LDGR\settings\`. Use a Resend key made for this PC alone, and never email the file. Leave it out for email off.
3. Double-click `C:\LDGR\tools\Create shortcuts.cmd`. It adds "LDGR" to the Desktop and the Start Menu of the signed-in Windows account; repeat it for each account that will use LDGR.
4. Start LDGR from the Desktop shortcut. The first start after copying is slower while the antivirus scans the 400 MB image. If it is very slow every time, add an exclusion for `C:\LDGR`, with the owner's consent.
5. Enter the first day as usual: the first-day tick box appears.
6. Close LDGR with the X. Check that `C:\LDGR\Records\` now holds the month's folder, and that `C:\LDGR\logs\` has today's log ending in "Stopped.".
7. If email is on, the log's "Email :" line says `on -> …`. Do the live check as on 29 September: a scheduled report, and the healthchecks.io watchdog.
8. **Backups:** agree with the owner how `C:\LDGR\Records\` is copied elsewhere, for example weekly to a USB drive or cloud folder. LDGR does not do this.

**Removing LDGR:** copy `C:\LDGR\Records\` somewhere safe first, then delete `C:\LDGR` and the two shortcuts.

## Updating

Brand art: `LDGR.exe`'s icon comes from `packaging\brand\icon\ldgr.ico` (copied to `packaging\icon\`), and its start and closing pictures are PNGs from `packaging\brand\`, embedded as resources by `build.jl launcher()`. The form's header is `public\header.svg`.

| Change | What to send | Rebuild |
|---|---|---|
| Any `.jl` file, the form, an account name | `LDGR-update-<version>.zip` | Image (15-25 min) |
| Email settings | Edit `settings\notify.toml` on the PC | None |
| The window (`LDGR.cs`), or its start/closing art | A new `LDGR.exe` (it carries the art) | Seconds (`build.jl launcher`) |
| A package or Julia upgrade | A new full zip; keep `settings\` and `Records\` | Everything |

To apply an update, close LDGR and drag the zip onto `tools\Apply update.cmd`. The current `ldgr.dll` goes into `backups\<date time>\` first. To go back, close LDGR and copy the two files from the backup folder into `runtime\`.

## When something is wrong

- **The log:** `C:\LDGR\logs\LDGR <date>.log` holds everything Julia printed (the start banner, warnings, errors with their stack traces) and the window's own events, marked `[launcher]`.
- **`tools\Debug LDGR.cmd`:** the normal window, plus DevTools, F5 and a console that mirrors the log live.
- **`tools\Julia console.cmd`:** a Julia REPL with the program loaded, pointing at the real books and real settings. It holds the same lock as the app, so it cannot run beside it. Use it with care: anything typed there acts on the books.
- **"LDGR could not start":** read the end of the log. Common causes:
  - `runtime\ldgr.dll` was refused on this processor ("Unable to find compatible target").
  - A file in `runtime\` is missing.
  - The antivirus has quarantined a DLL.
- **"LDGR has stopped":** read the log for the last error. The books are safe: every save is written before the form says so.
