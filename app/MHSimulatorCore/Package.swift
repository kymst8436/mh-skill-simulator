// swift-tools-version:5.9
// MHシミュレーター コアロジック(UI非依存。Phase 2)
// 検索エンジン(F-1)・逆引き(F-2)・規則評価(F-3補助)と、bundled.dbの読み込み。
// Phase 3のXcodeプロジェクトからローカルパッケージとして取り込む。
import PackageDescription

let package = Package(
    name: "MHSimulatorCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MHSimulatorCore", targets: ["MHSimulatorCore"]),
    ],
    targets: [
        // Debugビルドでも最適化する: 検索・逆引きは-Ononeだと実測18倍遅く、
        // 実機Debug確認で時間予算(最大256秒)に届かないため(2026-09-01)。
        // Coreをブレークポイントで追いたいときはこの行を一時的に外す
        .target(
            name: "MHSimulatorCore",
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "MHSimulatorCoreTests", dependencies: ["MHSimulatorCore"]),
    ]
)
