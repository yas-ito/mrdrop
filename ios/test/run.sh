#!/bin/bash
# 日付の引き継ぎを確かめる:  bash ios/test/run.sh
#
# 🔴 Xcode のテストターゲットは作っていない。`Shared/FileDate.swift` は Mac でもそのまま
#    動くので、Mac のコマンドとして組み立てて走らせる（シミュレータも実機も要らない）。
# 🔵 動画の分だけ ffmpeg で素材を作る。無ければその節を飛ばす（写真と書類の分は必ず走る）。
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d /tmp/mrdrop-datetest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if command -v ffmpeg >/dev/null 2>&1; then
  # 撮影日時を持った動画。中の値は main.swift の movTaken / mp4Taken と対で直すこと
  ffmpeg -y -v error -f lavfi -i testsrc=size=320x240:rate=30:duration=2 \
    -f lavfi -i sine=frequency=440:duration=2 -c:v h264 -c:a aac \
    -metadata creation_time="2019-05-03T14:25:36+0900" "$WORK/sample.mov"
  ffmpeg -y -v error -f lavfi -i testsrc=size=320x240:rate=30:duration=2 \
    -f lavfi -i sine=frequency=440:duration=2 -c:v h264 -c:a aac \
    -metadata creation_time="2021-11-07T09:01:02+0900" "$WORK/sample.mp4"
  ffmpeg -y -v error -f lavfi -i testsrc=size=320x240:rate=30:duration=1 \
    -c:v h264 -map_metadata -1 "$WORK/nodate.mp4"
else
  echo "⚠️ ffmpeg が無いので、動画の分は飛ばします"
fi

swiftc -O -suppress-warnings -o "$WORK/datetest" "$HERE/../Shared/FileDate.swift" "$HERE/main.swift"
"$WORK/datetest" "$WORK"
