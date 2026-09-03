import SwiftUI

@main
struct MrDropApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    MrDrop.log("アプリ", "起動")
                    MrDrop.sweepStaging()
                    MrDrop.exportLog()      // Mac から取り出せる場所へ写す
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 共有拡張が始めた転送の後始末は、拡張が消えたあとに本体が引き継ぐ決まり。
    /// 🔴 ここを実装しないと、共有シートから送った大きい動画が終わりきらないことがある。
    private static var keepAlive: Uploader?

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        let u = Uploader(identifier: identifier)
        u.backgroundCompletion = completionHandler
        Self.keepAlive = u
    }
}
