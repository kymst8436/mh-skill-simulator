import SwiftUI

/// コーチマークで指し示す対象要素(2026-08-30追加)
nonisolated enum CoachMarkID: Hashable {
    case weaponSection
    case skillSection
    case searchSettingsButton
    case searchButton
    case adFreeButton
    case charmAddButton
    case wishlistTab
}

/// コーチマークのツアー(タブ単位で初回表示時に1回だけ流す)
nonisolated enum CoachMarkTour: String, CaseIterable {
    case search
    case charm

    var doneKey: String { "coachmark.\(rawValue).done" }
}

/// コーチマーク1ステップ分の内容
struct CoachMarkStep: Identifiable {
    let id: CoachMarkID
    let text: String
}

/// 初回起動時コーチマークの状態管理。
/// 対象要素の枠はcoachMarkTarget修飾子がglobal座標で随時報告し、
/// 表示済みフラグはUserDefaultsに永続化する
@Observable
final class CoachMarkCenter {
    static let shared = CoachMarkCenter()

    /// 対象要素の画面上の枠(globalスペース)
    var frames: [CoachMarkID: CGRect] = [:]
    private(set) var activeTour: CoachMarkTour?
    private(set) var steps: [CoachMarkStep] = []
    private(set) var stepIndex = 0

    private let defaults = UserDefaults.standard

    private init() {}

    var currentStep: CoachMarkStep? {
        guard activeTour != nil, steps.indices.contains(stepIndex) else { return nil }
        return steps[stepIndex]
    }

    var isLastStep: Bool { stepIndex >= steps.count - 1 }

    /// 未表示のツアーを開始する(表示済みなら何もしない)
    func startTourIfNeeded(_ tour: CoachMarkTour) {
        guard activeTour == nil, !defaults.bool(forKey: tour.doneKey) else { return }
        let built = makeSteps(tour)
        guard !built.isEmpty else { return }
        steps = built
        stepIndex = 0
        withAnimation(.easeOut(duration: 0.25)) { activeTour = tour }
    }

    /// 次のステップへ(最終ステップなら終了)
    func advance() {
        if isLastStep {
            finish()
        } else {
            withAnimation(.easeOut(duration: 0.25)) { stepIndex += 1 }
        }
    }

    /// ツアーを終了し表示済みとして記録する(スキップも同扱い)
    func finish() {
        if let tour = activeTour { defaults.set(true, forKey: tour.doneKey) }
        withAnimation(.easeOut(duration: 0.2)) { activeTour = nil }
        steps = []
        stepIndex = 0
    }

    #if DEBUG
    /// 表示済みフラグを消す(開発者ツール用。該当タブを開き直すと再表示される)
    func resetAll() {
        for tour in CoachMarkTour.allCases { defaults.removeObject(forKey: tour.doneKey) }
    }
    #endif

    private func makeSteps(_ tour: CoachMarkTour) -> [CoachMarkStep] {
        switch tour {
        case .search:
            var steps: [CoachMarkStep] = [
                CoachMarkStep(
                    id: .weaponSection,
                    text: String(localized: "使用したい武器を選択します。")),
                CoachMarkStep(
                    id: .skillSection,
                    text: String(localized: "欲しいスキルを選択します。\nスキルを長押しすると対象スキルの詳細が確認できます。")),
                CoachMarkStep(
                    id: .searchSettingsButton,
                    text: String(localized: "固定したい装備や、除外したい装備・装飾品がある場合は、こちらで検索設定を行います。")),
                CoachMarkStep(
                    id: .searchButton,
                    text: String(localized: "装備の組み合わせを検索します。")),
            ]
            // 広告非表示ボタンはPro版では存在しない(AdFreeToolbarButton参照)
            if !ProStore.shared.isPro {
                steps.append(CoachMarkStep(
                    id: .adFreeButton,
                    text: String(localized: "広告が煩わしい場合は、こちらから一定時間非表示にすることができます。")))
            }
            return steps
        case .charm:
            return [
                CoachMarkStep(
                    id: .charmAddButton,
                    text: String(localized: "所持している護石を登録します。\nゲーム画面をカメラでスキャンすることでも登録できます。")),
                CoachMarkStep(
                    id: .wishlistTab,
                    text: String(localized: "欲しい護石はウィッシュリストに登録しておきましょう。")),
            ]
        }
    }
}

extension View {
    /// コーチマーク対象として画面上の枠を登録する(nilなら何もしない)
    @ViewBuilder
    func coachMarkTarget(_ id: CoachMarkID?) -> some View {
        if let id {
            onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                CoachMarkCenter.shared.frames[id] = frame
            }
        } else {
            self
        }
    }
}
