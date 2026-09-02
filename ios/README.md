# iPhone 側（Xcode・Mac でしか作れません）

ここにあるのは **Swift のソースだけ**です。Xcode プロジェクトは入っていません。
Windows では Xcode が動かないので、**まだ一度もビルドしていません**。
Mac 側で下の手順どおりに作れば、そのまま乗るはずです（乗らなかった所は直して
`HANDOFF.md` に書いてください）。

---

## 1. プロジェクトを作る

Xcode → **File ▸ New ▸ Project ▸ iOS ▸ App**

| 項目 | 値 |
|---|---|
| Product Name | `YasDrop` |
| Interface | SwiftUI |
| Language | Swift |
| Minimum Deployments | **iOS 17.0**（`onChange` の新しい書き方を使っています） |
| Organization Identifier | `jp.yastools` |

Bundle Identifier は `jp.yastools.yasdrop` になります。

## 2. 共有拡張のターゲットを足す

**File ▸ New ▸ Target ▸ iOS ▸ Share Extension**

| 項目 | 値 |
|---|---|
| Product Name | `ShareExtension` |
| Bundle Identifier | `jp.yastools.yasdrop.ShareExtension`（自動でこうなる） |

「Activate scheme?」は **Cancel** で構いません。

## 3. ソースを入れる

| ファイル | 入れるターゲット |
|---|---|
| `Shared/YasDropShared.swift` | 🔴 **YasDrop と ShareExtension の両方** |
| `YasDrop/Uploader.swift` | 🔴 **両方**（拡張も転送を始めるため） |
| `YasDrop/YasDropApp.swift` | YasDrop のみ |
| `YasDrop/ContentView.swift` | YasDrop のみ |
| `YasDrop/Discovery.swift` | YasDrop のみ |
| `ShareExtension/ShareViewController.swift` | ShareExtension のみ（生成された同名ファイルを置き換える） |

⚠️ 「両方」のものは、追加時の **Target Membership** で2つともチェックを入れてください。
片方だけだと、共有シートから送ったときにだけ落ちます（原因が分かりにくい失敗の典型）。

## 4. App Groups を入れる（両方のターゲット）

**Signing & Capabilities ▸ + Capability ▸ App Groups**

両方に同じものを足します:

```
group.jp.yastools.yasdrop
```

🔴 これが無いと、拡張がコピーしたファイルを転送側が読めません。
`YasDropShared.swift` の `appGroup` と**文字列を完全に一致させること**。

## 5. Info.plist に足す（🔴 ここが最大の罠）

### YasDrop（本体）

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>同じ Wi-Fi にあるパソコンを探して、写真や動画を送るために使います。</string>

<key>NSBonjourServices</key>
<array>
  <string>_yasdrop._tcp</string>
</array>

<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

- **`NSBonjourServices` を書き忘れると、権限のダイアログすら出ずに、ただ「1台も見つからない」だけになります。**
  ここで何時間も溶かす人が多いので、まずここを疑ってください。
- `NSAllowsLocalNetworking` が無いと、平文 HTTP なので接続そのものが弾かれます。

### ShareExtension

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

受け付けるものを決める `NSExtensionActivationRule`（`NSExtension ▸ NSExtensionAttributes` の中）:

```xml
<key>NSExtensionActivationRule</key>
<dict>
  <key>NSExtensionActivationSupportsImageWithMaxCount</key><integer>100</integer>
  <key>NSExtensionActivationSupportsMovieWithMaxCount</key><integer>20</integer>
  <key>NSExtensionActivationSupportsFileWithMaxCount</key><integer>20</integer>
</dict>
```

## 6. 実機に入れる

1. iPhone を繋ぐ
2. Signing で自分の Team を選ぶ（両方のターゲット）
3. Run

## 7. 動かし方（初回）

1. **先に Windows で受信サーバーを動かしておく**（`node server/yasdrop.js`）
2. iPhone で YasDrop アプリを開く → 「ローカルネットワーク」の許可を **許可**
3. PC の名前が一覧に出る → タップして選ぶ
4. 写真アプリ → 共有 → **YasDrop** が並ぶ

🔴 **手順3を一度やるまで、共有シートからは送れません。**
拡張は「最後に選んだ PC」を見て送るので、まだ何も選ばれていないと
「先にアプリを開いてください」と出ます。これは仕様です。

---

## 分かっている弱点

- **PC の IP が変わると、共有シートからの送信が失敗します。**
  拡張は解決済みの IP を使う設計です（`.local` 名だと拡張側で名前解決に失敗しやすいため）。
  失敗したらアプリを一度開けば、探し直して覚え直します。
  → ルータで PC の IP を固定しておくと、この問題自体が消えます。
- **署名は1年で切れます。**切れるとアプリが起動しなくなります。
  Xcode で Run し直せば直ります（データは残ります）。
  切れた日は、Safari で `http://<PC名>.local:48630` を開けば送れます。
- 写真の名前は iOS が付けたもの（`IMG_0001.HEIC` など）になります。
- まだ **PC → iPhone** はアプリ側に作っていません。ブラウザの画面からは受け取れます。
