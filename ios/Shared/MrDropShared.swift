import Foundation
import UniformTypeIdentifiers

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

    /// 「PC で扱いやすい形式にして送る」。写真は JPEG、動画は MP4（容器の詰め替えのみ・無劣化）。
    /// 既定は **入**（本人の用途が Windows と YouTube のため）。
    /// 🔴 `bool(forKey:)` は未設定でも false を返すので、既定を入にするには
    ///    「まだ一度も触っていないか」を object(forKey:) で見る必要がある。
    static var convertForPC: Bool {
        get {
            guard let d = defaults else { return true }
            return d.object(forKey: "convertForPC") == nil ? true : d.bool(forKey: "convertForPC")
        }
        set { defaults?.set(newValue, forKey: "convertForPC") }
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

    // MARK: - 端末の中の記録
    //
    // 画面の赤い字だけでは「unknown error」しか分からないので、本体と拡張の両方から
    // App Group の中の1本のファイルに書き足す。Mac からはこれで読み出す:
    //   xcrun devicectl device copy from --device <UDID> \
    //     --domain-type appGroupDataContainer --domain-identifier group.jp.yastools.mrdrop \
    //     --source mrdrop.log --destination .

    static func log(_ who: String, _ text: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let d = "\(stamp) [\(who)] \(text)\n".data(using: .utf8) else { return }

        // 🔴 App Group の中身は devicectl から見えないことがある（実測）ので、
        //    自分の Documents にも同じものを書く。取り出せるのはこちら。
        var targets: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            targets.append(docs.appendingPathComponent("mrdrop.log"))
        }
        if let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            targets.append(base.appendingPathComponent("mrdrop.log"))
        }
        for f in targets {
            if let h = try? FileHandle(forWritingTo: f) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: d)
                try? h.close()
            } else {
                try? d.write(to: f)
            }
        }
    }

    /// 置き去りになった一時ファイルを片付ける。
    /// 🔴 取り込みを途中で止める（アプリを閉じる）と、App Group の中に数GBが残る。
    ///    溜まると端末の空きを食い、iCloud からのダウンロードすら止まる。
    static func sweepStaging(olderThan seconds: TimeInterval = 3600) {
        guard let dir = try? stagingDirectory(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        var freed: Int64 = 0
        var count = 0
        for n in names {
            let f = dir.appendingPathComponent(n)
            guard let a = try? FileManager.default.attributesOfItem(atPath: f.path),
                  let m = a[.modificationDate] as? Date, -m.timeIntervalSinceNow > seconds else { continue }
            freed += (a[.size] as? Int64) ?? 0
            try? FileManager.default.removeItem(at: f)
            count += 1
        }
        if count > 0 { log("掃除", "置き去りの一時ファイル \(count) 個・\(freed / 1_048_576) MB を消しました") }
        else { log("掃除", "置き去りはありません（\(names.count) 個が処理中）") }
    }

    /// 記録を、アプリ自身の Documents にも写す。
    /// 🔴 App Group の中身は `devicectl` から見えないことがある（実測）。Documents なら確実に取り出せる:
    ///   xcrun devicectl device copy from --device <UDID> \
    ///     --domain-type appDataContainer --domain-identifier jp.yastools.mrdrop \
    ///     --source Documents/mrdrop.log --destination .
    static func exportLog() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        // 共有拡張が書いた分を、取り出せる場所へ足す
        let from = base.appendingPathComponent("mrdrop.log")
        let to = docs.appendingPathComponent("拡張の記録.log")
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: from, to: to)
    }

    /// 🔴 `localizedDescription` は「unknown error」としか言わないことが多い。
    ///    領域・番号・内側のエラーまで出さないと原因にたどり着けない。
    static func describe(_ error: Error) -> String {
        let e = error as NSError
        var s = "\(e.domain) code=\(e.code) 「\(e.localizedDescription)」"
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError {
            s += " ← 内側: \(u.domain) code=\(u.code) 「\(u.localizedDescription)」"
        }
        let keys = e.userInfo.keys.filter { $0 != NSUnderlyingErrorKey }
        if !keys.isEmpty { s += " userInfo=[\(keys.joined(separator: ", "))]" }
        return s
    }

    /// その型は「Windows で扱いにくい HEIC / HEIF」か。
    /// 🔴 変換するのはこれだけ。PNG（スクリーンショット）は Windows でも困らないし、
    ///    JPEG にすると文字がにじむ。すでに JPEG のものも触らない。
    static func isHEIF(_ identifier: String) -> Bool {
        guard let t = UTType(identifier) else { return false }
        if let heif = UTType("public.heif"), t.conforms(to: heif) { return true }
        return t.conforms(to: .heic)
    }

    /// 拡張子を小文字に揃える。
    /// 🔴 写真アプリは元のファイル名を大文字で持っている（`IMG_0001.HEIC`）が、
    ///    アプリ経由だと iOS が作り直すので小文字になる。同じ1枚が2つの名前で
    ///    PC に並ぶのを防ぐため、送る直前にここで揃える。
    static func tidyName(_ name: String) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty else { return name }
        return ns.deletingPathExtension + "." + ext.lowercased()
    }

    // MARK: - 送るための組み立て

    static func uploadRequest(to peer: Peer, filename: String, modified: Date?) -> URLRequest? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"

        // 🔴 IPv6 は角括弧で囲まないと URL にならない（`http://fe80::1:48630` は解釈できない）。
        //    Bonjour の解決先が IPv6 になることは普通にあるので、ここで必ず包む。
        var host = peer.host
        if host.contains(":") && !host.hasPrefix("[") { host = "[\(host)]" }
        guard let url = URL(string: "http://\(host):\(peer.port)/put/\(encoded)") else { return nil }

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
