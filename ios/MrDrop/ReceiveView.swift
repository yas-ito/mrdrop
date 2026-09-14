import SwiftUI

/// PC の送信箱から受け取る画面。
///
/// 🔴 この画面が無かったせいで、発売翌日に「PC → iPhone が動かない」と苦情が来た
///    （2026-09-14）。**送れた人は、当然アプリの中に受け取る所があると読む。**
///    ブラウザで住所を打つ作りは、説明書に書いても届かなかった。
///
/// 🔴 通知は出せない（iOS は閉じたアプリに LAN を見張らせない）。
///    だから「開けば分かる」ことがすべて。開いた瞬間に一覧を取りに行く。
struct ReceiveView: View {
    @EnvironmentObject private var conn: Connection
    @ObservedObject var discovery: Discovery
    @StateObject private var downloader = Downloader()

    @State private var message: String?
    @State private var intoPhotos = MrDrop.receiveIntoPhotos

    private var peer: MrDrop.Peer? { conn.current(discovery) }

    /// まだ受け取っていないもの
    private var fresh: [MrDrop.RemoteFile] {
        downloader.files.filter { !downloader.receivedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !downloader.jobs.isEmpty { jobsSection }
                peerSection
                filesSection
                destinationSection
            }
            .navigationTitle("受け取る")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await downloader.refresh(from: peer) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(peer == nil || downloader.listing)
                }
            }
            .refreshable { await downloader.refresh(from: peer) }
            // 🔴 開いた瞬間と、PC を選び直したときに取りに行く。
            //    「更新ボタンを押さないと何も出ない」では、また同じ苦情になる。
            .task(id: peer?.id) { await downloader.refresh(from: peer) }
            .alert("お知らせ", isPresented: .constant(message != nil)) {
                Button("わかりました") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var peerSection: some View {
        PeerSection(
            discovery: discovery,
            title: "受け取り元の PC",
            footer: "PC の「送信箱」フォルダに入っているものが、下に出ます。"
                  + "送信箱の場所は Windows も Mac も「デスクトップ › Mr.Drop送信箱」です。",
            message: $message
        )
    }

    // MARK: - 送信箱の中身

    private var filesSection: some View {
        Section {
            if peer == nil {
                Text("先に上で PC を選んでください。").foregroundStyle(.secondary)
            } else if downloader.listing && downloader.files.isEmpty {
                HStack { ProgressView(); Text("送信箱を見ています…").foregroundStyle(.secondary) }
            } else if let e = downloader.listError {
                // 🔴 「つながらない」を「空です」と言わない。今回の苦情と同じ型の事故になる
                Text(e).foregroundStyle(.red).font(.callout)
            } else if downloader.files.isEmpty {
                emptyGuide
            } else {
                ForEach(downloader.files) { f in fileRow(f) }
            }
        } header: {
            HStack {
                Text("PC の送信箱")
                Spacer()
                if !fresh.isEmpty, let p = peer {
                    Button(fetchAllLabel) { downloader.fetchAll(fresh, from: p) }
                        .font(.caption)
                }
            }
        } footer: {
            if !downloader.files.isEmpty {
                // 🔴 ここを書かないと「受け取ったのに PC から消えない」を不具合と読まれる
                Text("受け取っても、PC の送信箱からは消えません（置いた人の物を勝手に消さないため）。"
                     + "同じものを二度受け取らないよう、済んだ行には印が付きます。"
                     + "通知は出ないので、届いたかどうかはこの画面を開いて確かめてください。")
            }
        }
    }

    /// まとめて受け取るボタンの文字。
    /// 🔴 「まだの◯件」は日本語として不自然（本人指摘 2026-09-14）。
    ///    全部まだなら「すべて」、一部だけ残っているなら「残りの」と言い分ける。
    ///    ⚠️ 一部だけ残っているときに「すべて」と書くと、済んだ分も落とし直すように読めるので嘘になる。
    private var fetchAllLabel: String {
        fresh.count == downloader.files.count
            ? "\(fresh.count) 件すべて受け取る"
            : "残りの \(fresh.count) 件を受け取る"
    }

    /// 空っぽのときの案内。**「空です」だけで終わらせない。**
    /// 送信箱がどこにあるか分からないまま「壊れている」と思われるのが、いちばん多い詰まり方。
    private var emptyGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("送信箱は空です").foregroundStyle(.primary)
            // 🔴 `+` でつないだ文字列は Markdown として読まれない（`**` がそのまま画面に出る）。
            //    太字を使う Text は、必ず1本のリテラルのまま置くこと（実機で出した 2026-09-14）。
            Text("パソコンの **デスクトップ › Mr.Drop送信箱** に、iPhone へ渡したいファイルを入れてください。入れたら、この画面を下に引いて更新します。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func fileRow(_ f: MrDrop.RemoteFile) -> some View {
        let done = downloader.receivedIDs.contains(f.id)
        let working = downloader.isWorking(f)
        return Button {
            guard let p = peer else { return }
            if done {
                // 済んだ物をもう一度押したときは、取り直すか聞く代わりに印を外して落とし直す
                downloader.forget(f)
            }
            downloader.fetch(f, from: p)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: f.name))
                    .foregroundStyle(done ? Color.secondary : Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).lineLimit(1).foregroundStyle(done ? .secondary : .primary)
                    Text("\(f.human)　\(f.modified.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if working {
                    ProgressView()
                } else if done {
                    Label("受け取り済み", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working || peer == nil)
    }

    private func icon(for name: String) -> String {
        switch MrDrop.photoKind(for: name) {
        case .video: return "film"
        case .photo: return "photo"
        case nil:    return "doc"
        }
    }

    // MARK: - 進み具合と結果

    private var receiving: Int { downloader.jobs.filter { !$0.finished }.count }
    private var gotOK: Int { downloader.jobs.filter { $0.finished && $0.error == nil }.count }
    private var failed: Int { downloader.jobs.filter { $0.error != nil }.count }

    private var jobsHeadline: String {
        if receiving > 0 { return "受け取っています（あと \(receiving) 件）" }
        if failed > 0 { return "受け取れませんでした \(failed) 件 ／ 受け取りました \(gotOK) 件" }
        return "✅ \(gotOK) 件 受け取りました"
    }

    private var jobsSection: some View {
        Section {
            ForEach(downloader.jobs) { j in
                VStack(alignment: .leading, spacing: 4) {
                    Text(j.name).lineLimit(1)
                    if let e = j.error {
                        Text(e).font(.caption).foregroundStyle(.red)
                    } else if j.saving {
                        HStack(spacing: 6) { ProgressView(); Text("保存しています…").font(.caption) }
                    } else if j.finished, let d = j.saved {
                        // 🔴 「受け取りました」だけでは足りない。**どこへ入ったか**まで言う。
                        //    ここが無いと、受け取れているのに「どこにも無い」と言われる
                        Text(d.label).font(.caption).foregroundStyle(.green)
                    } else if j.total > 0 {
                        ProgressView(value: Double(j.got), total: Double(j.total))
                    } else {
                        ProgressView()
                    }
                }
            }
        } header: {
            HStack {
                Text(jobsHeadline)
                    .font(.headline)
                    .foregroundStyle(receiving > 0 ? Color.primary : (failed > 0 ? Color.red : Color.green))
                Spacer()
                if receiving == 0 {
                    Button("消す") { downloader.clearFinished() }.font(.caption)
                }
            }
        }
    }

    // MARK: - 保存先

    private var destinationSection: some View {
        Section {
            Toggle("写真・動画は「写真」アプリに入れる", isOn: $intoPhotos)
                .onChange(of: intoPhotos) { _, v in MrDrop.receiveIntoPhotos = v }
        } header: {
            Text("保存先")
        } footer: {
            Text(intoPhotos
                 ? "写真と動画は「写真」アプリへ、それ以外は「ファイル」アプリ（Mr.Drop › 受信）へ入ります。"
                 : "全部「ファイル」アプリ（Mr.Drop › 受信）へ入ります。")
        }
    }
}
