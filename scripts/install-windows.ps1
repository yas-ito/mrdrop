# Mr.Drop を「いつでも使える状態」にする。
#
#   .\scripts\install-windows.ps1            ファイアウォールを開けて、ログオン時に自動起動させる
#   .\scripts\install-windows.ps1 -Status    いまどうなっているかを見るだけ
#   .\scripts\install-windows.ps1 -Uninstall 元に戻す
#
# 🔴 ファイアウォールを触るので、管理者の PowerShell で実行してください。
#    （-Status だけは管理者でなくても動きます）

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
$Launcher  = Join-Path $AppDir "start-hidden.vbs"
$LogFile   = Join-Path $AppDir "mrdrop.log"

function Head($s) { Write-Host ""; Write-Host "== $s" -ForegroundColor Cyan }
function Say($s)  { Write-Host "   $s" }
function Warn($s) { Write-Host "   ! $s" -ForegroundColor Yellow }
function Fail($s) { Write-Host "   x $s" -ForegroundColor Red; exit 1 }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Port {
  $cfgPath = Join-Path $Repo "config.json"
  if (Test-Path $cfgPath) {
    try { $c = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.port) { return [int]$c.port } } catch { }
  }
  return 48630
}

# ── 状態を見る ─────────────────────────────────────────────
if ($Status) {
  Head "Mr.Drop の状態"
  $port = Get-Port
  Say "置き場所 : $Repo"
  Say "番号     : $port"
  $node = (Get-Command node -ErrorAction SilentlyContinue)
  if ($node) { Say "Node     : $($node.Source)" } else { Warn "Node が見つかりません" }
  foreach ($r in @($RuleTcp, $RuleUdp)) {
    $exists = Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue
    if ($exists) { Say "壁の穴   : $r … あり" } else { Warn "壁の穴   : $r … ありません" }
  }
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) { Say "自動起動 : あり（$($task.State)）" } else { Warn "自動起動 : ありません" }
  $running = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  if ($running) { Say "いま     : 動いています" } else { Warn "いま     : 動いていません" }
  if (Test-Path $LogFile) { Say "記録     : $LogFile" }
  Write-Host ""
  exit 0
}

# ── 元に戻す ───────────────────────────────────────────────
if ($Uninstall) {
  if (-not (Test-Admin)) { Fail "管理者の PowerShell で実行してください。" }
  Head "元に戻します"
  foreach ($r in @($RuleTcp, $RuleUdp)) {
    if (Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue) {
      Remove-NetFirewallRule -DisplayName $r; Say "壁の穴を塞ぎました: $r"
    }
  }
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; Say "自動起動を外しました"
  }
  if (Test-Path $Launcher) { Remove-Item $Launcher -Force; Say "起動役を消しました" }
  Say "受信箱と送信箱の中身はそのままです（消したいときは手で消してください）"
  Write-Host ""
  exit 0
}

# ── 入れる ─────────────────────────────────────────────────
if (-not (Test-Admin)) {
  Fail "管理者の PowerShell で実行してください（ファイアウォールを開けるため）。"
}
if (-not (Test-Path $Entry)) { Fail "$Entry が見つかりません。" }
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { Fail "Node が見つかりません。先に Node を入れてください。" }

$port = Get-Port

Head "1. ファイアウォールを開ける"
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

Head "2. 隠れて動く起動役を作る"
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
# node をそのまま自動起動すると黒い窓が出っぱなしになる。VBS 経由で隠す。
$vbs = @"
' MrDrop を窓を出さずに起動する（install-windows.ps1 が作ります）
Set sh = CreateObject("WScript.Shell")
cmd = "cmd /c """"$($node.Source)"" ""$Entry"" >> ""$LogFile"" 2>&1"""
sh.Run cmd, 0, False
"@
# 🔴 UTF8 で書くと BOM が付き、wscript.exe が1行目で構文エラーになる。
#    wscript は .vbs を ANSI(CP932) で読むので、こちらに合わせる。
#    （`エンコード.bat` が空振りしたのと同じ種類の事故）
Set-Content -Path $Launcher -Value $vbs -Encoding Default
Say $Launcher

Head "3. ログオンしたら勝手に動くようにする"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}
$action  = New-ScheduledTaskAction -Execute "wscript.exe" -Argument """$Launcher"""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $set `
  -Description "iPhone から同じ Wi-Fi でファイルを受け取る常駐" | Out-Null
Say "タスク $TaskName を作りました"

Head "4. いま動かす"
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($listening) { Say "動き出しました" } else { Warn "まだ上がっていません。$LogFile を見てください。" }

Write-Host ""
Write-Host "  済みました。iPhone の Safari で開いてください:" -ForegroundColor Green
Write-Host "    http://$($env:COMPUTERNAME.ToLower()).local:$port"
Write-Host ""
Write-Host "  状態を見る : .\scripts\install-windows.ps1 -Status"
Write-Host "  元に戻す   : .\scripts\install-windows.ps1 -Uninstall"
Write-Host ""
