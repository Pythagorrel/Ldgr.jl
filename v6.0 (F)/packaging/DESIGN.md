# LDGR 6.0 packaged app: design

What the clinic's PC gets, how it starts and stops, and the contract between the window (`LDGR.exe`, C#) and the program (Julia with LDGR compiled into `runtime\ldgr.dll`). Baseline: the first-pass plan of 5 October (`Package & Compile\LDGR Packaging and Compilation Plan.txt`), with the owner's decisions of 8 October:

- **LDGR's source is compiled into the image.** Every `.jl` file, `Config.jl` (account names) included, is compiled into `runtime\ldgr.dll` as a package named `LDGR`. No `.jl` file ships. The form's files (`index.html`, `app.js`, `styles.css`) are compiled in too, minified. A code fix means rebuilding the image.
- Packaging only: there are no atomic writes and no caller check.
- Staff-facing wording: never "call SolRegia". Staff are told to "contact the technician".

## 1. The installed folder (default `C:\LDGR`; any folder works, nothing is hard-coded)

```
LDGR\
  LDGR.exe                     the window; what staff double-click
  settings\
     notify.toml               email settings, placed by hand at install (holds the Resend key)
     README.txt                what this folder is
  runtime\
     julia\                    Julia 1.10.12 (official build), without lib\julia\sys.dll, include\, share\doc
     ldgr.dll                  the system image: HTTP, JSON3, DataFrames, CSV and LDGR itself
     depot\artifacts\<hash>\   the OpenSSL artifact (HTTPS to Resend)
     env\Project.toml          the five package names and ids (no source)
     webview2\                 Microsoft.Web.WebView2.Core.dll, .WinForms.dll, WebView2Loader.dll, LICENSE.txt, NOTICE.txt
     VERSION.txt               e.g. "6.0.0 (built 2026-10-08)"
     THIRD-PARTY-NOTICES.txt   licences of everything not written by SolRegia
  tools\
     Debug LDGR.cmd            LDGR.exe --debug
     Julia console.cmd         LDGR.exe --console
     Apply update.cmd          LDGR.exe --update "%~1"
     Create shortcuts.cmd      LDGR.exe --install
  Records\                     the books (created on first start)
  logs\                        one log per day, "LDGR yyyy-MM-dd.log", kept 60 days
  backups\                     previous runtime\ldgr.dll + VERSION.txt, made by --update
```

Every path is relative to the folder holding `LDGR.exe` (call it `HOME`).

## 2. How Julia is started (the only place that knows this is LDGR.exe)

```
HOME\runtime\julia\bin\julia.exe --startup-file=no --history-file=no
     --project=HOME\runtime\env -J HOME\runtime\ldgr.dll -e "LDGR.app_main()"
```

- **Environment.** Start from the launcher's own environment. Remove every variable whose name starts with `JULIA_`, `SSL_CERT_` or `WEBVIEW2_`, and also `LEDGER_ROOT`, `LDGR_NO_DIGEST`, `LDGR_DIGEST_NOW`, `LDGR_NO_WARMUP` and `LDGR_NOTIFY_CONFIG`. Then set:
  - `JULIA_DEPOT_PATH=HOME\runtime\depot`
  - `LEDGER_ROOT=HOME\Records`
  - `LDGR_NOTIFY_CONFIG=HOME\settings\notify.toml`
  - `LDGR_NO_BROWSER=1`
- **Process.** No window (`CreateNoWindow = true`, `UseShellExecute = false`). All three streams are redirected as UTF-8 with no BOM. Julia joins a job object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, and the job handle is kept for the launcher's whole life, so killing LDGR.exe kills Julia.
- **Output.** Every line from stdout and stderr is appended, as it arrives, to `HOME\logs\LDGR yyyy-MM-dd.log`, prefixed with `HH:mm:ss `. The launcher's own events go in the same file, prefixed `[launcher]`. Draining never stops: a full pipe would freeze Julia in the middle of a save, so a failed log write is ignored and reading carries on. At start, logs older than 60 days are deleted.

### The protocol (stdout lines)

| Line | Meaning |
|---|---|
| `LDGR 6.0.0 (built …), Julia 1.10.12` | first line; log only |
| `  Records folder : …`, `  Email : …`, `  Warm-up took … s` | log only |
| `LDGR-READY http://127.0.0.1:<port>` | the form can be served; navigate the window to that URL |
| `LDGR-FAIL <reason>` | Julia will exit; show "could not start" |
| `  Closing...`, `  Stopped.` | log only |

**Stop signal: closing Julia's standard input.** Julia closes its server (a save in flight finishes first), hands the daily report over one last time (at most 10 s) and exits with code 0.

## 3. LDGR.exe behaviour

C# 5, built with the in-box compiler `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (`/target:winexe /platform:x64 /win32icon:ldgr.ico /win32manifest:app.manifest`). It references the WebView2 SDK 1.0.4258.31 DLLs, which it loads from `runtime\webview2\`, using `AppDomain.AssemblyResolve` for the two managed DLLs and `CoreWebView2Environment.SetLoaderDllFolderPath` for `WebView2Loader.dll`. Code that names WebView2 types lives in a class that is touched only after the resolver is registered. The manifest declares PerMonitorV2 DPI awareness and Windows 10 support (the spike's manifest).

1. **One instance per computer.** A mutex named `Global\LDGR-6-<hash of HOME, lower-cased>`.
   - If LDGR is already open in this Windows session, bring that window to the front (restore it if minimised) and exit.
   - If the mutex is held but no LDGR window can be found in this session (another Windows account has it), show: "LDGR is already open under another Windows account on this computer. Ask the person using it to close LDGR or sign out."
   - If the first instance is still closing, wait up to 25 s for the mutex.
2. **A floating banner while LDGR starts (owner, 9 Oct).** A borderless window holding only the start-up banner floats on the desktop, centred on the main screen's desktop area (above the taskbar), both ways (owner, 9 Oct; the brief's 42% height was for the old in-window screen, which had text under the banner). It is drawn with per-pixel transparency, so the paper's rounded corners and soft shadow sit on whatever is behind it. It has no text, a taskbar button ("LDGR", with the icon) and is not kept on top. Closing it (from the taskbar, or Alt+F4) closes LDGR, as closing the window during start-up did. The LDGR window, title "LDGR" with the icon, stays hidden meanwhile. It appears maximised when the form has loaded, and the banner closes at the same moment.
   - **Slow or failed start:** the window appears earlier, maximised, showing the banner on the page colour `#FAF9F6` with the sentence under it, and the floating banner closes. That is "Still starting. Please wait." after 60 s, the 3-minute sentence, "could not start" and "WebView2 missing" (section 8 and 10).
   - **The art** is embedded in `LDGR.exe` as resources from `packaging\brand\` (classes `Art`, `FloatingBanner` and `Splash` in `LDGR.cs`), the file chosen by the dpi. Each PNG exists for 100, 125, 150 and 200 % scaling; at any other scaling the next larger one is drawn smaller, and above 200 % (no larger file) the 2× one is drawn larger.
   - **Fallbacks:** if the banner picture is missing, or the banner cannot be shown, the window appears at once with the old centred Segoe UI text in the accent `#1F6F5C` ("Starting LDGR…"). The same text-only screen is used when a sentence has to show and the window (restored, not maximised) is too small for the banner and the sentence together, so the sentence can always be read.
3. **Julia starts** as in section 2.
4. **On `LDGR-READY <url>`** the WebView2 control navigates to the URL, and only the page shows once the navigation has succeeded. The window settings:
   - Profile in `%LOCALAPPDATA%\LDGR\WebView2`.
   - Browser accelerator keys off, so F5, Ctrl+P, F12, Ctrl+F and Ctrl+R do nothing. The form's own Ctrl+S, Ctrl+N, Ctrl+Alt+C and Ctrl+Alt+Z still reach the page.
   - Zoom control off, and zoom factor 1.0.
   - No context menu, no DevTools, no status bar, no swipe navigation, no autofill and no password saving.
   - No new windows: `NewWindowRequested` is handled and nothing opens.
   - No navigation away from `<url>/`.
   - `AllowExternalDrop = false`, so a file dropped on the window does not replace the form.
5. **Dialogs.** `AreDefaultScriptDialogsEnabled = false`. The form's one `confirm()` (marking an Off day) is shown as a Windows OK/Cancel box titled "LDGR", owned by the window, using the dialog's own message text. OK accepts it and Cancel does not. Use a deferral, so the page waits for the answer. An `alert()`, if one ever appears, is an OK box titled "LDGR".
6. **Closing (X, Alt+F4 or the taskbar).**
   - Cancel the first close.
   - Show the closing image in place of the page. The text "Closing LDGR…" shows only if the image is missing.
   - Close Julia's stdin and wait up to 20 s for it to exit, keeping the UI responsive. Kill it if it has not exited by then.
   - Then exit.
   - A close during start-up (before READY) kills Julia at once: nothing has been written yet.
7. **Windows shutting down or signing out.**
   - On `WM_QUERYENDSESSION` / `SessionEnding` / `FormClosing` with `CloseReason.WindowsShutDown`, close Julia's stdin at once.
   - Wait up to 3 s, then kill it and allow the shutdown.
8. **Julia does not become ready.**
   - If no READY arrives within 3 minutes, show "LDGR is taking too long to start. Close this window and open LDGR again. If it happens again, contact the technician." The window stays open, and closing it kills Julia.
   - If Julia exits before READY (or prints `LDGR-FAIL`), show "LDGR could not start. Please contact the technician." and, on a second line, the log file's full path.
9. **Julia stops while the form is open** (an exit that LDGR.exe did not ask for).
   - Show a Windows message box titled "LDGR" over the form, which stays visible behind it: "LDGR has stopped. Unsaved figures will need to be re-entered. Press OK, then open LDGR again."
   - After OK, exit.
10. **WebView2 runtime missing** (`GetAvailableBrowserVersionString` throws, or creating the environment fails with `WebView2RuntimeNotFoundException`).
    - Show in the window: "LDGR needs a Windows component that is missing on this computer (Microsoft Edge WebView2). Please contact the technician."
    - Kill Julia.
11. **A second mode is never started without the mutex.** `--console` and `--update` take the same mutex, so they cannot run beside the open app (and the app cannot start beside them).

### Other modes (for the technician; one source of truth for how Julia is started)

| Switch | What it does |
|---|---|
| (none) | the window, as above |
| `--debug` | As the window, plus DevTools, the context menu and F5. The log is also mirrored live to a console window (`AllocConsole`). |
| `--console` | Starts the same Julia with the same environment, in a visible console, but with `-i -e "using LDGR"` in place of `-e "LDGR.app_main()"`. The result is a REPL with the program loaded and pointing at the real books. LDGR.exe waits for it to exit and returns its exit code. |
| `--install` | Creates "LDGR" shortcuts to `HOME\LDGR.exe` (icon from the exe, working folder `HOME`) on the current user's Desktop and in their Start Menu Programs folder, then says so in a message box. |
| `--update <zip>` | Refuses while LDGR is open: "Close LDGR first." The zip holds `ldgr.dll` and `VERSION.txt`. The update copies the current `runtime\ldgr.dll` and `runtime\VERSION.txt` into `backups\<yyyy-MM-dd HHmm>\`, extracts the zip to a temp folder under `HOME`, checks that `ldgr.dll` is in it, replaces the two files and reports the new version in a message box. If anything fails, it puts the old files back and says what failed. |

## 4. Staff-facing wording (owner-approved, 8 Oct)

| Where | Text |
|---|---|
| Starting | The floating banner only, no text. After 60 s the window opens with "Still starting. Please wait." under the banner |
| Window, after 3 minutes | "LDGR is taking too long to start. Close this window and open LDGR again. If it happens again, contact the technician." |
| Window, closing | The closing image (script "Closing..."), no text |
| Open under another account | "LDGR is already open under another Windows account on this computer. Ask the person using it to close LDGR or sign out." |
| Could not start | "LDGR could not start. Please contact the technician." plus the log's path |
| Stopped while open | "LDGR has stopped. Unsaved figures will need to be re-entered. Press OK, then open LDGR again." |
| WebView2 missing | "LDGR needs a Windows component that is missing on this computer (Microsoft Edge WebView2). Please contact the technician." |
| Form, server unreachable (`app.js`) | "LDGR has stopped. Unsaved figures will need to be re-entered. Close this window and open LDGR again." |
| Form, unexpected error (`server.jl` 500) | "Something went wrong. Try again. If it keeps happening, contact the technician." |

The window's status sentences sit under the banner in the window: the slow states in 14 px grey (`#5B6660`), failures in 15 px ink (`#1C2521`) with the log path under them in 13 px grey.

## 5. Julia side (already in `vFinal (6.0)` source)

- `server.jl`: `start_app(; port = 0)` prints READY and returns 0 when stdin closes, or prints LDGR-FAIL and returns 2. `PUBLIC_FILES` serves the embedded form.
- `Notify.finish!(; timeout = 10)`.
- `Layout.ROOT` is set in `Layout.__init__`, at load, not at compile time.
- The build (`packaging/build.jl`) wraps the source as package `LDGR`. Its `src/LDGR.jl` includes `server.jl`, fills `PUBLIC_FILES`, strips LDGR's docstrings and defines `app_main()`, which prints the version line, runs `start_app()` and exits with its code.
