#Requires -Version 5.1
# 紹介動画の図を撮る（Chrome ヘッドレス）。
#
# 🔴 倍率2（3840×2160）で撮ってから 1920×1080 へ**縮める**。拡大は絶対にしない。
#    （紹介動画/台本.md の「画の決まり」）
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\紹介動画\図\shot.ps1
#
# 🔵 chrome は USB まわりの警告を stderr に出すことがある。PowerShell 5.1 は
#    native の stderr を ErrorRecord に包むので、Stop のままだと**撮る前に落ちる**
#    （BOOTH の商品画像で実際に踏んだ）。ここだけ Continue にする。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) "_build\紹介動画\図"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "Chrome が見つかりません" }

$ffmpeg = "C:\yas-tools\_tools\ffmpeg.exe"
if (-not (Test-Path $ffmpeg)) { throw "ffmpeg が見つかりません: $ffmpeg" }

foreach ($h in Get-ChildItem -Path $here -Filter *.html) {
  $big = Join-Path $env:TEMP ("mrdrop_" + $h.BaseName + "_2x.png")
  $png = Join-Path $out ($h.BaseName + ".png")
  $url = "file:///" + ($h.FullName -replace '\\', '/')

  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $chrome --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=6000 `
    --force-device-scale-factor=2 --window-size="1920,1080" `
    --screenshot="$big" $url | Out-Null
  $ErrorActionPreference = $prev

  if (-not (Test-Path $big)) { throw "撮れませんでした: $($h.Name)" }
  & $ffmpeg -hide_banner -loglevel error -i $big -vf "scale=1920:1080:flags=lanczos" -y $png
  Remove-Item $big -Force

  Add-Type -AssemblyName System.Drawing
  $img = [System.Drawing.Image]::FromFile($png)
  Write-Host ("{0}  {1}x{2}" -f $h.BaseName, $img.Width, $img.Height)
  $img.Dispose()
}
Write-Host "できました: $out"
