# Mr.Drop の設定を、非エンジニアでも触れるようにする。
#
#   -ChooseInbox    保存先をフォルダ選択で変える（Mac のメニュー「保存先を変える…」と同じ）
#   -OpenInbox      保存先をエクスプローラで開く（Mac の「保存先を開く」と同じ）
#   -ChooseName     この PC の名前を変える（iPhone の一覧に出る名前）
#   -MakeResident   窓なしで常駐させる（install-windows.ps1 を呼ぶ。管理者へ昇格する）
#   -Uninstall      入れる前に戻す（同上。届いたファイルは消さない）
#   -FromTray       常駐アイコン（MrDropTray.exe）から呼ばれた。入れ直しは呼んだ側がやる
#   -Pause          終わりに Enter を待つ。スタートメニューのショートカットから呼ぶとき用
#                   （.bat には pause があるが、ショートカットは powershell を直接呼ぶので
#                    これが無いと画面が一瞬で閉じて何も読めない）
#
# 🔴 隣の .bat とスタートメニューのショートカットから呼ばれる前提。**日本語はここに置く**
#    （.bat は cmd が CP932 で読むので非ASCII を書けない。だから案内文は全部こちら側）。
# 🔴 このファイルは **BOM 付き UTF-8**（社法。PowerShell 5.1 が BOM 無しを CP932 として読む）。

[CmdletBinding()]
param(
  [switch]$ChooseInbox,
  [switch]$OpenInbox,
  [switch]$ChooseName,
  [switch]$MakeResident,
  [switch]$Uninstall,
  [switch]$FromTray,
  [switch]$Pause
)

$ErrorActionPreference = "Stop"
$Repo     = Split-Path -Parent $PSScriptRoot

# 🔴 設定はプログラムの隣に置かない。%LOCALAPPDATA%\MrDrop\config.json 一本。
#    server/lib/config.js の defaultFile() と**必ず同じ場所**にすること。
#    ・展開したフォルダは「はじめる.bat」のあと捨ててよい作りなので、隣に置くと消える
#    ・展開したフォルダに残った .bat を押しても、入っている方の設定を触れる
$AppDir   = Join-Path $env:LOCALAPPDATA "MrDrop"
$CfgFile  = Join-Path $AppDir "config.json"
$TrayExe  = Join-Path $AppDir "app\MrDropTray.exe"
$RunKey   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunName  = "MrDrop"

function Say  ($m) { Write-Host "   $m" }
function Head ($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "   ! $m" -ForegroundColor Yellow }
function Wait-IfAsked {
  if ($Pause) { Write-Host ""; Read-Host "  Enter を押すと閉じます" | Out-Null }
}
function Fail ($m) {
  Write-Host ""; Write-Host "🔴 $m" -ForegroundColor Red; Write-Host ""
  Wait-IfAsked
  exit 1
}

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
    outbox = "%USERPROFILE%\Desktop\Mr.Drop送信箱"
    name   = ""
    token  = ""
  }
}

function Write-Config ($cfg) {
  # 🔴 Set-Content の既定は CP932。config.js は UTF-8 として読むので、必ず UTF-8 で書く。
  #    BOM は付けない（JSON.parse が BOM を嫌う）。
  New-Item -ItemType Directory -Path (Split-Path -Parent $CfgFile) -Force | Out-Null
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

# 管理者に昇格して install-windows.ps1 を呼ぶ。-MakeResident と -Uninstall の共通部分。
# 🔴 昇格した側の画面はすぐ閉じるので、結果をファイルに残して読み返す。
#    「何も起きなかった」と見えるのが一番こまる。
function Invoke-Installer ([bool]$DoUninstall, [string]$denyMessage) {
  $installer = Join-Path $PSScriptRoot "install-windows.ps1"
  if (-not (Test-Path -LiteralPath $installer)) { Fail "scripts\install-windows.ps1 が見つかりません。" }

  $isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)

  if ($isAdmin) {
    if ($DoUninstall) { & $installer -Uninstall } else { & $installer }
    return
  }

  $log = Join-Path $env:TEMP "mrdrop-setup.log"
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
  $inner = if ($DoUninstall) { "& '$installer' -Uninstall *>&1 | Tee-Object -FilePath '$log'" }
           else                { "& '$installer' *>&1 | Tee-Object -FilePath '$log'" }
  $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
  try {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList `
      "-NoProfile","-ExecutionPolicy","Bypass","-EncodedCommand",$b64
  } catch {
    Fail $denyMessage
  }
  if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
  else { Fail "うまくいきませんでした。もう一度やり直してください。" }
}

# 設定を変えたら、常駐アイコンごと入れ直す。
# 🔴 設定は起動したときにしか読まない。変えただけでは効かない。
# 🔴 本体（node）を抱えているのは MrDropTray.exe なので、**アイコンを入れ直す**。
#    前はタスクスケジューラを入れ直していた。その作りはもう無い。
function Restart-Tray {
  # アイコン自身から呼ばれたときは、入れ直しは向こうがやる（二重に殺さない）
  if ($FromTray) { return $true }

  $procs = @(Get-Process -Name "MrDropTray" -ErrorAction SilentlyContinue)
  if (-not $procs) { return $false }

  $port = [int]((Read-Config).port)
  if (-not $port) { $port = 48630 }

  try {
    foreach ($p in $procs) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

    # 🔴 プロセスはすぐには消えない。時間で逃げると、古い方が番号を握ったまま
    #    新しい方が立ち上がり、「48630 番はすでに使われています」で**両方止まる**
    #    （タスクスケジューラ時代に実際に踏んだ）。番号が空くのを見てから起動する。
    $freed = $false
    foreach ($i in 1..30) {
      Start-Sleep -Milliseconds 300
      if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) { $freed = $true; break }
    }
    if (-not $freed) {
      Warn "前のものが $port 番を離しません。パソコンを再起動すると効きます。"
      return $false
    }

    if (-not (Test-Path -LiteralPath $TrayExe)) { Warn "常駐アイコンが見つかりません: $TrayExe"; return $false }
    Start-Process -FilePath $TrayExe -WorkingDirectory (Split-Path -Parent $TrayExe)

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
    Wait-IfAsked
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
  if (Restart-Tray) { Say "常駐を入れ直したので、もう効いています。" }
  else { Warn "動いていなければ、次に Mr.Drop を開いたときから効きます。" }
  Write-Host ""
  Wait-IfAsked
  exit 0
}

# ── 保存先を開く ──────────────────────────────────────────
if ($OpenInbox) {
  $p = Get-InboxPath
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  Start-Process explorer.exe $p
  exit 0
}

# ── この PC の名前を変える ────────────────────────────────
# 🔴 これが要る理由（Mac が実機で踏んだ 2026-09-12）:
#    iPhone の一覧に `yas`（Windows）と `yasnoMac-mini-local`（Mac）が並び、
#    本人が `yas` を選んで送って「Mac に届かない＝消えた」と思った。
#    動きは正常で、**分からないのは名前の方**だった。
#    既定はホスト名そのままで良い（加工しても短くならない＝区別が付かない）。
#    足りないのは「**自分で名前を付けられる口**」。
if ($ChooseName) {
  Head "この PC の名前を変える"
  $cfg = Read-Config
  $now = [string]$cfg.name
  # 🔴 host と args は PowerShell の自動変数。自分の変数名に使わない
  $pcName = $env:COMPUTERNAME
  if ($now) { Say "いまの名前: $now" } else { Say "いまの名前: $pcName （パソコンの名前をそのまま使っています）" }
  Write-Host ""
  Say "iPhone の「送り先」の一覧に、この名前で出ます。"
  Say "うちの居間のPC、編集用、などと付けておくと迷いません。"
  Write-Host ""

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Fail "名前を入れる画面を出せません（STA ではありません）。"
  }

  $form = New-Object System.Windows.Forms.Form
  $form.Text = "Mr.Drop — この PC の名前"
  $form.ClientSize = New-Object System.Drawing.Size(420, 150)
  $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
  $form.MinimizeBox = $false
  $form.MaximizeBox = $false

  $label = New-Object System.Windows.Forms.Label
  $label.Text = "iPhone の一覧に出る名前を入れてください。"
  $label.SetBounds(14, 14, 392, 20)
  $form.Controls.Add($label)

  $box = New-Object System.Windows.Forms.TextBox
  $box.SetBounds(14, 40, 392, 24)
  $box.MaxLength = 40
  $box.Text = $now
  $form.Controls.Add($box)

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = "空にすると、パソコンの名前（$pcName）に戻ります。"
  $hint.SetBounds(14, 70, 392, 20)
  $hint.ForeColor = [System.Drawing.Color]::DimGray
  $form.Controls.Add($hint)

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = "OK"; $ok.SetBounds(226, 104, 84, 28)
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $form.Controls.Add($ok); $form.AcceptButton = $ok

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "キャンセル"; $cancel.SetBounds(320, 104, 84, 28)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $form.Controls.Add($cancel); $form.CancelButton = $cancel

  $result = $form.ShowDialog()
  $new = $box.Text
  $form.Dispose()

  if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host ""
    Say "やめました。名前は変えていません。"
    Wait-IfAsked
    exit 0
  }

  # 前後の空白は落とす。制御文字は入れさせない（mDNS の名前に乗るため）
  $new = ([string]$new).Trim()
  if ($new -match "[\x00-\x1f]") { Fail "その名前は使えません（見えない文字が入っています）。" }

  $cfg.name = $new
  Write-Config $cfg

  Write-Host ""
  if ($new) { Say "名前を変えました: $new" } else { Say "パソコンの名前（$pcName）に戻しました。" }
  if (Restart-Tray) { Say "常駐を入れ直したので、もう効いています。" }
  else { Warn "動いていなければ、次に Mr.Drop を開いたときから効きます。" }
  Write-Host ""
  Wait-IfAsked
  exit 0
}

# ── 常駐にする ────────────────────────────────────────────
if ($MakeResident) {
  Head "Mr.Drop を使えるようにします"
  Say "これから、次の3つをやります。1回だけです。"
  Say "  1. この PC の中（$(Join-Path $AppDir 'app')）へ写す"
  Say "  2. ファイアウォールを開ける（同じ Wi-Fi の中だけ）"
  Say "  3. タスクバーの右下に常駐させる（パソコンを起動したら勝手に出ます）"
  Write-Host ""
  Say "🔴 Windows が「許可しますか」と聞いてきます。「はい」を押してください。"
  Write-Host ""

  Invoke-Installer $false ("「はい」が押されなかったので、設定できませんでした。`n" +
    "   もう一度「はじめる.bat」を押して、「はい」を選んでください。`n" +
    "   どうしても入れたくないときは scripts\run-once.bat で、1回だけ動かせます。")

  # 🔴 install-windows.ps1 は CIM 越しなので、失敗しても止まらないことがある。
  #    作れたかどうかは、必ず自分の目で確かめる（install 側と同じ理由）。
  Write-Host ""
  $run = (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
  if ($run) {
    Head "できました"
    Say "もう何もしなくて大丈夫です。"
    Say "パソコンを起動したら、Mr.Drop が勝手に出ます（黒い画面は出ません）。"
    Say "iPhone の Mr.Drop アプリから、そのまま送ってください。"
    Write-Host ""
    Say "🔵 タスクバーの右下に Mr.Drop のアイコンが出ています。"
    Say "   右クリックで 保存先を開く / 保存先を変える / 取扱説明書 /"
    Say "   Windows 起動時に自動で開始 / アンインストール / 終了。"
    Write-Host ""
    Say "🔵 展開したこのフォルダは、もう消して構いません。"
  } else {
    Fail "常駐にできませんでした。上の出力を見てください。"
  }
  Write-Host ""
  Wait-IfAsked
  exit 0
}

# ── 入れる前に戻す ────────────────────────────────────────
if ($Uninstall) {
  Head "Mr.Drop をアンインストールします"
  Say "この PC から、Mr.Drop が入れたものを全部外します。"
  Say "  ・自動起動（パソコンを起動しても、もう出ません）"
  Say "  ・ファイアウォールに開けた穴"
  Say "  ・タスクバーの常駐アイコン"
  Say "  ・スタートメニューの Mr.Drop"
  Say "  ・入れたプログラムと設定と記録（$AppDir）"
  Write-Host ""
  Say "🔵 届いたファイルは消しません。保存先も送信箱も、そのまま残ります。"
  Write-Host ""
  Say "🔴 Windows が「許可しますか」と聞いてきます。「はい」を押してください。"
  Write-Host ""

  Invoke-Installer $true ("「はい」が押されなかったので、やめられませんでした。`n" +
    "   もう一度やり直して、「はい」を選んでください。")

  Write-Host ""
  if ((Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName) {
    Fail "自動起動がまだ残っています。上の出力を見てください。"
  }
  Head "やめました"
  Say "Mr.Drop はもう動きません。届いたファイルはそのままです。"
  Say "また使いたくなったら、ZIP を展開して「はじめる.bat」を押してください。"
  Write-Host ""
  Wait-IfAsked
  exit 0
}

Write-Host "使い方: 隣の .bat をダブルクリックしてください。"
exit 1
