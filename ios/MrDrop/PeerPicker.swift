import SwiftUI

/// いま選んでいる PC と合言葉。**「送る」と「受け取る」で1つを分け合う。**
///
/// 🔴 タブごとに別々に持たせないこと。「送るタブでは選べているのに、
///    受け取るタブでは選ばれていない」という、いちばん理解されない状態になる。
@MainActor
final class Connection: ObservableObject {

    @Published var peer: MrDrop.Peer? = MrDrop.lastPeer {
        didSet { MrDrop.lastPeer = peer }
    }

    @Published var token: String = MrDrop.token {
        didSet { MrDrop.token = token.trimmingCharacters(in: .whitespaces) }
    }

    /// 手で入れる住所まわり
    @Published var manualAddress = ""
    @Published var manualBusy = false
    @Published var showManual = false

    /// 探し始めて数秒たっても見つからない
    @Published var noPeerHint = false

    /// 画面から「いまの送り先」を聞かれたときの答え。
    func current(_ discovery: Discovery) -> MrDrop.Peer? {
        peer ?? MrDrop.lastPeer ?? discovery.peers.first
    }

    /// 手で入れた住所を確かめてから送り先にする。
    /// `http://192.168.1.20:48630` でも `192.168.1.20:48630` でも `my-pc.local` でも通す。
    /// - Returns: 駄目だったときの言い分（成功なら nil）
    func connectManually() async -> String? {
        var s = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(of: "/") { s = String(s[..<i]) }
        var host = s
        var port = 48630
        if let i = s.lastIndex(of: ":"), let p = Int(s[s.index(after: i)...]) {
            host = String(s[..<i])
            port = p
        }
        guard !host.isEmpty else { return "住所の形が違います。例: 192.168.1.20:48630" }

        let candidate = MrDrop.Peer(name: host, host: host, port: port)
        guard let req = MrDrop.infoRequest(to: candidate) else {
            return "住所の形が違います。例: 192.168.1.20:48630"
        }
        manualBusy = true
        defer { manualBusy = false }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard info?["app"] as? String == "mrdrop" else {
                return "その住所に Mr.Drop はいませんでした。"
            }
            peer = MrDrop.Peer(name: (info?["name"] as? String) ?? host, host: host, port: port)
            manualAddress = ""
            showManual = false
            MrDrop.log("アプリ", "手入力で送り先を決めた \(host):\(port)")
            return nil
        } catch {
            MrDrop.log("アプリ", "手入力の住所につながらない \(host):\(port) \(MrDrop.describe(error))")
            return "つながりませんでした。PC で Mr.Drop が動いているか、同じ Wi-Fi かを確かめてください。"
        }
    }
}

/// PC を選ぶところ。**「送る」と「受け取る」の両方に同じ物を出す。**
struct PeerSection: View {
    @EnvironmentObject private var conn: Connection
    @ObservedObject var discovery: Discovery

    /// 見出しと説明は、送る側と受け取る側で言い方を変える
    let title: String
    let footer: String
    /// 何か言うことがあったときに画面へ返す
    @Binding var message: String?

    /// 手で入れた PC（自動発見の一覧に無いもの）。前回の PC が今いない場合もここに来る
    private var manualPeer: MrDrop.Peer? {
        guard let p = conn.peer, !discovery.peers.contains(p) else { return nil }
        return p
    }
    private var listedPeers: [MrDrop.Peer] { discovery.peers + (manualPeer.map { [$0] } ?? []) }

    var body: some View {
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
                    conn.noPeerHint = true
                }
                if conn.noPeerHint { noPeerGuide }   // 前回の PC が残っていても、自動で見つからない限り出す
            }
            ForEach(listedPeers) { p in
                Button {
                    conn.peer = p
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text("\(p.host):\(String(p.port))" +
                                 (discovery.peers.contains(p) ? "" : "　自動発見では見つかっていません"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if conn.peer == p { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    // 🔴 これが無いと当たり判定が文字の上だけになり、
                    //    行の余白を押しても選べない（実機で必ず戸惑う）
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            manualEntry
        } header: {
            Text(title)
        } footer: {
            // 🔴 ここは最初から見えている。noPeerGuide は6秒待たないと出ないので、
            //    「PC 側にも要る」ことは、待たずに分かるようにしておく。
            Text(footer)
        }
    }

    /// PC が見つからないときの案内。
    /// 🔴 いちばん大事な画面。ここで詰まると、入れた人は何もできずにアプリを消す。
    /// **「PC 版が要る」だけでなく「どこで手に入るか」まで書くこと。**
    /// 買わせるためではなく、使えないまま放置しないため。「買う」ボタンは置かない（文字で書く）。
    private var noPeerGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("見つからないときは").font(.subheadline.bold()).foregroundStyle(.primary)
            Text("• 受け取る側のパソコンで **Mr.Drop（PC 版）** が動いている必要があります")
            Text("　PC 版（Windows / Mac）は **yas-tools.booth.pm** で手に入ります")
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
            if conn.showManual || (conn.noPeerHint && discovery.peers.isEmpty) {
                HStack {
                    TextField("例: 192.168.1.20:48630", text: $conn.manualAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { message = await conn.connectManually() } }
                    Button(conn.manualBusy ? "確かめています…" : "つなぐ") {
                        Task { message = await conn.connectManually() }
                    }
                    .disabled(conn.manualBusy || conn.manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button { conn.showManual = true } label: { Label("住所を手で入れる…", systemImage: "keyboard") }
            }
        }
    }
}

/// 合言葉。**両方のタブに出す**（受け取りも同じ合言葉で通る）。
struct TokenSection: View {
    @EnvironmentObject private var conn: Connection

    var body: some View {
        Section {
            TextField("合言葉（PC 側で決めたもの）", text: $conn.token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("合言葉")
        } footer: {
            Text("PC 側の Mr.Drop で合言葉を決めたときだけ入れます。空のままなら合言葉なしでやりとりします。")
        }
    }
}
