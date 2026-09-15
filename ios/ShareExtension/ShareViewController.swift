import UIKit
import UniformTypeIdentifiers
import os

/// 写真アプリの共有ボタンから直接送るための拡張。ここが AirDrop と同じ導線になる。
///
/// 🔴 共有拡張のメモリ上限はおよそ 120MB しかない。
///    だから中身は**絶対に読まない**。ファイルを App Group へコピーして、
///    バックグラウンド転送に渡したら即座に手を引く。
final class ShareViewController: UIViewController {

    private let uploader = Uploader(identifier: MrDrop.sessionIDExtension)
    private let card = UIView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// 🔴 長い動画は詰め替えにも転送にも時間がかかる。**何も出ないと「固まった」に見える**
    ///    （2026-09-15 本人指摘）。進み具合と、閉じてよいことを必ず出す。
    private let bar = UIProgressView(progressViewStyle: .default)
    private let closeButton = UIButton(type: .system)
    private var ticker: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        Task { await process() }
    }

    private func buildUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        label.text = "送っています…"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false

        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true

        closeButton.setTitle("閉じる", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        card.addSubview(spinner)
        card.addSubview(label)
        card.addSubview(bar)
        card.addSubview(closeButton)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            card.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor, multiplier: 0.7),

            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),

            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 14),
            bar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            bar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),

            closeButton.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12),
            closeButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }

    /// 🔵 転送は**閉じても続く**（background セッションのため）。待たせない。
    @objc private func closeTapped() {
        ticker?.invalidate()
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// 詰め替え中・転送中の一行を書き換える。
    private func show(_ text: String, progress: Double?, canClose: Bool) {
        label.text = text
        bar.isHidden = progress == nil
        if let p = progress { bar.setProgress(Float(p), animated: true) }
        closeButton.isHidden = !canClose
    }

    private func process() async {
        guard let peer = MrDrop.lastPeer else {
            finish("先に Mr.Drop アプリを一度開いて、送り先の PC を選んでください。\n受け取るパソコン（Windows / Mac）にも Mr.Drop が要ります。",
                   ok: false)
            return
        }

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var count = 0
        var keptAsIs = 0
        MrDrop.log("拡張", "起動 項目数=\(items.count) 送り先=\(peer.name)")
        for item in items {
            for provider in item.attachments ?? [] {
                MrDrop.log("拡張", "受け取れる型=\(provider.registeredTypeIdentifiers.joined(separator: ",")) → 選んだ型=\(originalType(of: provider))")
                guard let picked = await copyToStaging(provider) else { continue }
                // 🔴 撮影日時は中（EXIF・動画のメタデータ）から読む。ここで渡さないと、
                //    PC に着いたファイルの日付が「送った日」になる。
                let taken = await FileDate.best(of: picked.file)
                var file = picked.file
                var name = picked.name
                if MrDrop.convertForPC, isMovie(file) {
                    // 🔴 ここはメモリ約120MB の中。詰め替えが収まるかを**測りながら**やる。
                    //    落ちるようなら、この節ごと外して「共有シートは変換しません」に戻すこと。
                    let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? nil
                    let before = Date()
                    MrDrop.log("拡張", "詰め替え開始 \(size ?? -1) バイト 使用=\(footprintMB())MB 余り=\(availableMB())MB")
                    let mb = Double(size ?? 0) / 1_048_576
                    await MainActor.run {
                        show("MP4 にしています…（\(Int(mb)) MB）", progress: 0, canClose: false)
                    }
                    let r = await Remux.toMP4(file, taken: taken,
                                              log: { MrDrop.log("変換", $0) }, describe: MrDrop.describe,
                                              onProgress: { [weak self] p in
                                                  Task { @MainActor in
                                                      self?.show("MP4 にしています… \(Int(p * 100))%（\(Int(mb)) MB）",
                                                                 progress: p, canClose: false)
                                                  }
                                              })
                    MrDrop.log("拡張", "詰め替え終了 \(String(format: "%.1f", -before.timeIntervalSinceNow))秒 "
                                     + "使用=\(footprintMB())MB 余り=\(availableMB())MB")
                    if let mp4 = r.url {
                        file = mp4
                        name = (name as NSString).deletingPathExtension + ".mp4"
                    } else if r.note != nil {
                        keptAsIs += 1
                    }
                }
                if uploader.send(fileURL: file, filename: name, to: peer, modified: taken) {
                    count += 1
                }
            }
        }

        // 🔴 MP4 にできなかったときは黙らない（本体アプリの一覧と同じ約束）
        let note = keptAsIs > 0 ? "\n（\(keptAsIs)件は MP4 にできなかったので、元の形式のまま送ります）" : ""
        guard count > 0 else { finish("送れるものがありませんでした。", ok: false); return }
        // 🔴 ここで即座に閉じない。**大きい動画は転送に何十秒もかかる**ので、
        //    進み具合と残り時間を出し、「閉じても続く」ことを伝える（2026-09-15 本人指摘）。
        watchTransfer(to: peer.name, extra: note)
    }

    private func isMovie(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    /// いま自分がどれだけ使っていて、あとどれだけ使えるか。
    /// 🔴 共有拡張の上限はおよそ 120MB。**測らずに「たぶん大丈夫」で足すと、写真アプリごと落ちる。**
    private func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    /// あと何 MB 使えるか（iOS が教えてくれる残り）。
    private func availableMB() -> Int { Int(os_proc_available_memory() / 1_048_576) }

    /// 🔴 **型を自分で選んではいけない。**Photos は頼まれた型に「変換して」渡してくる。
    ///    実測（2026-09-03）: MP4 の 1080p 動画に `com.apple.quicktime-movie` を頼んだら、
    ///    **568×320・611 kbps のメール用書き出し**が返ってきた（60分で 336MB）。
    ///    `public.item` でも写真は JPEG に変換される。
    ///
    ///    正解は「**相手が並べた順の先頭**」。NSItemProvider は元に近い順に並べるので、
    ///    明らかに縮小版だと分かるものだけ外して、先頭を採る。
    private func originalType(of provider: NSItemProvider) -> String {
        let avoid = [
            "com.apple.private.photos.mail-movie-export",   // メール用の縮小動画
        ]
        let usable = provider.registeredTypeIdentifiers.filter {
            !avoid.contains($0) && !$0.contains("thumbnail")
        }
        let best = usable.first ?? provider.registeredTypeIdentifiers.first ?? UTType.item.identifier

        // 🔴 動画は、相手が並べた先頭をそのまま使う（型を指定すると変換されて画質が落ちる）。
        //    🔵 mp4 への詰め替えは、受け取ったあとに `Remux` で行う（パススルー＝作り直さない）。
        //       メモリに収まるかは `process()` で毎回測っている。
        guard UTType(best)?.conforms(to: .image) == true else { return best }

        // 写真は選び直す。
        // 🔴 写真アプリは `public.jpeg` を先頭に並べてくることがあるので、
        //    「先頭をそのまま」だと、切にしていても JPEG になってしまう。
        if MrDrop.convertForPC {
            if usable.contains(UTType.jpeg.identifier) { return UTType.jpeg.identifier }
            return best
        }
        // 切のときは、撮ったままの HEIC / HEIF があればそれを選ぶ
        return usable.first(where: { MrDrop.isHEIF($0) }) ?? best
    }

    /// 🔴 loadFileRepresentation が渡してくる URL は、このクロージャの中でだけ有効。
    ///    必ずこの場でコピーしきること。あとで開こうとしても消えている。
    private func copyToStaging(_ provider: NSItemProvider) async -> (file: URL, name: String)? {
        await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: originalType(of: provider)) { url, _ in
                guard let url else {
                    MrDrop.log("拡張", "🔴 取り込み: iOS が渡してくれなかった")
                    cont.resume(returning: nil); return
                }
                do {
                    let dir = try MrDrop.stagingDirectory()
                    let dest = dir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    // 🔴 数GB の動画を複製しない。同じディスクならハードリンクで一瞬
                    do {
                        try FileManager.default.linkItem(at: url, to: dest)
                    } catch {
                        try FileManager.default.copyItem(at: url, to: dest)
                    }
                    cont.resume(returning: (dest, url.lastPathComponent))
                } catch {
                    MrDrop.log("拡張", "🔴 取り込み失敗 \(MrDrop.describe(error))")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// 転送の進み具合を 0.5 秒ごとに出す。速さから残り時間も見積もる。
    /// 🔴 転送そのものは background セッションなので、**閉じても・写真アプリへ戻っても続く**。
    private func watchTransfer(to peerName: String, extra: String) {
        spinner.stopAnimating(); spinner.isHidden = true
        let started = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let jobs = self.uploader.jobs
            let total = jobs.reduce(Int64(0)) { $0 + $1.total }
            let sent  = jobs.reduce(Int64(0)) { $0 + $1.sent }
            let done  = jobs.allSatisfy { $0.finished }
            if done {
                t.invalidate()
                let failed = jobs.filter { $0.error != nil }.count
                self.show(failed > 0 ? "\(failed)件は送れませんでした" : "\(peerName) へ送りました" + extra,
                          progress: nil, canClose: false)
                self.finish(failed > 0 ? "\(failed)件は送れませんでした" : "\(peerName) へ送りました" + extra,
                            ok: failed == 0)
                return
            }
            let p = total > 0 ? Double(sent) / Double(total) : 0
            let secs = -started.timeIntervalSinceNow
            var rest = ""
            if sent > 0, secs > 1 {
                let perSec = Double(sent) / secs
                let left = Double(total - sent) / max(perSec, 1)
                rest = left > 1 ? "・残り約 \(Int(left.rounded()))秒" : ""
            }
            self.show("\(peerName) へ送っています… \(Int(p * 100))%\(rest)\n閉じても続きます",
                      progress: p, canClose: true)
        }
    }

    /// 🔴 うまくいった時と、そうでない時で閉じるまでの時間を変える。
    ///    どちらも 1.2 秒だと、**読ませたい文章ほど読む前に消える**（2026-09-12 に気づいた）。
    private func finish(_ text: String, ok: Bool = true) {
        ticker?.invalidate()
        spinner.stopAnimating()
        spinner.isHidden = true
        bar.isHidden = true
        closeButton.isHidden = true
        label.text = text
        DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 1.2 : 4.5)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
