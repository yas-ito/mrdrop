import UIKit
import UniformTypeIdentifiers

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

        card.addSubview(spinner)
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),

            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
        ])
    }

    private func process() async {
        guard let peer = MrDrop.lastPeer else {
            finish("先に Mr.Drop アプリを一度開いて、送り先の PC を選んでください。")
            return
        }

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var count = 0
        MrDrop.log("拡張", "起動 項目数=\(items.count) 送り先=\(peer.name)")
        for item in items {
            for provider in item.attachments ?? [] {
                MrDrop.log("拡張", "受け取れる型=\(provider.registeredTypeIdentifiers.joined(separator: ",")) → 選んだ型=\(originalType(of: provider))")
                guard let picked = await copyToStaging(provider) else { continue }
                if uploader.send(fileURL: picked.file, filename: picked.name, to: peer, modified: nil) {
                    count += 1
                }
            }
        }

        finish(count > 0 ? "\(peer.name) へ送っています（\(count)件）" : "送れるものがありませんでした。")
    }

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
        //    ここでは変換もしない。メモリ 120MB の中で作り直すと落ちる。
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

    private func finish(_ text: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        label.text = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
