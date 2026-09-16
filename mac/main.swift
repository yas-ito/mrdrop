// Mr.Drop（Mac 版・受け取る側）。メニューバーに常駐して、同梱の node で受信サーバーを回す。
//
// 🔴 買った人が「zip を開いてダブルクリックするだけ」で使えることが最優先。
//    Node を入れてもらう・ターミナルを開いてもらう、は全部やらせない。
//    そのために nodejs.org の公式バイナリ（自己完結）を Contents/MacOS/node に同梱する。
//    Homebrew の node は Homebrew のライブラリに依存していて他の Mac では動かない（実測）。
//
// 作るのは build/make-mac-app.sh（コンパイル → .app → 署名 → 公証 → zip）。
// 🔴 swiftc には -parse-as-library が要る。無いと @main が「トップレベルコード」扱いで通らない。
//
// サーバー本体は server/ の JS のまま（Windows と共通）。この Swift がやるのは
//   ・同梱の node で server/mrdrop.js を子プロセスとして回し、出力を読む
//   ・メニューバーに状態と住所を出す
//   ・受信先／合言葉／ログイン時起動の面倒を見る
// だけ。**転送のロジックをこちらに書かない**（両 OS で二重になる）。
import AppKit
import ServiceManagement

@main
final class App: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)     // Dock に出さない（Info.plist の LSUIElement と二重に）
        app.run()
    }

    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    private var item: NSStatusItem!
    private var server: Process?
    private var status = "起動中…"
    private var addresses: [String] = []       // サーバーが名乗った住所（http://…）
    private var inboxFromServer: String?       // サーバーが実際に使っている受信先
    private var outboxFromServer: String?      // サーバーが実際に使っている送信箱
    private var nameFromServer: String?        // iPhone の一覧に出ている名前（displayName）
    private var logFile: String?               // サーバーの記録ファイル
    private var received = 0
    private var restarts = 0
    private var portBusy = false
    private var pending = ""                   // 行の途中で切れた出力の残り
    private var stdinKeeper: Pipe?             // 握っている間だけ node が生きる

    // 設定の置き場所。アプリの中には書き込まない（署名が壊れる）
    private let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Mr.Drop", isDirectory: true)
    private var configFile: URL { support.appendingPathComponent("config.json") }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Mr.Drop")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        rebuildMenu()
        startServer()
    }

    func applicationWillTerminate(_ n: Notification) {
        stopServer()
    }

    // MARK: - サーバー

    /// 同梱の node。開発中だけ Homebrew の node に逃げる（配布物には必ず同梱されている）。
    private func nodeURL() -> URL? {
        let bundled = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("node").path
        for p in [bundled, "/opt/homebrew/bin/node", "/usr/local/bin/node"]
            where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    private func startServer() {
        guard let node = nodeURL() else {
            status = "🔴 node が入っていません（作り直してください）"
            rebuildMenu(); return
        }
        let script = Bundle.main.resourceURL!.appendingPathComponent("server/mrdrop.js")
        guard FileManager.default.fileExists(atPath: script.path) else {
            status = "🔴 server/mrdrop.js が入っていません（作り直してください）"
            rebuildMenu(); return
        }

        let p = Process()
        p.executableURL = node
        p.arguments = [script.path, "--config", configFile.path, "--follow-stdin"]
        p.currentDirectoryURL = support
        // 🔴 stdin をパイプで渡す。このアプリが強制終了されてもパイプが閉じるので、
        //    node は --follow-stdin で自分から終わる（番号を握ったまま残らない）
        let stdinPipe = Pipe()
        p.standardInput = stdinPipe
        stdinKeeper = stdinPipe
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }      // 終わった
            guard let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(s) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.serverEnded(proc) }
        }
        do {
            try p.run()
            server = p
            portBusy = false
            status = "待っています"
        } catch {
            status = "🔴 起動できませんでした: \(error.localizedDescription)"
        }
        rebuildMenu()
    }

    /// 自分で止める。server を先に nil にしておくと、terminationHandler が「自分で止めた分」と分かる。
    private func stopServer() {
        guard let p = server else { return }
        server = nil
        if p.isRunning {
            p.terminate()          // SIGTERM。サーバー側は mDNS の別れを打ってから終わる
            p.waitUntilExit()      // 最長 1.5 秒（サーバー側が見切る）
        }
        stdinKeeper = nil
    }

    private func restartServer() {
        stopServer()
        addresses.removeAll()
        inboxFromServer = nil
        outboxFromServer = nil
        pending = ""
        startServer()
    }

    /// 自分で止めたのでなければ、少し待って立ち上げ直す（launchd の KeepAlive 相当）。
    /// 🔴 番号が塞がっているときは追いかけない。即死 → 再起動の空回りになるだけ。
    private func serverEnded(_ proc: Process) {
        guard proc === server else { return }     // stopServer() で止めた分。何もしない
        server = nil
        if portBusy { rebuildMenu(); return }
        guard restarts < 5 else {
            status = "🔴 止まりました（「記録を開く」で理由が分かります）"
            rebuildMenu(); return
        }
        restarts += 1
        status = "止まりました。立ち上げ直します…"
        rebuildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.server == nil else { return }
            self.addresses.removeAll()
            self.pending = ""
            self.startServer()
        }
    }

    /// サーバーの出力から、見せたい情報だけ拾う。行の途中で切れて届くので、改行まで溜める。
    /// 🔴 出力の書式は server/mrdrop.js と lib/http.js のもの。そちらを変えたらここも合わせる。
    private func consume(_ text: String) {
        pending += text
        var lines = pending.components(separatedBy: "\n")
        pending = lines.removeLast()
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let r = line.range(of: #"https?://[^\s（）()]+"#, options: .regularExpression) {
                let url = String(line[r])
                if !addresses.contains(url) { addresses.append(url) }
            } else if line.hasPrefix("Mr.Drop ") {
                // "Mr.Drop 1.0.0   やすの Mac" ← 版のあとが、iPhone の一覧に出る名前
                let rest = String(line.dropFirst("Mr.Drop ".count))
                if let sp = rest.firstIndex(of: " ") {
                    nameFromServer = String(rest[sp...]).trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("受信先") {
                inboxFromServer = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("送信箱") {
                // 🔵 「🔵 送信箱を、デスクトップの…」の行は先頭が🔵なので、ここには来ない
                outboxFromServer = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("記録") {
                logFile = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.contains("すでに使われています") {
                portBusy = true
                status = "🔴 番号が塞がっています。別の Mr.Drop が動いていませんか"
            } else if line.hasPrefix("📥") {
                received += 1
                let body = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                let name = body.components(separatedBy: "  ").first ?? body
                status = "受け取りました（\(received) 件）: \(name)"
            } else if line.hasPrefix("自動発見"), line.contains("使えません") {
                status = "⚠️ 自動発見が使えません（Safari の住所からは使えます）"
            } else if line.hasPrefix("🔴") || line.hasPrefix("⚠️") {
                status = line
            }
        }
        rebuildMenu()
    }

    // MARK: - メニュー

    private func rebuildMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Mr.Drop \(version)：\(status)", action: nil, keyEquivalent: "")
        if !addresses.isEmpty {
            m.addItem(.separator())
            m.addItem(withTitle: "iPhone の Safari で開く住所（押すとコピー）", action: nil, keyEquivalent: "")
            for a in addresses.prefix(4) {
                let mi = NSMenuItem(title: "    " + a, action: #selector(copyAddress(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = a
                m.addItem(mi)
            }
        }
        m.addItem(.separator())
        add(m, "受信先を開く", #selector(openInbox), key: "o")
        add(m, "受信先を変える…", #selector(chooseInbox))
        // 🔵 Windows 版（雫の右クリック）と同じ2つ。送信箱がどこにあっても、ここから開ける。
        add(m, "送信箱を開く", #selector(openOutbox))
        add(m, "送信箱を移動する…", #selector(moveOutbox))
        add(m, "この PC の名前を変える…", #selector(setName))
        add(m, "合言葉を決める…", #selector(setToken))
        add(m, "記録を開く", #selector(openLog))
        let login = add(m, "ログイン時に起動", #selector(toggleLogin))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(.separator())
        add(m, "Mr.Drop を終了", #selector(quit), key: "q")
        item.menu = m
    }

    @discardableResult
    private func add(_ m: NSMenu, _ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        m.addItem(mi)
        return mi
    }

    @objc private func copyAddress(_ sender: NSMenuItem) {
        guard let a = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(a, forType: .string)
    }

    @objc private func openInbox() {
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        NSWorkspace.shared.open(inbox)
    }

    /// 送信箱（iPhone へ渡す物を置く場所）を開く。
    /// 🔵 ふだんはデスクトップの中だが、下の「移動する…」で動かせるので、ここが逃げ道になる。
    @objc private func openOutbox() {
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outbox)
    }

    /// 送信箱を、選んだ場所へ**フォルダごと**移す（中身も付いていく）。
    ///
    /// 🔴 選んでもらうのは**置き場所（親フォルダ）だけ**。送信箱の名前は変えない。
    ///    Windows 版は「好きなフォルダを送信箱にできる」作りで事故を起こしている
    ///    （買った人の持ち物が送信箱になり、次に変えたとき中身ごと運んだ。2026-09-15）。
    ///    **動かしてよいのは Mr.Drop が作った「Mr.Drop送信箱」だけ。**
    /// 🔵 中身・文言とも Windows 版（scripts/settings-windows.ps1 の -MoveOutbox）と揃えてある。
    ///    どちらかを直したら、もう片方も。
    @objc private func moveOutbox() {
        let fm = FileManager.default
        let now = outbox
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = now.deletingLastPathComponent()
        panel.message = "「\(Self.outboxName)」をどこに置きますか。フォルダごと、その中へ移します（中身もそのまま付いていきます）。"
        panel.prompt = "ここに置く"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        // 置ける場所かを先に試す。動かす途中で失敗するより、いま分かった方がよい。
        let probe = parent.appendingPathComponent(".mrdrop-write-test")
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: probe)
        } catch {
            alert("そこには置けません", "書き込めませんでした:\n\(parent.path)\n\n別の場所を選んでください。")
            return
        }

        if samePlace(parent, now.deletingLastPathComponent()) {
            alert("そこは、いまの置き場所と同じです", "何も変えていません。")
            return
        }

        let dest = parent.appendingPathComponent(Self.outboxName)
        var note = ""
        if !fm.fileExists(atPath: now.path) {
            // いまの送信箱が消えている（手で消した人がいる）。新しい場所に作るだけ。
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            note = "\n\n（前の送信箱が見つからなかったので、新しく作りました）"
        } else if now.lastPathComponent != Self.outboxName {
            // 🔴 前の送信箱が「あなたのフォルダ」。動かすと名前まで変えて運ぶことになる。触らない。
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            note = "\n\n前の送信箱はあなたのフォルダ（\(now.lastPathComponent)）でした。\n動かさず、そのまま残してあります:\n\(now.path)"
        } else if fm.fileExists(atPath: dest.path) {
            // 🔴 行き先に同じ名前の送信箱が先にあった。**上書きしない**で中身を足す。
            let r = mergeOutbox(now, dest)
            if r.left > 0 {
                note = "\n\n\(r.left) 個は同じ名前が先にあったので、前の場所に残してあります:\n\(now.path)"
            } else {
                note = "\n\n（行き先に同じ名前の送信箱があったので、中身を足しました）"
                // 空になったときだけ片付ける。中身が残っているフォルダは消さない。
                if let rest = try? fm.contentsOfDirectory(atPath: now.path), rest.isEmpty {
                    try? fm.removeItem(at: now)
                }
            }
        } else {
            // ふつうはこちら。**フォルダごと**動かす。
            do {
                try fm.moveItem(at: now, to: dest)
            } catch {
                alert("動かせませんでした", "\(now.path)\n→ \(dest.path)\n\n\(error.localizedDescription)")
                return
            }
        }

        writeConfig { $0["outbox"] = dest.path }
        restartServer()
        alert("送信箱を動かしました", dest.path + note)
    }

    /// 同じ場所か。シンボリックリンク（/tmp → /private/tmp など）を開いてから比べる。
    private func samePlace(_ a: URL, _ b: URL) -> Bool {
        let x = a.resolvingSymlinksInPath().standardizedFileURL.path
        let y = b.resolvingSymlinksInPath().standardizedFileURL.path
        return x.compare(y, options: [.caseInsensitive]) == .orderedSame
    }

    /// 中身を1つずつ移す。**同じ名前が先にあるものは動かさない**（上書きしない）。
    private func mergeOutbox(_ from: URL, _ to: URL) -> (moved: Int, left: Int) {
        let fm = FileManager.default
        var moved = 0, left = 0
        let items = (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
        for it in items {
            let dest = to.appendingPathComponent(it.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { left += 1; continue }
            do { try fm.moveItem(at: it, to: dest); moved += 1 } catch { left += 1 }
        }
        return (moved, left)
    }

    @objc private func openLog() {
        let p = logFile ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MrDrop/mrdrop.log").path
        guard FileManager.default.fileExists(atPath: p) else {
            alert("記録はまだありません", "サーバーがまだ一度も立ち上がっていません。"); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    /// 受信先を選び直す。Premiere の素材フォルダにしておくのが自作の一番のうまみ。
    @objc private func chooseInbox() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = inbox
        panel.message = "iPhone から届いたものを入れるフォルダ。Premiere の素材フォルダにしておくと、撮ったものがそのまま編集用に落ちます。"
        panel.prompt = "ここにする"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeConfig { $0["inbox"] = url.path }
        restartServer()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("ログイン時の起動を切り替えられませんでした", error.localizedDescription)
        }
        rebuildMenu()
    }

    /// 合言葉。同じ Wi-Fi の他人に受け取られたくないとき用。
    @objc private func setToken() {
        let a = NSAlert()
        a.messageText = "合言葉を決める"
        a.informativeText = "同じ Wi-Fi の他の人に受け取られたくないときに設定します。空にすると誰でも送れます。\niPhone 側にも同じ言葉を入れてください。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = (readConfig()?["token"] as? String) ?? ""
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.addButton(withTitle: "決定")
        a.addButton(withTitle: "やめる")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        writeConfig { $0["token"] = field.stringValue.trimmingCharacters(in: .whitespaces) }
        restartServer()
    }

    /// iPhone の「送り先」の一覧に出る名前。
    ///
    /// 🔴 既定はホスト名そのまま（`yasnoMac-mini.local`）で、人には読み分けられない。
    ///    本人の iPhone に `yas`（Windows 機）と `yasnoMac-mini-local`（この Mac）が並び、
    ///    `yas` を選んで送って「送ったのに Mac に無い＝消えた」と誤解した（2026-09-12 実機）。
    ///    動きは正常で、分からないのは名前の方だった。**名前を付けられる口が要る。**
    /// 🔵 中身・文言・置き場所とも Windows 版（scripts/settings-windows.ps1 の -ChooseName）と揃えてある。
    ///    どちらかを直したら、もう片方も。`server/` 側は何も要らない（cfg.name を既に見ている）。
    @objc private func setName() {
        let now = (readConfig()?["name"] as? String) ?? ""
        // 🔴 サーバー（node の os.hostname()）と Swift の ProcessInfo では大文字小文字が違うことがある
        //    （実測: os.hostname() は yasnoMac-mini.local ／ ProcessInfo は yasnomac-mini.local）。
        //    名前が空のときは「いま名乗っている名前」がそのまま戻り先なので、そちらを見せる。
        let pcName = (now.isEmpty ? nameFromServer : nil) ?? ProcessInfo.processInfo.hostName
        let a = NSAlert()
        a.messageText = "この PC の名前"
        a.informativeText = """
            iPhone の「送り先」の一覧に、この名前で出ます。
            うちの居間の Mac、編集用、などと付けておくと迷いません。
            空にすると、この Mac の名前（\(pcName)）に戻ります。
            """
        if let seen = nameFromServer, !seen.isEmpty, seen != pcName {
            a.informativeText += "\n\nいま出ている名前: \(seen)"
        }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = now
        field.placeholderString = pcName
        field.formatter = MaxLength(40)         // Windows の TextBox.MaxLength = 40 と同じ
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.addButton(withTitle: "決定")
        a.addButton(withTitle: "やめる")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let new = field.stringValue.trimmingCharacters(in: .whitespaces)
        // 🔴 制御文字は入れさせない（mDNS の名前にそのまま乗る）
        if new.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            alert("その名前は使えません", "見えない文字が入っています。"); return
        }
        guard new != now else { return }
        writeConfig { $0["name"] = new }
        restartServer()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - 設定（config.json はサーバーが作る。ここでは変えたい所だけ書く）

    private var inbox: URL {
        if let p = inboxFromServer { return URL(fileURLWithPath: p) }
        if let p = readConfig()?["inbox"] as? String {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// 送信箱の名前。**server/lib/config.js の OUTBOX と同じ**。あちこちに書き散らさない。
    private static let outboxName = "Mr.Drop送信箱"

    private var outbox: URL {
        if let p = outboxFromServer { return URL(fileURLWithPath: p) }
        if let p = readConfig()?["outbox"] as? String {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").appendingPathComponent(Self.outboxName)
    }

    private func readConfig() -> [String: Any]? {
        guard let d = try? Data(contentsOf: configFile) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// 無い項目はサーバー側の既定で埋まるので、変えたい所だけ書けばよい
    private func writeConfig(_ change: (inout [String: Any]) -> Void) {
        var o = readConfig() ?? [:]
        change(&o)
        guard let out = try? JSONSerialization.data(withJSONObject: o,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? out.write(to: configFile, options: .atomic)
    }

    private func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}


/// 決めた文字数より先を打たせない。NSTextField は maxLength を持っていないので Formatter で止める。
/// （mDNS の名前に乗るので、Windows 版の TextBox.MaxLength = 40 と揃えるために要る）
private final class MaxLength: Formatter {
    private let limit: Int
    init(_ limit: Int) { self.limit = limit; super.init() }
    required init?(coder: NSCoder) { fatalError("使わない") }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partial: String,
                                       newEditingString _: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription _: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return partial.count <= limit
    }
}
