#!/bin/bash
# Mac でログイン時に受信サーバーを立ち上げる（launchd）。Windows の scripts/install-windows.ps1 に相当。
#
#   入れる:  bash scripts/install-mac.sh
#   外す:    bash scripts/install-mac.sh --uninstall
#
# 🔴 受信箱の既定（%USERPROFILE%\Desktop\受信箱）は Mac で展開されないので、
#    ここで config.json を作って Mac 向けの場所を書いておく。
set -euo pipefail

LABEL="jp.yastools.mrdrop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/config.json"
INBOX="${MRDROP_INBOX:-$HOME/Downloads/受信箱}"
LOGDIR="$HOME/Library/Logs/MrDrop"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "常駐を外しました（$PLIST を削除）"
  exit 0
fi

NODE="$(command -v node || true)"
[ -n "$NODE" ] || { echo "🔴 node が見つかりません。brew install node してください" >&2; exit 1; }

mkdir -p "$INBOX" "$HOME/Downloads/送信箱" "$LOGDIR" "$HOME/Library/LaunchAgents"

# 置き場所だけ書いた config.json を作る（既にあれば触らない）
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<JSON
{
  "port": 48630,
  "inbox": "$INBOX",
  "outbox": "$HOME/Downloads/送信箱",
  "name": "",
  "token": ""
}
JSON
  echo "config.json を作りました（受信箱: $INBOX）"
else
  echo "config.json は既にあるので触りません（$CONFIG）"
fi

cat > "$PLIST" <<PLI
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE</string>
    <string>$ROOT/server/mrdrop.js</string>
    <string>--config</string>
    <string>$CONFIG</string>
  </array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>RunAtLoad</key><true/>
  <!-- 落ちても立ち上げ直す。ただし自分で止めたときは追いかけない -->
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$LOGDIR/mrdrop.out.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/mrdrop.err.log</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLI

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 1
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "✅ 常駐しました。ログイン時に自動で立ち上がります"
  echo "   受信箱: $INBOX"
  echo "   記録:   $LOGDIR/mrdrop.out.log"
  echo "   外すとき: bash scripts/install-mac.sh --uninstall"
else
  echo "🔴 登録できませんでした。$LOGDIR/mrdrop.err.log を見てください" >&2
  exit 1
fi
