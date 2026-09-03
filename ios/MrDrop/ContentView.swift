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
    @StateObject private var discovery = Discovery()
    @StateObject private var uploader = Uploader(identifier: MrDrop.sessionIDApp)

    @State private var peer: MrDrop.Peer? = MrDrop.lastPeer
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var message: String?
    @State private var convertForPC = MrDrop.convertForPC
    @State private var token = MrDrop.token
    @State private var noPeerHint = false          // 探し始めて数秒たっても見つからない
    @State private var manualAddress = ""          // 手で入れる住所（192.168.1.20:48630）
    @State private var manualBusy = false
    @State private var showManual = false          // 「住所を手で入れる」を開いているか

    var body: some View {
        NavigationStack {
            List {
                // 🔴 結果をいちばん上に出す。Windows のブラウザ画面では
                //    「送れているのに送れたことが伝わらず、同じ写真を4回送った」事故が起きた
                if !uploader.jobs.isEmpty { jobsSection }
                peerSection
                sendSection
                formatSection
                tokenSection
            }
            .navigationTitle("Mr.Drop")
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .alert("お知らせ", isPresented: .constant(message != nil)) {
                Button("わかりました") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    /// 手で入れた PC（自動発見の一覧に無いもの）。前回の PC が今いない場合もここに来る
    private var manualPeer: MrDrop.Peer? {
        guard let p = peer, !discovery.peers.contains(p) else { return nil }
        return p
    }
    private var listedPeers: [MrDrop.Peer] { discovery.peers + (manualPeer.map { [$0] } ?? []) }

    private var peerSection: some View {
        Section {
            if discovery.peers.isEmpty {
                HStack {
                    ProgressView()
                    Text("同じ Wi-Fi の PC を探しています…").foregroundStyle(.secondary)
                }
                // 🔴 黙って探し続けるだけにしない。受け取る側の PC が無い人（審査官もそう）には
                //    「何も起きないアプリ」に見える。数秒で理由と手立てを出す
                .task {
                    try? await Task.sleep(for: .seconds(6))
                    noPeerHint = true
                }
                if noPeerHint { noPeerGuide }      // 前回の PC が残っていても、自動で見つからない限り出す
            }
            ForEach(listedPeers) { p in
                Button {
                    peer = p
                    MrDrop.lastPeer = p
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text("\(p.host):\(String(p.port))" +
                                 (discovery.peers.contains(p) ? "" : "　自動発見では見つかっていません"))
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
            manualEntry
        } header: {
            Text("送り先の PC")
        } footer: {
            Text("見つからないときは、PC で Mr.Drop が動いているか、同じ Wi-Fi につながっているかを確かめてください。")
        }
    }

    /// PC が見つからないときの案内。
    /// 🔴 アプリの中に「PC 版を買う」導線は置かない（App Store の 3.1.1 に触れる）。事実だけ言う。
    private var noPeerGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("見つからないときは").font(.subheadline.bold()).foregroundStyle(.primary)
            Text("• 受け取る側のパソコンで **Mr.Drop（PC 版）** が動いている必要があります")
            Text("• iPhone とパソコンが同じ Wi-Fi につながっているか確かめてください")
            Text("• iPhone の「設定 › プライバシーとセキュリティ › ローカルネットワーク」で Mr.Drop が許可されているか")
            Text("• それでも出ないときは、PC の画面に出ている住所を下に入れてください")
        }
        .font(.footnote).foregroundStyle(.secondary)
    }

    /// 住所を手で入れる口。いつでも使える（見つかった PC が違う・別のサブネットにいる、など）。
    /// 見つからないまま数秒たったら自動で開く。
    private var manualEntry: some View {
        Group {
            if showManual || (noPeerHint && discovery.peers.isEmpty) {
                HStack {
                    TextField("例: 192.168.1.20:48630", text: $manualAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await connectManually() } }
                    Button(manualBusy ? "確かめています…" : "つなぐ") { Task { await connectManually() } }
                        .disabled(manualBusy || manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button { showManual = true } label: { Label("住所を手で入れる…", systemImage: "keyboard") }
            }
        }
    }

    /// 手で入れた住所を確かめてから送り先にする。
    /// `http://192.168.1.20:48630` でも `192.168.1.20:48630` でも `my-pc.local` でも通す。
    private func connectManually() async {
        var s = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(of: "/") { s = String(s[..<i]) }
        var host = s
        var port = 48630
        if let i = s.lastIndex(of: ":"), let p = Int(s[s.index(after: i)...]) {
            host = String(s[..<i])
            port = p
        }
        guard !host.isEmpty, let url = URL(string: "http://\(host):\(port)/api/info") else {
            message = "住所の形が違います。例: 192.168.1.20:48630"
            return
        }
        manualBusy = true
        defer { manualBusy = false }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard info?["app"] as? String == "mrdrop" else {
                message = "その住所に Mr.Drop はいませんでした。"
                return
            }
            let p = MrDrop.Peer(name: (info?["name"] as? String) ?? host, host: host, port: port)
            peer = p
            MrDrop.lastPeer = p
            manualAddress = ""
            showManual = false
            MrDrop.log("アプリ", "手入力で送り先を決めた \(host):\(port)")
        } catch {
            MrDrop.log("アプリ", "手入力の住所につながらない \(host):\(port) \(MrDrop.describe(error))")
            message = "つながりませんでした。PC で Mr.Drop が動いているか、同じ Wi-Fi かを確かめてください。"
        }
    }

    private var tokenSection: some View {
        Section {
            TextField("合言葉（PC 側で決めたもの）", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: token) { _, v in MrDrop.token = v.trimmingCharacters(in: .whitespaces) }
        } header: {
            Text("合言葉")
        } footer: {
            Text("PC 側の Mr.Drop で合言葉を決めたときだけ入れます。空のままなら合言葉なしで送ります。")
        }
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

    private func currentPeer() -> MrDrop.Peer? {
        if let p = peer { return p }
        if let p = MrDrop.lastPeer { return p }
        if let p = discovery.peers.first { return p }
        return nil
    }

    /// `.mov` を **作り直さずに** `.mp4` へ詰め替える（パススルー）。画質は変わらず、数秒で終わる。
    /// 🔴 共有拡張ではやらない。メモリ 120MB の中で走らせると落ちる。
    private func remuxToMP4(_ url: URL) async -> URL? {
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
                        if convertForPC, isMovie, let mp4 = await remuxToMP4(f.url) {
                            f = (url: mp4, name: (f.name as NSString).deletingPathExtension + ".mp4")
                        }
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
