import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// そのファイルが「いつのものか」を、**中身から**読み取る。
///
/// 🔴 ファイルの更新日時は当てにならない。iOS はアプリに渡すとき書き出し直すので、
///    そのまま送ると PC には「送った日」が付く。撮影日時は**中**にある——
///    写真なら EXIF、動画なら QuickTime のメタデータ。
///
/// 🔴 写真アプリ（PHAsset）を覗けば撮影日時は確実に取れるが、それには
///    写真ライブラリの**読み取り許可**が要る。読み取りは求めないと決めてあるので
///    （`project.yml` は入れる許可だけ）、渡されたファイルの中身だけで済ませる。
enum FileDate {

    // MARK: - 読む

    /// 中に書いてある日付。無ければ nil。
    static func embedded(in url: URL) async -> Date? {
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if t.conforms(to: .movie) { return plausible(await fromMovie(url)) }
        if t.conforms(to: .image) { return plausible(fromImage(url)) }
        return nil
    }

    /// PC に伝える日付。中に書いてあればそれ、無ければファイル自身の更新日時。
    /// 🔴 書類や PDF は中に日付を持たないので、そこはファイルの日付が頼りになる。
    static func best(of url: URL) async -> Date? {
        if let d = await embedded(in: url) { return d }
        return fileDate(of: url)
    }

    /// ファイル自身の更新日時。
    static func fileDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: - 書く

    /// 保存したファイルに日付を付け直す。
    /// 🔴 付けるのは**更新日時だけ**。作成日時は「手元に来た時刻」のままにしておく
    ///    （PC 側 `server/lib/http.js` と同じ流儀。届いた順に並べたい人の逃げ道を残す）。
    static func apply(_ date: Date?, to url: URL) {
        guard let date, plausible(date) != nil else { return }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - 写真（EXIF）

    private static func fromImage(_ url: URL) -> Date? {
        // 🔴 中身は展開しない。ヘッダだけ読む（共有拡張はメモリ 120MB しかない）。
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any]
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
                     ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
                     ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        else { return nil }

        // 🔴 EXIF の日時には時差が書いていない（「2026:09:14 12:34:56」だけ）。
        //    別の欄に時差があればそれを使い、無ければこの端末の時差とみなす（写真アプリと同じ）。
        let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String
                  ?? exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = offset.flatMap(zone(from:)) ?? .current
        return f.date(from: raw)
    }

    /// 「+09:00」「-0500」を時差に直す。
    private static func zone(from offset: String) -> TimeZone? {
        let t = offset.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "")
        guard t.count == 5, let sign = t.first, sign == "+" || sign == "-",
              let h = Int(t.dropFirst().prefix(2)), let m = Int(t.suffix(2)) else { return nil }
        return TimeZone(secondsFromGMT: (h * 3600 + m * 60) * (sign == "-" ? -1 : 1))
    }

    // MARK: - 動画（QuickTime / MP4）

    private static func fromMovie(_ url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)
        guard let item = (try? await asset.load(.creationDate)) ?? nil else { return nil }
        if let d = (try? await item.load(.dateValue)) ?? nil { return d }
        if let s = (try? await item.load(.stringValue)) ?? nil { return parseISO(s) }
        return nil
    }

    /// 「2026-09-14T12:34:56+0900」。iPhone が書くのは時差入りだが、Z の物も来る。
    static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // 🔴 QuickTime は「+0900」とコロン無しで書く。ISO8601DateFormatter はこれを読めない
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f.date(from: s)
    }

    /// QuickTime に書き込む形。iPhone の実物に合わせて時差はコロン無し。
    static func quickTimeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f.string(from: d)
    }

    /// 書き出す動画に付ける「作成日時」の札。
    ///
    /// 🔴 パススルーの詰め替え（mov → mp4）は、中の作成日時を**「変換した時刻」に書き換える**
    ///    （2026-09-14 に測った。消えるのではなく化ける＝嘘の日付が入る）。
    ///    `AVAssetExportSession.metadata` に入れ直すと、元の日付が残る。
    /// 🔴 出す形式に合わない札は AVFoundation が黙って捨てるだけなので、2種類とも載せる。
    ///    共通欄は出力形式に合わせて書き換えられ、QuickTime 欄は写真アプリが読む方。
    static func creationMetadata(_ date: Date) -> [AVMetadataItem] {
        let text = quickTimeString(date) as NSString
        return [AVMetadataIdentifier.commonIdentifierCreationDate,
                AVMetadataIdentifier.quickTimeMetadataCreationDate].map { id in
            let item = AVMutableMetadataItem()
            item.identifier = id
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.value = text
            return item
        }
    }

    // MARK: - 書き出した mp4 のヘッダを直す

    /// 詰め替えた mp4 の**ヘッダの作成日時**を、元の日付に直す。
    ///
    /// 🔴 `AVAssetExportSession` は札（`uiso/date`）には言われた日付を書くが、
    ///    ヘッダ（`moov` → `mvhd`）には**必ず「書き出した時刻」**を入れる（2026-09-14 実測）。
    ///    Apple のアプリは札を読むので気づけない。だが **ffprobe・Windows の
    ///    「メディアの作成日」・多くの編集ソフトはヘッダの方を見る**ので、直さないと
    ///    「写真アプリでは合っているのに、PC で見ると変換した日」になる。
    ///
    /// 🔴 中身は1バイトも動かさない。決まった場所の 8（または16）バイトを書き換えるだけ。
    ///    少しでも読み方が合わなければ**何もせずに帰る**。壊すくらいなら直さない方がいい。
    static func patchContainerDate(_ url: URL, to date: Date) {
        // QuickTime の時刻は 1904-01-01 から数える
        let stamp = Int64(date.timeIntervalSince1970) + 2_082_844_800
        guard stamp > 0, stamp < 0xFFFF_FFFF else { return }
        guard let h = try? FileHandle(forUpdating: url) else { return }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return }

        /// 箱を順に見て、目当ての型の「中身が始まる場所」と「中身の長さ」を返す。
        func find(_ want: String, from: UInt64, to: UInt64) -> (body: UInt64, size: UInt64)? {
            var at = from
            while at + 8 <= to {
                guard (try? h.seek(toOffset: at)) != nil,
                      let head = try? h.read(upToCount: 8), head.count == 8 else { return nil }
                var size = UInt64(head[0..<4].reduce(0) { $0 << 8 | UInt32($1) })
                var body = at + 8
                if size == 1 {                                  // 4GB 超えの箱は 64bit の長さが続く
                    guard let big = try? h.read(upToCount: 8), big.count == 8 else { return nil }
                    size = big.reduce(0) { $0 << 8 | UInt64($1) }
                    body = at + 16
                } else if size == 0 {
                    size = to - at                              // 最後の箱＝ファイル末尾まで
                }
                guard size >= body - at, at + size <= to else { return nil }
                let type = String(decoding: head[4..<8], as: UTF8.self)
                if type == want { return (body, at + size - body) }
                at += size
            }
            return nil
        }

        guard let moov = find("moov", from: 0, to: end),
              let mvhd = find("mvhd", from: moov.body, to: moov.body + moov.size),
              mvhd.size >= 4 else { return }
        guard (try? h.seek(toOffset: mvhd.body)) != nil,
              let ver = try? h.read(upToCount: 1), ver.count == 1 else { return }

        // version 0 は 4 バイト×2、version 1 は 8 バイト×2（作成日時・更新日時の順）
        let wide = ver[ver.startIndex] == 1
        let need = UInt64(4 + (wide ? 16 : 8))
        guard mvhd.size >= need else { return }
        var bytes: [UInt8] = []
        for i in stride(from: (wide ? 7 : 3), through: 0, by: -1) {
            bytes.append(UInt8((stamp >> (i * 8)) & 0xFF))      // 上の桁から並べる（ビッグエンディアン）
        }
        guard (try? h.seek(toOffset: mvhd.body + 4)) != nil else { return }
        try? h.write(contentsOf: Data(bytes + bytes))           // 作成日時と更新日時の両方
    }

    // MARK: - ありえない日付を通さない

    /// 壊れた EXIF は「0000:00:00 00:00:00」のような値を返す。
    /// そのまま付けると、ファイルの日付が 1601 年や 2160 年になる。
    private static func plausible(_ d: Date?) -> Date? {
        guard let d else { return nil }
        let lower = Date(timeIntervalSince1970: 631_152_000)      // 1990-01-01
        let upper = Date().addingTimeInterval(2 * 86_400)         // 時差のずれ幅より広く取る
        return (d >= lower && d <= upper) ? d : nil
    }
}
