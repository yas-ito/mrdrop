import SwiftUI

/// アプリの土台。**「送る」と「受け取る」の2枚**。
///
/// 🔴 タブを2枚にしたのは 2026-09-14 の苦情がきっかけ。
///    「アプリで送れたのだから、受け取るのもアプリの中にあるはず」と読まれる。
///    受け取りをブラウザに追い出していたのは、こちらの都合でしかなかった。
///
/// 🔴 `Discovery` と `Connection` は**ここで1つだけ**作って両方に配る。
///    画面ごとに持たせると、片方のタブで選んだ PC がもう片方に伝わらない。
struct RootView: View {
    @StateObject private var discovery = Discovery()
    @StateObject private var connection = Connection()

    var body: some View {
        TabView {
            ContentView(discovery: discovery)
                .tabItem { Label("送る", systemImage: "arrow.up.circle") }

            ReceiveView(discovery: discovery)
                .tabItem { Label("受け取る", systemImage: "arrow.down.circle") }
        }
        .environmentObject(connection)
        // 🔴 PC 探しはタブをまたいで動かし続ける。タブを変えるたびに探し直すと、
        //    切り替えた直後だけ一覧が空になり「見失った」ように見える。
        .onAppear {
            discovery.start()
            MrDrop.log("アプリ", "起動")
            MrDrop.sweepStaging()
            MrDrop.exportLog()      // Mac から取り出せる場所へ写す
        }
        .onDisappear { discovery.stop() }
    }
}
