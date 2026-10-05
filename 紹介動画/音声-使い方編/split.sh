#!/bin/bash
# MiniMax Audio（Web）で1回に作った WAV を、場面ごと（S1〜S6）に切り分ける。
#
#   bash 紹介動画/音声-使い方編/split.sh ~/Downloads/minimax-xxxx.wav
#     → ~/Movies/編集/Pr/Mr.Drop紹介動画アップデート版/音声/S1.wav … S6.wav
#
# しくみ: minimax-貼る.txt は場面の切れ目に <#2#>（2秒のポーズ）を入れてあるので、
#        1.2秒以上の無音を探せば、そこが場面の境目。
#
# 🔴 MiniMax の出力は小さい（実測 −29 LUFS）。SNS の目安 −14 LUFS まで持ち上げます。
# 🔴 「切れました」で終わらせない。**場面の数・尺・音の大きさを測って出します。**
set -euo pipefail

WAV="${1:-}"
SCENES=6                      # 台本の S1〜S6
PAUSE_MIN=1.2                 # これ以上の無音を「場面の切れ目」とみなす
NOISE=-42dB                   # 無音とみなす音の大きさ（MiniMax の実測に合わせてある）
MARGIN=0.15                   # 切り口の前後に残す余白（秒）
OUT="$HOME/Movies/編集/Pr/Mr.Drop紹介動画アップデート版/音声"

[ -n "$WAV" ] || { echo "使い方: bash split.sh <MiniMax から落とした .wav>" >&2; exit 1; }
[ -f "$WAV" ] || { echo "🔴 そのファイルがありません: $WAV" >&2; exit 1; }
command -v ffmpeg  >/dev/null || { echo "🔴 ffmpeg がありません" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "🔴 ffprobe がありません" >&2; exit 1; }

mkdir -p "$OUT"
TOTAL="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV")"

# ── 無音を探す ────────────────────────────────────────────
# 🔴 「ffmpeg | grep」は使わない。pipefail 下で左が SIGPIPE で落ちる（Mr.Drop の CLAUDE.md の罠）
LOG="$(ffmpeg -hide_banner -nostats -i "$WAV" -af "silencedetect=noise=$NOISE:d=$PAUSE_MIN" -f null - 2>&1 || true)"

# 途中の無音だけを拾う（末尾の無音は silence_end が出ないので自然に外れる）
STARTS=()
ENDS=()
while read -r line; do
  case "$line" in
    *silence_start:*) STARTS+=("$(printf '%s\n' "$line" | sed -n 's/.*silence_start: *\([0-9.]*\).*/\1/p')") ;;
    *silence_end:*)   ENDS+=("$(printf '%s\n' "$line" | sed -n 's/.*silence_end: *\([0-9.]*\).*/\1/p')") ;;
  esac
done <<< "$LOG"

N="${#ENDS[@]}"
WANT=$((SCENES - 1))
echo "全体 $(printf '%.1f' "$TOTAL") 秒 / 場面の切れ目 $N か所（欲しいのは $WANT か所）"

if [ "$N" -ne "$WANT" ]; then
  echo "" >&2
  echo "🔴 場面の切れ目が $WANT か所ではありません。切り分けを中止します。" >&2
  echo "   見つかった無音:" >&2
  for i in $(seq 0 $((N - 1))); do
    printf '     %2d) %6.2f 秒 〜 %6.2f 秒\n' "$((i + 1))" "${STARTS[$i]}" "${ENDS[$i]}" >&2
  done
  echo "" >&2
  echo "   よくある原因:" >&2
  echo "     ・<#2#> を入れ忘れた／場面を分けずに作った → minimax-貼る.txt を貼り直す" >&2
  echo "     ・話の途中の間が長くて拾われた → PAUSE_MIN を 1.5 に上げて試す" >&2
  echo "     ・場面ごとに分けて作った → その場合は切り分け不要。そのまま S1.wav … と名前を付ける" >&2
  exit 1
fi

# ── 切り分けて、−14 LUFS に持ち上げる ────────────────────
echo ""
for i in $(seq 1 "$SCENES"); do
  if [ "$i" -eq 1 ]; then FROM=0
  else FROM="$(awk -v e="${ENDS[$((i - 2))]}" -v m="$MARGIN" 'BEGIN{v=e-m; if(v<0)v=0; printf "%.3f", v}')"; fi

  if [ "$i" -eq "$SCENES" ]; then TO="$TOTAL"
  else TO="$(awk -v s="${STARTS[$((i - 1))]}" -v m="$MARGIN" 'BEGIN{printf "%.3f", s+m}')"; fi

  DUR="$(awk -v a="$FROM" -v b="$TO" 'BEGIN{printf "%.3f", b-a}')"
  DST="$OUT/S$i.wav"

  ffmpeg -hide_banner -loglevel error -y -i "$WAV" -ss "$FROM" -t "$DUR" \
    -af "loudnorm=I=-14:TP=-1.0:LRA=11" -ar 48000 -ac 1 "$DST"

  # 🔴 作って終わりにしない。実際の尺と音の大きさを測って出す
  GOT="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$DST")"
  LUFS="$(ffmpeg -hide_banner -nostats -i "$DST" -af ebur128 -f null - 2>&1 | sed -n 's/.*I: *\(-*[0-9.]*\) LUFS.*/\1/p' | tail -1)"
  printf 'S%d  %6.2f 秒  %s LUFS  %s\n' "$i" "$GOT" "${LUFS:-?}" "$DST"
done

echo ""
echo "できました: $OUT"
echo "🔵 尺は 台本-使い方編.md の「全体の流れ」の見積もりと見比べてください（±5秒なら気にしない）。"
