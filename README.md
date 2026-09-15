# Mr.Drop

iPhone から、同じ Wi-Fi にいる Windows へ写真・動画・ファイルを送る道具。
写真アプリの共有ボタンから送るだけ、を目指しています。クラウドに出ません。iPhone とパソコンが直接やりとりします。

- **写真アプリの共有ボタンから直接送れる**（iPhone アプリを入れた場合）
- **設定なしで PC が見つかる**（Bonjour で広告しています。IP を打つ必要はありません）
- **元のまま送れる**（HEIC が JPEG に落とされない）
- **アプリが無くても送れる**（Safari で開くだけの画面もあります）
- **npm install が要りません**（外部パッケージを1つも使っていません）

---

## 🔴 2つそろって、はじめて動きます

**iPhone アプリだけでは何もできません。**送る側と受け取る側の両方が要ります。

| | 何をするもの | どこにあるか |
|---|---|---|
| **iPhone アプリ** | **送る側。**写真アプリの共有ボタンから送る | App Store で無料 — <https://apps.apple.com/jp/app/id6808082392> |
| **パソコン側** | **受け取る側。**これが動いていないと iPhone から PC が見つかりません | このリポジトリのソース、または <https://yas-tools.booth.pm/items/8832410>（Node 同梱・説明書つき） |

**iPhone アプリを入れたのに PC が出てこない**、という方へ。
**パソコン側の Mr.Drop が動いていないから**です。上の表のパソコン側を用意して、
`node server/mrdrop.js` で立ち上げてください（Node が入っていれば、このリポジトリだけで動きます）。

---

## 使い方（いちばん短い道）

### 1. PC で動かす（Windows / Mac）

```bash
node server/mrdrop.js
```

こう出ます。

```
  Mr.Drop 1.0.6   MY-PC
────────────────────────────────────────────────────
  受信先  C:\Users\<あなた>\Downloads
  送信箱  C:\Users\<あなた>\Desktop\Mr.Drop送信箱
────────────────────────────────────────────────────
  iPhone アプリは自動で見つけます。ブラウザから使うときはこちら:
    http://my-pc.local:48630
    http://192.168.1.20:48630      （イーサネット）
────────────────────────────────────────────────────
  自動発見  _mrdrop._tcp で広告中
```

Mac では受信先が **`~/Downloads`**（ダウンロードフォルダそのもの）になります
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

次の3つをやります。

1. 🔴 **中身を `%LOCALAPPDATA%\MrDrop\app` へ写す**
2. ファイアウォールを開ける（プライベートのみ）
3. 🔴 **タスクバーの右下に常駐させる**（`MrDropTray.exe`）。自動起動は
   `HKCU\...\CurrentVersion\Run` なので**管理者は要りません**

さらに **スタートメニュー > Mr.Drop** に「Mr.Drop（出し直す）／取扱説明書／
アンインストール」を作ります。ふだんの入口は**タスクバーのアイコン**です。

> 🔴 **常駐はタスクスケジューラ（S4U）をやめました**（2026-09-12）。
> 窓を出さずに常駐できるのは良かったのですが、**動いているかがどこにも見えない**のが
> 致命的でした（本人が何度も「動いてる？」と迷った）。いまは
> **`MrDropTray.exe` が node を子として抱え、アイコンを閉じれば本体も終わります**
> （`--follow-stdin`）。**Mac 版のメニューバー常駐とまったく同じ考え方**です。
> 入れ直すとき、昔のタスクは自動で片付けます。

> 🔵 アイコンは **C# + `NotifyIcon`** を、Windows に最初から入っている C# コンパイラ
> （`csc.exe` / .NET Framework 4.x）で `/target:winexe` にしてビルドしています。
> **SDK も外部の部品も要りません**（英かな君と同じやり方）。
> `build\build-tray.ps1` / `build\make-tray-icon.ps1`。

> 🔴 **写すのは、展開したフォルダを捨てられるようにするためです。**
> 本人がダウンロードフォルダで展開して押し、そのあと片付けようとして
> 「消せない」で詰まりました（2026-09-12）。展開した場所のまま動かすと、
> **片付けようとすると消せない／片付けたら黙って壊れる**のどちらかになります。
> いまはどこで展開しても構わず、押したあとフォルダは捨てられます。

> 🔴 **写す先に `.bat` は置きません。**cmd.exe は実行中の `.bat` を掴んだまま
> 行単位で読み直すので、「やめる」で自分のいるフォルダを消すと途中で壊れます。
> 入れたあとの入口はショートカット（`powershell` を直接呼ぶ）だけです。

```powershell
.\scripts\install-windows.ps1 -Status      # いまどうなっているか
.\scripts\install-windows.ps1 -Uninstall   # 入れる前に戻す（届いたファイルは消さない）
```

`-Uninstall` は、自動起動・壁の穴・スタートメニュー・`%LOCALAPPDATA%\MrDrop`（プログラム・
設定・記録）を全部外します。**受信先と送信箱の中身には触りません。**

Mac は `launchd` に登録します（ログイン時に立ち上がります）。**これは開発者向け**で、
配布する `Mr.Drop.app` はメニューの「ログイン時に起動」で同じことができます。

```bash
bash scripts/install-mac.sh              # 入れる
bash scripts/install-mac.sh --uninstall  # 外す
```

---

## 置き場所と設定

初回に `config.json` ができます。書き換えれば変わります。

| OS | 場所 |
|---|---|
| **Windows** | `%LOCALAPPDATA%\MrDrop\config.json`（記録と同じ所） |
| **Mac（アプリ）** | `~/Library/Application Support/Mr.Drop/config.json` |
| **Mac（ソースから直接）** | リポジトリ直下の `config.json` |

> 🔴 **Windows でプログラムの隣に置かないのは、隣が消えるからです。**
> 展開したフォルダは「はじめる.bat」のあと捨ててよい作りなので、
> 設定を隣に置くと一緒に消えます。`--config` で場所を指定することもできます。
> **`server/lib/config.js` の `defaultFile()` と `scripts/settings-windows.ps1` の
> `$CfgFile` は必ず同じ場所を指すこと**（`server/test/config.test.js` が突き合わせます）。

```json
{
  "port": 48630,
  "inbox": "C:\\Users\\あなた\\Downloads",
  "outbox": "C:\\Users\\あなた\\Desktop\\Mr.Drop送信箱",
  "name": "",
  "token": ""
}
```

置き場所の既定は OS で変わります（上は Windows）。Mac では `~/Downloads`・
`~/Desktop/Mr.Drop送信箱` になります。**送信箱だけはデスクトップ**で、両OSとも同じです。`~` と `%USERPROFILE%` はどちらの OS でも家に開くので、
**Windows で書いた `config.json` を Mac へ持っていってもそのまま読めます。**

🔴 **Windows では、置き場所を決め打ちしません**（2026-09-15・買った人の報告で直しました）。
OneDrive の「PC のフォルダーのバックアップ」が入っていると、本当のデスクトップは
`C:\Users\あなた\OneDrive\デスクトップ` へ移っていて、`%USERPROFILE%\Desktop` は
**画面に出てこない抜け殻**として残ります。そこへ送信箱を作ると、買った人のデスクトップには
何も現れません（**エラーは一つも出ません**）。だから初回に OS へ聞いて、
`config.json` には**実際の場所**を書きます。1.0.0 で作られた古い設定は、
起動したときに黙って直します（中身も引っ越します。`server/lib/config.js` の `fixStaleOutbox`）。

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

`_build/MrDrop_v<版>_win.zip` ができます。入口の `.bat` は4本
（`はじめる.bat`・`アンインストール.bat`・`受信先を変える.bat`・`受信先を開く.bat`）と
`scripts/run-once.bat`。あとは `取扱説明書.html`・`server/`・`scripts/`。
受け取った人は**どこかに展開して `はじめる.bat` を押すだけ**で、そのあとフォルダは捨てられます。

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
- 受信先は `~/Downloads`（ダウンロードフォルダそのもの）。メニューの「受信先を変える…」で Premiere の素材フォルダにできます
- 設定は `~/Library/Application Support/Mr.Drop/config.json`、記録は `~/Library/Logs/MrDrop/mrdrop.log`
  （メニューの「記録を開く」で開きます。問い合わせのときはこれを送ってもらう）
- アプリを強制終了しても受信サーバーは残りません（`--follow-stdin`。`test/follow.test.js` で固定）
- 🔴 `make-package.js` に `--target mac` は作りません。`.app` は実行権限と署名を保ったまま
  zip にする必要があり、自前の zip では壊れるためです（`ditto` で作ります）

## iPhone アプリ

`ios/` にソースがあります。**Xcode が要るので Mac で作ります。**
手順は [`ios/README.md`](ios/README.md) を見てください。

アプリを入れると、写真アプリの共有ボタンに Mr.Drop が並びます。
これで、写真を開いたまま共有ボタンから送れます。

---

## 困ったとき

| 症状 | 見る所 |
|---|---|
| iPhone から開けない | PC と同じ Wi-Fi か。`install-windows.ps1` でファイアウォールを開けたか |
| `.local` で開けない | 代わりに IP（`http://192.168.…`）で開く |
| アプリが PC を見つけない | `node server/mrdrop.js --browse` で PC 自身が見つけられるか確かめる。<br>見つかるならアプリ側（`Info.plist` の `NSBonjourServices`）を疑う |
| 大きい動画が途中で止まる | 半端なファイルは受信先に出さない作りです。もう一度送ってください |
| 動いているか分からない | **タスクバー右下のアイコン**。🔴 **Windows 11 は新しいアイコンを既定で「∧」の中に隠す**ので、まず ∧ を開くこと。それでも無ければ動いていません |
| 自動起動しているか分からない | `%LOCALAPPDATA%\MrDrop\app\scripts\install-windows.ps1 -Status` |
| やめたい | アイコンを右クリック > Mr.Drop をアンインストール（または `アンインストール.bat`） |
| Mac で「開発元を確認できない」と出る | 公証していない版。`make-mac-app.sh` を `--no-notarize` なしで作り直す |
| Mac で「ローカルネットワーク」の許可を聞かれた | 「許可」を押す。断ると iPhone から見つからなくなる（設定 › プライバシーとセキュリティ › ローカルネットワーク で直せる） |

## 作りの確かめ方

```bash
node server/test/run.js
```

`../` でどこにでも書けないこと、途中で切れたものを受信先に出さないこと、
mDNS のパケットを組んで読み戻せることを固定してあります。
