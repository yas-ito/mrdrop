# 審査の催促（返信から動きが無いとき）— 1.0.0 (1)

**2026-09-07 時点の状態**（App Store Connect で確認した事実）:

| 項目 | 中身 |
|---|---|
| ステータス | **却下済み** `2.1.0 Performance: App Completeness` |
| Apple のメッセージ | **2026/09/04 9:47 の1通だけ**（Guideline 2.1 - Information Needed - New App Submission） |
| こちらの返信 | **2026/09/04 12:29**（6項目の回答＋実機の画面収録を添付） |
| その後 | **Apple からの新しいメッセージは無し**（メッセージは2件のまま） |
| 「App Reviewに再提出」 | **グレーで押せない** |

Submission ID: `03842473-e333-43a4-999f-ef476f014fa3`

🔴 **Apple の指示は「Reply in App Store Connect with all of the following information」**なので、
返信して待つ手順そのものは間違っていない。ただし返信から中3日 動きが無いので、
**①まだ情報が要るのか ②再提出が必要なのか**の2つを聞く。

## 送り方（本人の手）

1. App Store Connect →「配信」→ 左メニュー **App Review** → 提出（木曜日 13:10 の行）を開く
2. 下の返信欄に**下の英文をそのまま貼る**
3. 🔴 **送信ボタンは本人が押す**
4. ⚠️ **返信欄は4000字まで。**超えると「このフィールドは無効です」が出て、
   短くしても消えない（ダイアログを閉じて開き直すと直る）。この文面は約1,600字なので余裕がある

## 貼る文面（英語・そのまま）

```
Hello,

On 4 September 2026 (JST) I replied in App Store Connect to the Guideline 2.1 -
Information Needed message for Mr.Drop 1.0.0 (1) (Submission ID
03842473-e333-43a4-999f-ef476f014fa3). That reply answered all six points and
included a screen recording captured on a physical iPhone 13 Pro Max running
iOS 26.6.1, beginning with launching the app and showing the full user flow from
the Home Screen to the files arriving on the computer. The same information was
also added to the Notes field of the App Review Information section.

Since then the submission still shows "Rejected - 2.1.0 Performance: App
Completeness" and I have not received a further message, so I would like to ask
two things:

1. Is any additional information still needed? I am glad to provide anything that
   is missing, including another screen recording or a longer one.
2. Should I resubmit the version for review, or will the review continue from my
   reply? The "Resubmit to App Review" button is currently greyed out on my side,
   so I want to make sure I am not holding up the review by waiting.

For reference: Mr.Drop has no accounts, no login, no user-generated content shared
between users, no in-app purchases and no paid features. It sends photos, videos
and files from the iPhone to the user's own computer over the local network only.
Nothing passes through the internet or any server of ours.

Thank you for your time.
```

## 日本語訳（送るのは上の英文）

> 2026年9月4日（日本時間）に、Mr.Drop 1.0.0 (1) の Guideline 2.1（情報要求）へ
> App Store Connect から返信しました。6項目すべてに回答し、実機の iPhone 13 Pro Max
> （iOS 26.6.1）で撮った画面収録を添付しています（ホーム画面でアプリを起動する所から、
> ファイルがパソコンに届くまで）。同じ内容を App Review Information の Notes 欄にも入れました。
>
> それ以降、提出は「却下済み - 2.1.0 Performance: App Completeness」のままで、
> 新しいご連絡もいただいていないため、2点うかがいます。
>
> 1. まだ足りない情報はありますか。必要なら、別の画面収録でも何でもお出しします
> 2. バージョンを再提出すべきでしょうか。それとも返信から審査は続きますか。
>    こちらでは「App Reviewに再提出」ボタンがグレーで押せないので、
>    待っていることで審査を止めていないか確かめたいです
>
> （参考）Mr.Drop にはアカウント・ログイン・利用者間で共有される投稿・アプリ内課金・
> 有料機能がありません。iPhone の写真・動画・ファイルを、**同じ Wi-Fi の自分のパソコンへ
> ローカルネットワークだけで**送ります。インターネットや当方のサーバーは一切通りません。

## それでも動かないとき

- Apple の返事が1週間以上無ければ、**バージョンの「編集」から再提出**を検討する
  （再提出ボタンが無効なのは、却下された項目を編集していないからと思われる。断定はできない）
- 🔵 **リリースは「手動」のまま**（審査に通っても勝手に公開されない。BOOTH の PC 側と足並みを揃えるため）
