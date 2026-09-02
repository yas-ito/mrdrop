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
            finish("先に MrDrop アプリを一度開いて、送り先の PC を選んでください。")
            return
        }

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var count = 0
        for item in items {
            for provider in item.attachments ?? [] {
                guard let picked = await copyToStaging(provider) else { continue }
                if uploader.send(fileURL: picked.file, filename: picked.name, to: peer, modified: nil) {
                    count += 1
                }
            }
        }

        finish(count > 0 ? "\(peer.name) へ送っています（\(count)件）" : "送れるものがありませんでした。")
    }

    /// 🔴 loadFileRepresentation が渡してくる URL は、このクロージャの中でだけ有効。
    ///    必ずこの場でコピーしきること。あとで開こうとしても消えている。
    private func copyToStaging(_ provider: NSItemProvider) async -> (file: URL, name: String)? {
        await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                do {
                    let dir = try MrDrop.stagingDirectory()
                    let dest = dir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: (dest, url.lastPathComponent))
                } catch {
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
