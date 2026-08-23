import Foundation

// 並行実行(アプリのバックグラウンド検索)のためのSendable適合。
// 3クラスとも初期化後に不変(格納プロパティは全てlet)のため@unchecked。
extension MasterDatabase: @unchecked Sendable {}
extension SearchEngine: @unchecked Sendable {}
extension CharmOracle: @unchecked Sendable {}
