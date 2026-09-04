# 審査への返信（Guideline 2.1 - Information Needed・1.0.0 (1)）

**2026-09-04 受領。落ちたのではなく「情報が足りない」＝ビルドの作り直しは不要。**
App Store Connect の App Review ページから**返信**し、同じ内容を
**App Review Information の Notes 欄にも貼る**（次回以降のため）。

Submission ID: `03842473-e333-43a4-999f-ef476f014fa3`

## 🔴 先にやること（本人の手）— 実機で画面収録

Apple の 1 番は「**実機で撮った**画面収録」。前回添付した `_build/ios/demo-for-review.mp4` は
**シミュレータ収録（1320×2868・30fps）**なので、これは受け付けられない。

1. Mac（または Windows）で受信側を動かす … `Mr.Drop.app` を起動、または `node server/mrdrop.js`
2. iPhone の**コントロールセンターの「画面収録」**で撮る。🔴 **ホーム画面でアプリを起動する所から映す**
3. 映す順番: 起動 → ローカルネットワークの許可 → PC が見つかる → 「写真・動画を送る」→ 3 枚選ぶ
   → 送る → PC の受信箱に届く → 戻って「**住所を手で入れる**」の画面も一度見せる
4. 止める → 写真アプリに入る → Mac へ送る（Mr.Drop 自身で送ればよい）
5. 1〜2 分・縦のまま。App Review ページの返信に**添付**する（大きすぎるときだけ YouTube 限定公開）

## 貼る文面（英語・そのまま）

```
Thank you for the review. Mr.Drop has no accounts, no user-generated content shared
between users, no in-app purchases and no paid features, so the account and paid-content
items below do not apply. Answers to all six points follow.

1. SCREEN RECORDING (physical device)

Attached: a screen recording captured on a physical iPhone running the latest iOS,
starting from launching the app. It shows the typical user flow end to end:
launch -> Local Network permission -> the PC is found automatically -> "Send photos
and videos" -> selecting 3 photos -> transfer progress -> the files arriving in the
Inbox folder on the PC -> the "enter the address manually" screen.

Not applicable, and why:
- Account registration / login / account deletion: the app has no accounts of any kind.
  Nothing is registered, no credentials are stored, and no personal data leaves the device
  except the files the user explicitly chooses to send to their own computer.
- User-generated content: nothing is published or shared with other users, so there is
  no feed, no other users, and therefore no reporting or blocking mechanism.
- Paid content or features: the app is free and contains no purchases of any kind.

2. PURPOSE AND TARGET AUDIENCE

Problem: Windows PCs have no AirDrop. Moving photos and videos from an iPhone to a PC
normally means a cable, a cloud service, or a re-compressed copy sent by email or chat.

Mr.Drop sends the original file straight to a computer on the same Wi-Fi network, over
the local network only. Nothing passes through the internet or through any server of ours.

Target audience: iPhone owners who work on a Windows (or Mac) computer - video editors,
photographers, and ordinary users who move large photo and video files to their computer
every day. The app is written in Japanese and is aimed primarily at users in Japan.

Value: original quality (HEIC and MOV are not re-encoded), no account, no cloud storage,
multi-gigabyte videos are supported, and it works from the standard iOS share sheet.

3. SETTING UP AND ACCESSING THE MAIN FEATURES

Mr.Drop is the sending side. It needs the companion receiver running on a computer on
the same Wi-Fi network. The receiver is free and open source:

    https://github.com/yas-ito/mrdrop

  On a Mac or a Windows PC with Node.js installed:   node server/mrdrop.js
  The receiver prints its address, for example:      http://192.168.1.20:48630

On the iPhone:
  1. Launch Mr.Drop and allow Local Network access.
  2. The computer is discovered automatically over Bonjour (_mrdrop._tcp). If the review
     network blocks Bonjour or multicast, tap the row "Enter the address manually"
     (Japanese: 住所を手で入れる), type the address printed by the receiver, and tap
     "Connect" (つなぐ). The app verifies it before adding it as a destination.
  3. Tap "Send photos and videos" (写真・動画を送る), choose items, tap "Send" (送る).
     The files appear in the Inbox folder on the computer.
  Sending also works from the iOS share sheet: Photos -> Share -> Mr.Drop.

No login credentials exist, because there are no accounts. The optional "pass phrase"
field (合言葉) is only used when the owner of the receiving computer sets a token on the
computer; leave it empty for review. No sample files are needed - any photo works.

If running the receiver is not practical during review, the attached recording shows the
complete flow. We are also happy to arrange a call or a screen share.

4. EXTERNAL SERVICES, TOOLS AND PLATFORMS

None. The app uses only Apple frameworks (SwiftUI, PhotosUI, Network.framework / Bonjour,
URLSession). There are no third-party SDKs or libraries, no analytics, no crash reporting,
no advertising, no authentication service, no payment processor and no AI services.

We operate no server. Files are transferred directly from the iPhone to the user's own
computer over plain HTTP inside the local network; nothing is uploaded to the internet.
This is why the app declares NSAllowsLocalNetworking and NSBonjourServices, and why the
privacy answers state that no data is collected.

5. REGIONAL DIFFERENCES

There are none. The app behaves identically in every country and region. There is no
region-gated feature, no region-specific content, and no server-side configuration that
could vary by region. The user interface is currently Japanese only.

6. REGULATED INDUSTRY / PROTECTED THIRD-PARTY MATERIAL

Not applicable. The app is not part of a regulated industry and contains no third-party
or protected material. It transfers only the user's own files, chosen by the user, to a
computer owned by the same user. All code, icon and screenshots are our own work.

The current build 1.0.0 (1) is unchanged and ready for review.
```

## 補足

- 落ちた理由は文面のとおり「**開発者アカウントの審査履歴が浅いので、もっと情報がほしい**」（2.1）。
  コードの不具合は 1 つも指摘されていない
- 返信で足りれば**再提出は不要**。もし再提出になったら `project.yml` の
  `CURRENT_PROJECT_VERSION` を **2** に上げてから上げ直す
- 同じ文面を **App Review Information ▸ Notes** にも貼る（次の版から毎回これが効く）
