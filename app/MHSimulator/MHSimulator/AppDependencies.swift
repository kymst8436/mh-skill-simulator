import Foundation
import Observation
import MHSimulatorCore

/// アプリ全体の依存一式(マスタDB+検索エンジン+逆引き+ユーザーデータ)
struct AppDependencies {
    let master: MasterDatabase
    let engine: SearchEngine
    let oracle: CharmOracle
    let userStore: UserStore

    /// 所持護石の表示名(「攻撃Lv2・見切りLv1」)
    func charmDisplayName(_ charm: OwnedCharm) -> String {
        charm.skills
            .map { MHFormat.skillLine(master.skills[$0.skillId]?.name ?? "?", $0.level) }
            .joined(separator: "・")
    }

    /// 検索エンジンに渡す所持護石一覧
    func loadOwnedCharmsForSearch() -> [Charm] {
        let charms = (try? userStore.loadCharms()) ?? []
        return charms.map { $0.asCharm(name: charmDisplayName($0)) }
    }
}

/// 起動時読み込み(仕様5.2)。bundled.dbを開きintegrity_checkを通す。
/// 失敗時は全機能を読み取り不能状態にする(画面設計ダイアログ4)
@Observable
final class AppBootstrap {
    enum Phase {
        case loading
        case ready(AppDependencies)
        case failed
    }

    private(set) var phase: Phase = .loading
    /// user.db破損からの復旧が起きたか(画面設計 ダイアログ5「護石データを初期化しました」)
    var shouldNotifyUserDataRecovery = false

    func load() {
        guard case .loading = phase else { return }
        guard let url = Bundle.main.url(forResource: "bundled", withExtension: "db") else {
            phase = .failed
            return
        }
        do {
            let master = try MasterDatabase(path: url.path)
            let engine = SearchEngine(master: master)
            let userStore = try UserStore(path: Self.userDbPath())
            shouldNotifyUserDataRecovery = userStore.didRecoverFromCorruption
            phase = .ready(AppDependencies(
                master: master,
                engine: engine,
                oracle: CharmOracle(engine: engine),
                userStore: userStore))
        } catch {
            phase = .failed
        }
    }

    /// Application Support/MHSimulator/user.db(仕様5章。端末バックアップ対象領域)
    private static func userDbPath() throws -> String {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent("MHSimulator/user.db").path
    }
}
