# iPhone アプリを App Store に出す手順（Mac の作業）

**方針（2026-09-03・本人の決定）**: iPhone アプリは **App Store で無料**、お金は **PC 側（BOOTH で有料）** で取る。
Windows 版は無署名のまま。

🔴 **アプリの中に「PC 版を買う」導線を置かない。**App Store の規約 3.1.1 が、アプリ内から外部の
購入ページへ誘導することを嫌う。アプリは黙って動くだけにして、商品ページは BOOTH や X から辿ってもらう。

## 0. 済んでいること（コード側）

- `ITSAppUsesNonExemptEncryption: false`（輸出コンプライアンス）… `project.yml` に入っている
- PC が見つからないときの案内と、住所の手入力（`ContentView.swift` の `noPeerGuide`）
  … 審査官の手元に受信側の PC は無い。「何も起きないアプリ」に見えないようにするため
- 合言葉の入力欄（PC 側で合言葉を決めた人向け）
- アプリアイコン（`ios/アイコン/`）

## 1. 本人がやること（App Store Connect・ブラウザ）

1. https://appstoreconnect.apple.com → **マイ App → ＋ → 新規 App**
   - プラットフォーム iOS ／ 名前 **Mr.Drop** ／ プライマリ言語 日本語
   - バンドル ID **jp.yastools.mrdrop**（無ければ developer.apple.com の Identifiers で先に登録。
     **App Groups の `group.jp.yastools.mrdrop` を付けること**）／ SKU は `mrdrop`
2. **価格** 無料 ／ **カテゴリ** 写真/ビデオ（サブ: ユーティリティ）
3. **App のプライバシー**: 「データを収集しない」。全部の質問に「いいえ」
   （ファイルは LAN の中で iPhone → PC へ直接行く。こちらのサーバーは無い）
4. **プライバシーポリシーの URL**（必須）: `ios/プライバシーポリシー.md` を公開の場所に置いて、その URL
   （GitHub のリポジトリが公開なので https://github.com/yas-ito/mrdrop/blob/main/ios/プライバシーポリシー.md で通る）
5. **年齢制限** 4+
6. **スクリーンショット**: 6.9 インチ（1320×2868）が必須。シミュレータ「iPhone 17 Pro Max」で
   `xcrun simctl io <UDID> screenshot` で撮れる。最低 1 枚、できれば「PC 一覧」「送っている最中」「送れた」の 3 枚
7. **審査メモ**（下の 4 をそのまま貼る）と **デモ動画の URL**（YouTube 限定公開でよい）

## 2. ビルドして上げる（Xcode）

```bash
cd ios
# project.yml の DEVELOPMENT_TEAM を "6Q847K48UY" にしてから
xcodegen generate && open MrDrop.xcodeproj
```

Xcode で **Product ▸ Archive** → Organizer → **Distribute App ▸ App Store Connect ▸ Upload**。
アップロードのたびに `project.yml` の **`CURRENT_PROJECT_VERSION` を 1 つ上げる**（同じ番号は拒まれる）。

🔴 Xcode の画面で設定をいじらない（`xcodegen generate` で消える）。直すのは `project.yml`。

## 3. 審査で落ちるとしたら、ほぼこの 2 つ

1. **審査官が試せない**（受信側の PC が無い） → 審査メモ ＋ デモ動画で見せる
2. **ローカルネットワークの用途** → `NSLocalNetworkUsageDescription` に理由が書いてある。メモにも書く

落ちたら Resolution Center の文面を読んで、**メモを直して再提出**（コードを直す必要はたいてい無い）。
時間の目安: 審査 24〜48 時間、落ちるたび +1〜2 日、全体で 1〜2 週間。

## 4. 審査メモ（案・そのまま貼る）

```
Mr.Drop sends photos and videos from iPhone to a computer on the same Wi-Fi network,
directly over the local network (no cloud, no account, no server of ours).

IMPORTANT FOR REVIEW: the app needs a companion receiver program running on a
Mac or Windows PC on the same Wi-Fi. Without it, the app shows "Searching for a PC..."
and, after a few seconds, an explanation of what is needed plus a field to type the
PC's address manually. This is expected behavior, not a bug.

Please see the demo video showing the full flow (select photos on iPhone -> files
appear on the PC): <YouTube URL>

Local network / Bonjour: used only to discover the receiver (_mrdrop._tcp) and to
send files to it over HTTP within the LAN. Photo library: used only to let the user
pick what to send. No data is collected or transmitted anywhere else.

The receiver program is not sold or linked inside the app.
```

## 5. 公開したら Windows 側へ返すもの（`HANDOFF.md`）

- App Store の URL（取扱説明書の「iPhone アプリはありますか」に載せる）
- 出した `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION`
