# Mr.Drop を「いつでも使える状態」にする。
#
#   .\scripts\install-windows.ps1            入れる（写す・壁を開ける・タスクバーに常駐）
#   .\scripts\install-windows.ps1 -Status    いまどうなっているかを見るだけ
#   .\scripts\install-windows.ps1 -Uninstall 入れる前に戻す（届いたファイルは消しません）
#
# 🔴 管理者が要るのは**ファイアウォールを開ける1回だけ**です。
#    自動起動はレジストリの Run なので、管理者は要りません。
#
# 🔴 **展開したフォルダから直接動かさない**（本人が実際につまずいた 2026-09-12）。
#    ダウンロードフォルダで展開してここを押す人が普通なので、そのまま動かすと
#    「片付けようとしたら消せない」「片付けたら黙って壊れる」のどちらかになる。
#    だから中身を %LOCALAPPDATA%\MrDrop\app へ写し、そこから動かす。
#    展開したフォルダは、押したあと捨ててよい。どこで展開しても構わない。
#
# 🔴 常駐は **MrDropTray.exe（タスクバー右下のアイコン）** が受け持つ（本人決定 2026-09-12）。
#    アイコンが node を子として抱え、アイコンを終了すれば本体も終わる。
#    Mac 版（メニューバー常駐）とまったく同じ考え方。
#    前はタスクスケジューラの S4U で窓なし常駐にしていたが、
#    **動いているかがどこにも見えない**のが致命的だった。古いタスクはここで片付ける。

[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Repo      = Split-Path -Parent $PSScriptRoot
$OldTask   = "MrDrop"                               # 昔の作り。あれば外す
$RuleTcp   = "MrDrop (受信 TCP)"
$RuleUdp   = "MrDrop (自動発見 mDNS UDP 5353)"

# 置き場所。app だけを入れ替えれば版を上げられるよう、設定と記録は1つ上に置く。
$AppDir    = Join-Path $env:LOCALAPPDATA "MrDrop"
$AppRoot   = Join-Path $AppDir "app"                # ← プログラム本体を写す先
$CfgFile   = Join-Path $AppDir "config.json"        # ← server/lib/config.js の defaultFile と同じ
$LogFile   = Join-Path $AppDir "mrdrop.log"
$OldVbs    = Join-Path $AppDir "start-hidden.vbs"   # もっと昔の作り。あれば片付ける
$MenuDir   = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Mr.Drop"
$TrayExe   = Join-Path $AppRoot "MrDropTray.exe"
$RunKey    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunName   = "MrDrop"

# 🔴 写すのは**これだけ**。.bat は写さない。
#    cmd.exe は実行中の .bat を開いたまま行単位で読み直すので、やめる操作で
#    自分のいるフォルダを消すと「バッチ ファイルが見つかりません」になる。
$CopyDirs  = @("server", "scripts", "node")
$CopyFiles = @("取扱説明書.html", "MrDropTray.exe")

function Head($s) { Write-Host ""; Write-Host "== $s" -ForegroundColor Cyan }
function Say($s)  { Write-Host "   $s" }
function Warn($s) { Write-Host "   ! $s" -ForegroundColor Yellow }
function Fail($s) { Write-Host "   x $s" -ForegroundColor Red; exit 1 }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 配布物には node.exe を同梱できる（build/make-package.js --with-node）。
function Get-NodePath($root) {
  $bundled = Join-Path $root "node\node.exe"
  if (Test-Path -LiteralPath $bundled) { return $bundled }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-Port {
  if (Test-Path -LiteralPath $CfgFile) {
    try { $c = Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.port) { return [int]$c.port } } catch { }
  }
  return 48630
}

function Test-Listening($port) {
  [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Get-TrayProcesses {
  Get-Process -Name "MrDropTray" -ErrorAction SilentlyContinue
}

# 動いているものを止めて、**番号が空くまで待つ**。
# 🔴 待たずに先へ進むと、① 写すときに node.exe を掴まれたままで上書きできない
#    ② 古い方が番号を握ったまま新しい方が立ち上がって、両方死ぬ（実際に踏んだ）
function Stop-Running($port) {
  Get-TrayProcesses | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch { } }
  Start-Sleep -Milliseconds 300
  Get-TrayProcesses | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

  # 昔の作り（タスクスケジューラ）が残っていれば、そちらも止める
  if (Get-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue
  }
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -like "*mrdrop.js*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

  foreach ($i in 1..40) {
    if (-not (Test-Listening $port)) { return $true }
    Start-Sleep -Milliseconds 300
  }
  return $false
}

function New-Shortcut($linkPath, $target, $arguments, $workDir, $desc) {
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($linkPath)
  $sc.TargetPath = $target
  if ($arguments) { $sc.Arguments = $arguments }
  if ($workDir)   { $sc.WorkingDirectory = $workDir }
  if ($desc)      { $sc.Description = $desc }
  $sc.Save()
}

# ── 状態を見る ─────────────────────────────────────────────
if ($Status) {
  Head "Mr.Drop の状態"
  $port = Get-Port
  if (Test-Path -LiteralPath $AppRoot) { Say "入っている場所 : $AppRoot" }
  else { Warn "入っている場所 : ありません（まだ入れていません）" }
  Say "いま動かした元 : $Repo"
  if (Test-Path -LiteralPath $CfgFile) { Say "設定           : $CfgFile" }
  else { Warn "設定           : $CfgFile （まだありません）" }
  Say "番号           : $port"
  $node = Get-NodePath $AppRoot
  if (-not $node) { $node = Get-NodePath $Repo }
  if ($node) { Say "Node           : $node" } else { Warn "Node が見つかりません" }
  foreach ($r in @($RuleTcp, $RuleUdp)) {
    if (Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue) { Say "壁の穴         : $r … あり" }
    else { Warn "壁の穴         : $r … ありません" }
  }
  $run = (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
  if ($run) { Say "自動起動       : あり（$run）" } else { Warn "自動起動       : ありません" }
  $tp = Get-TrayProcesses
  if ($tp) { Say "常駐アイコン   : 出ています（PID $($tp[0].Id)）" } else { Warn "常駐アイコン   : 出ていません" }
  if (Get-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue) {
    Warn "昔のタスク     : 残っています（入れ直すと片付きます）"
  }
  if (Test-Path -LiteralPath $MenuDir) { Say "スタートメニュー: $MenuDir" }
  if (Test-Listening $port) { Say "いま           : 動いています" } else { Warn "いま           : 動いていません" }
  if (Test-Path -LiteralPath $LogFile) { Say "記録           : $LogFile" }
  Write-Host ""
  exit 0
}

# ── 入れる前に戻す ─────────────────────────────────────────
if ($Uninstall) {
  Head "Mr.Drop を入れる前に戻します"
  $port = Get-Port

  # 自動起動を外す（管理者は要らない）
  if ((Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName) {
    Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue
    Say "自動起動を外しました"
  }
  # 昔の作り（タスクスケジューラ）も片付ける
  if (Get-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $OldTask -Confirm:$false -ErrorAction SilentlyContinue
    Say "昔の自動起動（タスク）も外しました"
  }

  Get-TrayProcesses | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Say "常駐アイコンを閉じました（$($_.Id)）" }
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -like "*mrdrop.js*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Say "動いていたものを止めました（$($_.ProcessId)）" }
  foreach ($i in 1..40) { if (-not (Test-Listening $port)) { break }; Start-Sleep -Milliseconds 300 }

  if (Test-Admin) {
    foreach ($r in @($RuleTcp, $RuleUdp)) {
      if (Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $r; Say "壁の穴を塞ぎました: $r"
      }
    }
  } else {
    Warn "壁の穴はそのままです（塞ぐには管理者で実行してください）"
  }

  if (Test-Path -LiteralPath $MenuDir) {
    Remove-Item -LiteralPath $MenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Say "スタートメニューから消しました"
  }
  if (Test-Path -LiteralPath $OldVbs) { Remove-Item -LiteralPath $OldVbs -Force -ErrorAction SilentlyContinue }

  # 🔴 いま自分がこの中から動いていることがある（$AppRoot\scripts\…）。
  #    PowerShell は .ps1 を掴み続けないので、自分のいるフォルダごと消せる（実測で確認）。
  #    .bat をここへ写さないのは、cmd.exe が同じことをできないため。
  if (Test-Path -LiteralPath $AppDir) {
    Start-Sleep -Milliseconds 500      # 閉じたばかりの .exe が離れるのを待つ
    try {
      Remove-Item -LiteralPath $AppDir -Recurse -Force -ErrorAction Stop
      Say "入れたもの・設定・記録を消しました（$AppDir）"
    } catch {
      Warn "消しきれませんでした: $AppDir"
      Warn "パソコンを再起動してから、このフォルダを手で消してください。"
    }
  }

  Write-Host ""
  Say "🔵 届いたファイルはそのままです（受信先も送信箱も触っていません）。"
  Write-Host ""
  exit 0
}

# ── 入れる ─────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath (Join-Path $Repo "server\mrdrop.js"))) {
  Fail "server\mrdrop.js が見つかりません。ZIP をフォルダごと展開してください。"
}
if (-not (Test-Path -LiteralPath (Join-Path $Repo "MrDropTray.exe"))) {
  Fail "MrDropTray.exe が見つかりません。ZIP をフォルダごと展開してください。"
}
if (-not (Get-NodePath $Repo)) {
  Fail "Node が見つかりません。先に Node を入れてください（https://nodejs.org/ja の LTS）。"
}

# 🔴 管理者が要るのはファイアウォールだけ。すでに開いていれば無しでも通る。
$port = Get-Port
$needFirewall = @($RuleTcp, $RuleUdp) | Where-Object { -not (Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue) }
if ($needFirewall.Count -gt 0 -and -not (Test-Admin)) {
  Fail "管理者の PowerShell で実行してください（ファイアウォールを開けるのに要ります）。"
}

Head "1. この PC の中へ写す"
Say "写す先 : $AppRoot"
if ($Repo -eq $AppRoot) {
  Say "すでにここから動いています（写しません）"
} else {
  if (-not (Stop-Running $port)) {
    Warn "前のものが $port 番を離しません。パソコンを再起動してからやり直してください。"
  }
  New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
  foreach ($d in $CopyDirs) {
    $from = Join-Path $Repo $d
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $AppRoot $d
    # /MIR で古い版の残骸も消える。robocopy の 0〜7 は成功、8 以上が失敗。
    # 🔴 /XF *.bat …「入れたあとの場所に .bat を置かない」を守る。
    robocopy $from $to /MIR /XF *.bat /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "写せませんでした（$from → $to）。robocopy の戻り値: $LASTEXITCODE" }
    Say "  $d"
  }
  foreach ($f in $CopyFiles) {
    $from = Join-Path $Repo $f
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $AppRoot $f) -Force; Say "  $f" }
  }
  # 🔴 /XF で除いたファイルは /MIR でも**消えない**（実測 2026-09-12）。
  #    robocopy の除外は「無かったことにする」なので、古い版が置いていった .bat が
  #    ここに残り続ける。除外だけでは足りないので、写したあとに自分で掃く。
  Get-ChildItem -LiteralPath $AppRoot -Recurse -Filter *.bat -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
  # 展開したフォルダに古い config.json があって、こちらに無いなら引き継ぐ。
  $oldCfg = Join-Path $Repo "config.json"
  if ((Test-Path -LiteralPath $oldCfg) -and -not (Test-Path -LiteralPath $CfgFile)) {
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    Copy-Item -LiteralPath $oldCfg -Destination $CfgFile -Force
    Say "  前の設定を引き継ぎました"
  }
}
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $TrayExe)) { Fail "写したあとに MrDropTray.exe が見つかりません: $AppRoot" }

Head "2. ファイアウォールを開ける"
if ($needFirewall.Count -eq 0) {
  Say "すでに開いています（触りません）"
} else {
  # 🔴 プライベート（家・職場）だけ。公衆 Wi-Fi では開けない。
  foreach ($spec in @(
      @{ Name = $RuleTcp; Proto = "TCP"; Port = $port },
      @{ Name = $RuleUdp; Proto = "UDP"; Port = 5353 })) {
    if (Get-NetFirewallRule -DisplayName $spec.Name -ErrorAction SilentlyContinue) {
      Remove-NetFirewallRule -DisplayName $spec.Name
    }
    New-NetFirewallRule -DisplayName $spec.Name -Direction Inbound -Action Allow `
      -Protocol $spec.Proto -LocalPort $spec.Port -Profile Private | Out-Null
    Say "$($spec.Proto) $($spec.Port) を開けました（プライベートのみ）"
  }
}

Head "3. 昔の作りを片付ける"
# 🔴 前の版はタスクスケジューラ（S4U）で常駐していた。残したままだと
#    二重に立ち上がって「48630 番はすでに使われています」で両方死ぬ。
if (Get-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $OldTask -Confirm:$false -ErrorAction SilentlyContinue
  Say "昔の自動起動（タスク $OldTask）を外しました"
} else {
  Say "残っていません"
}
if (Test-Path -LiteralPath $OldVbs) { Remove-Item -LiteralPath $OldVbs -Force; Say "昔の起動役（VBS）を片付けました" }

Head "4. ログオンしたら勝手に出るようにする"
# 🔴 レジストリの Run。管理者は要らない。アイコン側のメニューからも切り替えられる。
Set-ItemProperty -Path $RunKey -Name $RunName -Value ("`"$TrayExe`"")
$run = (Get-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
if (-not $run) { Fail "自動起動を登録できませんでした。" }
Say "登録しました: $run"

Head "5. スタートメニューに入口を作る"
# 🔴 ふだんの入口は**タスクバー右下のアイコン**。ここは「閉じてしまった人が戻る道」。
New-Item -ItemType Directory -Path $MenuDir -Force | Out-Null
Get-ChildItem -LiteralPath $MenuDir -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force
New-Shortcut (Join-Path $MenuDir "Mr.Drop.lnk") $TrayExe $null $AppRoot "Mr.Drop を動かす（タスクバー右下に出ます）"
$ps       = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$settings = Join-Path $AppRoot "scripts\settings-windows.ps1"
New-Shortcut (Join-Path $MenuDir "Mr.Drop をアンインストール.lnk") $ps `
  "-NoProfile -ExecutionPolicy Bypass -File `"$settings`" -Uninstall -Pause" $AppRoot `
  "Mr.Drop をこの PC から外す（届いたファイルは残ります）"
$manual = Join-Path $AppRoot "取扱説明書.html"
if (Test-Path -LiteralPath $manual) {
  New-Shortcut (Join-Path $MenuDir "取扱説明書.lnk") $manual $null $AppRoot "Mr.Drop の取扱説明書"
}
Say "スタートメニュー > Mr.Drop に入れました"

Head "6. いま動かす"
# 🔴 管理者で動かしたままにしない。アイコンは**ふだんの自分**として出す必要がある
#    （管理者の常駐は、他のアプリからドラッグできないなど行儀が悪い）。
#    explorer.exe に頼むと、ログオンしている本人として立ち上がる。
if (Test-Admin) {
  Start-Process -FilePath (Join-Path $env:SystemRoot "explorer.exe") -ArgumentList "`"$TrayExe`""
} else {
  Start-Process -FilePath $TrayExe -WorkingDirectory $AppRoot
}

$up = $false
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 500
  if (Test-Listening $port) { $up = $true; break }
}
if ($up) { Say "動き出しました（$([math]::Round($i * 0.5, 1)) 秒）" }
else { Warn "20秒待っても上がりませんでした。$LogFile を見てください。" }

Write-Host ""
if ($up) {
  # 🔴 ここで URL を出さないこと（2026-09-15・本人の指摘）。
  #    1.0.0 の頃は Safari が唯一の入口だったので正しかったが、いまは iPhone アプリが
  #    **設定なしでこの PC を見つける**。URL を見せても iPhone で手打ちさせるだけで、
  #    そもそも黒い画面の文字を iPhone へ渡す手立てが無い。
  #    アプリを使わない道は取扱説明書にある。入れ終わった人の第一声はアプリでよい。
  Write-Host "  済みました。iPhone に「Mr.Drop」アプリを入れてください（App Store・無料）。" -ForegroundColor Green
  Write-Host "  写真アプリの共有ボタンから送ると、この PC に届きます。"
} else {
  Write-Host "  設定は済みましたが、まだ動いていません。" -ForegroundColor Yellow
}
Write-Host ""
# 🔴 Windows 11 は、新しく出たトレイアイコンを**既定で「∧」の中に隠す**。
#    「右下に出ています」とだけ言うと、押した人は「何も出ない＝動いていない」と思う
#    （タスクスケジューラをやめた理由と同じ失敗）。居場所と、出し方まで書くこと。
#    ※ レジストリの IsPromoted=1 は、あとから書いても効かない（26200 で確認済み）。
#      隠れているアイコンからの吹き出しも Windows が出さない。だからここで文字で伝える。
Write-Host "  🔵 タスクバーの右下に Mr.Drop のアイコン（青い雫）が出ています。" -ForegroundColor Green
Write-Host "     見当たらないときは「∧」を押してください。Windows 11 は新しいアイコンを"
Write-Host "     最初は隠します。雫をドラッグしてタスクバーへ出しておくと、"
Write-Host "     動いているかがひと目で分かります。"
Write-Host "     右クリックで「受信先を変える」「アンインストール」ができます。"
Write-Host ""
Write-Host "  🔵 展開したフォルダは、もう消して構いません。" -ForegroundColor Green
Write-Host "     この PC の中（$AppRoot）へ写してあります。"
Write-Host ""
