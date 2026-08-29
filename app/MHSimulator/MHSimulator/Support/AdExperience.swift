import Foundation
import Observation
import GoogleMobileAds

/// 広告非表示(リワード報酬)の状態管理(画面設計§2 2026-08-29追加)。
/// 報酬1つ=8時間の全広告非表示。3つ分までスタック可能で上限は現在時刻から24時間。
/// 期限はUserDefaultsで永続化し、期限中は広告のロード自体を行わない
@Observable
final class AdFreeCenter {
    static let shared = AdFreeCenter()

    static let hoursPerReward = 8
    static let maxHours = 24  // 報酬3つ分

    private static let expiryKey = "adFree.expiry"

    /// 全広告を非表示にすべきか(リワード期限内またはPro版。2026-08-29 Pro版追加)
    var isAdFree: Bool { isRewardActive || ProStore.shared.isPro }

    /// リワード報酬による非表示が有効か(期限到来で自動的にfalseへ戻る)
    private(set) var isRewardActive = false
    private var expiry: Date?
    private var expiryTask: Task<Void, Never>?

    private init() {
        expiry = UserDefaults.standard.object(forKey: Self.expiryKey) as? Date
        revalidate()
    }

    /// リワード報酬1つ分(8時間)を加算。既存の残り時間に積み増し、現在時刻+24時間で頭打ち
    func grantReward(now: Date = Date()) {
        let base = max(now, expiry ?? now)
        let granted = min(
            base.addingTimeInterval(TimeInterval(Self.hoursPerReward) * 3600),
            now.addingTimeInterval(TimeInterval(Self.maxHours) * 3600))
        expiry = granted
        UserDefaults.standard.set(granted, forKey: Self.expiryKey)
        revalidate()
    }

    /// 残り時間(期限内のときのみ)
    func remaining(now: Date = Date()) -> TimeInterval? {
        guard let expiry, expiry > now else { return nil }
        return expiry.timeIntervalSince(now)
    }

    /// これ以上再生しても残り時間が増えない状態か(上限24時間に到達)
    func isAtStackLimit(now: Date = Date()) -> Bool {
        guard let remaining = remaining(now: now) else { return false }
        return remaining >= TimeInterval(Self.maxHours) * 3600 - 60
    }

    /// 期限からisRewardActiveを再評価し、期限到来で自動復帰するタイマーを張り直す
    private func revalidate() {
        expiryTask?.cancel()
        guard let expiry, expiry > Date() else {
            isRewardActive = false
            return
        }
        isRewardActive = true
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.revalidate()
        }
    }
}

/// インタースティシャル広告の頻度制御(画面設計§2 2026-08-29追加)。
/// 「検索する」3回に1回、かつ前回表示から5分以上経過しているとき、
/// 検索結果から検索条件に戻るタイミングで表示する(検索中・結果表示は妨げない)
final class InterstitialAdCoordinator {
    static let shared = InterstitialAdCoordinator()

    private static let searchesPerAd = 3
    private static let minInterval: TimeInterval = 5 * 60
    private static let countKey = "interstitial.searchCount"
    private static let lastShownKey = "interstitial.lastShownAt"

    private var loadedAd: InterstitialAd?
    private var isLoading = false

    private init() {}

    /// 「検索する」タップのたびに呼ぶ。カウントを進め、表示に備えて事前ロードする
    func recordSearch() {
        guard !AdFreeCenter.shared.isAdFree else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.countKey) + 1, forKey: Self.countKey)
        loadIfNeeded()
    }

    /// 検索結果から検索条件に戻ったときに呼ぶ。条件を満たせば表示する
    func presentAfterReturnIfEligible() {
        guard isEligible, let ad = loadedAd else { return }
        loadedAd = nil
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: Self.countKey)
        defaults.set(Date(), forKey: Self.lastShownKey)
        Task {
            // 画面ポップのアニメーションと重ならないよう一拍置く
            try? await Task.sleep(for: .milliseconds(400))
            ad.present(from: nil)
        }
    }

    private var isEligible: Bool {
        guard !AdFreeCenter.shared.isAdFree else { return false }
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.countKey) >= Self.searchesPerAd else { return false }
        if let last = defaults.object(forKey: Self.lastShownKey) as? Date,
           Date().timeIntervalSince(last) < Self.minInterval {
            return false
        }
        return true
    }

    private func loadIfNeeded() {
        guard loadedAd == nil, !isLoading, !AdFreeCenter.shared.isAdFree else { return }
        isLoading = true
        InterstitialAd.load(with: AdConfig.interstitialUnitId, request: Request()) { [weak self] ad, _ in
            guard let self else { return }
            isLoading = false
            loadedAd = ad  // 失敗時はnilのまま(次のrecordSearchで再試行)
        }
    }
}

/// リワード広告のロード・表示(広告非表示sheet用。画面設計§2 2026-08-29追加)。
/// 報酬「Reward」×1につきAdFreeCenterへ8時間分を付与する
@Observable
final class RewardedAdController: NSObject, FullScreenContentDelegate {
    enum Phase {
        case loading
        case ready
        case presenting
        case failed
    }

    private(set) var phase: Phase = .loading
    private var loadedAd: RewardedAd?
    private var isLoading = false

    func loadIfNeeded() {
        guard !isLoading, loadedAd == nil, phase != .presenting else { return }
        isLoading = true
        phase = .loading
        RewardedAd.load(with: AdConfig.rewardedUnitId, request: Request()) { [weak self] ad, _ in
            guard let self else { return }
            isLoading = false
            if let ad {
                loadedAd = ad
                phase = .ready
            } else {
                phase = .failed
            }
        }
    }

    func retryLoad() {
        guard phase == .failed else { return }
        loadIfNeeded()
    }

    /// 再生。報酬付与時にonRewardを呼ぶ
    func present(onReward: @escaping () -> Void) {
        guard phase == .ready, let ad = loadedAd else { return }
        loadedAd = nil
        phase = .presenting
        // デリゲート設定はMainActor文脈で行う(nonisolatedなロード完了クロージャ内だと隔離違反警告)
        ad.fullScreenContentDelegate = self
        ad.present(from: nil) {
            onReward()
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 閉じたら次の再生(スタック)に備えて再ロード
        loadedAd = nil
        phase = .loading
        loadIfNeeded()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        loadedAd = nil
        phase = .failed
    }
}
