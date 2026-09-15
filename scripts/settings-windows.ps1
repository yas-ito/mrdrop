# Mr.Drop の設定を、非エンジニアでも触れるようにする。
#
#   -ChooseInbox    受信先をフォルダ選択で変える（Mac のメニュー「受信先を変える…」と同じ）
#   -OpenInbox      受信先をエクスプローラで開く（Mac の「受信先を開く」と同じ）
#   -OpenOutbox     送信箱をエクスプローラで開く（iPhone へ渡す物を置く場所）
#   -MoveOutbox     「Mr.Drop送信箱」フォルダごと、選んだ場所へ移す（中身も付いていきます）
#   -ChooseName     この PC の名前を変える（iPhone の一覧に出る名前）
#   -MakeResident   窓なしで常駐させる（install-windows.ps1 を呼ぶ。管理者へ昇格する）
#   -Uninstall      入れる前に戻す（同上。届いたファイルは消さない）
#   -FromTray       常駐アイコン（MrDropTray.exe）から呼ばれた。入れ直しは呼んだ側がやる
#   -Pause          終わりに Enter を待つ。スタートメニューのショートカットから呼ぶとき用
#                   （.bat には pause があるが、ショートカットは powershell を直接呼ぶので
#                    これが無いと画面が一瞬で閉じて何も読めない）
#   -PrintDefaults  既定の置き場所を JSON で吐いて終わる（買った人は使わない）。
#                   server/test/config.test.js が、node 側の既定と食い違っていないかを
#                   これで突き合わせる。**手で揃えるのは必ずまた外れる**ため
#   -MergeOutboxFrom / -MergeOutboxTo
#                   送信箱の中身を足すだけ（買った人は使わない）。移す先に同じ名前の
#                   送信箱が先にあったときに使う道。
#                   🔴 **ファイルを失いかねない処理なので、テストから直接呼んで固めている**
#                   （server/test/config.test.js）。画面は出さず、結果を JSON で吐く
#
# 🔴 隣の .bat とスタートメニューのショートカットから呼ばれる前提。**日本語はここに置く**
#    （.bat は cmd が CP932 で読むので非ASCII を書けない。だから案内文は全部こちら側）。
# 🔴 このファイルは **BOM 付き UTF-8**（社法。PowerShell 5.1 が BOM 無しを CP932 として読む）。

[CmdletBinding()]
param(
  [switch]$ChooseInbox,
  [switch]$OpenInbox,
  [switch]$OpenOutbox,
  [switch]$ChooseName,
  [switch]$MakeResident,
  [switch]$Uninstall,
  [switch]$FromTray,
  [switch]$MoveOutbox,
  [switch]$Pause,
  [switch]$PrintDefaults,
  [string]$MergeOutboxFrom,
  [string]$MergeOutboxTo
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
# 🔴 送信箱のフォルダ名。server/lib/config.js の OUTBOX と**必ず同じ**にすること
#    （server/test/config.test.js が突き合わせます）。
$OutboxName = "Mr.Drop送信箱"

function Say  ($m) { Write-Host "   $m" }
function Head ($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "   ! $m" -ForegroundColor Yellow }
function Wait-IfAsked {
  if ($Pause) { Write-Host ""; Read-Host "  Enter を押すと閉じます" | Out-Null }
}
# 🔴 雫のメニューから呼ばれたときは、**窓が隠れています**
#    （MrDropTray が -WindowStyle Hidden で起動するため）。
#    Write-Host だけで済ませると「**誰も読めない画面に出して終わる**」ことになり、
#    押した人には「何も起きない」に見えます（2026-09-15 に実際に起きました）。
#    **画面が無いときは、必ず窓を出して知らせること。**
# 🔴 雫から呼ばれたとき、こちらには窓がありません。親を渡さないと、出した窓が
#    **ほかのウィンドウの後ろに隠れて**、押した人には見えません（本人の指摘 2026-09-15）。
#    見えない透明な窓を最前面に1つ置いて、それを親にします。
function New-TopWindow {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $f = New-Object System.Windows.Forms.Form
  $f.TopMost        = $true
  $f.ShowInTaskbar  = $false
  $f.FormBorderStyle = 'None'
  $f.Opacity        = 0
  $f.Size           = New-Object System.Drawing.Size(1, 1)
  $f.StartPosition  = 'CenterScreen'
  $f.Show()
  $f.Activate()
  return $f
}

function Show-Box ($m, $icon) {
  if (-not $FromTray) { return }        # .bat から呼ばれたときは黒い画面が出ているので要らない
  try {
    $top = New-TopWindow
    try {
      [System.Windows.Forms.MessageBox]::Show($top, $m, "Mr.Drop", 'OK', $icon) | Out-Null
    } finally { $top.Dispose() }
  } catch { }
}

function Fail ($m) {
  Write-Host ""; Write-Host "🔴 $m" -ForegroundColor Red; Write-Host ""
  # 黒い画面用の字下げは、窓に出すときは邪魔なので落とす
  Show-Box ((($m -split "`n") | ForEach-Object { $_.TrimStart() }) -join "`n") 'Warning'
  Wait-IfAsked
  exit 1
}

# ── 設定の読み書き ────────────────────────────────────────
# 🔴 config.json が無いこともある（一度も起動していないとき）。既定を組み立てて作る。
# 🔴 server/lib/config.js の defaults() と必ず同じ答えにする。ここがずれると、
#    一度も起動していない人が先に「受信先を変える.bat」を押したとき、
#    間違った既定が config.json に書き込まれて固定される（Mac 側の指摘 2026-09-12）。
#    手で揃えるのは必ずまた外れるので、`-PrintDefaults` で機械が突き合わせています。
#
# 🔴 置き場所を決め打ちしないこと（2026-09-15・買った人の報告で発覚）。
#    OneDrive の「PC のフォルダーのバックアップ」が入っていると、本当のデスクトップは
#    %USERPROFILE%\OneDrive\デスクトップ へ移っていて、%USERPROFILE%\Desktop は
#    **画面に出てこない抜け殻**として残る。そこに送信箱を作ると、買った人のデスクトップには
#    何も現れない。しかもエラーは一つも出ないので、こちらからは気づけない。
function Get-Defaults {
  $desk = [Environment]::GetFolderPath('DesktopDirectory')
  if (-not $desk) { $desk = Join-Path $env:USERPROFILE "Desktop" }

  # ダウンロードは .NET が知らないので、既知フォルダの ID でレジストリから読む。
  $dl = $null
  try {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $dl = Expand-Path (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
  } catch { }
  if (-not $dl -or $dl.Contains("%") -or -not [System.IO.Path]::IsPathRooted($dl)) {
    $dl = Join-Path $env:USERPROFILE "Downloads"
  }

  return [pscustomobject]@{
    port   = 48630
    inbox  = $dl
    outbox = Join-Path $desk "Mr.Drop送信箱"
    name   = ""
    token  = ""
  }
}

function Read-Config {
  if (Test-Path -LiteralPath $CfgFile) {
    try { return Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Fail "config.json が読めません（中身が壊れています）: $CfgFile" }
  }
  return Get-Defaults
}

# 🔴 古い config.json には、その項目がまだ無いことがある。PSCustomObject は
#    **無いプロパティに代入するとエラーになる**ので、無ければ足してから入れる。
function Set-Prop ($obj, $name, $value) {
  if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
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
  $p = Expand-Path (Read-Config).inbox
  if (-not $p) { $p = (Get-Defaults).inbox }   # 設定が欠けていても迷子にしない
  return $p
}

function Get-OutboxPath {
  $p = Expand-Path (Read-Config).outbox
  if (-not $p) { $p = (Get-Defaults).outbox }
  return $p
}

# 🔴 2つのパスが**同じ場所**かどうか。文字列では見抜けません
#    （ジャンクション・大文字小文字・別名。2026-09-15 に node 側で実際に踏みました）。
#    印を1つ置いて、もう片方から見えるかで確かめます。**これがいちばん確実**です。
function Test-SamePlace ($a, $b) {
  if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) { return $false }
  $name = ".mrdrop-same-" + [System.IO.Path]::GetRandomFileName()
  $probe = Join-Path $a $name
  try {
    [System.IO.File]::WriteAllText($probe, "")
    return (Test-Path -LiteralPath (Join-Path $b $name))
  } catch {
    return $false
  } finally {
    try { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } catch { }
  }
}

# 送信箱の中身を足す（移す先に同じ名前の送信箱が先にあったときだけ使う道）。
#
# 🔴 **上書きしない**（この道具の決まり）。同じ名前が先にあったら、残して見送る。
# 🔴 **全部移せたときだけ**、空になった元を片付ける。1つでも残っていたら元も残す。
# 🔴 **同じ場所なら何もしない。**ここを見落とすと「引っ越したつもりで本物を消す」
#    （node 側の fixStaleOutbox で実際に踏んだ）。
function Move-OutboxContents ($from, $to) {
  $moved = 0
  $left = 0
  $same = $false
  $removed = $false

  if (Test-Path -LiteralPath $from) {
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    if (Test-SamePlace $from $to) {
      $same = $true
    } else {
      foreach ($item in @(Get-ChildItem -LiteralPath $from -Force)) {
        $dest = Join-Path $to $item.Name
        if (Test-Path -LiteralPath $dest) { $left++; continue }     # 🔴 上書きしない
        try {
          Move-Item -LiteralPath $item.FullName -Destination $dest -ErrorAction Stop
          $moved++
        } catch {
          $left++
        }
      }
      if ($left -eq 0) {
        # 🔴 Remove-Item は中身があると確認を求めて止まる（画面の無い所では固まる）。
        #    空のときだけ消したいので .NET で消す（空でなければ例外になって何も起きない）。
        try { [System.IO.Directory]::Delete($from); $removed = $true } catch { }
      }
    }
  }
  return [pscustomobject]@{ moved = $moved; left = $left; same = $same; removed = $removed }
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

# ── 既定を吐くだけ（テスト用。買った人は使わない） ────────
# 🔴 node 側の既定と食い違っていないかを、server/test/config.test.js が読みます。
#    日本語（…\OneDrive\デスクトップ）が化けないよう、UTF-8 で出すこと。
if ($PrintDefaults) {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
  (Get-Defaults) | ConvertTo-Json -Compress
  exit 0
}

# ── 引っ越しだけ走らせる（テスト用。買った人は使わない） ──
# 🔴 ファイルを失いかねない処理なので、テストから直接呼んで固めています。
if ($MergeOutboxFrom) {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
  if (-not $MergeOutboxTo) { Fail "-MergeOutboxTo も要ります。" }
  (Move-OutboxContents $MergeOutboxFrom $MergeOutboxTo) | ConvertTo-Json -Compress
  exit 0
}

# ── 受信先を変える ────────────────────────────────────────
if ($ChooseInbox) {
  Head "受信先を変える"
  $now = Get-InboxPath
  Say "いまの受信先: $now"
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
    Fail "フォルダ選択の画面を出せません（STA ではありません）。`n   隣の「受信先を変える.bat」から実行してください。"
  }

  # 🔴 親を渡さないと、選ぶ画面がほかのウィンドウの後ろに出る（本人の指摘 2026-09-15）。
  $top = $null
  try { $top = New-TopWindow } catch { }
  $res = if ($top) { $dlg.ShowDialog($top) } else { $dlg.ShowDialog() }
  if ($top) { $top.Dispose() }

  if ($res -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host ""
    Say "やめました。受信先は変えていません。"
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
  Set-Prop $cfg "inbox" $new
  Write-Config $cfg

  Write-Host ""
  Say "受信先を変えました: $new"
  # 🔴 雫から呼ばれたときは黒い画面が見えない。必ず窓で知らせる。
  Show-Box "受信先を変えました:`n`n$new" 'Information'
  if (Restart-Tray) { Say "常駐を入れ直したので、もう効いています。" }
  else { Warn "動いていなければ、次に Mr.Drop を開いたときから効きます。" }
  Write-Host ""
  Wait-IfAsked
  exit 0
}

# ── 受信先を開く ──────────────────────────────────────────
if ($OpenInbox) {
  $p = Get-InboxPath
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  Start-Process explorer.exe $p
  exit 0
}

# ── 送信箱を開く ──────────────────────────────────────────
# 🔴 送信箱はデスクトップの中ですが、**デスクトップの場所は人によって違います**
#    （OneDrive の「PC のフォルダーのバックアップ」を入れていると別の場所にあります）。
#    2026-09-15 に買った人が「デスクトップに出てこない」で詰まりました。ここが逃げ道です。
if ($OpenOutbox) {
  $p = Get-OutboxPath
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  Start-Process explorer.exe $p
  exit 0
}

# ── 送信箱を移動する ──────────────────────────────────────
# 🔴 **「Mr.Drop送信箱」フォルダごと**移します（本人の指示 2026-09-15）。
#    選んでもらうのは**置き場所（親フォルダ）**だけで、送信箱の名前は変えません。
#
#    前は「好きなフォルダを送信箱にする」作りでした。それだと**買った人の持ち物を
#    送信箱にできてしまい、次に変えたときその中身を丸ごと運ぶ**事故を起こしました
#    （ビデオ → デスクトップで、ビデオの中身7つが動いた）。
#    **フォルダごと動かす形なら、他人の持ち物に触る余地がそもそもありません。**
#    前の場所に空の送信箱が残ることもありません。
if ($MoveOutbox) {
  Head "送信箱を移動する"
  $now = Get-OutboxPath
  Say "いまの送信箱: $now"
  Write-Host ""
  Say "「$OutboxName」フォルダごと、選んだ場所へ移します。"
  Say "中身もそのまま付いていきます。"

  Add-Type -AssemblyName System.Windows.Forms

  # 🔴 ShowDialog は STA スレッドでないと黙って失敗する（黙って何も起きないのが最悪）。
  if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Fail "フォルダ選択の画面を出せません（STA ではありません）。`n   タスクバーの雫のメニューから実行してください。"
  }

  # 🔴 親を渡さないと、選ぶ画面がほかのウィンドウの後ろに出る（本人の指摘）。
  $top = $null
  try { $top = New-TopWindow } catch { }
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description  = "「$OutboxName」をどこに置きますか（フォルダごと、その中へ移します）"
  $dlg.SelectedPath = Split-Path -Parent $now
  $dlg.ShowNewFolderButton = $true
  $res = if ($top) { $dlg.ShowDialog($top) } else { $dlg.ShowDialog() }
  if ($top) { $top.Dispose() }

  if ($res -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host ""
    Say "やめました。送信箱は動かしていません。"
    Wait-IfAsked
    exit 0
  }

  $parent = $dlg.SelectedPath
  if (-not (Test-Path -LiteralPath $parent)) { Fail "そのフォルダが見つかりません: $parent" }

  # 置ける場所かを実際に試す。動かす途中で失敗するより、いま分かった方がよい。
  $probe = Join-Path $parent ".mrdrop-write-test"
  try {
    [System.IO.File]::WriteAllText($probe, "ok")
    Remove-Item -LiteralPath $probe -Force
  } catch {
    Fail "そこには置けません（書き込めませんでした）: $parent`n   別の場所を選んでください。"
  }

  if (Test-SamePlace $parent (Split-Path -Parent $now)) {
    Write-Host ""
    Say "そこは、いまの置き場所と同じです。何も変えていません。"
    Show-Box "そこは、いまの置き場所と同じです。`n`n何も変えていません。" 'Information'
    Wait-IfAsked
    exit 0
  }

  $dest = Join-Path $parent $OutboxName
  $note = ""

  if (-not (Test-Path -LiteralPath $now)) {
    # いまの送信箱が消えている（手で消した人がいる）。新しい場所に作るだけ。
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $note = "`n`n（前の送信箱が見つからなかったので、新しく作りました）"
  } elseif (Test-Path -LiteralPath $dest) {
    # 🔴 行き先に同じ名前の送信箱が先にあった。**上書きしない**で中身を足す。
    $r = Move-OutboxContents $now $dest
    if ($r.moved -gt 0) { Say "中身を $($r.moved) 個、移しました。" }
    if ($r.left -gt 0) {
      Warn "$($r.left) 個は同じ名前が先にあったので、前の場所に残してあります:"
      Say "  $now"
      $note = "`n`n$($r.left) 個は同じ名前が先にあったので、前の場所に残してあります:`n$now"
    } else {
      $note = "`n`n（行き先に同じ名前の送信箱があったので、中身を足しました）"
    }
  } else {
    # ふつうはこちら。**フォルダごと**動かす。
    try {
      Move-Item -LiteralPath $now -Destination $dest -ErrorAction Stop
    } catch {
      Fail "動かせませんでした:`n   $now`n   → $dest`n   $($_.Exception.Message)"
    }
  }

  $cfg = Read-Config
  Set-Prop $cfg "outbox" $dest
  Write-Config $cfg

  Write-Host ""
  Say "送信箱を動かしました: $dest"
  # 🔴 雫から呼ばれたときは黒い画面が見えない。必ず窓で知らせる。
  Show-Box ("送信箱を動かしました:`n`n$dest" + $note) 'Information'
  if (Restart-Tray) { Say "常駐を入れ直したので、もう効いています。" }
  else { Warn "動いていなければ、次に Mr.Drop を開いたときから効きます。" }
  Write-Host ""
  Wait-IfAsked
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
    # 🔴 ここは install-windows.ps1 の最後の案内と**同じことを2回目に言う場所**。
    #    Windows 11 は新しいトレイアイコンを既定で「∧」の中に隠すので、
    #    片方だけ直すと、下に出るこちらが古いまま残る（実際そうなった）。
    Say "🔵 タスクバーの右下に Mr.Drop のアイコン（青い雫）が出ています。"
    Say "   見当たらないときは「∧」を押してください（Windows 11 は最初は隠します）。"
    Say "   雫をドラッグしてタスクバーへ出しておくと、ひと目で分かります。"
    Say "   右クリックで 受信先を開く / 受信先を変える / 取扱説明書 /"
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
  Say "🔵 届いたファイルは消しません。受信先も送信箱も、そのまま残ります。"
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
