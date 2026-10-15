# Packs PNG files into ICO files with PNG-compressed entries (layout as WriteIco in MakeIcon.cs:
# 6-byte header, 16-byte directory entry per image, PNG data; width/height byte 0 means 256).
param([string]$Dir = $PSScriptRoot)
function Write-Ico([string]$path, [int[]]$sizes) {
    $data = @(); foreach ($s in $sizes) { $data += ,[System.IO.File]::ReadAllBytes((Join-Path $Dir "ldgr-$s.png")) }
    $fs = [System.IO.File]::Create($path); $w = New-Object System.IO.BinaryWriter($fs)
    $w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$sizes.Length)
    $offset = 6 + 16 * $sizes.Length
    for ($i = 0; $i -lt $sizes.Length; $i++) {
        $s = $sizes[$i]; $b = if ($s -ge 256) { 0 } else { $s }
        $w.Write([byte]$b); $w.Write([byte]$b); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([int16]1); $w.Write([int16]32); $w.Write([int32]$data[$i].Length); $w.Write([int32]$offset)
        $offset += $data[$i].Length
    }
    foreach ($d in $data) { $w.Write($d) }
    $w.Close(); $fs.Close()
}
Write-Ico (Join-Path $Dir 'ldgr.ico') @(16,20,24,32,40,48,64,96,128,256)
Write-Ico (Join-Path $Dir 'favicon.ico') @(16,32,48)
Write-Host 'wrote ldgr.ico and favicon.ico'
