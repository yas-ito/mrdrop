#!/bin/bash
# Mac 版 Mr.Drop（メニューバー常駐アプリ）を、ほかの人に渡せる形にする。
#
#   bash build/make-mac-app.sh                  作る → 署名 → 公証 → zip（配布用・数分かかる）
#   bash build/make-mac-app.sh --no-notarize    署名まで（手元で動かして確かめる用・公証は飛ばす）
#
# できる物: _build/MrDrop_v<版>_mac.zip（中身は Mr.Drop.app 1つ。展開してダブルクリックするだけ）
#
# Mr.Drop.app の中身:
#   Contents/MacOS/MrDrop              ← mac/main.swift（arm64 + x86_64 の universal）
#   Contents/MacOS/node                ← nodejs.org の公式バイナリ（universal・自己完結）
#   Contents/Resources/server/…        ← server/ の JS 6 本（Windows と共通・外部パッケージゼロ）
#   Contents/Resources/Node.js-LICENSE.txt
#   Contents/Resources/MrDrop.icns
#
# 🔴 Homebrew の node は同梱できない。Homebrew のライブラリに依存していて他の Mac で動かない（実測）。
#    nodejs.org の tar.gz から取り出した bin/node は自己完結なので、これを使う。
#    版は NODE_VER で固定し、SHASUMS256.txt で検算する。上げるときはここを変えるだけ。
# 🔴 node の署名は付け直す。公式の署名には get-task-allow（デバッグ用）が付いていて、
#    そのままでは公証が落ちる。mac/node.entitlements は公式が使っている権利から
#    get-task-allow だけ抜いたもの（V8 の JIT に allow-jit などが要る）。
# 🔴 zip は自前の build/make-package.js ではなく ditto で作る。実行権限と署名を保ったまま
#    入れる必要があるため（自前 zip だと .app が壊れる）。
# 🔴 「作れた」で終わらせない。中身の数・署名・公証の貼り付けを読み返して確かめる。
#
# 前提（1回だけ）:
#   ・Developer ID Application の証明書がキーチェーンにある
#   ・notarytool の資格情報が保存してある（一撃極と同じ「ichigeki-notary」を使う）:
#       xcrun notarytool store-credentials ichigeki-notary --apple-id <Apple ID> --team-id 6Q847K48UY --password <App用パスワード>
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_VER="v24.20.0"                              # nodejs.org の LTS
PROFILE="${NOTARY_PROFILE:-ichigeki-notary}"     # notarytool の資格情報（一撃極と共用）
NOTARIZE=1
for a in "$@"; do
  case "$a" in
    --no-notarize) NOTARIZE=0 ;;
    *) echo "🔴 知らない引数: $a" >&2; exit 1 ;;
  esac
done

fail() { echo "🔴 $*" >&2; exit 1; }
say()  { echo "  $*"; }

echo "=== 0. 前提 ==="
command -v swiftc >/dev/null || fail "swiftc が無い（Xcode を入れて xcode-select を通す）"
command -v lipo   >/dev/null || fail "lipo が無い"
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$REPO/package.json" | head -1)"
[ -n "$VERSION" ] || fail "package.json の version が読めない"
JSVER="$(sed -n 's/^const VERSION = "\([^"]*\)".*/\1/p' "$REPO/server/mrdrop.js" | head -1)"
[ "$JSVER" = "$VERSION" ] || fail "版数が食い違っている: package.json=$VERSION / mrdrop.js=$JSVER"
IDENT="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')"
[ -n "$IDENT" ] || fail "Developer ID Application の証明書がキーチェーンに無い"
if [ "$NOTARIZE" = 1 ]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "notarytool の資格情報「$PROFILE」が無い。冒頭の store-credentials を1回やる"
fi
say "版: $VERSION ／ 署名: $IDENT ／ 公証: $([ "$NOTARIZE" = 1 ] && echo する || echo しない)"

echo "=== 1. node（nodejs.org 公式・$NODE_VER）==="
CACHE="$REPO/_build/node"
mkdir -p "$CACHE"
(
  cd "$CACHE"
  SUMS="SHASUMS256-$NODE_VER.txt"
  [ -f "$SUMS" ] || curl -sSL --fail -o "$SUMS" "https://nodejs.org/dist/$NODE_VER/SHASUMS256.txt"
  for arch in arm64 x64; do
    tgz="node-$NODE_VER-darwin-$arch.tar.gz"
    if [ ! -f "$tgz" ]; then
      echo "  nodejs.org から $tgz を取ってくる（50MB ほど）"
      curl -sSL --fail -o "$tgz" "https://nodejs.org/dist/$NODE_VER/$tgz"
    fi
    grep " $tgz\$" "$SUMS" | shasum -a 256 -c - >/dev/null 2>&1 || fail "$tgz の検算が合わない（壊れているか、差し替えられている）"
    tar xzf "$tgz" "node-$NODE_VER-darwin-$arch/bin/node" "node-$NODE_VER-darwin-$arch/LICENSE"
  done
  lipo -create "node-$NODE_VER-darwin-arm64/bin/node" "node-$NODE_VER-darwin-x64/bin/node" -output node-universal
)
# 🔴 「コマンド | grep -q」は使わない。pipefail 下では grep が先に抜けると左側が SIGPIPE で落ち、
#    合っているのに失敗扱いになる（実際に踏んだ）。一度変数に受けてから見る。
ARCHS="$(lipo -info "$CACHE/node-universal")"
grep -q "x86_64 arm64\|arm64 x86_64" <<<"$ARCHS" || fail "node が universal になっていない: $ARCHS"
say "node: $(lipo -info "$CACHE/node-universal" | sed 's/.*are: //')（検算済み）"

echo "=== 2. コンパイル（arm64 + x86_64）==="
OUT="$REPO/_build/mac"
rm -rf "$OUT"
mkdir -p "$OUT/obj"
for t in arm64 x86_64; do
  # 🔴 -parse-as-library が無いと @main が通らない
  swiftc -O -parse-as-library -target "$t-apple-macos13.0" \
    -framework AppKit -framework ServiceManagement \
    "$REPO/mac/main.swift" -o "$OUT/obj/MrDrop-$t"
done
lipo -create "$OUT/obj/MrDrop-arm64" "$OUT/obj/MrDrop-x86_64" -output "$OUT/obj/MrDrop"
say "MrDrop: $(lipo -info "$OUT/obj/MrDrop" | sed 's/.*are: //')"

echo "=== 3. .app を組む ==="
APP="$OUT/Mr.Drop.app"
C="$APP/Contents"
mkdir -p "$C/MacOS" "$C/Resources/server/lib"
cp "$OUT/obj/MrDrop" "$C/MacOS/MrDrop"
cp "$CACHE/node-universal" "$C/MacOS/node"
chmod 755 "$C/MacOS/MrDrop" "$C/MacOS/node"
sed "s/__VERSION__/$VERSION/g" "$REPO/mac/Info.plist" > "$C/Info.plist"
plutil -lint "$C/Info.plist" >/dev/null || fail "Info.plist が壊れている"
printf 'APPL????' > "$C/PkgInfo"
cp "$REPO/mac/MrDrop.icns" "$C/Resources/MrDrop.icns"
cp "$CACHE/node-$NODE_VER-darwin-arm64/LICENSE" "$C/Resources/Node.js-LICENSE.txt"
for f in mrdrop.js lib/config.js lib/http.js lib/mdns.js lib/names.js lib/ui.js; do
  cp "$REPO/server/$f" "$C/Resources/server/$f"
done
# 🔴 物を足さない。中身がこの数とちょうど同じかを数える（署名前）
N="$(find "$APP" -type f | wc -l | tr -d ' ')"
[ "$N" = 12 ] || { find "$APP" -type f | sed 's/^/     /'; fail "中身が 12 ファイルではない（$N）"; }
say "中身: $N ファイル"

echo "=== 4. 署名（Developer ID・hardened runtime）==="
# 🔴 順序: 中の node を先に。あとから .app 全体を署名すると、node は「入れ子のコード」として封じられる
codesign --force --sign "$IDENT" --options runtime --timestamp \
  --entitlements "$REPO/mac/node.entitlements" "$C/MacOS/node"
codesign --force --sign "$IDENT" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/     /'
ENT="$(codesign -d --entitlements - "$C/MacOS/node" 2>/dev/null || true)"
if grep -q "get-task-allow" <<<"$ENT"; then fail "node に get-task-allow が残っている（公証が落ちる）"; fi
for f in "$C/MacOS/node" "$C/MacOS/MrDrop"; do
  INFO="$(codesign -dv "$f" 2>&1)"
  grep -q "flags=.*runtime" <<<"$INFO" || fail "$(basename "$f") に hardened runtime が付いていない: $INFO"
done
say "署名 OK（node・MrDrop とも hardened runtime）"

if [ "$NOTARIZE" = 1 ]; then
  echo "=== 5. 公証（Apple に送って待つ・数分）==="
  SUBMIT="$OUT/submit.zip"
  ditto -c -k --keepParent "$APP" "$SUBMIT"
  RES="$(xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait 2>&1 || true)"
  echo "$RES" | sed 's/^/     /'
  SUBID="$(echo "$RES" | sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' | head -1)"
  if ! echo "$RES" | grep -q "status: Accepted"; then
    [ -n "$SUBID" ] && xcrun notarytool log "$SUBID" --keychain-profile "$PROFILE" 2>&1 | sed 's/^/     /' >&2
    fail "公証が通らなかった"
  fi
  xcrun stapler staple "$APP" >/dev/null || fail "公証の貼り付け（staple）に失敗"
  SP="$(spctl -a -t exec -vv "$APP" 2>&1 || true)"
  grep -q "accepted" <<<"$SP" || fail "spctl が受け付けない（Gatekeeper に止められる）: $SP"
  say "公証 OK・貼り付け済み（spctl: accepted）"
else
  echo "=== 5. 公証は飛ばした（--no-notarize）。配ってはいけない ==="
fi

echo "=== 6. zip にして読み返す ==="
ZIP="$REPO/_build/MrDrop_v${VERSION}_mac.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
T="$OUT/verify"
rm -rf "$T"; mkdir -p "$T"
ditto -x -k "$ZIP" "$T"
codesign --verify --deep --strict "$T/Mr.Drop.app" || fail "zip から出した .app の署名が壊れている"
[ -x "$T/Mr.Drop.app/Contents/MacOS/node" ] || fail "zip から出した node に実行権限が無い"
if [ "$NOTARIZE" = 1 ]; then
  xcrun stapler validate "$T/Mr.Drop.app" >/dev/null || fail "zip から出した .app に公証が貼られていない"
fi
say "zip から出し直しても署名・実行権限とも無事"

echo ""
echo "できあがり: $ZIP"
echo "  サイズ: $(du -h "$ZIP" | cut -f1 | tr -d ' ')"
echo "  手元で動かす: open \"$APP\""
