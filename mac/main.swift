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
//   ・受信箱／合言葉／ログイン時起動の面倒を見る
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
    private var inboxFromServer: String?       // サーバーが実際に使っている受信箱
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
            } else if line.hasPrefix("受信箱") {
                inboxFromServer = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
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
        add(m, "受信箱を開く", #selector(openInbox), key: "o")
        add(m, "受信箱を変える…", #selector(chooseInbox))
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

    @objc private func openLog() {
        let p = logFile ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MrDrop/mrdrop.log").path
        guard FileManager.default.fileExists(atPath: p) else {
            alert("記録はまだありません", "サーバーがまだ一度も立ち上がっていません。"); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    /// 受信箱を選び直す。Premiere の素材フォルダにしておくのが自作の一番のうまみ。
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

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - 設定（config.json はサーバーが作る。ここでは変えたい所だけ書く）

    private var inbox: URL {
        if let p = inboxFromServer { return URL(fileURLWithPath: p) }
        if let p = readConfig()?["inbox"] as? String {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/受信箱")
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
