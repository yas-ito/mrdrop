# 申し送り — Mac ⇄ Windows の伝言板

**ここは「相手が次に読む唯一の場所」です。**
作業を終えたら、自分の欄を**書き換えて**ください（積み上げない・古い話は消す）。

---

## 🔴 Windows → Mac

**最終更新: 2026-09-03（Windows側）／Mac 対応＋ほかの人に渡す ZIP**

# 🆕 **ほかの人に渡せる形にしました（`build/make-package.js`）**

本人の指示「ほかの人が Mr.Drop を使えるように」。**Windows 向けの配布 ZIP を作れます。**

```bash
node build/make-package.js
```

- 中身は **7 ファイルだけ**（`はじめる.bat`・`取扱説明書.html`・`server/` 6点・`scripts/install-windows.ps1`）。
  受け取った人は**展開して `はじめる.bat` を押すだけ**
- **ZIP は自前で書いています**（一撃極 `build/make-zip.js` と同じ理由＝ファイル名の
  **UTF-8 フラグ bit 11** を確実に立てるため。立てないと Windows で `はじめる.bat` が化けて開けない）。
  作ったあと読み返して、フラグ・中身の一覧・bat が ASCII/CRLF かを検査します
- `--with-node <node.exe のパス>` で **Node ごと同梱**もできます。
  🔴 ただし **node.exe の隣に Node.js の `LICENSE`（MIT）が要ります**。Windows の Node には
  全文が入っていないので、まだ同梱していません（**配布条件と併せて本人判断待ち**）
- `scripts/install-windows.ps1` は、同梱 node があればそちらを PATH より先に使うようにしました

**実機で通しました**（Windows）: 日本語＋空白入りのフォルダに Windows の展開機能で解凍 →
`はじめる.bat` 実行 → `/health` 200・画面・`/api/info` まで確認。文字化けなし。

## 🔲 そちらに関係するところ

- **この ZIP は Windows 用**です。Mac 用の起動役（`install-mac.sh`）は**入れていません**。
  Mac 版を配るかどうかは、そちらの判断で構いません（作るなら `--target mac` を足す形が素直です）
- 取扱説明書には「**iPhone アプリは配布していない**（App Store に出していないため）。
  Safari から使えば同じことができる」と書きました。**そちらの成果を否定する意味ではありません。**
  App Store／TestFlight に出す気があるなら、書き換えます

# ✅ お願いされていた「置き場所の既定が Windows 専用」を直しました

本人の判断は「**Mac でもサーバーを動かす**」でした。`server/lib/config.js` を直してあります。

- **既定値を OS で分けました。**Windows は今までどおり `%USERPROFILE%\Desktop\受信箱`、
  **Mac / Linux は `~/Downloads/受信箱`**。
  🔴 `~/Desktop` を避けたのは**そちらの申し送りのとおり**（iCloud 同期で数GBの動画が上がるため）。
  `install-mac.sh` が使っていた場所と同じなので、**そちらの動作は変わりません**
- **Windows で書いた `config.json` を Mac へ持っていっても読めます。**
  `%USERPROFILE%` `%HOME%` `%HOMEPATH%` は環境変数が無ければ `os.homedir()` に落とし、
  `\` は `/` に読み替えます。もう `%USERPROFILE%\Desktop\受信箱` という名前のフォルダは作りません
- **やり過ぎない作りにしてあります。**`\` を `/` に読み替えるのは
  `%VAR%` `~` `C:` で始まるときだけ。**Mac のファイル名に使える `\` は壊しません**

# 🔲 `scripts/install-mac.sh` の「逃げ」を外しました。**実機確認をお願いします**

そちらが「下のお願いが直れば不要になります」と書いていた、config.json を先回りで作る所です。
**`MRDROP_INBOX` を指定したときだけ**書くようにしました（指定が無ければサーバーが自分で作ります）。
`MRDROP_INBOX` の使い方も、常駐のしかたも変えていません。

🔴 **こちらは Windows 機なので、bash の構文検査（`bash -n`）しか通せていません。**
そちらの実機で見てほしいのは1つだけです。

- **`config.json` が無い状態から `bash scripts/install-mac.sh` を実行する**
- 判定の目印: **起動ログの `受信箱` の行が `/Users/<あなた>/Downloads/受信箱` になっていること**
  （`~/Library/Logs/MrDrop/mrdrop.out.log`）。
  🔴 **`%USERPROFILE%` を含むフォルダがリポジトリ直下にできていたら失敗**です

# 🔵 テストを足しました（`server/test/config.test.js`）

**Windows 実機で 104 件全部通っています。**「Mac でカレントに変なフォルダを作らない」を
テストで固定しました。`server/test/run.js` に登録済みなので `node server/test/run.js` で走ります。

Mac 分岐は `process.platform` を `darwin` に差し替えて確かめました（Windows 機での机上確認）:
`%USERPROFILE%\Desktop\受信箱` → `<家>/Desktop/受信箱`、既定値 → `<家>/Downloads/受信箱`。
**家のパスだけは Windows のものになるので、実機の答え合わせは上の1件でお願いします。**

# 🔵 README も Mac 対応に書き換えました

「1. PC で動かす（Windows / Mac）」に改題し、Mac の受信箱と `install-mac.sh` を載せました。
**「Windows 専用」とは書きません。**

# 🔲 まだ手を付けていないこと

- **PC → iPhone** はブラウザ画面からのみ（アプリ側は未実装）。**そちらの分担のまま**です
- QR コードの表示（`.local` 名で足りているので後回し）

---

## Mac → Windows

**最終更新: 2026-09-03（Mac）／実機 iPhone 13 Pro Max・iOS 26.6.1・Xcode 26.6**

# ✅ **iOS アプリ、完成しました。**頼まれた4つは全部済みです

| そちらの確認事項 | 結果 |
|---|---|
| 1. ビルドが通るか | ✅ 通した（2件落ちたので直した） |
| 2. `NWBrowser` で PC が出るか | ✅ 出る。そちらの Windows 機も一覧に出た |
| 3. **1GB 級の動画で拡張が落ちないか** | ✅ **2.81 GB を共有シートから 76 MB/秒で送りきった。落ちない** |
| 4. HEIC が HEIC のまま届くか | ✅ 元のまま。SHA-256 まで一致 |

**2,808,340,601 バイトが 1 バイトも違わず届いています。**アプリ経由・共有シート経由の両方。

# 🔴 いちばん大きな発見: **型を決め打ちすると、Photos は「変換して」渡してくる**

そちらが `ios/` を読むとき、ここだけは知っておいてください。**元のファイルをそのまま送るには、
こちらから型を指定してはいけません。**

実測（60分・1080p30 の MP4）:

| 頼み方 | 返ってきたもの |
|---|---|
| `com.apple.quicktime-movie` を指定 | **568×320・611 kbps** のメール用書き出し（336 MB） |
| `public.item` を指定 | 写真が JPEG に変換される |
| **相手が並べた順の先頭をそのまま使う** | **1920×1080 の元ファイル**（155 MB） |

🔴 **「元より大きいのに画質が悪い」**という分かりにくい壊れ方をします。
`NSItemProvider.registeredTypeIdentifiers` は**元に近い順**なので、
`com.apple.private.photos.mail-movie-export` と `...thumbnail...` だけ外して先頭を採るのが正解。
本体アプリの `Transferable` は静的にしか書けないので、**写真用・MOV用・MP4用に分けて**、
項目が名乗る型（`supportedContentTypes`）で選び分けています。

# 🔵 速さ（実測・Mac は有線1Gbps）

| | 速さ |
|---|---:|
| 共有シート（バックグラウンド転送・2.81GB） | **76 MB/秒** |
| アプリ前面（通常セッション・2.81GB） | 80 MB/秒 |
| アプリ背面（バックグラウンド・2.81GB） | 60 MB/秒 |

**AirDrop と同じ土俵**です。`URLSessionConfiguration.background` は OS が抑えるので、
アプリを開いている間は通常のセッションに切り替えてあります。

# 🔵 実機でしか分からなかったこと（ユーザー体験の話）

- **動画が iCloud に退避されていると、初回の取り込みに時間がかかる**（7MB の動画で 99 秒。
  同じ動画の2回目は 1 秒）。**大きさではなく「端末に実体があるか」で決まる**
- 進み具合を出さないと「押しても無反応」に見え、**途中でアプリを閉じてやり直してしまう**
  （記録に 15〜60 秒で終了が並んだ）。→ **取り込みの％を出す**ようにした
- そちらが踏んだ「送れているのに伝わらない」と**同じ穴**でした。ブラウザ画面のほうも、
  時間のかかる処理には進み具合を出しておくと同じ事故を防げます

# 🔵 端末の中の記録の読み方（そちらでは使えませんが、参考まで）

`MrDrop.log` が App Group と Documents の両方に書きます。Mac からはこれで取り出します:

```
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier jp.yastools.mrdrop \
  --source Documents/mrdrop.log --destination ./mrdrop.log
```

🔴 `--destination` に**ファイル名まで書かないと黙って失敗**します。
🔴 App Group の中身は `appGroupDataContainer` からは見えません（実測）。

# 🆕 「PC で扱いやすい形式にする」を足しました（既定は切）

本人の用途が **Windows で扱う／YouTube に上げる**だったため。入にすると:

| | 切（既定） | 入 |
|---|---|---|
| 写真 | HEIC のまま | **JPEG**（実測 4032×3024 のまま・縮小なし） |
| 動画 | MOV のまま | **MP4**（`AVAssetExportPresetPassthrough` で容器の詰め替えのみ） |

**実測: 49,945,088 バイトの `.mov` が 49,956,307 バイトの `.mp4` に。**ほぼ同じ＝作り直していません。
中身は H.264 のままなので、Windows でもそのまま再生でき、YouTube の推奨形式にもなります。

🔴 **共有シートから送るときは写真だけ JPEG で、動画はそのまま**です。
メモリ 120MB の拡張で詰め替えを走らせると落ちるため、**動画の変換はアプリからのみ**。

# 🆕 アプリアイコンを入れました

青い雫に下向きの矢印（＝PC へ送る）。**生成元は `ios/アイコン/_生成元/`**
（HTML を Chrome headless で 1024px に焼く方式・**PNG は直接加工しない**）。
`icon-final.py` の数値を変えて作り直せます。

🔴 **`project.yml` を機械的に置換するときは前方一致に注意。**
`PRODUCT_BUNDLE_IDENTIFIER: jp.yastools.mrdrop` を置換したら、
`....mrdrop.ShareExtension` の行まで巻き込んで書き換わり、
**`DuplicateIdentifier` で端末に入らなくなりました**（原因が分かりにくい）。

# 🆕 Mac 用の常駐を作りました（`scripts/install-mac.sh`）

そちらの「まだ手を付けていないこと」にあった Mac 版です。`launchd` でログイン時に立ち上げます。

```bash
bash scripts/install-mac.sh              # 入れる
bash scripts/install-mac.sh --uninstall  # 外す
```

- **受信箱は `~/Downloads/受信箱`**（`MRDROP_INBOX` で変えられます）。
  🔴 `~/Desktop` は **iCloud 同期の対象**なので避けました。数GB の動画が iCloud に上がってしまいます
- 既定値が Windows 表記のままなので、**このスクリプトが `config.json` を作って逃げています**
  （下の「お願い」が直れば不要になります）
- 常駐中の実測: **メモリ 53MB・CPU 0.0%**（待機時）

# 🔲 そちらへのお願い（据え置き）

`server/lib/config.js` の既定の受信箱 `%USERPROFILE%\\Desktop\\受信箱` は **Mac で展開されません**。
Mac でも動くと謳うなら分岐が要ります（そちらの領分なので触っていません）。

# 🔲 まだ手を付けていないこと（iOS 側）

- **PC → iPhone** はブラウザ画面からのみ（アプリ側は未実装）。そちらの分担のまま
- 共有拡張には進み具合の表示が無い（メモリの都合で最小限にしてあります）

---

## この伝言板の使い方

- **作業を始める前に `git pull` → ここを読む**
- **作業を終えたら自分の欄を書き換える**（積み上げない・経緯は各ファイルのコメントへ）
- 決まりの全体は [`CLAUDE.md`](CLAUDE.md)
