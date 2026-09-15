// 日付の引き継ぎ（撮影日時・元のファイルの日付）を、実物のファイルで確かめる。
//
// 🔴 シミュレータも実機も要らない。`Shared/FileDate.swift` は Mac でもそのまま動くので、
//    Mac のコマンドとして組み立てて走らせている。走らせ方は `run.sh`。
// 🔴 ここで固定してあるのは、全部 2026-09-14 に**測って**分かったこと。
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

var pass = 0, fail = 0
func suite(_ name: String) { print("\n" + name) }
func check(_ ok: Bool, _ m: String) {
    if ok { pass += 1; print("  ok   " + m) } else { fail += 1; print("  NG   " + m) }
}
/// 画面に出すときだけ日本時間で読む（測っている中身は時刻そのもので、表示は関係ない）
func show(_ d: Date?) -> String {
    guard let d else { return "なし" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    return f.string(from: d)
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let hasMovies = FileManager.default.fileExists(atPath: dir.appendingPathComponent("sample.mov").path)

/// EXIF 付きの JPEG をその場でつくる
func makeJPEG(_ name: String, exif: [CFString: Any]) -> URL {
    let url = dir.appendingPathComponent(name)
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!,
                               [kCGImagePropertyExifDictionary: exif] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return url
}

/// 🔴 **本物の `Shared/Remux.swift` を通す。**ここに写しを置いていたせいで、
///    「テストは通るのに実機では半分失敗する」を見逃した（2026-09-15）。
///    素材は詰め替えで消えるので、その都度コピーしてから渡す。
var remuxLog: [String] = []
func remuxCopy(_ src: URL, as name: String, taken: Date?) async -> Remux.Result {
    let work = dir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: work)
    try? FileManager.default.copyItem(at: src, to: work)
    return await Remux.toMP4(work, taken: taken, log: { remuxLog.append($0) })
}

/// mp4 のヘッダ（moov → mvhd）に書いてある作成日時を、自前で読み出す。
/// 🔴 AVFoundation は別の札（uiso/date）を読むので、ヘッダが直ったかはこちらで見るしかない。
func headerDate(_ url: URL) -> Date? {
    guard let h = try? FileHandle(forReadingFrom: url), let end = try? h.seekToEnd() else { return nil }
    defer { try? h.close() }
    func find(_ want: String, from: UInt64, to: UInt64) -> (UInt64, UInt64)? {
        var at = from
        while at + 8 <= to {
            guard (try? h.seek(toOffset: at)) != nil,
                  let head = try? h.read(upToCount: 8), head.count == 8 else { return nil }
            var size = UInt64(head[0..<4].reduce(0) { $0 << 8 | UInt32($1) })
            var body = at + 8
            if size == 1 {
                guard let big = try? h.read(upToCount: 8), big.count == 8 else { return nil }
                size = big.reduce(0) { $0 << 8 | UInt64($1) }
                body = at + 16
            } else if size == 0 { size = to - at }
            guard size >= body - at, at + size <= to else { return nil }
            if String(decoding: head[4..<8], as: UTF8.self) == want { return (body, at + size - body) }
            at += size
        }
        return nil
    }
    guard let moov = find("moov", from: 0, to: end),
          let mvhd = find("mvhd", from: moov.0, to: moov.0 + moov.1),
          (try? h.seek(toOffset: mvhd.0)) != nil,
          let ver = try? h.read(upToCount: 1), ver.count == 1,
          // 🔴 version(1) のあとに flags(3) が続く。ここを飛ばさないと日付が 1904 年になる
          (try? h.seek(toOffset: mvhd.0 + 4)) != nil,
          let raw = try? h.read(upToCount: ver[ver.startIndex] == 1 ? 8 : 4) else { return nil }
    let secs = raw.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    return Date(timeIntervalSince1970: Double(secs) - 2_082_844_800)
}

// ffmpeg でつくった素材の中身（run.sh と同じ値）
let movTaken = Date(timeIntervalSince1970: 1_556_861_136)   // 2019-05-03 14:25:36 +0900
let mp4Taken = Date(timeIntervalSince1970: 1_636_243_262)   // 2021-11-07 09:01:02 +0900

func run() async {
    suite("写真（EXIF）から撮影日時を読む")
    let a = makeJPEG("tz.jpg", exif: [
        kCGImagePropertyExifDateTimeOriginal: "2019:05:03 14:25:36",
        kCGImagePropertyExifOffsetTimeOriginal: "+09:00",
    ])
    let ad = await FileDate.embedded(in: a)
    check(ad == movTaken, "時差つきの EXIF を読む → \(show(ad))")

    // 🔴 EXIF の日時には時差が書いていない方が普通。そのときは端末の時差とみなす（写真アプリと同じ）
    let b = makeJPEG("notz.jpg", exif: [kCGImagePropertyExifDateTimeOriginal: "2019:05:03 14:25:36"])
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.timeZone = .current
    check(await FileDate.embedded(in: b) == f.date(from: "2019:05:03 14:25:36"),
          "時差なしの EXIF は端末の時差で読む")

    check(await FileDate.embedded(in: makeJPEG("none.jpg", exif: [:])) == nil,
          "EXIF に日付が無ければ「なし」（スクリーンショット等）")
    // 🔴 壊れた EXIF は実在する。通すとファイルの日付が 1601 年になる
    check(await FileDate.embedded(in: makeJPEG("broken.jpg",
            exif: [kCGImagePropertyExifDateTimeOriginal: "0000:00:00 00:00:00"])) == nil,
          "🔴 壊れた EXIF（0000:00:00）は捨てる")

    if hasMovies {
        suite("動画（QuickTime / MP4）から作成日時を読む")
        let movd = await FileDate.embedded(in: dir.appendingPathComponent("sample.mov"))
        check(movd == movTaken, ".mov の作成日時を読む → \(show(movd))")
        let mp4d = await FileDate.embedded(in: dir.appendingPathComponent("sample.mp4"))
        check(mp4d == mp4Taken, ".mp4 の作成日時を読む → \(show(mp4d))")
        check(await FileDate.embedded(in: dir.appendingPathComponent("nodate.mp4")) == nil,
              "日付が入っていない動画は「なし」")
    }

    suite("中に日付が無いものは、ファイル自身の日付を使う")
    // 🔴 ここが本人の指摘の芯。書類や PDF は中に日付を持たないので、ここが唯一の手がかり
    let txt = dir.appendingPathComponent("覚書.txt")
    try? "メモ".write(to: txt, atomically: true, encoding: .utf8)
    FileDate.apply(movTaken, to: txt)
    check(await FileDate.embedded(in: txt) == nil, "書類は中に日付を持たない")
    check(await FileDate.best(of: txt) == movTaken, "🔴 だから best はファイルの更新日時を返す")

    suite("日付を付け直す")
    let t = dir.appendingPathComponent("付け直し.txt")
    try? "x".write(to: t, atomically: true, encoding: .utf8)
    FileDate.apply(movTaken, to: t)
    check(FileDate.fileDate(of: t) == movTaken, "更新日時が指定どおりになる → \(show(FileDate.fileDate(of: t)))")
    let before = FileDate.fileDate(of: t)
    FileDate.apply(Date(timeIntervalSince1970: 0), to: t)
    check(FileDate.fileDate(of: t) == before, "🔴 ありえない日付（1970年）は付けない")
    FileDate.apply(nil, to: t)
    check(FileDate.fileDate(of: t) == before, "nil なら何もしない")

    suite("書き込む形（QuickTime 用の文字列）")
    let s = FileDate.quickTimeString(movTaken)
    check(FileDate.parseISO(s) == movTaken, "書いた物を読み戻せる → \(s)")
    check(FileDate.parseISO("2019-05-03T14:25:36+0900") == movTaken, "iPhone が書く形（コロン無しの時差）を読める")
    check(FileDate.parseISO("2019-05-03T05:25:36Z") == movTaken, "Z 付きも読める")

    if hasMovies {
        suite("mp4 へ詰め替えても日付が残る")
        let src = dir.appendingPathComponent("sample.mov")
        // 🔴 これまでの症状の再現。「消える」のではなく**変換した時刻に化ける**。
        //    nil になるより悪い——もっともらしい嘘の日付なので、誰も間違いに気づけない
        let old = (await remuxCopy(src, as: "out-old.mov", taken: nil)).url
                  ?? dir.appendingPathComponent("out-old.mp4")
        let od = await FileDate.embedded(in: old)
        check(od != nil && abs(od!.timeIntervalSinceNow) < 300,
              "🔴 札を載せないと作成日時が「変換した時刻」に化ける（再現） → \(show(od))")

        let now = (await remuxCopy(src, as: "out-new.mov", taken: movTaken)).url
                  ?? dir.appendingPathComponent("out-new.mp4")
        let nd = await FileDate.embedded(in: now)
        check(nd == movTaken, "札を載せれば撮影日時が残る → \(show(nd))")

        FileDate.apply(movTaken, to: now)
        check(await FileDate.best(of: now) == movTaken, "ファイル自身の更新日時もそろう")

        // 🔴 札だけでは足りない。ヘッダ（mvhd）には書き出した時刻が入る。
        //    Apple のアプリは札を読むので気づけないが、ffprobe・Windows の「メディアの作成日」・
        //    多くの編集ソフトはヘッダを見る（2026-09-14 実測）
        check(headerDate(old).map { abs($0.timeIntervalSinceNow) < 300 } ?? false,
              "🔴 直さないとヘッダは「変換した時刻」のまま → \(show(headerDate(old)))")
        check(headerDate(now) == movTaken, "ヘッダも撮影日時に直る → \(show(headerDate(now)))")

        // ヘッダを書き換えても中身が壊れないこと（長さとトラック数で見る）
        let a = AVURLAsset(url: now)
        let dur = (try? await a.load(.duration)) ?? .zero
        let tracks = (try? await a.load(.tracks))?.count ?? 0
        check(abs(CMTimeGetSeconds(dur) - 2.0) < 0.2 && tracks == 2,
              "🔴 ヘッダを書き換えても中身は無傷（\(String(format: "%.2f", CMTimeGetSeconds(dur)))秒 / トラック \(tracks) 本）")

        let s1 = (try? Data(contentsOf: old).count) ?? 0
        let s2 = (try? Data(contentsOf: now).count) ?? -1
        check(abs(s1 - s2) < 4096, "大きさはほぼ同じ＝作り直していない（\(s1) / \(s2) バイト）")
    }

    if hasMovies {
        suite("詰め替えの手当て（2026-09-15・13回中6回黙って失敗していた件）")

        // ① mov は mp4 になる。元は消える（App Group に二重に置かないため）
        let src = dir.appendingPathComponent("sample.mov")
        let r = await remuxCopy(src, as: "case-ok.mov", taken: movTaken)
        check(r.url?.pathExtension == "mp4" && r.note == nil, "mov → mp4 になり、知らせは出ない")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("case-ok.mov").path),
              "元の mov は消える")
        let tracks = (try? await AVURLAsset(url: r.url!).load(.tracks))?.count ?? 0
        check(tracks == 2, "中身は無傷（トラック \(tracks) 本）＝作り直していない")

        // ② すでに mp4 なら何もしない（触ると日付とヘッダを壊す）
        let already = dir.appendingPathComponent("sample.mp4")
        let r2 = await Remux.toMP4(already, taken: movTaken, log: { remuxLog.append($0) })
        check(r2.url == already && r2.note == nil, "すでに mp4 ならそのまま返す")
        check(FileManager.default.fileExists(atPath: already.path), "そのままの mp4 は消さない")

        // ③ 🔴 詰め替えられない物は、黙らずに画面へ一行出す（09-15 に直した所）
        let broken = dir.appendingPathComponent("broken.mov")
        try? Data("これは動画ではありません".utf8).write(to: broken)
        remuxLog.removeAll()
        let r3 = await Remux.toMP4(broken, taken: nil, log: { remuxLog.append($0) })
        check(r3.url == nil, "詰め替えられない物は元のまま送る（url は nil）")
        check(r3.note?.contains("MP4 にできませんでした") == true,
              "🔴 黙らない＝画面に出す一行が返る → \(r3.note ?? "なし")")
        check(remuxLog.contains { $0.contains("元のまま送ります") },
              "記録にも理由が残る → \(remuxLog.first ?? "なし")")
        check(FileManager.default.fileExists(atPath: broken.path), "駄目だったときは元を消さない")
    }

    print("")
    if !hasMovies { print("⚠️ 動画の分は飛ばしました（ffmpeg が無いので素材を作れない）") }
    print("\(pass) passed, \(fail) failed")
    if fail > 0 { print("🔴 通っていないものがあります。") }
    exit(fail == 0 ? 0 : 1)
}
await run()
