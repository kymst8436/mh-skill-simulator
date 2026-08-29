import SwiftUI
import GoogleMobileAds

@main
struct MHSimulatorApp: App {
    @State private var bootstrap = AppBootstrap()

    init() {
        MHTheme.configureAppearance()
        MobileAds.shared.start()
        // 起動時にPro権利の検証とトランザクション監視を開始する(広告表示判定より先に走らせる)
        _ = ProStore.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: bootstrap)
                .preferredColorScheme(.dark)  // ダーク単一テーマ(DESIGN.md §1-4)
        }
    }
}
