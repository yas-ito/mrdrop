# Mr.Drop を「いつでも使える状態」にする。
#
#   .\scripts\install-windows.ps1            入れる（写す・壁を開ける・ログオン時に自動起動）
#   .\scripts\install-windows.ps1 -Status    いまどうなっているかを見るだけ
#   .\scripts\install-windows.ps1 -Uninstall 入れる前に戻す（届いたファイルは消しません）
#
# 🔴 管理者が要ります（ファイアウォールと、窓を出さない自動起動 S4U の登録）。
#
# 🔴 **展開したフォルダから直接動かさない**（本人が実際につまずいた 2026-09-12）。
#    ダウンロードフォルダで展開してここを押す人が普通なので、そのまま動かすと
#    「片付けようとしたら消せない」「片付けたら黙って壊れる」のどちらかになる。
#    だから中身を %LOCALAPPDATA%\MrDrop\app へ写し、タスクは写した先を指す。
#    展開したフォルダは、押したあと捨ててよい。どこで展開しても構わない。

[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Repo      = Split-Path -Parent $PSScriptRoot
$TaskName  = "MrDrop"
$RuleTcp   = "MrDrop (受信 TCP)"
$RuleUdp   = "MrDrop (自動発見 mDNS UDP 5353)"

# 置き場所。app だけを入れ替えれば版を上げられるよう、設定と記録は1つ上に置く。
$AppDir    = Join-Path $env:LOCALAPPDATA "MrDrop"
$AppRoot   = Join-Path $AppDir "app"                # ← プログラム本体を写す先
$CfgFile   = Join-Path $AppDir "config.json"        # ← server/lib/config.js の defaultFile と同じ
$LogFile   = Join-Path $AppDir "mrdrop.log"
$OldVbs    = Join-Path $AppDir "start-hidden.vbs"   # 昔の作り。あれば片付ける
$MenuDir   = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Mr.Drop"

# 🔴 写すのは**これだけ**。.bat は写さない。
#    cmd.exe は実行中の .bat を開いたまま行単位で読み直すので、やめる操作で
#    自分のいるフォルダを消すと「バッチ ファイルが見つかりません」になる。
#    入れたあとの入口はスタートメニューのショートカット（powershell を直接呼ぶ）。
$CopyDirs  = @("server", "scripts", "node")
$CopyFiles = @("取扱説明書.html")

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
# 同梱されていれば PATH より先にそちらを使う。受け取った人が Node を入れていなくても動く。
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

# 動いているものを止めて、**番号が空くまで待つ**。
# 🔴 Stop-ScheduledTask はすぐには殺さない。待たずに先へ進むと、
#    ① 写すときに node.exe が掴まれたままで上書きできない
#    ② 古い方が番号を握ったまま新しい方が立ち上がって、両方死ぬ（実際に踏んだ）
function Stop-Running($port) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
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
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    Say "自動起動       : あり（$($task.State) / $($task.Principal.LogonType)）"
    Say "  動かすもの   : $($task.Actions[0].Execute)"
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Say "  最後の実行   : $($info.LastRunTime)  結果: $($info.LastTaskResult)"
  } else { Warn "自動起動       : ありません" }
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

  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Say "自動起動を外しました"
  }
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
    try {
      Remove-Item -LiteralPath $AppDir -Recurse -Force -ErrorAction Stop
      Say "入れたもの・設定・記録を消しました（$AppDir）"
    } catch {
      Warn "消しきれませんでした: $AppDir"
      Warn "パソコンを再起動してから、このフォルダを手で消してください。"
    }
  }

  Write-Host ""
  Say "🔵 届いたファイルはそのままです（保存先も送信箱も触っていません）。"
  Write-Host ""
  exit 0
}

# ── 入れる ─────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath (Join-Path $Repo "server\mrdrop.js"))) {
  Fail "server\mrdrop.js が見つかりません。ZIP をフォルダごと展開してください。"
}
if (-not (Get-NodePath $Repo)) {
  Fail "Node が見つかりません。先に Node を入れてください（https://nodejs.org/ja の LTS）。"
}

# 🔴 管理者が要る理由は2つ:
#    ① ファイアウォールを開ける（すでに開いていれば要らない）
#    ② 窓を出さない自動起動（S4U）の登録。これは既定で管理者しか登録できない
if (-not (Test-Admin)) {
  Fail "管理者の PowerShell で実行してください（ファイアウォールと、窓を出さない自動起動の登録に要ります）。"
}

$port = Get-Port

Head "1. この PC の中へ写す"
Say "写す先 : $AppRoot"
if ($Repo -eq $AppRoot) {
  Say "すでにここから動いています（写しません）"
} else {
  # 動いているものを先に止める。node.exe を掴まれたままだと上書きできない。
  if (-not (Stop-Running $port)) {
    Warn "前のものが $port 番を離しません。パソコンを再起動してからやり直してください。"
  }
  New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null
  foreach ($d in $CopyDirs) {
    $from = Join-Path $Repo $d
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $AppRoot $d
    # /MIR で古い版の残骸も消える。robocopy の 0〜7 は成功、8 以上が失敗。
    # 🔴 /XF *.bat … 「入れたあとの場所に .bat を置かない」を守る。
    #    scripts\ をまるごと写すので、その中の run-once.bat がここを
    #    すり抜けていた（2026-09-12 の実測で発覚）。
    robocopy $from $to /MIR /XF *.bat /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "写せませんでした（$from → $to）。robocopy の戻り値: $LASTEXITCODE" }
    Say "  $d"
  }
  foreach ($f in $CopyFiles) {
    $from = Join-Path $Repo $f
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $AppRoot $f) -Force; Say "  $f" }
  }
  # 🔴 /XF で除いたファイルは、/MIR でも**消えない**（実測 2026-09-12）。
  #    robocopy の除外は「無かったことにする」なので、古い版が置いていった .bat が
  #    ここに残り続ける。除外だけでは足りないので、写したあとに自分で掃く。
  #    （入れた場所に .bat を置かない理由は、上の $CopyDirs のところに書いてある）
  Get-ChildItem -LiteralPath $AppRoot -Recurse -Filter *.bat -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
  # 展開したフォルダに古い config.json があって、こちらに無いなら引き継ぐ
  # （run-once.bat しか使っていなかった人の保存先を捨てないため）。
  $oldCfg = Join-Path $Repo "config.json"
  if ((Test-Path -LiteralPath $oldCfg) -and -not (Test-Path -LiteralPath $CfgFile)) {
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    Copy-Item -LiteralPath $oldCfg -Destination $CfgFile -Force
    Say "  前の設定を引き継ぎました"
  }
}
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
$Entry = Join-Path $AppRoot "server\mrdrop.js"
$node  = Get-NodePath $AppRoot
if (-not $node) { Fail "写したあとに Node が見つかりません: $AppRoot" }

Head "2. ファイアウォールを開ける"
$missing = @($RuleTcp, $RuleUdp) | Where-Object { -not (Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue) }
if ($missing.Count -eq 0) {
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

Head "3. ログオンしたら勝手に動くようにする"
# 🔴 node を直接起動する。VBS や cmd を挟むと引用符で必ず事故る（実際に踏んだ）。
#    窓を出さないのは S4U（対話セッションを持たない実行）でやる。パスワードは要らない。
#    記録は mrdrop.js が自分で $LogFile に書くので、リダイレクトも不要。
if (Test-Path -LiteralPath $OldVbs) { Remove-Item -LiteralPath $OldVbs -Force; Say "昔の起動役（VBS）を片付けました" }

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
$me        = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action    = New-ScheduledTaskAction -Execute $node -Argument """$Entry""" -WorkingDirectory $AppRoot
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $me
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U -RunLevel Limited
$set       = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
               -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Principal $principal -Settings $set -Description "iPhone から同じ Wi-Fi でファイルを受け取る常駐" | Out-Null

# 🔴 Register-ScheduledTask は CIM 越しなので、失敗しても $ErrorActionPreference="Stop" で
#    止まらないことがある（実際にアクセス拒否を握りつぶして「作りました」と嘘をついた）。
#    作れたかどうかは、必ず自分の目で確かめる。
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
  Fail "タスクを作れませんでした。上のエラーを見てください。"
}
Say "タスク $TaskName を作りました（$me / S4U）"

Head "4. スタートメニューに入口を作る"
# 🔴 ここが入れたあとの唯一の入口。展開したフォルダを捨てても使えるようにする。
#    ショートカットは powershell を直接呼ぶ（.bat を挟むと、やめるときに
#    cmd.exe が自分の .bat を掴んだまま消されて事故る）。
$ps        = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$settings  = Join-Path $AppRoot "scripts\settings-windows.ps1"
$common    = "-NoProfile -ExecutionPolicy Bypass -File ""$settings"""
New-Item -ItemType Directory -Path $MenuDir -Force | Out-Null
Get-ChildItem -LiteralPath $MenuDir -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force
New-Shortcut (Join-Path $MenuDir "保存先を変える.lnk")   $ps "$common -ChooseInbox -Pause" $AppRoot "iPhone から届いたものを入れるフォルダを選ぶ"
New-Shortcut (Join-Path $MenuDir "保存先を開く.lnk")     $ps "$common -OpenInbox"          $AppRoot "届いたものが入るフォルダを開く"
New-Shortcut (Join-Path $MenuDir "Mr.Drop をアンインストール.lnk") $ps "$common -Uninstall -Pause" $AppRoot "Mr.Drop をこの PC から外す（届いたファイルは残ります）"
$manual = Join-Path $AppRoot "取扱説明書.html"
if (Test-Path -LiteralPath $manual) {
  New-Shortcut (Join-Path $MenuDir "取扱説明書.lnk") $manual $null $AppRoot "Mr.Drop の取扱説明書"
}
Say "スタートメニュー > Mr.Drop に入れました"

Head "5. いま動かす"
Start-ScheduledTask -TaskName $TaskName

# 🔴 決め打ちで数秒待つと、まだ上がっていないのに「失敗」と言ってしまう。上がるまで見る。
$up = $false
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 500
  if (Test-Listening $port) { $up = $true; break }
}
if ($up) { Say "動き出しました（$([math]::Round($i * 0.5, 1)) 秒）" }
else { Warn "20秒待っても上がりませんでした。$LogFile を見てください。" }

Write-Host ""
if ($up) {
  Write-Host "  済みました。iPhone の Safari で開いてください:" -ForegroundColor Green
  Write-Host "    http://$($env:COMPUTERNAME.ToLower()).local:$port"
} else {
  Write-Host "  設定は済みましたが、まだ動いていません。" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  🔵 展開したフォルダは、もう消して構いません。" -ForegroundColor Green
Write-Host "     この PC の中（$AppRoot）へ写してあります。"
Write-Host ""
Write-Host "  保存先を変える : スタートメニュー > Mr.Drop > 保存先を変える"
Write-Host "  外したいとき   : スタートメニュー > Mr.Drop > Mr.Drop をアンインストール"
Write-Host ""
