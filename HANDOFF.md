# 申し送り — Mac ⇄ Windows の伝言板

**ここは「相手が次に読む唯一の場所」です。**
作業を終えたら、自分の欄を**書き換えて**ください（積み上げない・古い話は消す）。

---

## 🔴 Windows → Mac

**最終更新: 2026-09-02（Windows側）／新規に作りました**

# 🆕 Mr.Drop を新設。**Windows 側は完成・実機で通しました**

iPhone から Windows へ送る道具です。AirDrop の代わり。

## 動くと確かめたこと（Windows 実機・作り直し不要）

- **12MB のファイルを実際に送って、バイト単位で一致**（受信箱に落ちるところまで）
- **自動発見が通った**。`node server/mrdrop.js --browse` で
  `yas._mrdrop._tcp.local → 192.168.10.105:48630` が返る
- **全テスト 83件 成功**（`node server/test/run.js`）
- ブラウザの画面（`/`）も表示・アップロード・ダウンロードまで確認

## 🔴 実機で踏んだ罠（同じ所でハマらないように）

**mDNS の問い合わせに QU ビット（qclass の最上位）を立てないと、答えが返ってきません。**
応答は `224.0.0.251:5353` 宛のマルチキャストでしか飛ばないので、こちらが適当な番号で
待っていると受け取れない。最初これで「見つかりません」になりました。
`lib/mdns.js` の `buildQuery` で既定 true にし、`test/mdns.test.js` で固定済みです。

## 🔲 Mac にお願いしたいこと: **iPhone アプリを作る**

`ios/` に Swift のソースを置きました。**Xcode が無いので一度もビルドしていません。**
手順は [`ios/README.md`](ios/README.md) に全部書いてあります（ターゲット構成・
App Groups・Info.plist の鍵まで）。そのとおりに作れば乗るはずです。

- ファイル: `Shared/MrDropShared.swift`・`MrDrop/{MrDropApp,ContentView,Discovery,Uploader}.swift`・
  `ShareExtension/ShareViewController.swift`
- 🔴 `MrDropShared.swift` と `Uploader.swift` は**両ターゲットに入れる**こと
- 🔴 `Info.plist` の `NSBonjourServices` に `_mrdrop._tcp` を書き忘れると、
  権限ダイアログすら出ずに「1台も見つからない」だけになります。まずここを疑ってください
- 🔴 共有拡張はメモリ約120MB しかないので、**中身を読まない**設計にしてあります
  （ファイルをコピーしてバックグラウンド転送に渡すだけ）。ここは変えないでください

**確かめてほしいこと**

1. そもそもビルドが通るか（通らなかった所は直して、ここに書いてください）
2. `NWBrowser` で Windows の PC が一覧に出るか
3. 写真アプリ ▸ 共有 ▸ MrDrop で、**1GB 級の動画**を送っても拡張が落ちないか
   （ここが設計の当たり外れの分かれ目です）
4. HEIC が HEIC のまま届くか（JPEG に化けていないか）

**試すには Windows 側でサーバーが動いている必要があります。**
Mac にも Node があるので `node server/mrdrop.js` は Mac でも動きます
（受信箱は Mac 側になります）。iPhone の動作確認だけなら Mac 単独でできます。

## 🔵 まだ手を付けていないこと

- **PC → iPhone** はブラウザ画面からしかできません（アプリ側は未実装）
- QR コードの表示（`.local` 名で足りているので後回しにしました）
- Mac 用の常駐スクリプト（`scripts/` は Windows 用の PowerShell だけです）

---

## Mac → Windows

（まだありません）

---

## この伝言板の使い方

- **作業を始める前に `git pull` → ここを読む**
- **作業を終えたら自分の欄を書き換える**（積み上げない・経緯は各ファイルのコメントへ）
- 決まりの全体は [`CLAUDE.md`](CLAUDE.md)
