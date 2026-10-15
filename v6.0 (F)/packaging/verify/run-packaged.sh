#!/usr/bin/env bash
# Start / stop an LDGR server for black-box testing, from Git Bash.
#
#   run-packaged.sh start <HOME> <PORT> <SCRATCH_ROOT>   the packaged runtime (runtime\ldgr.dll, no .jl files)
#   run-packaged.sh loose <SRC>  <PORT> <SCRATCH_ROOT>   the loose source (include("server.jl")), to prove the scripts early
#   run-packaged.sh main  <HOME> -     <SCRATCH_ROOT>   the exact LDGR.app_main() command LDGR.exe runs (port chosen by the OS, read from LDGR-READY)
#   run-packaged.sh stop  <SCRATCH_ROOT>                 close stdin, wait for exit, report the exit code and "  Stopped."
#   run-packaged.sh <HOME> <PORT> <SCRATCH_ROOT>         same as "start"
#
# <HOME> is the installed folder (the one holding LDGR.exe and runtime\). <SRC> is the program folder
# (E:\Ldgr\vFinal (6.0)). <SCRATCH_ROOT> is the LEDGER_ROOT; it is created if missing and must not mention
# "Records". State for the run (log, stop file, exit code) lives beside it in "<SCRATCH_ROOT>.run", never inside it.
#
# Environment knobs: READY_TIMEOUT (seconds, default 180), JULIA_EXE (loose mode; default the juliaup 1.10.12 binary).
#
# Safety: LDGR_NO_DIGEST=1, LDGR_NO_BROWSER=1 and LDGR_NOTIFY_CONFIG -> a file that does not exist are always set,
# so nothing is emailed and nothing contacts Resend.
# Exit status: start/loose 0 when LDGR-READY was seen, 1 otherwise; stop 0 only when exit code was 0 and "  Stopped." printed.

set -u
JULIA_EXE_DEFAULT='C:\Users\jorre\.julia\juliaup\julia-1.10.12+0.x64.w64.mingw32\bin\julia.exe'
READY_TIMEOUT="${READY_TIMEOUT:-180}"

die() { echo "run-packaged: $*" >&2; exit 2; }
win() { cygpath -w "$1"; }

# A value from the launcher's own environment, whatever the case of the name.
getenvv() { printenv "$1" 2>/dev/null || printenv "$(echo "$1" | tr 'A-Z' 'a-z')" 2>/dev/null || true; }

state_dir_for() { local r; r="$(cygpath -u "$1")"; r="${r%/}"; echo "${r}.run"; }

do_stop() {
  local scratch="${1:-}"; [ -n "$scratch" ] || die "usage: stop <SCRATCH_ROOT>"
  local sd; sd="$(state_dir_for "$scratch")"
  [ -d "$sd" ] || die "no run state at $sd (not started, or already stopped and cleaned)"
  if [ -f "$sd/exit.code" ]; then
    echo "already exited on its own"
  else
    : > "$sd/stop"      # the stdin feeder sees this file and ends, which closes Julia's standard input
    local i
    for i in $(seq 1 240); do [ -f "$sd/exit.code" ] && break; sleep 0.5; done
  fi
  if [ ! -f "$sd/exit.code" ]; then
    # Fallback so a hung Julia does not keep holding its port and a locked ldgr.dll.
    local pat; pat="$(cat "$sd/kill-pattern" 2>/dev/null)"
    if [ -n "$pat" ]; then
      powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='julia.exe'\" | Where-Object { \$_.CommandLine -like '*$pat*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" > /dev/null 2>&1
      echo "killed the hung Julia (pattern: $pat)"
    fi
    echo "STOP FAILED: still running after 120 s (log: $sd/server.log)"
    return 1
  fi
  local code; code="$(cat "$sd/exit.code")"
  local stopped=no
  grep -q '^  Stopped\.' "$sd/server.log" && stopped=yes
  echo "exit code: $code    '  Stopped.' printed: $stopped    log: $sd/server.log"
  [ "$code" = "0" ] && [ "$stopped" = yes ] && return 0
  return 1
}

do_start() {
  local mode="$1" home="$2" port="$3" scratch="$4"
  [ -n "$home" ] && [ -n "$port" ] && [ -n "$scratch" ] || die "usage: $mode <HOME> <PORT> <SCRATCH_ROOT>"
  case "$scratch" in *[Rr][Ee][Cc][Oo][Rr][Dd][Ss]*) die "refusing a scratch root that mentions Records: $scratch";; esac
  [ -d "$home" ] || die "no such folder: $home"
  if [ "$mode" != main ] && netstat -ano | grep -qE ":$port +[^ ]+ +LISTENING"; then
    die "port $port is already in use by another program; choose a free port"
  fi
  mkdir -p "$scratch"
  local sd; sd="$(state_dir_for "$scratch")"
  rm -rf "$sd"; mkdir -p "$sd"
  local wscratch; wscratch="$(win "$scratch")"
  local nocfg; nocfg="$(win "$sd/no-such-notify.toml")"     # never created
  local whome; whome="$(win "$home")"

  local cmd=()
  if [ "$mode" = start ] || [ "$mode" = main ]; then
    [ -f "$home/runtime/ldgr.dll" ] || die "no $home/runtime/ldgr.dll (the image is not built yet; use 'loose')"
    [ -f "$home/runtime/julia/bin/julia.exe" ] || die "no $home/runtime/julia/bin/julia.exe"
    # The launcher's own clean environment (DESIGN.md section 2): only what Windows needs, plus the four LDGR variables.
    local envs=(env -i)
    local v val
    for v in SYSTEMROOT PATH TEMP TMP USERPROFILE LOCALAPPDATA APPDATA USERNAME COMPUTERNAME HOMEDRIVE HOMEPATH; do
      val="$(getenvv "$v")"; [ -n "$val" ] && envs+=("$v=$val")
    done
    envs+=("JULIA_DEPOT_PATH=$(win "$home/runtime/depot")" "LEDGER_ROOT=$wscratch" "LDGR_NOTIFY_CONFIG=$nocfg" "LDGR_NO_DIGEST=1" "LDGR_NO_BROWSER=1")
    local entry="exit(LDGR.start_app(port = $port))" killpat="start_app(port = $port)"
    # "main" runs the exact command LDGR.exe runs (DESIGN.md section 2). app_main() takes no port, so the OS picks one
    # and it is read from the LDGR-READY line; PORT is ignored.
    if [ "$mode" = main ]; then entry="LDGR.app_main()"; killpat="LDGR.app_main()"; fi
    cmd=("${envs[@]}" "$home/runtime/julia/bin/julia.exe" --startup-file=no --history-file=no
         "--project=$(win "$home/runtime/env")" -J "$(win "$home/runtime/ldgr.dll")" -e "$entry")
    echo "$killpat" > "$sd/kill-pattern"
  else
    [ -f "$home/server.jl" ] || die "no $home/server.jl"
    local jl="${JULIA_EXE:-$JULIA_EXE_DEFAULT}"
    cmd=(env "LEDGER_ROOT=$wscratch" "LDGR_NOTIFY_CONFIG=$nocfg" LDGR_NO_DIGEST=1 LDGR_NO_BROWSER=1
         "$jl" --startup-file=no -e "include(\"server.jl\"); exit(start_app(port=$port))")
    echo "start_app(port=$port)" > "$sd/kill-pattern"
    cd "$home" || die "cannot cd to $home"
  fi

  # The feeder holds Julia's stdin open until the stop file appears (or the state folder is deleted).
  # When Julia exits for any reason, its exit code is recorded and the stop file is created so the feeder ends too.
  (
    ( while [ ! -e "$sd/stop" ] && [ -d "$sd" ]; do sleep 0.5; done ) |
      { "${cmd[@]}" > "$sd/server.log" 2>&1; echo "$?" > "$sd/exit.code"; : > "$sd/stop"; }
  ) < /dev/null > /dev/null 2>&1 &
  disown 2>/dev/null || true

  local t0=$SECONDS
  while [ $((SECONDS - t0)) -lt "$READY_TIMEOUT" ]; do
    if grep -q '^LDGR-READY' "$sd/server.log" 2>/dev/null; then
      local ready; ready="$(grep '^LDGR-READY' "$sd/server.log" | head -1 | tr -d '\r')"
      # Guard: the server must be writing to the scratch root and not to a real books folder, and email must be off.
      local rec; rec="$(grep -m1 'Records folder :' "$sd/server.log" | sed -E 's/.*Records folder : *//' | tr -d '\r')"
      local bs='\\'
      local rec_n scr_n; rec_n="$(printf '%s' "$rec" | tr "$bs" '/' | tr 'A-Z' 'a-z')"; scr_n="$(printf '%s' "$wscratch" | tr "$bs" '/' | tr 'A-Z' 'a-z')"
      rec_n="${rec_n%/}"; scr_n="${scr_n%/}"
      if [ -z "$rec_n" ] || [ "$rec_n" != "$scr_n" ]; then
        echo "START REFUSED: the server's Records folder is '$rec', not the scratch root '$wscratch'. Stopping it."
        : > "$sd/stop"; return 1
      fi
      local em; em="$(grep -m1 'Email  *:' "$sd/server.log" | sed -E 's/.*Email *: *//' | tr -d '\r')"
      case "$em" in off*) ;; *) echo "START REFUSED: email is not off (Email : $em). Stopping it."; : > "$sd/stop"; return 1;; esac
      if [ "$mode" = main ]; then
        grep -q '^LDGR [0-9][0-9.]* (built ' "$sd/server.log" || { echo "START REFUSED: no 'LDGR x.y.z (built ...' version line from app_main"; : > "$sd/stop"; return 1; }
      fi
      echo "$ready  (after $((SECONDS - t0)) s, $mode mode)"
      echo "Email       : $em"
      if [ "$mode" != loose ]; then
        local stray; stray="$(find "$home" \( -path "$home/runtime/julia" -o -path "$home/runtime/depot" -o -path "$home/runtime/webview2" \) -prune -o -type f \( -name '*.jl' -o -name '*.html' -o -name '*.js' -o -name '*.css' \) -print 2>/dev/null | head -20)"
        if [ -n "$stray" ]; then echo "START REFUSED: source/front-end files visible in $home:"; echo "$stray"; : > "$sd/stop"; return 1; fi
        echo "no .jl/.html/.js/.css outside runtime/julia, runtime/depot, runtime/webview2"
      fi
      echo "LEDGER_ROOT : $scratch"
      echo "log         : $sd/server.log"
      echo "to stop     : $0 stop \"$scratch\""
      return 0
    fi
    if grep -q '^LDGR-FAIL' "$sd/server.log" 2>/dev/null || [ -f "$sd/exit.code" ]; then
      echo "START FAILED:"; tail -n 20 "$sd/server.log" 2>/dev/null; return 1
    fi
    sleep 0.5
  done
  echo "START FAILED: no LDGR-READY within ${READY_TIMEOUT} s"; tail -n 20 "$sd/server.log" 2>/dev/null
  : > "$sd/stop"
  return 1
}

case "${1:-}" in
  stop)  shift; do_stop "${1:-}" ;;
  start) shift; do_start start "${1:-}" "${2:-}" "${3:-}" ;;
  main)  shift; do_start main "${1:-}" "${2:-0}" "${3:-}" ;;
  loose) shift; do_start loose "${1:-}" "${2:-}" "${3:-}" ;;
  "")    die "usage: $0 start|loose <HOME|SRC> <PORT> <SCRATCH_ROOT>   |   $0 stop <SCRATCH_ROOT>" ;;
  *)     do_start start "${1:-}" "${2:-}" "${3:-}" ;;
esac
