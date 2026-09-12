# Mr.Drop のアイコン（PNG）から、Windows 用の .ico を作る。
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\make-tray-icon.ps1
#
# 元は iOS と同じ絵（ios\アイコン\AppIcon.png）。両OSで同じ顔にする。
# 🔴 外部の道具は使わない。Windows に入っている System.Drawing だけで作る。
# 🔴 ico の中身は PNG のまま入れる（Vista 以降が読める形）。BMP に直すと
#    透過の縁が汚れる。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root "ios\アイコン\AppIcon.png"
$out  = Join-Path $root "tray\app.ico"

if (-not (Test-Path -LiteralPath $src)) { throw "元の絵が見つかりません: $src" }
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null

Add-Type -AssemblyName System.Drawing

# 小さい方ほどよく使われる。タスクバーは画面の拡大率で 16〜40 を選ぶ。
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)

$origin = [System.Drawing.Image]::FromFile($src)
try {
  $pngs = @()
  foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $g.Clear([System.Drawing.Color]::Transparent)
      $g.DrawImage($origin, 0, 0, $s, $s)
    } finally { $g.Dispose() }

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngs += ,@($s, $ms.ToArray())
    $ms.Dispose()
  }
} finally { $origin.Dispose() }

# ── .ico を組み立てる ────────────────────────────────────────
$fs = [System.IO.File]::Create($out)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
  $bw.Write([UInt16]0)              # 予約
  $bw.Write([UInt16]1)              # 種類: アイコン
  $bw.Write([UInt16]$pngs.Count)

  $offset = 6 + 16 * $pngs.Count
  foreach ($p in $pngs) {
    $size = $p[0]; $data = $p[1]
    # 🔴 PowerShell 5.1 は if を式として引数に直接書けない。$( ) で包む
    $byte = $(if ($size -ge 256) { 0 } else { $size })           # 256 は 0 と書く決まり
    $bw.Write([Byte]$byte)                                       # 幅
    $bw.Write([Byte]$byte)                                       # 高さ
    $bw.Write([Byte]0)              # 色数（32bit なので 0）
    $bw.Write([Byte]0)              # 予約
    $bw.Write([UInt16]1)            # プレーン
    $bw.Write([UInt16]32)           # ビット数
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
  }
  foreach ($p in $pngs) { $bw.Write($p[1]) }
} finally { $bw.Dispose(); $fs.Dispose() }

$info = Get-Item -LiteralPath $out
Write-Host ("できました: {0}  ({1:N0} バイト・{2} 種類)" -f $info.FullName, $info.Length, $pngs.Count)
