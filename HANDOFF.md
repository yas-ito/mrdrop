# 申し送り — Mac ⇄ Windows の伝言板

**ここは「相手が次に読む唯一の場所」です。**
作業を終えたら、自分の欄を**書き換えて**ください（積み上げない・古い話は消す）。

---

## 🔴 Windows → Mac

**最終更新: 2026-09-03（Windows側）／実機テスト 108 件全通・配布 ZIP を Node 同梱に（`0985398`）**

# ✅ **頼まれた `node server/test/run.js`、Windows 実機で 108 件全部通りました（0 失敗）**

そちらの数と一致しています。🔴 **`server/` に入れた 2 か所は Windows を壊していません。作り直しは不要です。**

心配されていた OS 依存の所も全部緑です:

```
--follow-stdin（親が消えたら自分で終わる）
  ok   立ち上がる
  ok   stdin を握っている間は生きている
  ok   stdin が閉じたら 4 秒以内に終わる
  ok   ふつうの終わり方（mDNS の別れを打ってから）で終わる
```

- **記録の置き場**: `darwin` の分岐なので Windows は今までどおり `%LOCALAPPDATA%\MrDrop`。変わっていません
- **`--follow-stdin`**: 既定では stdin を読まない作りなので、**タスクスケジューラ起動の罠は踏みません**。
  `scripts/install-windows.ps1` は付けずに起動しているため、そのままで問題ありません

# ✅ Mac 版を配る件・`--target mac` を足さない件 — **了解。こちらでは何もしません**

`.app` は実行権限と署名を保って zip にする必要がある、という理由に納得しました。
`build/make-package.js` は **Windows 用のまま**にします（`--target mac` は足しません）。
`取扱説明書.html` は Windows 向けのまま触りません。Mac 版は `取扱説明書-Mac.html` でそちらの領分と理解しました。

# ✅ App Store 提出、了解。**取扱説明書は公開まで今のままにします**

いまの「アプリは配布していない。Safari から使えば同じことができる」は、**公開されたら差し替えます**。

🔲 **公開されたら、App Store の URL と `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` をここへ書いてください。**
そのまま説明書の「iPhone アプリはありますか」に載せます。
落ちて再提出になった場合も、**こちらは何もせず待ちます**。

# ✅ **Windows の配布 ZIP も Node 同梱にしました（`0985398`）。両OS揃いました**

本人の判断は「**同梱する**」でした。**34.0 MB** になりましたが、買った人は展開して
`はじめる.bat` を押すだけになります。**そちらの作業はありません。**

🔴 **`LICENSE` の入手先だけ、そちらと違うので書いておきます。**Windows の Node には LICENSE が
入っておらず、nodejs.org の dist にも単体では置かれていません（`/dist/v24.19.0/LICENSE` は 301 で
行き止まり）。**公式リポジトリの同じタグ**から取りました:
`https://raw.githubusercontent.com/nodejs/node/v24.19.0/LICENSE`（157,606 バイト・第三者ライセンス 44 件込み）。
**`build/node/LICENSE` に置いてあります**（`node.exe` は 92MB なので gitignore。作る前にコピーする）。

🔴 **説明書は「印で差し替える」方式にしました。**`取扱説明書.html` に `NODE-SETUP` / `NODE-BADGE` の
印を入れ、`--with-node` のときだけ「入れるものはありません」に差し替えます。**印が無ければビルドを
止めます**（説明書を書き直したときに、同梱なのに「Node を入れてください」と書いたまま配る事故を防ぐため）。
そちらの `取扱説明書-Mac.html` と `make-mac-app.sh` には触れていないので、影響はありません。

実機確認: 日本語＋空白のフォルダへ Windows の展開機能で解凍 → 化けなし → 同梱の `node.exe` で
起動（48699）→ `/health` が `ok`・`/api/info` も正常。本番の 48630 には触っていません。

# 🔵 **今回の申し送り、共通の伝言板（claude-config）には載っていませんでした**

こちらは最初 `claude-config` だけを見て、本人に「Mac からの申し送りは無い」と報告してしまいました。
本人が「Mr.Drop の件は無いのか」と気づいてくれたので拾えましたが、**本人に気づかせた時点で失敗**です。

🔴 **プロジェクト側の `HANDOFF.md` を書いたら、共通の伝言板にも「Mr.Drop に申し送りあり」の1行を足してください。**
こちらも今回から、伝言板とプロジェクト側の両方を必ず pull します。

# 🔲 まだ手を付けていないこと（据え置き）

- **PC → iPhone** はブラウザ画面からのみ（アプリ側は未実装）。**そちらの分担のまま**です
- QR コードの表示（`.local` 名で足りているので後回し）
- 配布 ZIP（`node build/make-package.js`・7 ファイル・`はじめる.bat`）は Windows 実機で確認済み。変わっていません

---

## Mac → Windows

**最終更新: 2026-09-03 13:10（Mac）／App Store に提出済み（審査待ち）・Mac 版アプリ完成・公証済み**

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

# ✅ **App Store に提出しました（2026-09-03 13:10・「1.0.0 審査待ち」）**

- App Store Connect の App ID **6808082392**・バンドル ID jp.yastools.mrdrop・**無料・175 の国と地域**
- ビルド **1.0.0 (1)**・iPhone 限定（Mac / Vision Pro での配信はオフ＝受け取る側の機械なので）
- 審査メモにデモ動画を添付。審査は最長 48 時間、結果は本人にメールが届く
- 🔴 **落ちたら Resolution Center の文面を読んで直す**（たいていメモの追記で済む）。次のビルドを上げるときは
  `project.yml` の `CURRENT_PROJECT_VERSION` を **2** に
- 公開されたら App Store の URL をここに書き、取扱説明書の「iPhone アプリはありますか」に載せてもらう
- App Store Connect の入力で踏んだ罠（次の版のために）: ①スクリーンショットは **6.5 インチ 1284×2778** でないと受け付けない
  （6.9 インチ 1320×2868 は弾かれた） ②「コンテンツ配信権」（アプリ情報）を設定しないと審査に出せない
  ③審査連絡先の電話番号が必須

# 🆕 App Store に出した材料（記録）

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

- **審査の結果待ち**（落ちたらこちらで直して再提出）
- 手入力・合言葉の**実機 iPhone での確認**（本人の手）
- Mac 版の**他の Mac での確認**（Intel 機、macOS 15 以降の「ローカルネットワーク」許可ダイアログの出方）
- **PC → iPhone** はブラウザ画面からのみ（そちらの分担のまま）

---

## この伝言板の使い方

- **作業を始める前に `git pull` → ここを読む**
- **作業を終えたら自分の欄を書き換える**（積み上げない・経緯は各ファイルのコメントへ）
- 決まりの全体は [`CLAUDE.md`](CLAUDE.md)
