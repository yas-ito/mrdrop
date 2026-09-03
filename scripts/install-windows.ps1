# Mr.Drop を「いつでも使える状態」にする。
#
#   .\scripts\install-windows.ps1            ファイアウォールを開けて、ログオン時に自動起動させる
#   .\scripts\install-windows.ps1 -Status    いまどうなっているかを見るだけ
#   .\scripts\install-windows.ps1 -Uninstall 元に戻す
#
# 管理者が要るのは**ファイアウォールを開けるときだけ**です。
# すでに穴が開いていれば、ふつうの PowerShell でも通ります。

[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Repo      = Split-Path -Parent $PSScriptRoot
$Entry     = Join-Path $Repo "server\mrdrop.js"
$TaskName  = "MrDrop"
$RuleTcp   = "MrDrop (受信 TCP)"
$RuleUdp   = "MrDrop (自動発見 mDNS UDP 5353)"
$AppDir    = Join-Path $env:LOCALAPPDATA "MrDrop"
$LogFile   = Join-Path $AppDir "mrdrop.log"
$OldVbs    = Join-Path $AppDir "start-hidden.vbs"   # 昔の作り。あれば片付ける

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
function Get-NodePath {
  $bundled = Join-Path $Repo "node\node.exe"
  if (Test-Path $bundled) { return $bundled }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Get-Port {
  $cfgPath = Join-Path $Repo "config.json"
  if (Test-Path $cfgPath) {
    try { $c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.port) { return [int]$c.port } } catch { }
  }
  return 48630
}

function Test-Listening($port) {
  [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

# ── 状態を見る ─────────────────────────────────────────────
if ($Status) {
  Head "Mr.Drop の状態"
  $port = Get-Port
  Say "置き場所 : $Repo"
  Say "番号     : $port"
  $node = Get-NodePath
  if ($node) { Say "Node     : $node" } else { Warn "Node が見つかりません" }
  foreach ($r in @($RuleTcp, $RuleUdp)) {
    if (Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue) { Say "壁の穴   : $r … あり" }
    else { Warn "壁の穴   : $r … ありません" }
  }
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    Say "自動起動 : あり（$($task.State) / $($task.Principal.LogonType)）"
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Say "最後の実行: $($info.LastRunTime)  結果: $($info.LastTaskResult)"
  } else { Warn "自動起動 : ありません" }
  if (Test-Listening $port) { Say "いま     : 動いています" } else { Warn "いま     : 動いていません" }
  if (Test-Path $LogFile) { Say "記録     : $LogFile" }
  Write-Host ""
  exit 0
}

# ── 元に戻す ───────────────────────────────────────────────
if ($Uninstall) {
  Head "元に戻します"
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Say "自動起動を外しました"
  }
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -like "*mrdrop.js*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Say "動いていたものを止めました（$($_.ProcessId)）" }
  if (Test-Path $OldVbs) { Remove-Item $OldVbs -Force; Say "昔の起動役を消しました" }
  if (Test-Admin) {
    foreach ($r in @($RuleTcp, $RuleUdp)) {
      if (Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $r; Say "壁の穴を塞ぎました: $r"
      }
    }
  } else {
    Warn "壁の穴はそのままです（塞ぐには管理者で実行してください）"
  }
  Say "受信箱と送信箱の中身はそのままです"
  Write-Host ""
  exit 0
}

# ── 入れる ─────────────────────────────────────────────────
if (-not (Test-Path $Entry)) { Fail "$Entry が見つかりません。" }
$node = Get-NodePath
if (-not $node) { Fail "Node が見つかりません。先に Node を入れてください（https://nodejs.org/ja の LTS）。" }
$port = Get-Port

# 🔴 管理者が要る理由は2つ:
#    ① ファイアウォールを開ける（すでに開いていれば要らない）
#    ② 窓を出さない自動起動（S4U）の登録。これは既定で管理者しか登録できない
if (-not (Test-Admin)) {
  Fail "管理者の PowerShell で実行してください（ファイアウォールと、窓を出さない自動起動の登録に要ります）。"
}

Head "1. ファイアウォールを開ける"
$missing = @($RuleTcp, $RuleUdp) | Where-Object { -not (Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue) }
if ($missing.Count -eq 0) {
  Say "すでに開いています（触りません）"
} elseif (-not (Test-Admin)) {
  Fail "壁の穴を開けるには管理者が要ります。管理者の PowerShell で実行し直してください。"
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

Head "2. ログオンしたら勝手に動くようにする"
# 🔴 node を直接起動する。VBS や cmd を挟むと引用符で必ず事故る（実際に踏んだ）。
#    窓を出さないのは S4U（対話セッションを持たない実行）でやる。パスワードは要らない。
#    記録は mrdrop.js が自分で $LogFile に書くので、リダイレクトも不要。
if (Test-Path $OldVbs) { Remove-Item $OldVbs -Force; Say "昔の起動役（VBS）を片付けました" }
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
$me        = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action    = New-ScheduledTaskAction -Execute $node -Argument """$Entry""" -WorkingDirectory $Repo
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

Head "3. いま動かす"
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -like "*mrdrop.js*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
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
Write-Host "  状態を見る : .\scripts\install-windows.ps1 -Status"
Write-Host "  元に戻す   : .\scripts\install-windows.ps1 -Uninstall"
Write-Host ""
