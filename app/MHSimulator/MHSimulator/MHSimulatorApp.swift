import SwiftUI
import GoogleMobileAds

@main
struct MHSimulatorApp: App {
    @State private var bootstrap = AppBootstrap()

    init() {
        MHTheme.configureAppearance()
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: bootstrap)
                .preferredColorScheme(.dark)  // ダーク単一テーマ(DESIGN.md §1-4)
        }
    }
}
