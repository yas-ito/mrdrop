import Foundation
import Photos

/// PC の送信箱から iPhone へ受け取る。`Uploader` の裏返し。
///
/// 🔴 必ず `downloadTask` を使う（`data(for:)` ではなく）。
///    本文をメモリに読むと、数GBの動画を受け取った瞬間に落ちる。
///    downloadTask なら iOS が勝手にディスクへ流してくれる。
///
/// 🔴 「落とせた」と「保存できた」は別。落ちた先は iOS の一時置き場で、
///    写真アプリかファイルアプリへ入れて初めて買った人の手に渡る。
///    どちらも失敗しうるので、行ごとに「どこに入ったか」まで出す。
@MainActor
final class Downloader: NSObject, ObservableObject {

    enum Destination: Equatable {
        case photos
        /// ファイルアプリに出る名前と、「写真アプリに断られて回ってきた」かどうか。
        /// 🔴 断られたことを黙っていると、動画を受け取った人が「写真」を探し続ける。
        ///    実測: 1.0GB は入ったが、1.4GB と 2.3GB は `PHPhotosErrorDomain 3302` で断られた
        ///    （Mac のシミュレータ・2026-09-14。実機での境目は未確認）。
        case files(String, fallback: Bool)

        var label: String {
            switch self {
            case .photos:
                return "「写真」アプリに入れました"
            case .files(let n, false):
                return "ファイルアプリ → Mr.Drop → 受信 → \(n)"
            case .files(let n, true):
                return "「写真」アプリが受け取らなかったので、ファイルアプリ → Mr.Drop → 受信 → \(n) に入れました（そのまま開けます）"
            }
        }
    }

    struct Job: Identifiable, Equatable {
        let id: Int             // URLSessionTask の taskIdentifier
        var fileID: String      // MrDrop.RemoteFile.id（一覧の行と結びつける）
        var name: String
        var got: Int64 = 0
        var total: Int64 = 0
        var finished = false
        var error: String?
        var saved: Destination?
        /// 落とし終えて、写真アプリ／ファイルアプリへ入れている最中
        var saving = false
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var files: [MrDrop.RemoteFile] = []
    @Published private(set) var listing = false
    @Published private(set) var listedOnce = false
    @Published var listError: String?
    @Published private(set) var receivedIDs: Set<String> = MrDrop.receivedIDs

    /// 画面を開いている間の転送。上りと同じ理由でこちらのほうが速い
    /// （背面用は OS が速度を抑える。`Uploader` のコメント参照）。
    private var live: URLSession!

    /// 一覧を取るだけの軽いセッション。転送用と分けておくと、
    /// 大きい動画を受けている最中でも一覧の取り直しが待たされない。
    private let probe: URLSession

    /// taskIdentifier → 何を落としているか。
    /// 🔴 デリゲートは主スレッド以外から来るので、`@MainActor` の外に置く。
    ///    画面の状態と一緒にしまうと、どこからでも触れないか、毎回ホップが要るかの
    ///    どちらかになる（Swift 6 ではコンパイルも通らない）。
    private final class Box: @unchecked Sendable {
        struct Pending { let file: MrDrop.RemoteFile; let started: Date }
        private var map: [Int: Pending] = [:]
        private let lock = NSLock()
        func put(_ id: Int, _ p: Pending) { lock.lock(); map[id] = p; lock.unlock() }
        func take(_ id: Int) -> Pending? { lock.lock(); defer { lock.unlock() }; return map.removeValue(forKey: id) }
    }
    nonisolated private let box = Box()

    override init() {
        let p = URLSessionConfiguration.ephemeral
        p.allowsCellularAccess = false          // LAN 専用
        p.timeoutIntervalForRequest = 10
        probe = URLSession(configuration: p)
        super.init()

        let f = URLSessionConfiguration.default
        f.allowsCellularAccess = false          // LAN 専用。モバイル通信では意味がない
        f.waitsForConnectivity = true
        f.timeoutIntervalForRequest = 3600
        f.timeoutIntervalForResource = 24 * 3600
        live = URLSession(configuration: f, delegate: self, delegateQueue: nil)
    }

    // MARK: - 送信箱の一覧

    /// PC に「いま何が置いてあるか」を聞く。
    /// 🔴 空っぽと「つながらない」は別物として出す。まぜると、PC が落ちているのに
    ///    「送信箱は空です」と言ってしまう（今回の苦情と同じ種類の事故）。
    func refresh(from peer: MrDrop.Peer?) async {
        guard let peer, let req = MrDrop.listRequest(to: peer) else {
            files = []
            listError = nil
            return
        }
        listing = true
        defer { listing = false; listedOnce = true }
        do {
            let (data, res) = try await probe.data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else {
                listError = code == 401
                    ? "合言葉が違います。「送る」タブで PC 側と同じ合言葉を入れてください。"
                    : "PC が一覧を返しませんでした（\(code)）"
                return
            }
            struct Reply: Decodable { let files: [MrDrop.RemoteFile] }
            let list = try JSONDecoder().decode(Reply.self, from: data).files
            files = list.sorted { $0.mtime > $1.mtime }
            listError = nil
            MrDrop.log("受信", "一覧 \(list.count) 件 ← \(peer.host):\(peer.port)")
        } catch {
            files = []
            listError = "PC につながりませんでした。Mr.Drop が動いているか、同じ Wi-Fi かを確かめてください。"
            MrDrop.log("受信", "🔴 一覧に失敗 \(MrDrop.describe(error))")
        }
    }

    // MARK: - 受け取る

    /// すでに落とし中か、この画面で落とし終えたもの
    func isWorking(_ file: MrDrop.RemoteFile) -> Bool {
        jobs.contains { $0.fileID == file.id && !$0.finished }
    }

    func fetch(_ file: MrDrop.RemoteFile, from peer: MrDrop.Peer) {
        guard !isWorking(file) else { return }
        guard let req = MrDrop.downloadRequest(from: peer, name: file.name) else {
            MrDrop.log("受信", "🔴 住所を組み立てられない \(file.name)")
            return
        }
        let task = live.downloadTask(with: req)
        box.put(task.taskIdentifier, Box.Pending(file: file, started: Date()))
        jobs.insert(Job(id: task.taskIdentifier, fileID: file.id, name: file.name, total: file.size), at: 0)
        MrDrop.log("受信", "開始 \(file.name) \(file.size) バイト ← \(peer.host):\(peer.port)")
        task.resume()
    }

    /// まだ受け取っていないものを全部。
    func fetchAll(_ list: [MrDrop.RemoteFile], from peer: MrDrop.Peer) {
        for f in list where !receivedIDs.contains(f.id) && !isWorking(f) {
            fetch(f, from: peer)
        }
    }

    func clearFinished() {
        jobs.removeAll { $0.finished }
    }

    /// 「受け取り済み」の印を消す（もう一度落としたいとき）。
    func forget(_ file: MrDrop.RemoteFile) {
        MrDrop.forgetReceived(file.id)
        receivedIDs = MrDrop.receivedIDs
        jobs.removeAll { $0.fileID == file.id }
    }

    // MARK: - 保存

    private func update(_ id: Int, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }

    /// 写真アプリへ入れる。
    /// 🔴 `shouldMoveFile = true` にする。コピーだと数GBの動画で空き容量を二重に食う。
    /// 🔴 許可は `.addOnly`（入れるだけ）。写真を読む許可は要らないし、求めるべきでもない。
    ///
    /// - Parameter when: 中に日付が**書いていないとき**だけ渡す。
    ///   🔴 EXIF や動画のメタデータがあるなら、写真アプリはそちらから正しく読む。
    ///      こちらから `creationDate` を入れると、その正しい日付を上書きしてしまう。
    private func saveToPhotos(_ url: URL, name: String, kind: MrDrop.PhotoKind, when: Date?) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "MrDrop", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "「写真」への追加が許可されていません（設定 › Mr.Drop › 写真）"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            if let when { req.creationDate = when }
            let opts = PHAssetResourceCreationOptions()
            opts.originalFilename = name
            opts.shouldMoveFile = true
            req.addResource(with: kind == .video ? .video : .photo, fileURL: url, options: opts)
        }
    }

    /// ファイルアプリへ置く。上書きはしない（`名前 (2)` にする）。
    private func saveToFiles(_ url: URL, name: String, when: Date?) throws -> String {
        let dir = try MrDrop.receivedDirectory()
        let fm = FileManager.default
        let final = MrDrop.uniqueName(name) { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
        let dest = dir.appendingPathComponent(final)
        try fm.moveItem(at: url, to: dest)
        FileDate.apply(when, to: dest)          // PC にあったときの日付に戻す
        return final
    }

    private func finish(_ id: Int, file: MrDrop.RemoteFile, staged: URL, seconds: Double, when: Date?) async {
        update(id) { $0.saving = true }

        let kind = MrDrop.receiveIntoPhotos ? MrDrop.photoKind(for: file.name) : nil
        var destination: Destination?
        var failure: String?

        // 🔴 中に日付が書いてあるなら、写真アプリにはそちらを読ませる（そのほうが正確）。
        //    書いていないものにだけ、PC で持っていた日付を付ける。
        let forPhotos = (await FileDate.embedded(in: staged)) == nil ? when : nil

        if let kind {
            do {
                try await saveToPhotos(staged, name: file.name, kind: kind, when: forPhotos)
                destination = .photos
            } catch {
                // 🔴 写真アプリに入らなかったら、黙って捨てない。ファイルアプリへ回す。
                //    ここで捨てると「受け取れたのに、どこにも無い」になる。
                MrDrop.log("受信", "⚠️ 写真アプリに入らず、ファイルアプリへ回します: \(MrDrop.describe(error))")
                if let saved = try? saveToFiles(staged, name: file.name, when: when) {
                    destination = .files(saved, fallback: true)
                } else {
                    failure = MrDrop.describe(error)
                }
            }
        } else {
            do {
                destination = .files(try saveToFiles(staged, name: file.name, when: when), fallback: false)
            } catch {
                failure = MrDrop.describe(error)
            }
        }

        try? FileManager.default.removeItem(at: staged)     // 写真へ移せていれば、もう無い

        update(id) { j in
            j.saving = false
            j.finished = true
            j.saved = destination
            j.error = failure
        }
        if destination != nil {
            MrDrop.markReceived(file.id)
            receivedIDs = MrDrop.receivedIDs
            let mbps = seconds > 0.2
                ? String(format: "%.1f MB/秒", Double(file.size) / seconds / 1_048_576) : "—"
            MrDrop.log("受信", "完了 \(file.name) \(file.size) バイト "
                       + String(format: "%.1f", seconds) + "秒 \(mbps) → "
                       + (destination == .photos ? "写真" : "ファイル"))
        } else {
            MrDrop.log("受信", "🔴 保存できず \(file.name) \(failure ?? "")")
        }
    }
}

extension Downloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            self.update(id) { j in
                j.got = totalBytesWritten
                if totalBytesExpectedToWrite > 0 { j.total = totalBytesExpectedToWrite }
            }
        }
    }

    /// 🔴 ここで渡される場所は、**このメソッドから戻った瞬間に消える**。
    ///    非同期の保存へ回す前に、必ず同期で自分の場所へ移すこと。
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0

        // 🔴 404 や 401 でも「ダウンロードは成功」になる（本文がエラー文になるだけ）。
        //    ここを見ないと、中身が「ありません」という8バイトのファイルを
        //    写真アプリに入れて「受け取りました」と言う。上りで一度やらかした型の事故。
        guard (200...299).contains(code) else {
            let body = (try? String(contentsOf: location, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _ = box.take(id)
            Task { @MainActor in
                self.update(id) { j in
                    j.finished = true
                    j.error = body.isEmpty ? "PC が渡してくれませんでした（\(code)）" : body
                }
                MrDrop.log("受信", "🔴 HTTP \(code) \(body)")
            }
            return
        }

        guard let info = box.take(id) else { return }

        // 一時置き場へ同期で退避する（App Group ではなく自分の tmp。写真へは move で渡す）
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + info.file.name)
        do {
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            let detail = MrDrop.describe(error)
            Task { @MainActor in
                self.update(id) { j in j.finished = true; j.error = detail }
                MrDrop.log("受信", "🔴 退避に失敗 \(detail)")
            }
            return
        }

        // 🔴 大きさが合わないものは保存しない。途中で切れた動画を写真アプリに入れない。
        let got = (try? FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? Int64) ?? nil
        if let got, info.file.size > 0, got != info.file.size {
            try? FileManager.default.removeItem(at: staged)
            Task { @MainActor in
                self.update(id) { j in
                    j.finished = true
                    j.error = "途中で切れました（\(got) / \(info.file.size) バイト）"
                }
                MrDrop.log("受信", "🔴 大きさが合わない \(info.file.name) \(got) / \(info.file.size)")
            }
            return
        }

        // 🔴 PC にあったときの日付。応答のヘッダが本命で、無ければ一覧の値を使う
        //    （一覧を取ってから落とすまでに差し替わっていることがあるので、ヘッダを先に見る）。
        let head = (downloadTask.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "X-MrDrop-Modified")
            .flatMap(Double.init)
        let when = head.map { Date(timeIntervalSince1970: $0 / 1000) } ?? info.file.modified

        let seconds = -info.started.timeIntervalSinceNow
        Task { @MainActor in
            await self.finish(id, file: info.file, staged: staged, seconds: seconds, when: when)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }     // 成功は didFinishDownloadingTo で片付けている
        let id = task.taskIdentifier
        let detail = MrDrop.describe(error)
        let short = error.localizedDescription
        _ = box.take(id)
        Task { @MainActor in
            self.update(id) { j in
                guard !j.finished else { return }
                j.finished = true
                j.error = short
            }
            MrDrop.log("受信", "🔴 失敗 \(detail)")
        }
    }
}
