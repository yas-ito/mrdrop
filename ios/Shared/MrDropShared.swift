import Foundation

/// 本体アプリと共有拡張の両方から使う土台。
/// 🔴 両方のターゲットに追加すること（片方だけだと共有シートから送れない）。
enum MrDrop {

    // MARK: - Xcode 側の設定と一致させる値

    /// App Groups の名前。Signing & Capabilities で同じ文字列を両ターゲットに入れる。
    static let appGroup = "group.jp.yastools.mrdrop"

    /// バックグラウンド転送の名札。本体と拡張で別にする決まり（同じにすると取り合いになる）。
    static let sessionIDApp = "jp.yastools.mrdrop.upload.app"
    static let sessionIDExtension = "jp.yastools.mrdrop.upload.ext"

    /// Info.plist の NSBonjourServices にも同じものを書く。書き忘れると PC が一切見つからない。
    static let serviceType = "_mrdrop._tcp"

    // MARK: - 見つけた PC

    struct Peer: Codable, Equatable, Identifiable {
        var name: String
        var host: String        // 🔴 名前(.local)ではなく解決済みの IP を入れる。拡張から確実に届くため
        var port: Int
        var id: String { "\(name)|\(host):\(port)" }
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// 最後に選んだ PC。共有拡張はこれを見て送り先を決める。
    static var lastPeer: Peer? {
        get {
            guard let d = defaults?.data(forKey: "lastPeer") else { return nil }
            return try? JSONDecoder().decode(Peer.self, from: d)
        }
        set {
            guard let d = defaults else { return }
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                d.set(data, forKey: "lastPeer")
            } else {
                d.removeObject(forKey: "lastPeer")
            }
        }
    }

    /// PC 側 config.json の token を入れたときだけ使う。空なら合言葉なし。
    static var token: String {
        get { defaults?.string(forKey: "token") ?? "" }
        set { defaults?.set(newValue, forKey: "token") }
    }

    /// 共有拡張が置いた一時ファイルの置き場（App Group の中）。
    static func stagingDirectory() throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw NSError(domain: "MrDrop", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group が設定されていません（\(appGroup)）"])
        }
        let dir = base.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 送るための組み立て

    static func uploadRequest(to peer: Peer, filename: String, modified: Date?) -> URLRequest? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"
        guard let url = URL(string: "http://\(peer.host):\(peer.port)/put/\(encoded)") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue(token, forHTTPHeaderField: "X-MrDrop-Token") }
        if let m = modified {
            req.setValue(String(Int64(m.timeIntervalSince1970 * 1000)), forHTTPHeaderField: "X-MrDrop-Modified")
        }
        req.timeoutInterval = 3600      // 大きい動画を Wi-Fi で送る。既定の60秒では足りない
        return req
    }
}
