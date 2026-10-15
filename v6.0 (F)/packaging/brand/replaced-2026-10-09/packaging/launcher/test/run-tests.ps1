# Tests for LDGR.exe (the window launcher) against a fake Julia. Windows PowerShell 5.1 or PowerShell 7.
# Never starts real Julia, never contacts the internet, never touches Records.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File run-tests.ps1 [-Scratch <folder>] [-SkipSlow]
param(
    [string]$Scratch = 'C:\Users\jorre\AppData\Local\Temp\ldgrb\agents\launcher',
    [switch]$SkipSlow
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pkg  = Split-Path -Parent (Split-Path -Parent $here)      # ...\packaging
$csc  = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$build = Join-Path $Scratch 'build'
$homes = Join-Path $Scratch 'homes'
$ico = Join-Path $pkg 'icon\ldgr.ico'

Add-Type -Namespace T -Name W -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
'@

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host ("PASS  " + $name + $(if ($detail) { "  [" + $detail + "]" })) }
    else     { $script:fail++; Write-Host ("FAIL  " + $name + $(if ($detail) { "  [" + $detail + "]" })) -ForegroundColor Red }
}

# ---------- build ----------
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $build | Out-Null
$cscArgs = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', "/out:$build\LDGR.exe")
if (Test-Path $ico) { $cscArgs += "/win32icon:$ico" }
$cscArgs += @("/win32manifest:$pkg\launcher\app.manifest",
    "/r:$pkg\webview2\Microsoft.Web.WebView2.Core.dll", "/r:$pkg\webview2\Microsoft.Web.WebView2.WinForms.dll",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll',
    "$pkg\launcher\LDGR.cs")
$o1 = & $csc @cscArgs 2>&1 | Out-String
Check 'LDGR.exe compiles with the build.jl command line (C# 5, no warnings)' (($LASTEXITCODE -eq 0) -and ($o1 -notmatch 'warning|error')) ($o1 -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(200, ($o1 -replace '\s+', ' ').Trim().Length))
$o2 = & $csc /nologo /target:exe /platform:x64 "/out:$build\julia.exe" "$here\FakeJulia.cs" 2>&1 | Out-String
Check 'FakeJulia.exe compiles' (($LASTEXITCODE -eq 0) -and ($o2 -notmatch 'error')) $o2.Trim()
if ($script:fail -gt 0) { Write-Host 'Build failed; stopping.'; exit 1 }

# ---------- environment: safety variables and ones that must NOT reach Julia ----------
$env:LDGR_TEST_NOACTIVATE = '1'
$env:LOCALAPPDATA = Join-Path $Scratch 'localappdata'
New-Item -ItemType Directory -Force $env:LOCALAPPDATA | Out-Null
$env:LEDGER_ROOT = Join-Path $Scratch 'must-not-reach-julia'
$env:LDGR_NO_DIGEST = '1'
$env:LDGR_NOTIFY_CONFIG = Join-Path $Scratch 'no-such-notify.toml'
$env:JULIA_PROJECT = 'C:\bogus\project'
$env:JULIA_NUM_THREADS = '7'
$env:SSL_CERT_FILE = 'C:\bogus\cert.pem'
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--no-first-run'
Remove-Item Env:\LDGR_TEST_READY_TIMEOUT_S -ErrorAction SilentlyContinue

# ---------- helpers ----------
function New-Home([string]$name) {
    $h = Join-Path $homes "$name x (y)\LDGR"
    if (Test-Path $h) { Remove-Item $h -Recurse -Force }
    foreach ($d in 'runtime\julia\bin', 'runtime\webview2', 'runtime\env', 'settings', 'logs') { New-Item -ItemType Directory -Force (Join-Path $h $d) | Out-Null }
    Copy-Item "$build\LDGR.exe" $h
    Copy-Item "$build\julia.exe" (Join-Path $h 'runtime\julia\bin\julia.exe')
    Copy-Item "$pkg\webview2\*" (Join-Path $h 'runtime\webview2')
    [IO.File]::WriteAllBytes((Join-Path $h 'runtime\ldgr.dll'), [byte[]]@())
    [IO.File]::WriteAllText((Join-Path $h 'runtime\VERSION.txt'), "6.0.0 (old)`r`n")
    $h
}
function Set-Mode([string]$h, [string]$mode) { [IO.File]::WriteAllText((Join-Path $h 'fake-mode.txt'), $mode) }
function Start-Ldgr([string]$h, [string[]]$argv = @()) {
    $psi = New-Object Diagnostics.ProcessStartInfo (Join-Path $h 'LDGR.exe')
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $h
    # quote every argument; none ends with a backslash
    $psi.Arguments = ($argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    [Diagnostics.Process]::Start($psi)
}
function Read-Text([string]$path) {
    try {
        $fs = New-Object IO.FileStream($path, 'Open', 'Read', 'ReadWrite,Delete')
        try { $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); $ms.ToArray() } finally { $fs.Dispose() }
    } catch { [byte[]]@() }
}
function Get-LogText([string]$h) {
    $sb = ''
    foreach ($f in Get-ChildItem (Join-Path $h 'logs') -Filter 'LDGR *.log' -ErrorAction SilentlyContinue) {
        $sb += [Text.Encoding]::UTF8.GetString((Read-Text $f.FullName))
    }
    $sb
}
function Wait-Until([scriptblock]$cond, [double]$sec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $sec) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 100 }
    return [bool](& $cond)
}
function Wait-Log([string]$h, [string]$pattern, [double]$sec) { Wait-Until { (Get-LogText $h) -match $pattern } $sec }
function Get-Window($p) { $p.Refresh(); $p.MainWindowHandle }
function Wait-Window($p, [double]$sec) { Wait-Until { (Get-Window $p) -ne [IntPtr]::Zero } $sec }
function Close-Window($p) { [T.W]::PostMessage((Get-Window $p), 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
function Get-FakeRun([string]$h) { $f = Join-Path $h 'fake-run.txt'; if (Test-Path $f) { Get-Content $f -Raw } else { '' } }
function Get-FakePid([string]$h) { $r = Get-FakeRun $h; if ($r -match 'PID=(\d+)') { [int]$Matches[1] } else { 0 } }
function Test-Alive([int]$id) { if ($id -le 0) { return $false }; [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) }
function Stop-All {
    Get-Process -Name LDGR, julia -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$homes\*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
function Fresh-Run([string]$h) { Remove-Item (Join-Path $h 'fake-run.txt'), (Join-Path $h 'fake-page-reports.txt') -ErrorAction SilentlyContinue }

Stop-All
$sw0 = [Diagnostics.Stopwatch]::StartNew()

# ============ 1. normal start, environment, args, log, WM_CLOSE ============
Write-Host "`n== 1. normal start / environment / log / WM_CLOSE =="
$h = New-Home 'normal'
Set-Mode $h 'normal'
[IO.File]::WriteAllText((Join-Path $h 'fake-autoconfirm.txt'), 'x')
# old and recent logs: 60-day cleanup
$old = Join-Path $h 'logs\LDGR 2020-01-01.log'; [IO.File]::WriteAllText($old, 'old'); (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-100)
$rec = Join-Path $h 'logs\LDGR 2020-02-02.log'; [IO.File]::WriteAllText($rec, 'recent'); (Get-Item $rec).LastWriteTime = (Get-Date).AddDays(-10)
$p = Start-Ldgr $h
$ok = Wait-Log $h 'navigation succeeded' 40
Check 'normal start: the form page was reached (log: READY and a successful navigation)' ($ok -and ((Get-LogText $h) -match 'READY http://127\.0\.0\.1:\d+'))
$run = Get-FakeRun $h
$hp = $h
Check 'args: --startup-file=no --history-file=no --project=HOME\runtime\env -J HOME\runtime\ldgr.dll -e LDGR.app_main() (HOME has spaces and parentheses)' (
    $run -match '(?m)^ARG\[0\]=--startup-file=no\r?$' -and $run -match '(?m)^ARG\[1\]=--history-file=no\r?$' -and
    $run.Contains("ARG[2]=--project=$hp\runtime\env") -and $run -match '(?m)^ARG\[3\]=-J\r?$' -and
    $run.Contains("ARG[4]=$hp\runtime\ldgr.dll") -and $run -match '(?m)^ARG\[5\]=-e\r?$' -and
    $run -match '(?m)^ARG\[6\]=LDGR\.app_main\(\)\r?$' -and $run -match '(?m)^ARGC=7\r?$') ($run -replace '\r?\n', ' ; ').Substring(0, [Math]::Min(300, $run.Length))
Check 'env: JULIA_DEPOT_PATH=HOME\runtime\depot' ($run.Contains("ENV JULIA_DEPOT_PATH=$hp\runtime\depot"))
Check 'env: LEDGER_ROOT=HOME\Records (the test''s own LEDGER_ROOT replaced)' ($run.Contains("ENV LEDGER_ROOT=$hp\Records"))
Check 'env: LDGR_NOTIFY_CONFIG=HOME\settings\notify.toml' ($run.Contains("ENV LDGR_NOTIFY_CONFIG=$hp\settings\notify.toml"))
Check 'env: LDGR_NO_BROWSER=1' ($run -match '(?m)^ENV LDGR_NO_BROWSER=1\r?$')
Check 'env: LDGR_NO_DIGEST (set in the test environment) did not reach Julia' ($run -match '(?m)^ENV LDGR_NO_DIGEST=<unset>\r?$')
Check 'env: JULIA_PROJECT, JULIA_NUM_THREADS, SSL_CERT_FILE, WEBVIEW2_* did not reach Julia' ($run -match '(?m)^OTHER_SCRUBBED_VARS=\r?$') (($run -split "`n" | Where-Object { $_ -like 'OTHER_SCRUBBED*' }) -join '')
$rep = ''; if (Test-Path (Join-Path $h 'fake-page-reports.txt')) { $rep = Get-Content (Join-Path $h 'fake-page-reports.txt') -Raw }
Check 'page loaded in the window and its confirm() was answered OK through the dialog hook' (($rep -match 'loaded') -and (Wait-Until { (Get-Content (Join-Path $h 'fake-page-reports.txt') -Raw) -match 'auto confirm=true' } 10)) $rep.Trim()
$log = Get-LogText $h
Check 'log: confirm text shown as a MESSAGE with its OK action' ($log -match '\[launcher\] MESSAGE: Mark this day as an Off day\?' -and $log -match '\[launcher\] ACTION: OK accepts')
$logFile = Get-ChildItem (Join-Path $h 'logs') -Filter 'LDGR *.log' | Where-Object { $_.Name -match '^LDGR \d{4}-\d{2}-\d{2}\.log$' -and $_.Name -ne 'LDGR 2020-02-02.log' } | Select-Object -First 1
Check "log file is named 'LDGR yyyy-MM-dd.log' (today's date)" ($logFile -and $logFile.Name -eq ('LDGR ' + (Get-Date -Format 'yyyy-MM-dd') + '.log')) $logFile.Name
$bytes = Read-Text $logFile.FullName
Check 'log is UTF-8 without BOM and keeps non-ASCII text from Julia' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -and ([Text.Encoding]::UTF8.GetString($bytes) -match "Records folder : caf\u00e9 \u2014 \u00fcber"))
Check 'log: Julia lines prefixed HH:mm:ss, stderr captured, launcher lines prefixed [launcher]' ($log -match '(?m)^\d\d:\d\d:\d\d LDGR 6\.0\.0 \(fake\), Julia 1\.10\.12' -and $log -match '(?m)^\d\d:\d\d:\d\d   \(a line on stderr\)' -and $log -match '(?m)^\d\d:\d\d:\d\d \[launcher\] starting Julia')
Check 'logs older than 60 days deleted, recent one kept' ((-not (Test-Path $old)) -and (Test-Path $rec))
Check 'window exists (found via MainWindowHandle)' (Wait-Window $p 5)
$fakePid = Get-FakePid $h
Check 'fake Julia is running' (Test-Alive $fakePid)
$sw = [Diagnostics.Stopwatch]::StartNew()
Close-Window $p
$exited = $p.WaitForExit(10000)
$t = $sw.Elapsed.TotalSeconds
Check 'WM_CLOSE: launcher exits within a few seconds with code 0' ($exited -and $p.ExitCode -eq 0) ("{0:N1}s, code {1}" -f $t, $(if ($exited) { $p.ExitCode } else { 'n/a' }))
Check 'WM_CLOSE: Julia exited too (stdin closed, "Stopped." logged, code 0)' ((-not (Test-Alive $fakePid)) -and ((Get-LogText $h) -match 'Stopped\.') -and ((Get-LogText $h) -match 'Julia exited with code 0') -and ((Get-LogText $h) -match 'Closing\.\.\.'))
Stop-All

# ============ 2. killing LDGR.exe kills Julia (job object) ============
Write-Host "`n== 2. job object =="
$h = New-Home 'job'; Set-Mode $h 'normal'
$p = Start-Ldgr $h
$null = Wait-Log $h 'READY http' 40
$fakePid = Get-FakePid $h
Check 'job: fake Julia running before the kill' (Test-Alive $fakePid)
$sw = [Diagnostics.Stopwatch]::StartNew()
Stop-Process -Id $p.Id -Force
$gone = Wait-Until { -not (Test-Alive $fakePid) } 3
Check 'job: Stop-Process on LDGR.exe killed the fake within 1 s' ($gone -and $sw.Elapsed.TotalSeconds -lt 1.0) ("{0:N2}s" -f $sw.Elapsed.TotalSeconds)
Stop-All

# ============ 3. second launch ============
Write-Host "`n== 3. second instance =="
$h = New-Home 'second'; Set-Mode $h 'normal'
$p = Start-Ldgr $h
$null = Wait-Log $h 'navigation succeeded' 40
$null = Wait-Window $p 5
$sw = [Diagnostics.Stopwatch]::StartNew()
$p2 = Start-Ldgr $h
$ex2 = $p2.WaitForExit(8000)
Check 'second launch exits quickly with code 0' ($ex2 -and $p2.ExitCode -eq 0) ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
$n = @(Get-Process -Name LDGR -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $h 'LDGR.exe') }).Count
Check 'exactly one instance (and one fake Julia) is left' ($n -eq 1 -and ((Get-LogText $h) -match 'second start: LDGR is already open') -and (@(Get-Process -Name julia -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$homes\*second*" }).Count -eq 1)) "LDGR.exe count $n"
Close-Window $p; $null = $p.WaitForExit(10000)
Stop-All

# ============ 4. failures before READY ============
Write-Host "`n== 4. Julia fails before READY =="
foreach ($m in 'fail-before-ready', 'ldgr-fail') {
    $h = New-Home $m; Set-Mode $h $m
    $p = Start-Ldgr $h
    $null = Wait-Log $h 'LDGR could not start' 15
    $log = Get-LogText $h
    $lp = Join-Path $h ('logs\LDGR ' + (Get-Date -Format 'yyyy-MM-dd') + '.log')
    Check "$m : could-not-start message logged with the log path" ($log -match 'LDGR could not start\. Please contact the technician\.' -and $log.Contains($lp))
    if ($m -eq 'ldgr-fail') { Check 'ldgr-fail : the LDGR-FAIL reason is in the log' ($log -match 'LDGR-FAIL test reason') }
    Check "$m : window stays open until closed" (-not $p.HasExited)
    Close-Window $p
    $ex = $p.WaitForExit(8000)
    Check "$m : nonzero exit code after the window is closed" ($ex -and $p.ExitCode -ne 0) "code $(if ($ex) { $p.ExitCode })"
    Stop-All
}

# ============ 5. Julia dies after READY ============
Write-Host "`n== 5. Julia dies after READY =="
$h = New-Home 'die'; Set-Mode $h 'die-after-ready'
$p = Start-Ldgr $h
$ex = $p.WaitForExit(30000)
$log = Get-LogText $h
Check 'die-after-ready: stopped-while-open message logged' ($log -match 'MESSAGE: LDGR has stopped\. Unsaved figures will need to be re-entered\. Press OK, then open LDGR again\.' -and $log -match 'ACTION: exit LDGR' -and $log -match 'Julia exited with code 5')
Check 'die-after-ready: launcher exits by itself with a nonzero code' ($ex -and $p.ExitCode -ne 0) "code $(if ($ex) { $p.ExitCode })"
Stop-All

# ============ 6. WebView2 component missing (loader removed) ============
Write-Host "`n== 6. WebView2 missing =="
$h = New-Home 'nowv'; Set-Mode $h 'normal'
Remove-Item (Join-Path $h 'runtime\webview2\WebView2Loader.dll')
$p = Start-Ldgr $h
$null = Wait-Log $h 'WebView2 is missing' 30
$fakePid = Get-FakePid $h
Check 'WebView2 loader missing: "missing component" handling logged and Julia killed' (((Get-LogText $h) -match 'WebView2 is missing or unusable') -and (Wait-Until { -not (Test-Alive $fakePid) } 5) -and ((Get-LogText $h) -match 'Julia killed'))
Close-Window $p; $ex = $p.WaitForExit(8000)
Check 'WebView2 loader missing: launcher closes at once, exit code 1' ($ex -and $p.ExitCode -eq 1) "code $(if ($ex) { $p.ExitCode })"
Stop-All

# ============ 7. never ready ============
Write-Host "`n== 7. never ready (timeout shortened to 4 s) =="
$h = New-Home 'never'; Set-Mode $h 'never-ready'
$env:LDGR_TEST_READY_TIMEOUT_S = '4'
$p = Start-Ldgr $h
Remove-Item Env:\LDGR_TEST_READY_TIMEOUT_S
$ok = Wait-Log $h 'taking too long to start' 15
Check 'never-ready: "taking too long to start" logged, window stays open' ($ok -and -not $p.HasExited)
$log = Get-LogText $h
Check 'never-ready: exact owner-approved sentence' ($log.Contains('LDGR is taking too long to start. Close this window and open LDGR again. If it happens again, contact the technician.'))
$fakePid = Get-FakePid $h
$sw = [Diagnostics.Stopwatch]::StartNew()
Close-Window $p; $ex = $p.WaitForExit(8000)
Check 'never-ready: closing the window kills Julia at once and exits' ($ex -and -not (Test-Alive $fakePid) -and $sw.Elapsed.TotalSeconds -lt 3) ("{0:N1}s" -f $sw.Elapsed.TotalSeconds)
Stop-All

# ============ 8. --update ============
Write-Host "`n== 8. --update =="
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Make-Zip([string]$zip, [hashtable]$files) {
    if (Test-Path $zip) { Remove-Item $zip }
    $za = [IO.Compression.ZipFile]::Open($zip, 'Create')
    foreach ($k in $files.Keys) {
        $e = $za.CreateEntry($k); $w = New-Object IO.StreamWriter($e.Open()); $w.Write($files[$k]); $w.Dispose()
    }
    $za.Dispose()
}
$h = New-Home 'update'; Set-Mode $h 'normal'
[IO.File]::WriteAllText((Join-Path $h 'runtime\ldgr.dll'), 'OLDDLL')
$good = Join-Path $Scratch 'update-good.zip'; Make-Zip $good @{ 'ldgr.dll' = 'NEWDLL'; 'VERSION.txt' = "6.0.1 (new)`r`n" }
$bad  = Join-Path $Scratch 'update-bad.zip';  Make-Zip $bad  @{ 'VERSION.txt' = "9.9.9 (bad)`r`n"; 'readme.txt' = 'x' }
function Dll($h) { [IO.File]::ReadAllText((Join-Path $h 'runtime\ldgr.dll')) }
function Ver($h) { ([IO.File]::ReadAllText((Join-Path $h 'runtime\VERSION.txt'))).Trim() }

# 8a. refuses while open
$p = Start-Ldgr $h
$null = Wait-Log $h 'navigation succeeded' 40
$u = Start-Ldgr $h @('--update', $good); $uex = $u.WaitForExit(15000)
Check '--update while the app is open: refused (exit 3, "Close LDGR first." logged), files unchanged' ($uex -and $u.ExitCode -eq 3 -and ((Get-LogText $h) -match 'MESSAGE: Close LDGR first\.') -and (Dll $h) -eq 'OLDDLL' -and (Ver $h) -eq '6.0.0 (old)') "code $($u.ExitCode)"
Close-Window $p; $null = $p.WaitForExit(10000); Stop-All

# 8b. zip lacking ldgr.dll
$u = Start-Ldgr $h @('--update', $bad); $uex = $u.WaitForExit(15000)
$bk = Join-Path $h 'backups'
Check '--update with a zip lacking ldgr.dll: fails (exit 3), changes nothing, no backup made' ($uex -and $u.ExitCode -eq 3 -and (Dll $h) -eq 'OLDDLL' -and (Ver $h) -eq '6.0.0 (old)' -and -not (Test-Path $bk) -and ((Get-LogText $h) -match 'does not contain ldgr\.dll')) "code $($u.ExitCode)"
Check '--update failure leaves no temp folder behind' (@(Get-ChildItem $h -Directory -Filter 'update-temp-*').Count -eq 0)

# 8c. good zip
$u = Start-Ldgr $h @('--update', $good); $uex = $u.WaitForExit(15000)
$bd = @(Get-ChildItem $bk -Directory -ErrorAction SilentlyContinue)
Check '--update with a good zip: exit 0, ldgr.dll and VERSION.txt replaced' ($uex -and $u.ExitCode -eq 0 -and (Dll $h) -eq 'NEWDLL' -and (Ver $h) -eq '6.0.1 (new)') "code $($u.ExitCode)"
Check '--update: old files backed up in backups\<yyyy-MM-dd HHmm>\' ($bd.Count -eq 1 -and $bd[0].Name -match '^\d{4}-\d{2}-\d{2} \d{4}' -and [IO.File]::ReadAllText((Join-Path $bd[0].FullName 'ldgr.dll')) -eq 'OLDDLL' -and ([IO.File]::ReadAllText((Join-Path $bd[0].FullName 'VERSION.txt'))).Trim() -eq '6.0.0 (old)') ($bd | ForEach-Object Name)
Check '--update: new version reported in the message, temp folder removed' (((Get-LogText $h) -match 'MESSAGE: LDGR was updated to 6\.0\.1 \(new\)\.') -and @(Get-ChildItem $h -Directory -Filter 'update-temp-*').Count -eq 0)
# 8d. update of a locked destination rolls back
$lock = New-Object IO.FileStream((Join-Path $h 'runtime\VERSION.txt'), 'Open', 'Read', 'Read')   # blocks overwrite of VERSION.txt
$good2 = Join-Path $Scratch 'update-good2.zip'; Make-Zip $good2 @{ 'ldgr.dll' = 'NEWDLL2'; 'VERSION.txt' = "6.0.2`r`n" }
$u = Start-Ldgr $h @('--update', $good2); $uex = $u.WaitForExit(15000)
$lock.Dispose()
Check '--update failing half way: old files put back, exit 3' ($uex -and $u.ExitCode -eq 3 -and (Dll $h) -eq 'NEWDLL' -and (Ver $h) -eq '6.0.1 (new)' -and ((Get-LogText $h) -match 'previous files were put back')) "dll=$(Dll $h) ver=$(Ver $h)"

# ============ 9. --console ============
Write-Host "`n== 9. --console =="
$h = New-Home 'console'; Set-Mode $h 'normal'
$c = Start-Ldgr $h @('--console'); $cex = $c.WaitForExit(15000)
$run = Get-FakeRun $h
Check '--console: starts the same Julia with -i -e "using LDGR" and returns Julia''s exit code (7)' ($cex -and $c.ExitCode -eq 7 -and $run -match '(?m)^ARG\[5\]=-i\r?$' -and $run -match '(?m)^ARG\[6\]=-e\r?$' -and $run -match '(?m)^ARG\[7\]=using LDGR\r?$' -and $run.Contains("ENV LEDGER_ROOT=$h\Records")) "code $($c.ExitCode)"

# ============ 10. --install (only if no LDGR.lnk exists) ============
Write-Host "`n== 10. --install =="
$desk = [Environment]::GetFolderPath('DesktopDirectory'); $prog = [Environment]::GetFolderPath('Programs')
if ((Test-Path (Join-Path $desk 'LDGR.lnk')) -or (Test-Path (Join-Path $prog 'LDGR.lnk'))) {
    Write-Host 'SKIP  --install: an LDGR.lnk already exists on this machine; not touching it.'
} else {
    $h = New-Home 'install'
    $i = Start-Ldgr $h @('--install'); $iex = $i.WaitForExit(15000)
    $l1 = Join-Path $desk 'LDGR.lnk'; $l2 = Join-Path $prog 'LDGR.lnk'
    $made = (Test-Path $l1) -and (Test-Path $l2)
    $tgt = ''
    if ($made) { $sh = New-Object -ComObject WScript.Shell; $s = $sh.CreateShortcut($l1); $tgt = $s.TargetPath + '|' + $s.WorkingDirectory }
    Check '--install: both shortcuts created, pointing at HOME\LDGR.exe with working folder HOME, exit 0' ($iex -and $i.ExitCode -eq 0 -and $made -and $tgt -eq ("$h\LDGR.exe|$h")) $tgt
    Remove-Item $l1, $l2 -Force -ErrorAction SilentlyContinue
    Write-Host "      cleaned up exactly: $l1 and $l2"
    Check '--install: shortcuts removed again' (-not (Test-Path $l1) -and -not (Test-Path $l2))
}

# ============ 11. closing wait + ignore-stdin killed after ~20 s (slow) ============
if ($SkipSlow) { Write-Host "`nSKIP  slow test (ignore-stdin / closing wait)" } else {
    Write-Host "`n== 11. ignore-stdin: killed about 20 s after WM_CLOSE; a new instance waits for the closing one =="
    $h = New-Home 'ignore'; Set-Mode $h 'ignore-stdin'
    $p = Start-Ldgr $h
    $null = Wait-Log $h 'navigation succeeded' 40
    $fakePid = Get-FakePid $h
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Close-Window $p
    Start-Sleep -Seconds 2
    $p2 = Start-Ldgr $h
    $waiting = Wait-Log $h 'still closing; waiting up to 25 s' 8
    Check 'a new instance started while the first is closing waits for it ("still closing" logged)' ($waiting -and -not $p2.HasExited)
    Start-Sleep -Seconds 10
    Check '10 s after WM_CLOSE the stubborn Julia is still alive and the launcher is still waiting' ((Test-Alive $fakePid) -and -not $p.HasExited)
    $ex = $p.WaitForExit(40000); $t = $sw.Elapsed.TotalSeconds
    Check 'ignore-stdin: launcher exits about 20 s after WM_CLOSE, Julia killed' ($ex -and $t -ge 19 -and $t -le 26 -and -not (Test-Alive $fakePid)) ("{0:N1}s" -f $t)
    Check 'ignore-stdin: "did not stop within 20 s" logged' ((Get-LogText $h) -match 'Julia did not stop within 20 s')
    $newUp = Wait-Until { (Get-FakePid $h) -ne $fakePid -and (Get-FakePid $h) -gt 0 } 20
    Check 'the waiting instance then opened normally (new window and new Julia)' ($newUp -and (Wait-Window $p2 10) -and -not $p2.HasExited)
    Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue
    Stop-All
}

# ============ 12. Windows shutdown: no "LDGR has stopped" box ============
Write-Host "`n== 12. WM_QUERYENDSESSION =="
$h = New-Home 'shutdown'
Set-Mode $h 'normal'
$p = Start-Ldgr $h
$null = Wait-Log $h 'navigation succeeded' 40
$null = Wait-Window $p 5
$fakePid = Get-FakePid $h
[T.W]::PostMessage((Get-Window $p), 0x11, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
$jx = Wait-Until { -not (Test-Alive $fakePid) } 10
Start-Sleep -Seconds 2
$log = Get-LogText $h
Check 'WM_QUERYENDSESSION: Julia stopped, session end logged, no "LDGR has stopped" message' ($jx -and $log -match 'Windows is ending the session' -and $log -notmatch 'MESSAGE: LDGR has stopped')
Stop-All

Write-Host ("`nDONE in {0:N0}s: {1} passed, {2} failed" -f $sw0.Elapsed.TotalSeconds, $script:pass, $script:fail)
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
