import Foundation
import Network

/// 同じ Wi-Fi にいる MrDrop の PC を、設定ゼロで見つける。
///
/// 🔴 ここが動かないときに疑う順番:
///   1. Info.plist の NSBonjourServices に "_mrdrop._tcp" があるか
///      （無いと権限ダイアログすら出ずに、ただ何も見つからない。いちばん多い罠）
///   2. NSLocalNetworkUsageDescription があるか
///   3. iPhone と PC が同じ Wi-Fi か（PC が有線でも、同じルータなら届く）
///   4. PC 側で `node server/mrdrop.js --browse` が自分を見つけられるか
@MainActor
final class Discovery: ObservableObject {

    @Published private(set) var peers: [MrDrop.Peer] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?
    private var resolving = Set<String>()

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false

        let b = NWBrowser(for: .bonjourWithTXTRecord(type: MrDrop.serviceType, domain: nil), using: params)

        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isSearching = true
                case .failed, .cancelled: self?.isSearching = false
                default: break
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }

        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        // 消えた PC を一覧から落とす
        let liveNames = Set(results.compactMap { r -> String? in
            if case let .service(name, _, _, _) = r.endpoint { return name }
            return nil
        })
        peers.removeAll { !liveNames.contains($0.name) }

        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            if peers.contains(where: { $0.name == name }) { continue }
            if resolving.contains(name) { continue }
            resolving.insert(name)
            resolve(r.endpoint, name: name)
        }
    }

    /// Bonjour の結果は名前だけ。実際の住所は繋いでみないと分からないので、
    /// 一度だけ接続して remoteEndpoint から IP と番号を取り出す。
    private func resolve(_ endpoint: NWEndpoint, name: String) {
        let conn = NWConnection(to: endpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                var found: MrDrop.Peer?
                if let path = conn.currentPath, case let .hostPort(host, port) = path.remoteEndpoint {
                    var h = "\(host)"
                    // fe80::1%en0 の %en0 を落とす。付いたままだと URL に使えない
                    if let i = h.firstIndex(of: "%") { h = String(h[h.startIndex..<i]) }
                    found = MrDrop.Peer(name: name, host: h, port: Int(port.rawValue))
                }
                conn.cancel()
                Task { @MainActor in
                    self?.resolving.remove(name)
                    guard let p = found else { return }
                    if !(self?.peers.contains(p) ?? true) { self?.peers.append(p) }
                    // 1台しかいないなら黙って選んでおく（毎回選ばせない）
                    if MrDrop.lastPeer == nil { MrDrop.lastPeer = p }
                }
            case .failed, .cancelled:
                conn.cancel()
                Task { @MainActor in self?.resolving.remove(name) }
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }
}
