# Mr.Drop

iPhone から、同じ Wi-Fi にいる Windows へ写真・動画・ファイルを送る道具。
AirDrop と同じ操作感を目指しています。クラウドを通りません。端末どうしで直接送ります。

- **写真アプリの共有ボタンから直接送れる**（iPhone アプリを入れた場合）
- **設定なしで PC が見つかる**（Bonjour で広告しています。IP を打つ必要はありません）
- **元のまま送れる**（HEIC が JPEG に落とされない）
- **アプリが無くても送れる**（Safari で開くだけの画面もあります）
- **npm install が要りません**（外部パッケージを1つも使っていません）

---

## 使い方（いちばん短い道）

### 1. PC で動かす（Windows / Mac）

```bash
node server/mrdrop.js
```

こう出ます。

```
  Mr.Drop 1.0.0   MY-PC
────────────────────────────────────────────────────
  受信箱  C:\Users\<あなた>\Desktop\受信箱
  送信箱  C:\Users\<あなた>\Desktop\送信箱
────────────────────────────────────────────────────
  iPhone の Safari から、このどれかを開いてください:
    http://my-pc.local:48630
    http://192.168.1.20:48630      （イーサネット）
────────────────────────────────────────────────────
  自動発見  _mrdrop._tcp で広告中
```

Mac では受信箱が **`~/Downloads/受信箱`** になります
（`~/Desktop` は iCloud 同期の対象で、数GB の動画が勝手に上がってしまうため）。

**Mac に配るのは `Mr.Drop.app`（メニューバー常駐）です。**Node を同梱しているので、
受け取った人はダブルクリックするだけ。作り方は下の「ほかの人に渡す」。

### 2. iPhone の Safari で開く

`http://<PC名>.local:48630` を開いて、写真を選ぶだけです。
共有ボタン →「ホーム画面に追加」しておくと、次からアプリのように開けます。

### 3. いつでも使えるようにする（任意）

管理者の PowerShell で:

```powershell
.\scripts\install-windows.ps1
```

ファイアウォールを開けて、ログオン時に勝手に動くようにします（窓は出ません）。

```powershell
.\scripts\install-windows.ps1 -Status      # いまどうなっているか
.\scripts\install-windows.ps1 -Uninstall   # 元に戻す
```

Mac は `launchd` に登録します（ログイン時に立ち上がります）。**これは開発者向け**で、
配布する `Mr.Drop.app` はメニューの「ログイン時に起動」で同じことができます。

```bash
bash scripts/install-mac.sh              # 入れる
bash scripts/install-mac.sh --uninstall  # 外す
```

---

## 置き場所と設定

初回に `config.json` ができます。書き換えれば変わります。

```json
{
  "port": 48630,
  "inbox": "%USERPROFILE%\\Desktop\\受信箱",
  "outbox": "%USERPROFILE%\\Desktop\\送信箱",
  "name": "",
  "token": ""
}
```

置き場所の既定は OS で変わります（上は Windows）。Mac では `~/Downloads/受信箱`・
`~/Downloads/送信箱` になります。`~` と `%USERPROFILE%` はどちらの OS でも家に開くので、
**Windows で書いた `config.json` を Mac へ持っていってもそのまま読めます。**

| 項目 | 意味 |
|---|---|
| `port` | 番号。一撃極ターボ（48620）とぶつからない番号にしてあります |
| `inbox` | iPhone から届いたものが入る所 |
| `outbox` | ここに置いたものを iPhone から受け取れます |
| `name` | iPhone に見える名前。空なら PC 名 |
| `token` | 合言葉。入れると `?t=…` が要るようになります（家の LAN なら空で構いません） |

**Premiere の素材フォルダを `inbox` にしておくと、iPhone で撮った素材がそのまま
編集用のフォルダに落ちます。**自作の一番のうまみはここです。

---

## ほかの人に渡す

git も node も知らない人に渡せる ZIP を作れます。

```bash
node build/make-package.js
```

`_build/MrDrop_v<版>_win.zip` ができます。中身は **7 ファイルだけ**（`はじめる.bat`・
`取扱説明書.html`・`server/`・`scripts/install-windows.ps1`）。
受け取った人は**展開して `はじめる.bat` を押すだけ**です。

- **受け取る人の PC には Node.js が要ります。**入っていなければ `はじめる.bat` がその旨を出します。
  取扱説明書の先頭に入れ方（`winget install OpenJS.NodeJS.LTS`）を書いてあります
- **Node ごと配るなら** `--with-node "C:\Program Files\nodejs\node.exe"` を付けます。
  🔴 その場合は **node.exe の隣に Node.js の `LICENSE`（MIT）を置いてください**。
  Windows の Node には全文が入っていないので、[nodejs.org の zip 版](https://nodejs.org/ja/download)
  から持ってきます。無いときは make-package.js が止めます
- 🔴 **ZIP は自前で書いています。**ファイル名の UTF-8 フラグ（bit 11）を立てないと、
  Windows で `はじめる.bat` が文字化けして開けなくなります。作ったあとに読み返して検査しています

```bash
node build/make-package.js --with-node "C:\Program Files\nodejs\node.exe"
```

### Mac 用（`build/make-mac-app.sh`・Mac でしか作れません）

```bash
bash build/make-mac-app.sh                # 作る → 署名 → 公証 → zip（数分）
bash build/make-mac-app.sh --no-notarize  # 手元で動かして確かめるだけ（配ってはいけない）
```

`_build/MrDrop_v<版>_mac.zip`（約 80MB）ができます。中身は **`Mr.Drop.app` 1つ**。
受け取った人は展開してダブルクリックするだけ。メニューバーの雫が Mr.Drop です。

- **Node は同梱しています**（nodejs.org の公式バイナリ・arm64 と Intel の universal）。
  受け取る人の Mac には何も要りません。🔴 Homebrew の node は持ち出せません（他の Mac で動かない）
- Developer ID で署名して Apple の公証を通します。通さないと「開発元を確認できない」で開けません
- 受信箱は `~/Downloads/受信箱`。メニューの「受信箱を変える…」で Premiere の素材フォルダにできます
- 設定は `~/Library/Application Support/Mr.Drop/config.json`、記録は `~/Library/Logs/MrDrop/mrdrop.log`
  （メニューの「記録を開く」で開きます。問い合わせのときはこれを送ってもらう）
- アプリを強制終了しても受信サーバーは残りません（`--follow-stdin`。`test/follow.test.js` で固定）
- 🔴 `make-package.js` に `--target mac` は作りません。`.app` は実行権限と署名を保ったまま
  zip にする必要があり、自前の zip では壊れるためです（`ditto` で作ります）

## iPhone アプリ

`ios/` にソースがあります。**Xcode が要るので Mac で作ります。**
手順は [`ios/README.md`](ios/README.md) を見てください。

アプリを入れると、写真アプリの共有ボタンに Mr.Drop が並びます。
これが AirDrop と同じ導線になります。

---

## 困ったとき

| 症状 | 見る所 |
|---|---|
| iPhone から開けない | PC と同じ Wi-Fi か。`install-windows.ps1` でファイアウォールを開けたか |
| `.local` で開けない | 代わりに IP（`http://192.168.…`）で開く |
| アプリが PC を見つけない | `node server/mrdrop.js --browse` で PC 自身が見つけられるか確かめる。<br>見つかるならアプリ側（`Info.plist` の `NSBonjourServices`）を疑う |
| 大きい動画が途中で止まる | 半端なファイルは受信箱に出さない作りです。もう一度送ってください |
| 自動起動しているか分からない | `.\scripts\install-windows.ps1 -Status` |
| Mac で「開発元を確認できない」と出る | 公証していない版。`make-mac-app.sh` を `--no-notarize` なしで作り直す |
| Mac で「ローカルネットワーク」の許可を聞かれた | 「許可」を押す。断ると iPhone から見つからなくなる（設定 › プライバシーとセキュリティ › ローカルネットワーク で直せる） |

## 作りの確かめ方

```bash
node server/test/run.js
```

`../` でどこにでも書けないこと、途中で切れたものを受信箱に出さないこと、
mDNS のパケットを組んで読み戻せることを固定してあります。
