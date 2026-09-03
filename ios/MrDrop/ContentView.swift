import SwiftUI
import PhotosUI
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
    @StateObject private var discovery = Discovery()
    @StateObject private var uploader = Uploader(identifier: MrDrop.sessionIDApp)

    @State private var peer: MrDrop.Peer? = MrDrop.lastPeer
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                // 🔴 結果をいちばん上に出す。Windows のブラウザ画面では
                //    「送れているのに送れたことが伝わらず、同じ写真を4回送った」事故が起きた
                if !uploader.jobs.isEmpty { jobsSection }
                peerSection
                sendSection
            }
            .navigationTitle("MrDrop")
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .alert("お知らせ", isPresented: .constant(message != nil)) {
                Button("わかりました") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var peerSection: some View {
        Section {
            if discovery.peers.isEmpty {
                HStack {
                    ProgressView()
                    Text("同じ Wi-Fi の PC を探しています…").foregroundStyle(.secondary)
                }
            }
            ForEach(discovery.peers) { p in
                Button {
                    peer = p
                    MrDrop.lastPeer = p
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text("\(p.host):\(String(p.port))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if peer == p { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    // 🔴 これが無いと当たり判定が文字の上だけになり、
                    //    行の余白を押しても選べない（実機で必ず戸惑う）
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("送り先の PC")
        } footer: {
            Text("見つからないときは、PC で MrDrop が動いているか、同じ Wi-Fi につながっているかを確かめてください。")
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

    private func currentPeer() -> MrDrop.Peer? {
        if let p = peer { return p }
        if let p = MrDrop.lastPeer { return p }
        if let p = discovery.peers.first { return p }
        return nil
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
        guard let p = currentPeer() else { message = "先に送り先の PC を選んでください。"; return }
        Task {
            for item in items {
                // 🔴 iOS が書き出し終えるまで `loadTransferable` は返ってこない。
                //    1時間の動画なら数分、iCloud にしか無ければダウンロードから始まる。
                //    先に行を出しておかないと「押したのに無反応」に見える。
                let ticket = uploader.beginStaging("取り込んでいます…")
                MrDrop.log("アプリ", "取り込み開始 types=\(item.supportedContentTypes.map(\.identifier).joined(separator: ","))")
                // 🔴 項目が名乗る型に合わせて受け口を選ぶ。ここを固定にすると変換されて画質が落ちる。
                let types = item.supportedContentTypes
                let outcome: Result<(url: URL, name: String)?, Error>
                if types.contains(.mpeg4Movie) {
                    outcome = await load(item, as: PickedMP4.self, ticket: ticket)
                } else if types.contains(where: { $0.conforms(to: .movie) }) {
                    outcome = await load(item, as: PickedMOV.self, ticket: ticket)
                } else {
                    outcome = await load(item, as: PickedPhoto.self, ticket: ticket)
                }
                do {
                    if let f = try outcome.get() {
                        uploader.endStaging(ticket)
                        let size = (try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size] as? Int64) ?? nil
                        MrDrop.log("アプリ", "取り込み成功 \(f.name) \(size ?? -1) バイト")
                        uploader.send(fileURL: f.url, filename: f.name, to: p, modified: nil, whileWatching: true)
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
        guard let p = currentPeer() else { message = "先に送り先の PC を選んでください。"; return }
        for u in urls {
            // 「ファイル」アプリのものは許可を取ってから読む
            let needsStop = u.startAccessingSecurityScopedResource()
            defer { if needsStop { u.stopAccessingSecurityScopedResource() } }
            do {
                let dir = try MrDrop.stagingDirectory()
                let dest = dir.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent)
                try FileManager.default.copyItem(at: u, to: dest)
                uploader.send(fileURL: dest, filename: u.lastPathComponent, to: p, modified: nil, whileWatching: true)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
