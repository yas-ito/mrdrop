#!/bin/bash
# 使い方編（2本目）の図を撮る。中身は ../図/shot-mac.sh をそのまま使う
# （書体の検査・倍率2で撮って縮める・大きさの読み返しは、あちらに1つだけ置いてあります）。
#
#   bash 紹介動画/図-使い方編/shot-mac.sh          → 編集フォルダの 図/ へ6枚
#   bash 紹介動画/図-使い方編/shot-mac.sh s5_all   → s5_all だけ撮る
#
# 🔴 出す場所は**本人の編集フォルダ**です（2026-09-16 に本人が移した先）。
#    _build に出すと、撮り直したときに古い方を Premiere に置いたままになる。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

EDIT="$HOME/Movies/編集/Pr/Mr.Drop紹介動画アップデート版/図"
[ -d "$(dirname "$EDIT")" ] || { echo "🔴 編集フォルダがありません: $(dirname "$EDIT")" >&2; exit 1; }
mkdir -p "$EDIT"

FIGDIR="$HERE" OUTDIR="$EDIT" bash "$HERE/../図/shot-mac.sh" "$@"
