# iPhone 側（Xcode・Mac でしか作れません）

ここにあるのは **Swift のソースだけ**です。Xcode プロジェクトは入っていません。
Windows では Xcode が動かないので、**まだ一度もビルドしていません**。
Mac 側で下の手順どおりに作れば、そのまま乗るはずです（乗らなかった所は直して
`HANDOFF.md` に書いてください）。

---

## 0. いちばん速い作り方（**Xcode の画面を触らない**・2026-09-02 に Mac で確立）

**`project.yml` が設計図です。**下の 1〜5 の手作業は、これ1つに置き換わりました。

```bash
brew install xcodegen
cd ios && xcodegen generate && open MrDrop.xcodeproj
```

ターゲット構成・App Groups・`Info.plist` の鍵・どのファイルをどちらのターゲットに入れるかは、
**全部 `project.yml` に書いてあります**。

🔴 **Xcode の画面で設定をいじらないでください。**`xcodegen generate` で消えます。直すのは `project.yml`。
🔴 `Info.plist` と `.entitlements` は**生成物**です（git は追いません）。

実機に入れるときだけ、Xcode の **Signing & Capabilities で自分の Team を選びます**（両ターゲット）。
シミュレータで動かすだけなら署名は要りません:

```bash
xcodebuild -project MrDrop.xcodeproj -scheme MrDrop -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### 🔴 シミュレータで App Groups を試すときは、**手で署名し直す**

**Team を選んでいないと、Xcode は App Groups の権限を署名から黙って落とします**
（`codesign -d --entitlements :- MrDrop.app` が空の `<dict/>` になる）。
すると `containerURL(forSecurityApplicationGroupIdentifier:)` が nil を返し、
**写真を選んだ瞬間に取り込みが失敗**します。実機（Team あり）では起きません。

```bash
A=<DerivedData>/Build/Products/Debug-iphonesimulator/MrDrop.app
codesign -f -s - --entitlements ShareExtension/ShareExtension.entitlements "$A/PlugIns/ShareExtension.appex"
codesign -f -s - --entitlements MrDrop/MrDrop.entitlements "$A"
xcrun simctl install <UDID> "$A"
```

### ビルドで実際に踏んだ罠（2件・直済み）

- **`escaping closure captures non-escaping parameter 'change'`**（`Uploader.update`）
  → `@escaping` を付けた。`DispatchQueue.main.async` の中で使うため
- **インストールが `does not have a CFBundleDisplayName key` で失敗**
  → **共有拡張の `Info.plist` にも `CFBundleDisplayName` が要る**。
  自前の `Info.plist` を渡すときは `INFOPLIST_KEY_*` のビルド設定は効かないので、plist に直接書く

---

## 1. プロジェクトを作る（Xcode の画面から手で作る場合。0 をやったなら不要）

Xcode → **File ▸ New ▸ Project ▸ iOS ▸ App**

| 項目 | 値 |
|---|---|
| Product Name | `MrDrop`（**点を入れない**。識別子に使われるので） |
| Interface | SwiftUI |
| Language | Swift |
| Minimum Deployments | **iOS 17.0**（`onChange` の新しい書き方を使っています） |
| Organization Identifier | `jp.yastools` |

Bundle Identifier は `jp.yastools.mrdrop` になります。

作ったあと、**General ▸ Display Name を `Mr.Drop`** にしてください。
ホーム画面と共有シートに出る名前がこれになります（Product Name は内部用なので点なし）。

## 2. 共有拡張のターゲットを足す

**File ▸ New ▸ Target ▸ iOS ▸ Share Extension**

| 項目 | 値 |
|---|---|
| Product Name | `ShareExtension` |
| Bundle Identifier | `jp.yastools.mrdrop.ShareExtension`（自動でこうなる） |

「Activate scheme?」は **Cancel** で構いません。

## 3. ソースを入れる

| ファイル | 入れるターゲット |
|---|---|
| `Shared/MrDropShared.swift` | 🔴 **MrDrop と ShareExtension の両方** |
| `MrDrop/Uploader.swift` | 🔴 **両方**（拡張も転送を始めるため） |
| `MrDrop/MrDropApp.swift` | MrDrop のみ |
| `MrDrop/ContentView.swift` | MrDrop のみ |
| `MrDrop/Discovery.swift` | MrDrop のみ |
| `ShareExtension/ShareViewController.swift` | ShareExtension のみ（生成された同名ファイルを置き換える） |

⚠️ 「両方」のものは、追加時の **Target Membership** で2つともチェックを入れてください。
片方だけだと、共有シートから送ったときにだけ落ちます（原因が分かりにくい失敗の典型）。

## 4. App Groups を入れる（両方のターゲット）

**Signing & Capabilities ▸ + Capability ▸ App Groups**

両方に同じものを足します:

```
group.jp.yastools.mrdrop
```

🔴 これが無いと、拡張がコピーしたファイルを転送側が読めません。
`MrDropShared.swift` の `appGroup` と**文字列を完全に一致させること**。

## 5. Info.plist に足す（🔴 ここが最大の罠）

### MrDrop（本体）

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>同じ Wi-Fi にあるパソコンを探して、写真や動画を送るために使います。</string>

<key>NSBonjourServices</key>
<array>
  <string>_mrdrop._tcp</string>
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

1. **先に Windows で受信サーバーを動かしておく**（`node server/mrdrop.js`）
2. iPhone で Mr.Drop アプリを開く → 「ローカルネットワーク」の許可を **許可**
3. PC の名前が一覧に出る → タップして選ぶ
4. 写真アプリ → 共有 → **Mr.Drop** が並ぶ

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
