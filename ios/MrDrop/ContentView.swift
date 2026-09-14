import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// 写真ピッカーから「**元のファイルのまま**」受け取るための入れ物。
///
/// 🔴 型を静的に並べてはいけない。**Photos は頼まれた型に「変換して」渡してくる。**
///    実測（2026-09-03）: MP4 の 1080p 動画に `com.apple.quicktime-movie` を頼んだら、
///    **568×320・611 kbps のメール用書き出し**が返ってきた（60分で 336MB）。
///    `.item` ひとつでも、写真は JPEG に変換される。
///    → **写真用・MOV用・MP4用を分けて持ち、項目が名乗る型に合わせて選ぶ。**
protocol StagedFile: Transferable {
    var url: URL { get }
    var name: String { get }
    init(url: URL, name: String)
}

extension StagedFile {
    /// 渡された場所はすぐ消えるので、App Group の中へ移しておく。
    /// 🔴 1時間の動画は数GB。同じディスクなので**ハードリンクなら一瞬**で、容量も食わない。
    static func stage(_ received: ReceivedTransferredFile) throws -> Self {
        let dir = try MrDrop.stagingDirectory()
        let dest = dir.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.linkItem(at: received.file, to: dest)
        } catch {
            MrDrop.log("アプリ", "ハードリンク不可（コピーに落ちます）: \(MrDrop.describe(error))")
            try FileManager.default.copyItem(at: received.file, to: dest)
        }
        return Self(url: dest, name: received.file.lastPathComponent)
    }
}

struct PickedPhoto: StagedFile {
    let url: URL
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .heic)  { try stage($0) }
        FileRepresentation(importedContentType: .png)   { try stage($0) }
        FileRepresentation(importedContentType: .jpeg)  { try stage($0) }
        FileRepresentation(importedContentType: .image) { try stage($0) }
        FileRepresentation(importedContentType: .item)  { try stage($0) }
    }
}

/// 「扱いやすい形式で」のとき、写真はこちらで受け取る。
/// iOS が同じ解像度の JPEG に変換して渡してくる（実測 1206×2622 のまま）。
struct PickedJPEG: StagedFile {
    let url: URL
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .jpeg)  { try stage($0) }
        FileRepresentation(importedContentType: .image) { try stage($0) }
        FileRepresentation(importedContentType: .item)  { try stage($0) }
    }
}

struct PickedMOV: StagedFile {
    let url: URL
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .quickTimeMovie) { try stage($0) }
        FileRepresentation(importedContentType: .movie)          { try stage($0) }
        FileRepresentation(importedContentType: .item)           { try stage($0) }
    }
}

struct PickedMP4: StagedFile {
    let url: URL
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .mpeg4Movie) { try stage($0) }
        FileRepresentation(importedContentType: .movie)      { try stage($0) }
        FileRepresentation(importedContentType: .item)       { try stage($0) }
    }
}

struct ContentView: View {
    @EnvironmentObject private var conn: Connection
    @ObservedObject var discovery: Discovery
    @StateObject private var uploader = Uploader(identifier: MrDrop.sessionIDApp)

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var message: String?
    @State private var convertForPC = MrDrop.convertForPC

    var body: some View {
        NavigationStack {
            List {
                // 🔴 結果をいちばん上に出す。Windows のブラウザ画面では
                //    「送れているのに送れたことが伝わらず、同じ写真を4回送った」事故が起きた
                if !uploader.jobs.isEmpty { jobsSection }
                peerSection
                sendSection
                formatSection
                TokenSection()
            }
            .navigationTitle("送る")
            // 🔴 Discovery は1台だけのとき黙って lastPeer に入れるが、画面の ✓ は peer を見ている。
            //    そのままだと「一覧に出ているのに、選ばれていないように見える」。
            .onChange(of: discovery.peers) { _, list in
                if conn.peer == nil { conn.peer = MrDrop.lastPeer ?? list.first }
            }
            .alert("お知らせ", isPresented: .constant(message != nil)) {
                Button("わかりました") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    /// PC を選ぶところは「受け取る」と同じ物を使う（`PeerPicker.swift`）。
    /// 🔴 ここを画面ごとに写して持つと、片方だけ直して食い違う。
    private var peerSection: some View {
        PeerSection(
            discovery: discovery,
            title: "送り先の PC",
            footer: "このアプリは送るだけでなく、PC の送信箱から受け取ることもできます（下の「受け取る」タブ）。"
                  + "受け取るパソコン（Windows / Mac）にも Mr.Drop を入れて動かしてください"
                  + "（yas-tools.booth.pm で手に入ります）。同じ Wi-Fi につながっていれば、自動で見つかります。",
            message: $message
        )
    }

    private var formatSection: some View {
        Section {
            Toggle("PC で扱いやすい形式にする", isOn: $convertForPC)
                .onChange(of: convertForPC) { _, v in MrDrop.convertForPC = v }
        } header: {
            Text("送る形式")
        } footer: {
            Text(convertForPC
                 ? "HEIC の写真は JPEG、動画は MP4 にして送ります。PNG やすでに JPEG のものは触りません。動画は容器を替えるだけなので画質は変わりません（共有シートから送るときは、動画はそのままです）。"
                 : "撮ったままの形式（HEIC・MOV）で送ります。画質と情報は一切変わりません。")
        }
    }

    private var sendSection: some View {
        Section("送る") {
            PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos])) {
                Label("写真・動画を送る", systemImage: "photo.on.rectangle")
            }
            Button {
                showFiles = true
            } label: {
                Label("ファイルを送る", systemImage: "folder")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { sendFiles(urls) }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            sendPhotos(items)
        }
    }

    /// 🔴 「選ぶ＝送る」なので、終わったことをはっきり見せる。
    private var staging: Int { uploader.jobs.filter { $0.staging }.count }
    private var sending: Int { uploader.jobs.filter { !$0.finished && !$0.staging }.count }
    private var sentOK:  Int { uploader.jobs.filter { $0.finished && $0.error == nil }.count }
    private var failed:  Int { uploader.jobs.filter { $0.error != nil }.count }

    private var jobsHeadline: String {
        if staging > 0 { return "取り込んでいます（\(staging) 件）… 長い動画は数分かかります" }
        if sending > 0 { return "送っています（あと \(sending) 件）" }
        if failed  > 0 { return "送れませんでした \(failed) 件 ／ 送りました \(sentOK) 件" }
        return "✅ \(sentOK) 件 送りました"
    }

    private var jobsSection: some View {
        Section {
            ForEach(uploader.jobs) { j in
                VStack(alignment: .leading, spacing: 4) {
                    Text(j.filename).lineLimit(1)
                    if j.staging {
                        ProgressView()
                    } else if let e = j.error {
                        Text(e).font(.caption).foregroundStyle(.red)
                    } else if j.finished {
                        Text("送りました").font(.caption).foregroundStyle(.green)
                    } else if j.total > 0 {
                        ProgressView(value: Double(j.sent), total: Double(j.total))
                    } else {
                        ProgressView()
                    }
                }
            }
        } header: {
            Text(jobsHeadline)
                .font(.headline)
                .foregroundStyle(sending + staging > 0 ? Color.primary : (failed > 0 ? Color.red : Color.green))
        }
    }

    /// 送り先が1つも無いときの言い方。「選んでください」だけだと、
    /// そもそも PC 版を入れていない人が何をすればいいのか分からない。
    private var noPeerMessage: String {
        "先に送り先の PC を選んでください。受け取るパソコン（Windows / Mac）にも Mr.Drop が要ります（yas-tools.booth.pm）。"
    }

    private func currentPeer() -> MrDrop.Peer? { conn.current(discovery) }

    /// `.mov` を **作り直さずに** `.mp4` へ詰め替える（パススルー）。画質は変わらず、数秒で終わる。
    /// 🔴 共有拡張ではやらない。メモリ 120MB の中で走らせると落ちる。
    ///
    /// 🔴 詰め替えると**中の作成日時が「変換した時刻」に化ける**（2026-09-14 に測った）。
    ///    消えるより悪い。もっともらしい嘘の日付が入るので、誰も間違いに気づけない。
    ///    「送る形式」を切にしたときだけ日付が残る、という食い違いになっていた。
    /// 🔴 だから日付は**呼ぶ側が詰め替える前に読んで**、ここへ渡す。あとから読んでは手遅れ。
    private func remuxToMP4(_ url: URL, taken: Date?) async -> URL? {
        guard url.pathExtension.lowercased() != "mp4" else { return url }
        let asset = AVURLAsset(url: url)
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            MrDrop.log("変換", "🔴 パススルーの書き出しを作れませんでした")
            return nil
        }
        let out = url.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: out)
        ex.outputURL = out
        ex.outputFileType = .mp4
        if let taken { ex.metadata = FileDate.creationMetadata(taken) }   // 🔴 これが無いと日付が消える
        let started = Date()
        await withCheckedContinuation { cont in
            ex.exportAsynchronously { cont.resume() }
        }
        guard ex.status == .completed else {
            // 詰め替えられない中身（Live Photo など）は、元のまま送る
            MrDrop.log("変換", "🔴 詰め替え失敗（元のまま送ります）: \(ex.error.map(MrDrop.describe) ?? "理由不明")")
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        MrDrop.log("変換", "mp4 へ詰め替え \(String(format: "%.1f", -started.timeIntervalSinceNow))秒")
        if let taken {
            // 🔴 札だけでは足りない。ヘッダには書き出した時刻が入るので、そこも直す
            //    （Windows の「メディアの作成日」や編集ソフトはヘッダを見る）。
            FileDate.patchContainerDate(out, to: taken)
        }
        FileDate.apply(taken, to: out)                   // 外側の日付もそろえておく
        try? FileManager.default.removeItem(at: url)     // 元は要らない
        return out
    }

    /// 進み具合（iCloud からのダウンロード）を拾いたいので、await 版ではなく
    /// Progress を返す版を使う。
    private func load<T: StagedFile>(_ item: PhotosPickerItem, as: T.Type,
                                     ticket: Int) async -> Result<(url: URL, name: String)?, Error> {
        await withCheckedContinuation { cont in
            let progress = item.loadTransferable(type: T.self) { result in
                cont.resume(returning: result.map { picked in picked.map { (url: $0.url, name: $0.name) } })
            }
            Task { @MainActor in uploader.track(progress, for: ticket) }
        }
    }

    private func sendPhotos(_ items: [PhotosPickerItem]) {
        guard let p = currentPeer() else { message = noPeerMessage; return }
        Task {
            for item in items {
                // 🔴 iOS が書き出し終えるまで `loadTransferable` は返ってこない。
                //    1時間の動画なら数分、iCloud にしか無ければダウンロードから始まる。
                //    先に行を出しておかないと「押したのに無反応」に見える。
                let ticket = uploader.beginStaging("取り込んでいます…")
                MrDrop.log("アプリ", "取り込み開始 types=\(item.supportedContentTypes.map(\.identifier).joined(separator: ","))")
                // 🔴 項目が名乗る型に合わせて受け口を選ぶ。ここを固定にすると変換されて画質が落ちる。
                let types = item.supportedContentTypes
                let isMovie = types.contains { $0.conforms(to: .movie) }
                let outcome: Result<(url: URL, name: String)?, Error>
                if types.contains(.mpeg4Movie) {
                    outcome = await load(item, as: PickedMP4.self, ticket: ticket)
                } else if isMovie {
                    outcome = await load(item, as: PickedMOV.self, ticket: ticket)
                } else if convertForPC, types.contains(where: { MrDrop.isHEIF($0.identifier) }) {
                    outcome = await load(item, as: PickedJPEG.self, ticket: ticket)   // HEIC → JPEG
                } else {
                    outcome = await load(item, as: PickedPhoto.self, ticket: ticket)
                }
                do {
                    if var f = try outcome.get() {
                        // 🔴 日付は**詰め替える前に**読む。詰め替えで消えるため。
                        let taken = await FileDate.best(of: f.url)
                        if convertForPC, isMovie, let mp4 = await remuxToMP4(f.url, taken: taken) {
                            f = (url: mp4, name: (f.name as NSString).deletingPathExtension + ".mp4")
                        }
                        uploader.endStaging(ticket)
                        let size = (try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size] as? Int64) ?? nil
                        MrDrop.log("アプリ", "取り込み成功 \(f.name) \(size ?? -1) バイト 日付=\(taken.map { ISO8601DateFormatter().string(from: $0) } ?? "不明")")
                        uploader.send(fileURL: f.url, filename: f.name, to: p, modified: taken, whileWatching: true)
                    } else {
                        MrDrop.log("アプリ", "🔴 取り込み: iOS が nil を返した")
                        uploader.failStaging(ticket, "iOS がこの項目を渡してくれませんでした")
                    }
                } catch {
                    let detail = MrDrop.describe(error)
                    MrDrop.log("アプリ", "🔴 取り込み失敗 \(detail)")
                    uploader.failStaging(ticket, detail)
                }
            }
            photoItems = []
        }
    }

    private func sendFiles(_ urls: [URL]) {
        guard let p = currentPeer() else { message = noPeerMessage; return }
        for u in urls {
            // 「ファイル」アプリのものは許可を取ってから読む
            let needsStop = u.startAccessingSecurityScopedResource()
            defer { if needsStop { u.stopAccessingSecurityScopedResource() } }
            do {
                // 🔴 元の日付は**写す前**に、許可が開いているうちに読む。
                //    書類や PDF は中に日付を持たないので、ここが唯一の手がかりになる。
                let onDisk = FileDate.fileDate(of: u)
                let dir = try MrDrop.stagingDirectory()
                let dest = dir.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent)
                try FileManager.default.copyItem(at: u, to: dest)
                let name = u.lastPathComponent
                Task {
                    let taken = await FileDate.embedded(in: dest) ?? onDisk
                    uploader.send(fileURL: dest, filename: name, to: p, modified: taken, whileWatching: true)
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
