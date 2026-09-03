import Foundation

/// ファイルを PC へ送る。
/// 🔴 必ず「ファイルから」送る（fromFile）。Data に読み込むと、共有拡張の
///    メモリ制限（およそ120MB）で動画を送った瞬間に落ちる。
final class Uploader: NSObject, ObservableObject {

    struct Job: Identifiable, Equatable {
        let id: Int
        var filename: String
        var sent: Int64 = 0
        var total: Int64 = 0
        var finished = false
        var error: String?
        /// まだ iOS から受け取っている最中（送信は始まっていない）
        var staging = false
    }

    @Published private(set) var jobs: [Job] = []

    /// 速さを出すための開始時刻（taskIdentifier ごと）
    private var started: [Int: Date] = [:]

    private var session: URLSession!
    /// 🔴 画面を開いている間だけ使う、普通のセッション。
    ///    バックグラウンド用は OS が速度を抑えるので、前面にいる間はこちらのほうが速い。
    ///    ただしアプリを閉じると止まるので、共有拡張は使わない（あちらは必ず background）。
    private var live: URLSession!
    /// 本体アプリが再起動されたときにシステムから渡される後始末の合図
    var backgroundCompletion: (() -> Void)?

    init(identifier: String) {
        super.init()
        let c = URLSessionConfiguration.background(withIdentifier: identifier)
        c.sharedContainerIdentifier = MrDrop.appGroup   // 🔴 これが無いと共有拡張から送れない
        c.isDiscretionary = false                        // すぐ送る（OS の都合で後回しにさせない）
        c.sessionSendsLaunchEvents = true
        c.allowsCellularAccess = false                   // LAN 専用。モバイル通信では意味がない
        c.waitsForConnectivity = true
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)

        let f = URLSessionConfiguration.default
        f.allowsCellularAccess = false          // LAN 専用
        f.waitsForConnectivity = true
        f.timeoutIntervalForRequest = 3600
        f.timeoutIntervalForResource = 24 * 3600
        live = URLSession(configuration: f, delegate: self, delegateQueue: nil)
    }

    // MARK: 取り込み中の表示
    //
    // 🔴 1時間の動画は、iOS が書き出すだけで数分かかる（iCloud にしか無ければ
    //    ダウンロードから始まる）。その間ずっと画面に何も出ないと、
    //    「押したのに無反応」に見えて同じものを何度も送ってしまう。
    //    だから**選んだ直後に行を出す**。

    private var stagingCounter = -1

    func beginStaging(_ name: String) -> Int {
        let id = stagingCounter
        stagingCounter -= 1
        let job = Job(id: id, filename: name, finished: false, staging: true)
        DispatchQueue.main.async { self.jobs.insert(job, at: 0) }
        return id
    }

    /// 取り込みの進み具合を見張る。iCloud にしか無い動画は、ここが
    /// ダウンロードの％になる（0% のまま動かないなら、まさにそれ）。
    private var watches: [Int: NSKeyValueObservation] = [:]

    func track(_ progress: Progress, for ticket: Int) {
        watches[ticket] = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] p, _ in
            let pct = Int(p.fractionCompleted * 100)
            self?.update(ticket) { j in j.filename = "取り込んでいます… \(pct)%" }
        }
    }

    private func stopWatching(_ id: Int) {
        watches[id]?.invalidate()
        watches[id] = nil
    }

    func endStaging(_ id: Int) {
        stopWatching(id)
        DispatchQueue.main.async { self.jobs.removeAll { $0.id == id } }
    }

    func failStaging(_ id: Int, _ message: String) {
        stopWatching(id)
        update(id) { j in
            j.staging = false
            j.finished = true
            j.error = message
        }
    }

    /// - Parameter fileURL: App Group の中に置いた実体。送り終えたら消える。
    @discardableResult
    /// - Parameter whileWatching: 画面を開いたまま送るなら true（速い普通のセッションを使う）。
    ///   共有拡張からは必ず false。アプリが消えても続くように background のままにする。
    func send(fileURL: URL, filename: String, to peer: MrDrop.Peer, modified: Date?,
              whileWatching: Bool = false) -> Bool {
        guard let req = MrDrop.uploadRequest(to: peer, filename: filename, modified: modified) else { return false }
        let task = (whileWatching ? live! : session!).uploadTask(with: req, fromFile: fileURL)
        task.taskDescription = fileURL.path              // 済んだら消すために覚えておく
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? nil
        MrDrop.log("転送", "開始 \(filename) \(size ?? -1) バイト → \(peer.host):\(peer.port) 経路=\(whileWatching ? "前面" : "背面")")
        let job = Job(id: task.taskIdentifier, filename: filename, total: size ?? 0)
        DispatchQueue.main.async { self.jobs.insert(job, at: 0) }
        task.resume()
        return true
    }

    // DispatchQueue.main.async の中で使うので @escaping が要る
    private func update(_ id: Int, _ change: @escaping (inout Job) -> Void) {
        DispatchQueue.main.async {
            guard let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            change(&self.jobs[i])
        }
    }
}

extension Uploader: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        update(task.taskIdentifier) { j in
            j.sent = totalBytesSent
            if totalBytesExpectedToSend > 0 { j.total = totalBytesExpectedToSend }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let path = task.taskDescription {
            try? FileManager.default.removeItem(atPath: path)   // 一時ファイルを溜めない
        }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let name = task.originalRequest?.url?.lastPathComponent ?? "?"
        if let e = error {
            MrDrop.log("転送", "🔴 失敗 \(name) \(MrDrop.describe(e))")
        } else {
            let secs = -(started[task.taskIdentifier]?.timeIntervalSinceNow ?? 0)
            let mbps = secs > 0.2 ? String(format: "%.1f MB/秒", Double(task.countOfBytesSent) / secs / 1_048_576) : "—"
            MrDrop.log("転送", "終了 \(name) HTTP \(status) \(task.countOfBytesSent) バイト \(String(format: "%.1f", secs))秒 \(mbps)")
        }
        started[task.taskIdentifier] = nil
        update(task.taskIdentifier) { j in
            j.finished = true
            if let e = error {
                j.error = e.localizedDescription
            } else if !(200...299).contains(status) {
                j.error = "PC が受け取りませんでした（\(status)）"
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
