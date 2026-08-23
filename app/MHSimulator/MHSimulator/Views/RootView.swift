import SwiftUI

/// 起動フェーズの出し分け: 読み込み中 → タブ本体 / マスタ読込失敗(終端)
struct RootView: View {
    let bootstrap: AppBootstrap

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            switch bootstrap.phase {
            case .loading:
                ProgressView()
                    .tint(Color.mhAccent)
            case .failed:
                // 画面設計 ダイアログ4: 全機能を読み取り不能状態にする(操作不可・終端)
                MHEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "データの読み込みに失敗しました",
                    message: "アプリの再インストールをお試しください")
            case .ready(let dependencies):
                MainTabView(dependencies: dependencies)
            }
        }
        .task { bootstrap.load() }
    }
}
