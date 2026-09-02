# YasDrop

iPhone から、同じ Wi-Fi にいる Windows へ写真・動画・ファイルを送る道具。
AirDrop と同じ操作感を目指しています。クラウドを通りません。端末どうしで直接送ります。

- **写真アプリの共有ボタンから直接送れる**（iPhone アプリを入れた場合）
- **設定なしで PC が見つかる**（Bonjour で広告しています。IP を打つ必要はありません）
- **元のまま送れる**（HEIC が JPEG に落とされない）
- **アプリが無くても送れる**（Safari で開くだけの画面もあります）
- **npm install が要りません**（外部パッケージを1つも使っていません）

---

## 使い方（いちばん短い道）

### 1. Windows で動かす

```bash
node server/yasdrop.js
```

こう出ます。

```
  YasDrop 1.0.0   yas
────────────────────────────────────────────────────
  受信箱  C:\Users\yasma\Desktop\受信箱
  送信箱  C:\Users\yasma\Desktop\送信箱
────────────────────────────────────────────────────
  iPhone の Safari から、このどれかを開いてください:
    http://yas.local:48630
    http://192.168.10.105:48630      （イーサネット）
────────────────────────────────────────────────────
  自動発見  _yasdrop._tcp で広告中
```

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

## iPhone アプリ

`ios/` にソースがあります。**Xcode が要るので Mac で作ります。**
手順は [`ios/README.md`](ios/README.md) を見てください。

アプリを入れると、写真アプリの共有ボタンに YasDrop が並びます。
これが AirDrop と同じ導線になります。

---

## 困ったとき

| 症状 | 見る所 |
|---|---|
| iPhone から開けない | PC と同じ Wi-Fi か。`install-windows.ps1` でファイアウォールを開けたか |
| `.local` で開けない | 代わりに IP（`http://192.168.…`）で開く |
| アプリが PC を見つけない | `node server/yasdrop.js --browse` で PC 自身が見つけられるか確かめる。<br>見つかるならアプリ側（`Info.plist` の `NSBonjourServices`）を疑う |
| 大きい動画が途中で止まる | 半端なファイルは受信箱に出さない作りです。もう一度送ってください |
| 自動起動しているか分からない | `.\scripts\install-windows.ps1 -Status` |

## 作りの確かめ方

```bash
node server/test/run.js
```

`../` でどこにでも書けないこと、途中で切れたものを受信箱に出さないこと、
mDNS のパケットを組んで読み戻せることを固定してあります。
