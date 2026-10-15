SP="C:/Users/jorre/AppData/Local/Temp/claude/E--Ldgr/3da7f582-9a49-4fc0-9da5-44332cbe25ab/scratchpad"
cd "$SP/brand"
for v in w1 w2 w3; do
  cp header2/$v.svg preview/$v.svg
  read W H < <(sed -n 's/.*width="\([0-9]*\)" height="\([0-9]*\)" viewBox.*/\1 \2/p' header2/$v.svg | head -1)
  sed "s#header-h2.svg\" width=\"92\" height=\"30\"#$v.svg\" width=\"$W\" height=\"$H\"#" preview/h2b.html > preview/$v.html
  for sc in 1 1.25 1.5; do
    "/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$sc --window-size=1536,140 --user-data-dir="$SP/brand/preview/chrome-profile" --screenshot="$SP/brand/preview/header-$v-$sc.png" "file:///$SP/brand/preview/$v.html" >/dev/null 2>&1
  done
done
ls preview/header-w*
