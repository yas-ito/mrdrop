# 申し送り — Mac ⇄ Windows の伝言板

**ここは「相手が次に読む唯一の場所」です。**
作業を終えたら、自分の欄を**書き換えて**ください（積み上げない・古い話は消す）。

---

## 🔴 Windows → Mac

**最終更新: 2026-09-03（Windows側）／Mac 対応・配布ZIP・iOS の配布準備**

# 🔲 **iPhone アプリを配るのは、そちらの作業です（Xcode が要るため）**

本人の指示は「**ほかの人が Mr.Drop を使えるように**」。Windows 側（ブラウザで使う分）は
下のとおり配れる形にしました。**残りは iPhone アプリで、これは Mac にしか出せません。**

🔵 **本人は Apple Developer Program に加入済みです**（2026-09-03・本人談）。
「加入していないから配れない」ではなくなりました。

## こちらで先にやっておいたこと（`77069e8`）

`ios/project.yml` の MrDrop ターゲットに **`ITSAppUsesNonExemptEncryption: false`** を入れました。

🔴 **これが無いと、アップロードのたびに App Store Connect で「暗号を使っていますか」と
聞かれて止まります**（答えるまでテスターに配られない）。Mr.Drop は LAN 内の平文 HTTP だけで
暗号を1つも使っていないので `false` が正しい答えです。`xcodegen generate` で入ります。
⚠️ 将来 HTTPS を入れたら、この行を消して答え直してください。

## 🔲 本人判断待ち: **TestFlight か App Store か**

まだ決まっていません。決まり次第こちらで取扱説明書を書き換えます。
**そちらは、決まってから動いてもらって構いません。**

- **TestFlight**（こちらの見立てではこれが妥当）: 審査が軽く、リンクを配るだけ。
  🔴 **90日でビルドが期限切れ**になるので、上げ直しが要ります。
  🔴 アップロードのたびに **`CURRENT_PROJECT_VERSION` を上げる**必要があります（いま `"1"`）
- **App Store**: 無期限だが本審査。
  🔴 **審査員は Windows PC を用意できません。**「LAN 内の自作サーバーに送る」アプリなので、
  レビューメモに**動かし方かデモ動画**を添えないと落ちやすいはずです（こちらの推測です）

## 🔲 決まったら、こちらへ返してほしいもの

- **配布リンク**（TestFlight の公開リンク、または App Store の URL）。
  取扱説明書の「iPhone アプリはありますか」の項に**そのまま載せます**
- 出したときの **`CURRENT_PROJECT_VERSION` / `MARKETING_VERSION`**（説明書の版数と合わせるため）

いまの取扱説明書には「**アプリは配布していない。Safari から使えば同じことができる**」と
書いてあります（**そちらの成果を否定する意味ではありません。**今日時点の事実です）。

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
- iPhone アプリの配布については、**上の「iPhone アプリを配るのは、そちらの作業です」**を見てください

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

**最終更新: 2026-09-03（Mac）／Mac 版アプリ完成・公証済み／iPhone アプリは App Store（無料）に決定**

# ✅ 本人の決定: **iPhone アプリは App Store で無料、お金は PC 側（BOOTH で有料）で取る**

「TestFlight か App Store か」の答えです。**売り物として不特定多数に配る**ので App Store。
Windows 版は**無署名のまま**でよい（本人判断。SmartScreen の警告は説明書で案内する形）。
手順と審査メモの案は **`ios/APPSTORE.md`**、プライバシーポリシーは **`PRIVACY.md`（リポジトリ直下・URL を ASCII にするため）**。
App Store Connect の操作は本人なので**公開日は未定**。URL と版数は公開したらここに書きます。

# 🆕 **Mac 版の受け取りアプリができました（`Mr.Drop.app`・メニューバー常駐・公証済み）**

そちらの「Mac 版を配るかどうかはそちらの判断」への答えです。**配ります。**
Windows の `はじめる.bat` に当たるものが、Mac では `Mr.Drop.app` です。

```bash
bash build/make-mac-app.sh                # 作る → 署名 → 公証 → zip（数分）
bash build/make-mac-app.sh --no-notarize  # 手元確認だけ（配ってはいけない）
```

- できる物: `_build/MrDrop_v1.0.0_mac.zip`（**80MB**・中身は .app 1つ）。展開してダブルクリックするだけ
- **Node を同梱**（nodejs.org 公式 v24.20.0・arm64＋Intel の universal・SHASUMS256 で検算）。
  🔴 **Homebrew の node は持ち出せません**（Homebrew のライブラリに依存・実測）。
  そちらの `--with-node` と同じ考え方で、Node.js の LICENSE も同梱しています
- 🔴 **`make-package.js` に `--target mac` は足しませんでした。**.app は実行権限と署名を保って zip に
  する必要があり、自前 zip では壊れるため。Mac は `ditto` で作る別スクリプトです
- サーバーは `server/` の JS をそのまま同梱（`Contents/Resources/server/`）。**Mac 側に転送ロジックは書いていません**
- メニュー: 状態／iPhone の Safari で開く住所（押すとコピー）／受信箱を開く／受信箱を変える／合言葉／記録を開く／ログイン時に起動／終了
- 設定 `~/Library/Application Support/Mr.Drop/config.json`（サーバーが既定で作る）、記録 `~/Library/Logs/MrDrop/mrdrop.log`
- 実機（Mac mini・macOS 26）で通した: 起動 → 48630 で待つ → `/health` `/api/info` OK → 通常終了で親子とも消える
  → **kill -9 でも node が残らない** → 公証 Accepted → zip から出し直して署名・staple とも無事

# 🔴 `server/` を 2 か所だけ触りました（そちらの領分ですが、Mac 版に要るので）

1. **`mrdrop.js` の記録の置き場所を Mac だけ `~/Library/Logs/MrDrop` に**（`process.platform === "darwin"` の分岐）。
   Windows は今までどおり `%LOCALAPPDATA%\MrDrop`。理由: Mac の tmpdir は 3 日で掃除され、問い合わせのときに読めない
2. **`--follow-stdin` を足した**（stdin が閉じたら `bye()`）。Mac 版アプリが子プロセスとして回すときだけ付ける。
   既定では stdin を読まない（タスクスケジューラ起動の罠を避けるため）。
   **`server/test/follow.test.js` で固定**（本物の入口を別プロセスで立て、stdin を閉じたら 4 秒以内に終わるか）。
   Mac で **108 件全部通っています**。🔴 **Windows 実機でも `node server/test/run.js` を通してください**
   （spawn と stdin パイプは OS 依存の可能性があるところ）

# ✅ お願いされていた `install-mac.sh` の実機確認、通りました

`config.json` を退避してから `bash scripts/install-mac.sh` → `mrdrop.out.log` の受信箱の行は
**`/Users/yas/Downloads/受信箱`**。リポジトリ直下に `%USERPROFILE%` のフォルダは**できていません**。
できた `config.json` は `~/Downloads/受信箱` 表記（サーバーの既定）。**そちらの直しは Mac で正しく動いています。**

# 🆕 iOS 側に 3 つ足しました（シミュレータで確認・実機 iPhone は未）

1. **PC が見つからないときの案内**（6 秒たっても見つからなければ理由と手立てを出す）… 審査対策と購入者の親切の両方。
   🔴 **画面では未確認**（同じ LAN にそちらの Windows 機「yas」がいて必ず見つかるため。ビルドは通っている）
2. **住所の手入力**（「住所を手で入れる…」の行がいつでも出ている。`192.168.1.20:48630` や `http://…` を入れて「つなぐ」
   → `/api/info` で確かめてから送り先にする。見つからないまま 6 秒たてば入力欄が自動で開く）
   … ゲスト Wi-Fi や AP 隔離で Bonjour が通らないときの逃げ道。**そちらの「見つからない」問い合わせの答えにも使えます**。
   シミュレータで、mDNS を出さない偽の PC（48631）に対して**送り先に加わるところまで確認済み**
3. **合言葉の入力欄**（PC 側で token を決めた人向け。今まで入れる場所が無かった）

🔴 アプリの中に「PC 版を買う」導線は置いていません（App Store 3.1.1）。案内は「PC 版が動いている必要がある」と事実だけ

# 🔲 そちらへのお願い

- 取扱説明書の「iPhone アプリはありますか」は **App Store 公開まで今のまま**で構いません。公開したら URL を渡します
- Mac 版の取扱説明書は**こちらで書きます**（`取扱説明書.html` は Windows 向けのまま触りません）
- Windows の配布 ZIP に `--with-node` を付けるか（LICENSE 同梱）は**本人判断待ちのまま**。
  Mac 版は同梱したので、揃えるなら Windows も同梱が自然です

# 🆕 App Store に出す材料は全部そろえました（残りは本人のサインインだけ）

- **アーカイブ済み・App Store 用に書き出し済み**: `_build/ios/export/MrDrop.ipa`（1.0.0 / build 1・iPhone 限定）
- **スクリーンショット 3 枚**（6.9 インチ・1320×2868）: `_build/ios/screenshots/`
- **審査用デモ動画**（iPhone で 3 枚選ぶ → Mac の受信箱に届くまで・50 秒）: `_build/ios/demo-for-review.mp4`
- **貼る文面**（名前・説明・キーワード・カテゴリ・審査メモ）: `ios/APPSTORE-metadata.md`
- 🔴 **`project.yml` を 3 つ直しました**（そちらで `xcodegen generate` するときに効きます）
  1. `CFBundleShortVersionString` / `CFBundleVersion` を `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` から取る。
     **xcodegen は既定で "1.0" / "1" を固定で書く**ので、そちらの「上げるたびに CURRENT_PROJECT_VERSION を上げる」が効いていませんでした
  2. `TARGETED_DEVICE_FAMILY: "1"`（iPhone だけ）。**ターゲット側に書かないと効かない**（プロジェクト側は xcodegen が 1,2 で上書き）
  3. `DEVELOPMENT_TEAM` を本人の Team に（Automatic 署名でアーカイブも実機も通る）
- Mac 版の取扱説明書は **`取扱説明書-Mac.html`**（そちらの `取扱説明書.html` と同じ体裁。Windows 版は触っていません）
- 実機 iPhone には新しいビルド（手入力・合言葉つき）を入れてあります。本人の手で確認してもらう

# 🔲 まだ手を付けていないこと

- **App Store Connect へのサインイン**（本人。ここだけは代われない）→ その後の App 登録・アップロード・提出はこちらで
- 手入力・合言葉の**実機 iPhone での確認**（本人の手）
- Mac 版の**他の Mac での確認**（Intel 機、macOS 15 以降の「ローカルネットワーク」許可ダイアログの出方）
- **PC → iPhone** はブラウザ画面からのみ（そちらの分担のまま）

---

## この伝言板の使い方

- **作業を始める前に `git pull` → ここを読む**
- **作業を終えたら自分の欄を書き換える**（積み上げない・経緯は各ファイルのコメントへ）
- 決まりの全体は [`CLAUDE.md`](CLAUDE.md)
