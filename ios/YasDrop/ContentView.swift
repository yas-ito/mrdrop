import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 写真ピッカーから「元のファイルのまま」受け取るための入れ物。
/// 🔴 Data で受け取ると HEIC が JPEG に落とされたり、動画でメモリが尽きたりする。
///    ファイルの場所として受け取ること。
struct PickedFile: Transferable {
    let url: URL
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .item) { f in
            SentTransferredFile(f.url)
        } importing: { received in
            let dir = try YasDrop.stagingDirectory()
            let dest = dir.appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedFile(url: dest, name: received.file.lastPathComponent)
        }
    }
}

struct ContentView: View {
    @StateObject private var discovery = Discovery()
    @StateObject private var uploader = Uploader(identifier: YasDrop.sessionIDApp)

    @State private var peer: YasDrop.Peer? = YasDrop.lastPeer
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                peerSection
                sendSection
                if !uploader.jobs.isEmpty { jobsSection }
            }
            .navigationTitle("YasDrop")
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
                    YasDrop.lastPeer = p
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
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("送り先の PC")
        } footer: {
            Text("見つからないときは、PC で YasDrop が動いているか、同じ Wi-Fi につながっているかを確かめてください。")
        }
    }

    private var sendSection: some View {
        Section("送る") {
            PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos])) {
                Label("写真・動画を選ぶ", systemImage: "photo.on.rectangle")
            }
            Button {
                showFiles = true
            } label: {
                Label("ファイルを選ぶ", systemImage: "folder")
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

    private var jobsSection: some View {
        Section("様子") {
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
        }
    }

    private func currentPeer() -> YasDrop.Peer? {
        if let p = peer { return p }
        if let p = YasDrop.lastPeer { return p }
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
                let dir = try YasDrop.stagingDirectory()
                let dest = dir.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent)
                try FileManager.default.copyItem(at: u, to: dest)
                uploader.send(fileURL: dest, filename: u.lastPathComponent, to: p, modified: nil)
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
