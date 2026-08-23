import SwiftUI

@main
struct MHSimulatorApp: App {
    @State private var bootstrap = AppBootstrap()

    init() {
        MHTheme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView(bootstrap: bootstrap)
                .preferredColorScheme(.dark)  // ダーク単一テーマ(DESIGN.md §1-4)
        }
    }
}
