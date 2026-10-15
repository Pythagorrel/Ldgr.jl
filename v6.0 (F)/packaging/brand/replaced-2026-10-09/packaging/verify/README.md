# Acceptance scripts for the packaged LDGR

Black-box tests of a running LDGR server. They talk to it over HTTP (and, for the browser suites, through Chrome), so
they work the same on the packaged runtime (`runtime\ldgr.dll`, no `.jl` files) and on the loose source.

Run them from **Git Bash**. Nothing here touches a real `Records` folder, emails anything or contacts Resend: every
server these scripts start has `LDGR_NO_DIGEST=1`, `LDGR_NO_BROWSER=1` and `LDGR_NOTIFY_CONFIG` pointing at a file
that does not exist, and a scratch `LEDGER_ROOT` (the scripts refuse a path that mentions `Records`).

| File | What it is |
|---|---|
| `run-packaged.sh` | Starts / stops one server in the background. |
| `smoke.mjs` | HTTP-only scripted story (135 checks in loose mode). Node 24, no dependencies. |
| `run-browser-suites.sh` | Runs the five Playwright suites in `handoff\`, each against a fresh server. |

## 1. `run-packaged.sh`

```
run-packaged.sh start <HOME> <PORT> <SCRATCH_ROOT>   packaged runtime
run-packaged.sh loose <SRC>  <PORT> <SCRATCH_ROOT>   loose source: julia -e 'include("server.jl"); exit(start_app(port=PORT))'
run-packaged.sh stop  <SCRATCH_ROOT>
```

* `<HOME>` is the folder holding `LDGR.exe` and `runtime\`. `<SRC>` is the program folder (`E:\Ldgr\vFinal (6.0)`).
* `start` launches exactly what DESIGN.md section 2 says, from a clean environment (`env -i` plus `SYSTEMROOT PATH TEMP
  TMP USERPROFILE LOCALAPPDATA APPDATA USERNAME COMPUTERNAME HOMEDRIVE HOMEPATH`, then `JULIA_DEPOT_PATH=<HOME>\runtime\depot`,
  `LEDGER_ROOT`, `LDGR_NOTIFY_CONFIG`, `LDGR_NO_DIGEST=1`, `LDGR_NO_BROWSER=1`), with `-J <HOME>\runtime\ldgr.dll` and
  `-e "exit(LDGR.start_app(port = PORT))"`. It waits up to `READY_TIMEOUT` (default 180) seconds for `LDGR-READY`
  and prints the URL, the log path and the stop command. `loose` does the same from the source folder with the default
  Julia environment (`JULIA_EXE` overrides the 1.10.12 path).
* Julia's standard input is held open by a small feeder loop, which ends when the file `<SCRATCH_ROOT>.run\stop`
  appears. Closing the input is the real stop signal LDGR.exe uses.
* `stop` creates that file and waits (up to 120 s) for Julia to exit, then prints the exit code and whether
  `  Stopped.` was in the log. It exits 0 only for code 0 **and** `  Stopped.` printed.
* Run state (log `server.log`, `exit.code`, `stop`) lives in `<SCRATCH_ROOT>.run`, beside the books, never inside them
  (so `smoke.mjs` sees an empty folder).

```
bash run-packaged.sh start /c/LDGR 8765 /c/Users/me/AppData/Local/Temp/ldgr-books
bash run-packaged.sh stop  /c/Users/me/AppData/Local/Temp/ldgr-books
```

## 2. `smoke.mjs`

```
BASE=http://127.0.0.1:8765 LEDGER_ROOT=<the same scratch folder, empty> node smoke.mjs        # packaged
BASE=... LEDGER_ROOT=... LOOSE=1 node smoke.mjs                                               # loose source
```

It refuses a `LEDGER_ROOT` that mentions `Records` or is not empty (exit 2). It checks:

* **Files:** `GET /` is HTML with no `<!--`; `/app.js` and `/styles.css` are 200 with the right content types and
  **minified** (fewer than one newline per 200 bytes, no whole-line `//` comments, no long `/* */` comments);
  `/prototype.html` is 404; `/favicon.ico` is 404 or `image/x-icon`; an unknown file is 404; path traversal is 404.
  With `LOOSE=1` the comment, minification and prototype rules are relaxed.
* **API:** `/api/config` lists every category; bad requests give 400; then a story in the past: first day on record
  (refused without `allowGenesis`, saved with it); a balanced day; a day with an opening that does not match **and** a
  closing that does not balance (refused with no reason, with only one, nothing written, then saved with both); an Off
  day; a re-save that changes a figure; a refused future date. Along the way `/api/check`, `/api/day`, `/api/prior`
  and `/api/next` are exercised.
* **Books:** after each save the Daily Journal row and the Daily Ledger file exist, every ledger Debit/Credit is
  plain digits with exactly two decimals (no exponent), debits equal credits, `Change Log.csv` has one more row per
  save, a refused save changes nothing, and no response is ever a 5xx.

Prints `PASS`/`FAIL` lines and `smoke: N passed, M failed`; exit 1 on any failure. Proven result: 135 passed, 0 failed
in loose mode against the 8 October source. Run without `LOOSE=1` against loose source it correctly fails the 6
package-only rules.

## 3. `run-browser-suites.sh`

```
run-browser-suites.sh <HOME>            packaged runtime in <HOME>
run-browser-suites.sh <SRC> loose       loose source
SUITES="save-gate ui" ...               only some (save-next ui date-change save-gate saved-day-loads)
OUTDIR=<folder> ...                     where logs, scratch books and screenshots go (default: a new folder in %TEMP%)
```

For each suite it copies the script from `handoff\` to the Node folder that has `playwright-core`
(`C:\Users\jorre\AppData\Local\Temp\ldgrb\node`, or `NODE_DIR`), starts a server on the suite's port with a fresh empty
scratch `LEDGER_ROOT`, runs it with `BASE` and `LEDGER_ROOT` (no `MUTATE`), reads the totals, stops the server and prints a
summary table. In package mode it also requires the server to stop with code 0 and `  Stopped.`. Exit 0 only if every
suite ran with no failed check **and** the expected pass count. Needs Google Chrome (the suites use `channel: "chrome"`).

| Suite | Script | Port | Expected passes |
|---|---|---|---|
| save-next | `verify-save-next.mjs` | 8798 | 185 at each width (1440 and 390), 370 in all |
| ui | `verify-ui-2026-09-29.mjs` | 8799 | 319 |
| date-change | `verify-date-change-2026-10-06.mjs` | 8771 | 350 |
| save-gate | `verify-save-gate-2026-10-06.mjs` | 8772 | 138 |
| saved-day-loads | `verify-saved-day-loads-2026-10-07.mjs` | 8773 | 437 (220 at 1536, 217 at 390) |

Each suite takes minutes (a server start is about 45 s in loose mode; the packaged image starts faster). A verdict
other than `PASS` is `FAIL` (a check failed), `COUNT` (all passed but not the expected number: a check was added or
lost), `NO TOTALS`, `BAD STOP` or `NOT RUN`. Logs are `<OUTDIR>\<suite>.log`.

The suites test the front end that the server serves, so run against the packaged runtime they also prove that the
minified, embedded `app.js` / `index.html` / `styles.css` behave exactly like the source.

## Notes (review round 1)

- `run-packaged.sh main <HOME> - <SCRATCH>` runs the exact `LDGR.app_main()` command that LDGR.exe runs (version line,
  READY, `  Stopped.`). The port is chosen by the OS; read it from the `LDGR-READY` line it prints.
- After READY, `start`/`main`/`loose` all check that the server's `Records folder :` line equals the scratch root and that
  the `Email :` line starts with `off`; otherwise the server is stopped and the start is refused. `start`/`main` also
  refuse if any `.jl`, `.html`, `.js` or `.css` is found under HOME outside `runtime\julia`, `runtime\depot`, `runtime\webview2`.
- `stop` falls back to killing the hung `julia.exe` (matched on its command line) if it has not exited after 120 s.
- These are build-machine tests only: they need Git Bash (cygpath, netstat, env), Node 24 and, for the browser suites,
  playwright-core with Chrome. None of that is needed on a clinic PC.
- Not yet seen against the real image: the minified-file heuristics in `smoke.mjs` (package mode only).
- The packaged (`start`/`main`) modes have not been run: `runtime\` does not exist yet.
