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
    }

    @Published private(set) var jobs: [Job] = []

    private var session: URLSession!
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
    }

    /// - Parameter fileURL: App Group の中に置いた実体。送り終えたら消える。
    @discardableResult
    func send(fileURL: URL, filename: String, to peer: MrDrop.Peer, modified: Date?) -> Bool {
        guard let req = MrDrop.uploadRequest(to: peer, filename: filename, modified: modified) else { return false }
        let task = session.uploadTask(with: req, fromFile: fileURL)
        task.taskDescription = fileURL.path              // 済んだら消すために覚えておく
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? nil
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
