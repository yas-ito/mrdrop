# Mr.Drop の設定を、非エンジニアでも触れるようにする。
#
#   -ChooseInbox    保存先をフォルダ選択で変える（Mac のメニュー「保存先を変える…」と同じ）
#   -OpenInbox      保存先をエクスプローラで開く（Mac の「保存先を開く」と同じ）
#   -MakeResident   窓なしで常駐させる（install-windows.ps1 を呼ぶ。管理者へ昇格する）
#
# 🔴 隣の .bat から呼ばれる前提。**日本語はここに置く**（.bat は cmd が CP932 で読むので
#    非ASCII を書けない。だから案内文は全部こちら側）。
# 🔴 このファイルは **BOM 付き UTF-8**（社法。PowerShell 5.1 が BOM 無しを CP932 として読む）。

[CmdletBinding()]
param(
  [switch]$ChooseInbox,
  [switch]$OpenInbox,
  [switch]$MakeResident
)

$ErrorActionPreference = "Stop"
$Repo     = Split-Path -Parent $PSScriptRoot
$CfgFile  = Join-Path $Repo "config.json"
$TaskName = "MrDrop"

function Say  ($m) { Write-Host "   $m" }
function Head ($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "   ! $m" -ForegroundColor Yellow }
function Fail ($m) { Write-Host ""; Write-Host "🔴 $m" -ForegroundColor Red; Write-Host ""; exit 1 }

# ── 設定の読み書き ────────────────────────────────────────
# 🔴 config.json が無いこともある（一度も起動していないとき）。既定を組み立てて作る。
function Read-Config {
  if (Test-Path -LiteralPath $CfgFile) {
    try { return Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Fail "config.json が読めません（中身が壊れています）: $CfgFile" }
  }
  return [pscustomobject]@{
    port   = 48630
    # 🔴 server/lib/config.js の DEFAULTS と必ず同じにする。ここがずれると、
    #    一度も起動していない人が先に「保存先を変える.bat」を押したとき、
    #    間違った既定が config.json に書き込まれて固定される（Mac 側の指摘 2026-09-12）。
    inbox  = "%USERPROFILE%\Downloads"
    outbox = "%USERPROFILE%\Downloads\Mr.Drop送信箱"
    name   = ""
    token  = ""
  }
}

function Write-Config ($cfg) {
  # 🔴 Set-Content の既定は CP932。config.js は UTF-8 として読むので、必ず UTF-8 で書く。
  #    BOM は付けない（JSON.parse が BOM を嫌う）。
  $json = ($cfg | ConvertTo-Json -Depth 5)
  [System.IO.File]::WriteAllText($CfgFile, $json + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

# `%USERPROFILE%` や `~` を実際の場所に開く（config.js の expand と同じことをする）。
function Expand-Path ($p) {
  $s = [Environment]::ExpandEnvironmentVariables([string]$p)
  if ($s -match '^~[\\/]') { $s = Join-Path $env:USERPROFILE $s.Substring(2) }
  return $s
}

function Get-InboxPath {
  return Expand-Path (Read-Config).inbox
}

# 常駐しているなら、設定を読み直させるために入れ直す。
# 🔴 設定は起動時にしか読まないので、変えただけでは効かない。
function Restart-IfResident {
  $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if (-not $t) { return $false }
  $port = [int]((Read-Config).port)
  if (-not $port) { $port = 48630 }
  try {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

    # 🔴 Stop-ScheduledTask はプロセスをすぐには殺さない。待ち時間で逃げると、
    #    古い方がポートを握ったまま新しい方が立ち上がり、
    #    「48630 番はすでに使われています」で**両方止まる**（実際に踏んだ）。
    #    だから時間ではなく、**ポートが空いたこと**を見てから起動する。
    $freed = $false
    foreach ($i in 1..30) {
      Start-Sleep -Milliseconds 300
      if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) { $freed = $true; break }
    }
    if (-not $freed) {
      Warn "前のものが $port 番を離しません。パソコンを再起動すると効きます。"
      return $false
    }

    Start-ScheduledTask -TaskName $TaskName

    # 立ち上がったことも自分の目で確かめる（黙って失敗するのが一番こまる）。
    foreach ($i in 1..20) {
      Start-Sleep -Milliseconds 300
      if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { return $true }
    }
    Warn "入れ直しましたが、まだ立ち上がっていません。少し待つか、パソコンを再起動してください。"
    return $false
  } catch {
    Warn "常駐を入れ直せませんでした。パソコンを再起動すると効きます。"
    return $false
  }
}

# ── 保存先を変える ────────────────────────────────────────
if ($ChooseInbox) {
  Head "保存先を変える"
  $now = Get-InboxPath
  Say "いまの保存先: $now"
  Write-Host ""
  Say "フォルダを選ぶ画面を出します。"
  Say "編集用の素材フォルダを選んでおくと、撮った動画がそのまま作業場所に届きます。"

  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description  = "iPhone から届いたものを入れるフォルダを選んでください"
  $dlg.SelectedPath = if (Test-Path -LiteralPath $now) { $now } else { [Environment]::GetFolderPath('Desktop') }
  $dlg.ShowNewFolderButton = $true

  # 🔴 ShowDialog は STA スレッドでないと黙って失敗する。powershell.exe は既定で STA なので
  #    通常は問題ないが、そうでない環境では理由を出して止める（黙って何も起きないのが最悪）。
  if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Fail "フォルダ選択の画面を出せません（STA ではありません）。`n   隣の「保存先を変える.bat」から実行してください。"
  }

  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host ""
    Say "やめました。保存先は変えていません。"
    exit 0
  }

  $new = $dlg.SelectedPath
  if (-not (Test-Path -LiteralPath $new)) { Fail "そのフォルダが見つかりません: $new" }

  # 書けるフォルダかを実際に試す。届いた瞬間に失敗するより、いま分かった方がよい。
  $probe = Join-Path $new ".mrdrop-write-test"
  try {
    [System.IO.File]::WriteAllText($probe, "ok")
    Remove-Item -LiteralPath $probe -Force
  } catch {
    Fail "そのフォルダには書き込めません: $new`n   別のフォルダを選んでください。"
  }

  $cfg = Read-Config
  $cfg.inbox = $new
  Write-Config $cfg

  Write-Host ""
  Say "保存先を変えました: $new"
  if (Restart-IfResident) { Say "常駐を入れ直したので、もう効いています。" }
  else { Warn "「はじめる.bat」で動かしているときは、一度閉じてから押し直してください。" }
  Write-Host ""
  exit 0
}

# ── 保存先を開く ──────────────────────────────────────────
if ($OpenInbox) {
  $p = Get-InboxPath
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  Start-Process explorer.exe $p
  exit 0
}

# ── 常駐にする ────────────────────────────────────────────
if ($MakeResident) {
  Head "いつでも使えるようにする"
  Say "これから、次の2つをやります。"
  Say "  1. ファイアウォールを開ける（同じ Wi-Fi の中だけ）"
  Say "  2. パソコンを起動したら、勝手に動くようにする（黒い画面は出ません）"
  Write-Host ""
  Say "🔴 Windows が「許可しますか」と聞いてきます。「はい」を押してください。"
  Write-Host ""

  $installer = Join-Path $PSScriptRoot "install-windows.ps1"
  if (-not (Test-Path -LiteralPath $installer)) { Fail "scripts\install-windows.ps1 が見つかりません。" }

  $isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)

  if ($isAdmin) {
    & $installer
  } else {
    # 🔴 昇格した側の画面はすぐ閉じるので、結果をファイルに残して読み返す。
    #    「何も起きなかった」と見えるのが一番こまる。
    $log = Join-Path $env:TEMP "mrdrop-setup.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $inner = "& '$installer' *>&1 | Tee-Object -FilePath '$log'"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    try {
      Start-Process powershell -Verb RunAs -Wait -ArgumentList `
        "-NoProfile","-ExecutionPolicy","Bypass","-EncodedCommand",$b64
    } catch {
      Fail "「はい」が押されなかったので、設定できませんでした。もう一度やり直してください。"
    }
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
    else { Fail "設定できませんでした。もう一度やり直してください。" }
  }

  # 🔴 install-windows.ps1 は CIM 越しなので、失敗しても止まらないことがある。
  #    作れたかどうかは、必ず自分の目で確かめる（install 側と同じ理由）。
  Write-Host ""
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Head "できました"
    Say "もう何もしなくて大丈夫です。"
    Say "パソコンを起動したら、Mr.Drop が勝手に動きます（黒い画面は出ません）。"
    Say "iPhone の Mr.Drop アプリから、そのまま送ってください。"
    Write-Host ""
    Say "保存先を変えたいときは「保存先を変える.bat」"
    Say "やめたいときは scripts\install-windows.ps1 -Uninstall"
  } else {
    Fail "常駐にできませんでした。上の出力を見てください。"
  }
  Write-Host ""
  exit 0
}

Write-Host "使い方: 隣の .bat をダブルクリックしてください。"
exit 1
