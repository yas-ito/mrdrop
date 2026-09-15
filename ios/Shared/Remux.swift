import Foundation
import AVFoundation

/// 動画を **作り直さずに** mp4 へ詰め替える（パススルー）。画質は変わらず、数秒で終わる。
///
/// 🔴 共有拡張では呼ばないこと。メモリ 120MB の中で走らせると落ちる。
/// 🔴 本体アプリとテストの**両方がここを使う**。写しを作ると、片方だけ直して食い違う
///    （実際、テストには `ContentView` の写しが置いてあった）。
///
/// 🔴 2026-09-15: **本人の動画13回のうち6回、黙って失敗していた**（同じ動画が2分違いで
///    成功したり失敗したり＝`AVFoundationErrorDomain -11800` / 内側 `-16979`）。欠陥は3つ:
///    ① **読み込みを待たずに書き出していた**（`AVURLAsset` の読み込みは非同期。コイン投げの正体）
///    ② **この動画を mp4 に入れられるか聞かずに** `.mp4` を入れていた
///    ③ **失敗しても黙って元のまま送っていた**（「MP4 にする」と書いておいて、半分破っていた）
///    → **待つ・聞く・1回やり直す・駄目なら画面に出す**に作り替えた。
enum Remux {

    /// 詰め替えの結果。`url` が nil なら**元のまま**送る。`note` はそのとき画面に出す一行。
    /// 🔴 黙って元のまま送らないための入れ物。約束を守れなかったときは、必ず本人に見せる。
    struct Result: Equatable {
        let url: URL?
        let note: String?
        static func done(_ url: URL) -> Result { Result(url: url, note: nil) }
        static let keptAsIs = Result(url: nil, note: "MP4 にできませんでした（元の形式のまま送ります）")
    }

    /// - Parameter taken: 撮影日時。🔴 **詰め替える前に**呼ぶ側が読んで渡すこと。
    ///   詰め替えると中の作成日時は「変換した時刻」に化けるので、あとから読んでは手遅れ。
    /// - Parameter log: 記録の書き方（本体は `MrDrop.log("変換", …)`、テストは自前）。
    /// - Parameter describe: エラーの書き表し方。🔴 既定の `localizedDescription` は
    ///   「unknown error」としか言わない。**本体は必ず `MrDrop.describe` を渡すこと**
    ///   （領域・番号・内側のエラーまで出る。09-15 の原因特定は、これが記録に残っていたから出来た）。
    /// - Returns: 成功したら mp4 の場所（**元のファイルは消す**）。駄目なら `.keptAsIs`。
    static func toMP4(_ url: URL, taken: Date?, log: (String) -> Void,
                      describe: (Error) -> String = { $0.localizedDescription }) async -> Result {
        guard url.pathExtension.lowercased() != "mp4" else { return .done(url) }
        let asset = AVURLAsset(url: url)

        // 🔴 ① 読み終えてから書き出す。待たないと、同じ動画でも成否が揺れる
        do {
            _ = try await asset.load(.tracks)
        } catch {
            log("🔴 動画を読めませんでした（元のまま送ります）: \(describe(error))")
            return .keptAsIs
        }

        // 🔴 ② 中身を見て「mp4 に入れられるか」を聞く。
        //    `supportedFileTypes` は preset しか見ないので、ここでは使えない（Apple の注記のとおり）。
        guard let probe = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            log("🔴 パススルーの書き出しを作れませんでした")
            return .keptAsIs
        }
        // 🔵 async 版は用意されていないので、完了ハンドラを待つ形で包む
        let ok: [AVFileType] = await withCheckedContinuation { cont in
            probe.determineCompatibleFileTypes { cont.resume(returning: $0) }
        }
        guard ok.contains(.mp4) else {
            log("この動画は mp4 に入れられません（元のまま送ります） 入れられる型=[\(ok.map(\.rawValue).joined(separator: ","))]")
            return .keptAsIs
        }

        // 🔴 ③ 一度失敗しても、もう一度だけやり直す。
        //    書き出しは使い捨てなので、やり直すときは作り直す（使い回すと必ず落ちる）。
        for attempt in 1...2 {
            if let out = await passthrough(asset, from: url, taken: taken, attempt: attempt,
                                           log: log, describe: describe) {
                try? FileManager.default.removeItem(at: url)     // 元は要らない
                return .done(out)
            }
        }
        return .keptAsIs
    }

    /// 1回分の書き出し。やり直せるように切り出してある。
    private static func passthrough(_ asset: AVURLAsset, from url: URL, taken: Date?, attempt: Int,
                                    log: (String) -> Void, describe: (Error) -> String) async -> URL? {
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            log("🔴 パススルーの書き出しを作れませんでした（\(attempt)回目）")
            return nil
        }
        let out = url.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: out)
        ex.outputURL = out
        ex.outputFileType = .mp4
        if let taken { ex.metadata = FileDate.creationMetadata(taken) }   // 🔴 これが無いと日付が消える
        let started = Date()
        await withCheckedContinuation { cont in
            ex.exportAsynchronously { cont.resume() }
        }
        guard ex.status == .completed else {
            let why = ex.error.map(describe) ?? "理由不明"
            log("🔴 詰め替え失敗（\(attempt)回目・元のまま送ります）: \(why)")
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        let secs = String(format: "%.1f", -started.timeIntervalSinceNow)
        log("mp4 へ詰め替え \(secs)秒" + (attempt > 1 ? "（\(attempt)回目で成功）" : ""))
        if let taken {
            // 🔴 札だけでは足りない。ヘッダには書き出した時刻が入るので、そこも直す
            //    （Windows の「メディアの作成日」や編集ソフトはヘッダを見る）。
            FileDate.patchContainerDate(out, to: taken)
        }
        FileDate.apply(taken, to: out)                   // 外側の日付もそろえておく
        return out
    }
}
