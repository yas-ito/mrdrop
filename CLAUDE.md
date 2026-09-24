# Mr.Drop — このリポジトリで作業するときの決まり

**このファイルは Claude Code が自動で読みます。**「必ずやること」だけを書いてあります。

## これは何か

iPhone から同じ Wi-Fi の Windows へ送る道具。AirDrop の代わり。

- `server/` … Windows で動く受信サーバー（Node・**外部パッケージゼロ**）
- `ios/` … iPhone アプリのソース（**Xcode が要るので Mac でしか作れない**）
- `scripts/` … ファイアウォールと自動起動の面倒を見る PowerShell

## 🔴 Mac と Windows は同じ権限です（2026-09-24 本人の決定）

どちらのパソコンでも、どこを直してもよい。「こちらは Mac の担当」という分担はしない。
道具の都合で、**動かして確かめられる場所**だけが違う：

| | 動かして確かめられるパソコン |
|---|---|
| `server/` `scripts/` | Windows（受信サーバーとファイアウォール・自動起動が Windows 用） |
| `ios/` | Mac（ビルドに Xcode が要る） |

作業を始める前に `git pull` → **`HANDOFF.md` を読む**。
終わったら**自分の欄を書き換えて** push（積み上げない・古い話は消す）。

**ブランチは `main` の1本だけ**です。一撃極の `git pushboth` は要りません
（あれは事情があって2本あるだけで、こちらは素直に `git push` で両機に届きます）。

Mac 側で最初に取ってくるとき:

```bash
cd ~/yas-tools/products     # 無ければ作る
git clone https://github.com/yas-ito/mrdrop.git
```

## 外部パッケージを入れない

`npm install` なしでいきなり動くこと自体がこの道具の価値です。
mDNS も HTTP も自前で書いてあります。**足したくなったら、まず本当に要るか考えてください。**

## 触る前に知っておくこと

- **大きい動画（数GB）が来ます。**本文は必ずディスクへ流す。`Data`／`Buffer` に溜めない
- **半端なファイルを受信箱に出さない。**途中で切れたら消す。ここは `test/http.test.js` で固定済み
- **上書きしない。**同じ名前は `(2)` にする。`fs.link` の EEXIST を衝突検出に使っています
- **`../` を弾く。**`lib/names.js` が全部引き受けます。ここを触ったらテストを必ず通すこと
- **ソースに生の制御文字を書かない。**（一度やらかしています。正規表現は `\u0000` 表記で）

## 🔴 Windows の「デスクトップ」は `%USERPROFILE%\Desktop` とは限らない

**2026-09-15、買った人の機械と本人の機械の両方で踏みました。**送信箱はデスクトップに置くので、
ここを外すと**買った人の画面には何も現れません**（しかもエラーは一つも出ません）。

1. **移っていることがある。**OneDrive の「PC のフォルダーのバックアップ」を入れると、
   本当のデスクトップは `%USERPROFILE%\OneDrive\デスクトップ` へ移り、`%USERPROFILE%\Desktop` は
   **画面に出てこない抜け殻**として残る。→ **場所は決め打ちせず OS に聞く**
   （`server/lib/config.js` の `askWindows()`）
2. 🔴 **名前が2つあるだけで、同じ場所のこともある。**`OneDrive\デスクトップ` が
   `%USERPROFILE%\Desktop` への**ジャンクション**になっている機械がある（本人の Windows がこれ）。
   `path.resolve` では見抜けない。**`fs.realpathSync.native()` で実体まで開いて比べること**
   （`samePlace()`）。見落とすと「引っ越したつもりで本物を消す」。
3. 🔴 **`reg.exe` では読めない。**出力が CP932 なので、`…\OneDrive\デスクトップ` を Node が開けない
   （外部パッケージを入れない方針のため）。**PowerShell を `-EncodedCommand` で呼んで UTF-8 で受ける**
4. 🔴 **Claude Code の作業シェルからは、本物の環境が見えない。**MSIX コンテナの中なので
   **レジストリ（HKCU）も `%LOCALAPPDATA%` も仮想側**を見ている。
   「この機械はリダイレクトされていない」と判断して**実際に間違えた**。
   **本物は `\\localhost\C$\Users\...` で回り込むと読める。**置き場所の話は必ずこちらで確かめること

## 🔴 常駐（タスクスケジューラ）で踏んだ罠

全部 Windows 実機で踏みました。**同じ所で溶かさないこと。**

1. **`process.stdout.isTTY` は嘘をつく。**タスクから起動された node には
   *見えないコンソール*が割り当てられるので `isTTY` が true になる。
   「画面が無いときだけファイルに書く」を作ると、誰も読めない画面に出して終わる。
   → 判定などせず、**常に画面とファイルの両方へ書く**。
2. **セッション0 のプロセスは通常権限では止められない。**S4U で動いている node は
   `Stop-Process` が黙って失敗する。`Get-CimInstance` の一覧にも出てこない。
   → 止めるのも入れ直すのも**管理者**。動いているかは `Get-NetTCPConnection -LocalPort` で見る。
3. **`Register-ScheduledTask` は失敗しても止まらない。**CIM 越しなので
   `$ErrorActionPreference="Stop"` が効かず、アクセス拒否を握りつぶして先へ進む。
   → 登録したら **`Get-ScheduledTask` で実在を必ず確かめる**。
4. **VBS も cmd も挟まない。**引用符が三重になって必ず事故る。実際、タスクから起動した
   `wscript` が固まった。**node を直接起動し、窓は S4U で消す**（パスワード不要）。
5. **`.ps1` は BOM 付き UTF-8。**BOM が無いと PowerShell 5.1 が CP932 として読み、
   日本語が全滅して構文エラーになる。`.gitattributes` で `*.ps1 -text` にしてある。

## 🔴 Mac でテスト用のサーバーを止めるとき

**`pkill -f "mrdrop.js --config"` を使わないこと。**
`Mr.Drop.app` も `--config` を付けて node を起動するので、**本人の常駐まで巻き添えで止まります**
（2026-09-14 に実際にやった。メニューバーの雫は残るので、止まったことに気づけない）。

止めるなら **PID を控えて、その PID だけ** 殺す:

```bash
nohup node server/mrdrop.js --config "$S/config.json" > "$S/server.log" 2>&1 &
echo $! > "$S/server.pid"
kill "$(cat "$S/server.pid")"
```

巻き添えで止めてしまったら、**`open "/Applications/Mr.Drop.app"` で開き直す**
（アプリ本体は生きているので `quit` してから開き直す）。直ったかは `node server/mrdrop.js --browse` で。

## テスト

```bash
node server/test/run.js     # サーバー（Node）
bash ios/test/run.sh        # 日付の引き継ぎ（Swift・シミュレータ不要）
```

ロジックだけでなく、実際にサーバーを立てて通しで確かめています。
**実機で踏んだ罠は必ずテストで固定してください**（例: mDNS の QU ビット）。

🔵 **iOS 側にも Xcode を使わないテストがあります。**`Shared/FileDate.swift` は Mac でも
そのまま動くので、Mac のコマンドとして組み立てて走らせています（`ios/test/run.sh`）。
EXIF・動画の作成日時・mp4 の詰め替えを、**本物のファイルを作って**測っています
（動画の分だけ ffmpeg が要る。無ければその節を飛ばします）。

## 実機で確かめるとき

```bash
node server/mrdrop.js            # 立てる
node server/mrdrop.js --browse   # 自分が LAN から見えるか確かめる
```

`--browse` で自分が見つからないなら、iPhone からも絶対に見つかりません。
**アプリ側を疑う前に、まずここを通してください。**

🔴 **ただし Mac では `--browse` が嘘をつきます**（2026-09-15 に踏んだ）。常駐は正しく広告していて
iPhone からも見えるのに、**ターミナルから起動した node だけ「見つかりませんでした」と言います**
（mDNS の返事を受け取れない＝ローカルネットワークの許可が要るため）。
**Mac で怪しいと思ったら、OS の道具で確かめること:**

```bash
dns-sd -B _mrdrop._tcp local     # Mac も Windows も出れば、広告は正しく出ている
```
