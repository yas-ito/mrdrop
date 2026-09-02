import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 写真ピッカーから「元のファイルのまま」受け取るための入れ物。
/// 🔴 Data で受け取ると HEIC が JPEG に落とされたり、動画でメモリが尽きたりする。
///    ファイルの場所として受け取ること。
struct PickedFile: Transferable {
    let url: URL
    let name: String

    /// 🔴 受け口を `.item` ひとつにすると、写真ピッカーからの取り込みが**必ず**
    ///    `CoreTransferable.TransferableSupportError error 0` で失敗する
    ///    （2026-09-02・iOS 26.5 で確認）。ピッカーが差し出す型に合わせて分けて用意する。
    ///    並び順が優先順位。画像・動画で受け、それ以外は `.item` で拾う。
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .heic)  { try stage($0) }
        FileRepresentation(importedContentType: .item)  { try stage($0) }
        FileRepresentation(importedContentType: .image) { try stage($0) }
        FileRepresentation(importedContentType: .movie) { try stage($0) }
    }

    /// 渡された場所はすぐ消えるので、App Group の中へ写しておく。
    private static func stage(_ received: ReceivedTransferredFile) throws -> PickedFile {
        let dir = try MrDrop.stagingDirectory()
        let dest = dir.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: received.file, to: dest)
        return PickedFile(url: dest, name: received.file.lastPathComponent)
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
    private var sending: Int { uploader.jobs.filter { !$0.finished }.count }
    private var sentOK:  Int { uploader.jobs.filter { $0.finished && $0.error == nil }.count }
    private var failed:  Int { uploader.jobs.filter { $0.error != nil }.count }

    private var jobsHeadline: String {
        if sending > 0 { return "送っています（あと \(sending) 件）" }
        if failed  > 0 { return "送れませんでした \(failed) 件 ／ 送りました \(sentOK) 件" }
        return "✅ \(sentOK) 件 送りました"
    }

    private var jobsSection: some View {
        Section {
            ForEach(uploader.jobs) { j in
                VStack(alignment: .leading, spacing: 4) {
                    Text(j.filename).lineLimit(1)
                    if let e = j.error {
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
                .foregroundStyle(sending > 0 ? Color.primary : (failed > 0 ? Color.red : Color.green))
        }
    }

    private func currentPeer() -> MrDrop.Peer? {
        if let p = peer { return p }
        if let p = MrDrop.lastPeer { return p }
        if let p = discovery.peers.first { return p }
        return nil
    }

    private func sendPhotos(_ items: [PhotosPickerItem]) {
        guard let p = currentPeer() else { message = "先に送り先の PC を選んでください。"; return }
        Task {
            for item in items {
                do {
                    if let f = try await item.loadTransferable(type: PickedFile.self) {
                        uploader.send(fileURL: f.url, filename: f.name, to: p, modified: nil)
                    }
                } catch {
                    message = error.localizedDescription
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
                uploader.send(fileURL: dest, filename: u.lastPathComponent, to: p, modified: nil)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
