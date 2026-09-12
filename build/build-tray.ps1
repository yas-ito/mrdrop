# Mr.Drop の常駐アイコン（MrDropTray.exe）をビルドする。
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build\build-tray.ps1
#
# 🔴 .NET SDK は要りません。Windows に最初から入っている C# コンパイラ
#    （.NET Framework 4.x の csc.exe）だけで作ります。英かな君と同じやり方
#    （products\eikana\build.ps1）。
# 🔴 /target:winexe にすること。console にすると**黒い画面が出ます**。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root "tray\MrDropTray.cs"
$icon = Join-Path $root "tray\app.ico"
$out  = Join-Path $root "tray\MrDropTray.exe"

if (-not (Test-Path -LiteralPath $src)) { throw "元のソースが見つかりません: $src" }

# アイコンが無ければ作る
if (-not (Test-Path -LiteralPath $icon)) {
  Write-Host "app.ico を作ります..."
  & (Join-Path $PSScriptRoot "make-tray-icon.ps1") | Out-Null
}

$candidates = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
  "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw "C# コンパイラ (csc.exe) が見つかりません。.NET Framework 4.x が要ります。" }
Write-Host "コンパイラ: $csc"

$cscArgs = @(
  "/target:winexe"          # 🔴 黒い画面を出さない
  "/optimize+"
  "/nologo"
  "/codepage:65001"         # ソースの日本語を UTF-8 として読ませる
  "/out:$out"
  "/win32icon:$icon"
  "/reference:System.dll"
  "/reference:System.Drawing.dll"
  "/reference:System.Windows.Forms.dll"
  $src
)
& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "ビルドに失敗しました（csc の戻り値 $LASTEXITCODE）" }

$info = Get-Item -LiteralPath $out
Write-Host ("できました: {0}  ({1:N0} バイト)" -f $info.FullName, $info.Length)
