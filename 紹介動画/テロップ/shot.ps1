#Requires -Version 5.1
# テロップを透過 PNG で撮る（Chrome ヘッドレス）。
#
# 🔴 倍率2（3840×2160）で撮ってから 1920×1080 へ**縮める**。拡大はしない。
# 🔴 このファイルは BOM 付き UTF-8 で保存すること（PowerShell 5.1 は BOM が無いと CP932 で読む）。

$ErrorActionPreference = "Stop"
$here = "C:\yas-tools\products\mrdrop\紹介動画\テロップ"
$out  = "C:\yas-tools\products\mrdrop\_build\紹介動画\テロップ"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "Chrome が見つかりません" }
$ffmpeg = "C:\yas-tools\_tools\ffmpeg.exe"

$n = 0
foreach ($h in Get-ChildItem -Path $here -Filter *.html) {
  $big = Join-Path $env:TEMP ("telop_" + $h.BaseName + "_2x.png")
  $png = Join-Path $out ($h.BaseName + ".png")
  $url = "file:///" + ($h.FullName -replace '\\', '/')

  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $chrome --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=4000 `
    --default-background-color=00000000 `
    --force-device-scale-factor=2 --window-size="1920,1080" `
    --screenshot="$big" $url | Out-Null
  $ErrorActionPreference = $prev

  if (-not (Test-Path $big)) { throw "撮れませんでした: $($h.Name)" }
  & $ffmpeg -hide_banner -loglevel error -i $big -vf "scale=1920:1080:flags=lanczos" -y $png
  Remove-Item $big -Force
  $n++
}
Write-Host "$n 枚 できました: $out"
