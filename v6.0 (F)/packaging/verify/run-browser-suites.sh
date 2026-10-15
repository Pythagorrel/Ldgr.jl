#!/usr/bin/env bash
# Run the five Playwright browser suites against a server started fresh for each one.
#
#   run-browser-suites.sh <HOME>            the packaged runtime in <HOME> (LDGR.exe's folder: runtime\ldgr.dll, no .jl files)
#   run-browser-suites.sh <SRC> loose       the loose source in <SRC> (default: the program folder this script lives in)
#
# Each suite: its script is copied to the Node folder where playwright-core is installed, a server is started on that
# suite's own port with a fresh, empty LEDGER_ROOT, the suite runs (no MUTATE), its pass/fail totals are read from its
# output, and the server is stopped (exit code and "  Stopped." checked in package mode).
#
# Environment: SUITES="save-next ui"   run only those (names in the table below)
#              OUTDIR=<folder>         logs, books and screenshots (default: a new folder under the Windows temp dir;
#                                      must not mention Records)
#              NODE_DIR=<folder>       where playwright-core is installed
#              READY_TIMEOUT           seconds to wait for LDGR-READY (default 180)
# Exit status: 0 only if every suite ran, passed every check, matched its expected count, and the server stopped cleanly.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROGRAM="$(cd "$HERE/../.." && pwd)"
HANDOFF="$PROGRAM/handoff"
NODE_DIR="${NODE_DIR:-/c/Users/jorre/AppData/Local/Temp/ldgrb/node}"
RUN="$HERE/run-packaged.sh"

HOME_ARG="${1:-}"; MODE=start
[ -n "$HOME_ARG" ] || { echo "usage: $0 <HOME> | $0 <SRC> loose" >&2; exit 2; }
if [ "${2:-}" = loose ]; then
  MODE=loose
  [ -f "$HOME_ARG/server.jl" ] || HOME_ARG="$PROGRAM"
fi

TMPW="$(cygpath -u "${TEMP:-/tmp}")"
OUTDIR="${OUTDIR:-$TMPW/ldgr-verify-$(date +%Y%m%d-%H%M%S)}"
case "$OUTDIR" in *[Rr][Ee][Cc][Oo][Rr][Dd][Ss]*) echo "OUTDIR must not mention Records: $OUTDIR" >&2; exit 2;; esac
mkdir -p "$OUTDIR" "$NODE_DIR" || exit 2
[ -d "$NODE_DIR/node_modules/playwright-core" ] || { echo "playwright-core is not installed in $NODE_DIR" >&2; exit 2; }

# name | script | port | expected pass count (save-next: per width, two widths)
SUITES_TABLE="
save-next|verify-save-next.mjs|8798|185
ui|verify-ui-2026-09-29.mjs|8799|322
date-change|verify-date-change-2026-10-06.mjs|8771|350
save-gate|verify-save-gate-2026-10-06.mjs|8772|138
saved-day-loads|verify-saved-day-loads-2026-10-07.mjs|8773|437
"

declare -a SUMMARY
overall=0
echo "mode: $MODE   program: $HOME_ARG   output: $OUTDIR"

while IFS='|' read -r name script port expect; do
  [ -n "$name" ] || continue
  if [ -n "${SUITES:-}" ]; then case " $SUITES " in *" $name "*) ;; *) continue;; esac; fi
  echo; echo "=== $name  ($script, port $port)"
  # Another program (or another test run) may already hold the suite's port: take the next free one.
  while netstat -ano | grep -qE ":$port +[^ ]+ +LISTENING"; do port=$((port + 1)); done
  books="$OUTDIR/$name/books"; shots="$OUTDIR/$name/shots"; log="$OUTDIR/$name.log"
  mkdir -p "$OUTDIR/$name" "$books" "$shots"
  cp "$HANDOFF/$script" "$NODE_DIR/$script" || { SUMMARY+=("$name|NOT RUN|-|-|could not copy $script"); overall=1; continue; }

  if ! "$RUN" "$MODE" "$HOME_ARG" "$port" "$books" > "$OUTDIR/$name/start.txt" 2>&1; then
    cat "$OUTDIR/$name/start.txt"
    SUMMARY+=("$name|NOT RUN|-|-|server did not start")
    overall=1; "$RUN" stop "$books" > /dev/null 2>&1; continue
  fi
  head -1 "$OUTDIR/$name/start.txt"

  ( cd "$NODE_DIR" && BASE="http://127.0.0.1:$port" LEDGER_ROOT="$(cygpath -w "$books")" OUT="$(cygpath -w "$shots")" \
      node "$script" ) > "$log" 2>&1
  rc=$?

  stopmsg="$("$RUN" stop "$books" 2>&1)"; stoprc=$?
  echo "stop: $stopmsg"

  # Totals. save-next prints one "<w>px: P pass, F fail" line per width; the others print one "P pass(ed), F fail(ed)" line.
  if grep -qE '^[0-9]+px: [0-9]+ pass' "$log"; then
    pass=$(grep -E '^[0-9]+px: [0-9]+ pass' "$log" | sed -E 's/^[0-9]+px: ([0-9]+) pass.*/\1/' | awk '{s+=$1} END{print s+0}')
    fail=$(grep -E '^[0-9]+px: [0-9]+ pass' "$log" | sed -E 's/.* ([0-9]+) fail.*/\1/' | awk '{s+=$1} END{print s+0}')
    perw=$(grep -E '^[0-9]+px: [0-9]+ pass' "$log" | sed -E 's/^([0-9]+)px: ([0-9]+) pass.*/\1px=\2/' | paste -sd' ')
    exp_total=$((expect * 2)); detail="per width: $perw"
  else
    line=$(grep -E '^[0-9]+ pass(ed)?, [0-9]+ fail(ed)?' "$log" | tail -1)
    pass=$(echo "$line" | sed -E 's/^([0-9]+) pass.*/\1/'); fail=$(echo "$line" | sed -E 's/.* ([0-9]+) fail.*/\1/')
    exp_total=$expect; detail=""
  fi
  [ -n "${pass:-}" ] || { pass="?"; fail="?"; }

  verdict=PASS
  if [ "$pass" = "?" ]; then verdict="NO TOTALS"
  elif [ "$fail" != "0" ] || [ "$rc" != "0" ]; then verdict="FAIL"
  elif [ "$pass" != "$exp_total" ]; then verdict="COUNT"      # all passed, but not the number the README expects
  fi
  note="exit $rc, expected $exp_total${detail:+; $detail}"
  if [ "$MODE" = start ] && [ "$stoprc" != 0 ]; then verdict="BAD STOP"; note="$note; $stopmsg"; fi
  [ "$verdict" = PASS ] || overall=1
  if [ "$verdict" != PASS ]; then echo "--- last lines of $log"; grep -E '^FAIL|^  - ' "$log" | head -15; fi
  SUMMARY+=("$name|$verdict|$pass|$fail|$note")
done <<< "$SUITES_TABLE"

echo; echo "=================== summary ($MODE) ==================="
printf '%-16s %-10s %6s %6s  %s\n' suite verdict pass fail notes
for s in "${SUMMARY[@]}"; do IFS='|' read -r a b c d e <<< "$s"; printf '%-16s %-10s %6s %6s  %s\n' "$a" "$b" "$c" "$d" "$e"; done
echo "logs: $OUTDIR"
exit $overall
