import Foundation
import Observation
import MHSimulatorCore

/// アプリ全体の依存一式(マスタDB+検索エンジン+逆引き)
struct AppDependencies {
    let master: MasterDatabase
    let engine: SearchEngine
    let oracle: CharmOracle
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

    func load() {
        guard case .loading = phase else { return }
        guard let url = Bundle.main.url(forResource: "bundled", withExtension: "db") else {
            phase = .failed
            return
        }
        do {
            let master = try MasterDatabase(path: url.path)
            let engine = SearchEngine(master: master)
            phase = .ready(AppDependencies(
                master: master,
                engine: engine,
                oracle: CharmOracle(engine: engine)))
        } catch {
            phase = .failed
        }
    }
}
