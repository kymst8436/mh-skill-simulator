import SwiftUI
import GoogleMobileAds

/// 広告設定(画面設計§2。タブごとにユニットを分ける。2026-08-24ユーザー発行)
enum AdConfig {
    #if DEBUG
    // 開発中はGoogle公式テストユニット(本番ユニットへの誤クリック防止)
    static let searchBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let charmBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let mySetBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let toolsBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let nativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"
    static let detailNativeAdUnitId = "ca-app-pub-3940256099942544/3986624511"
    static let interstitialUnitId = "ca-app-pub-3940256099942544/4411468910"
    static let rewardedUnitId = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let searchBannerUnitId = "ca-app-pub-4797364772307900/3487951268"
    static let charmBannerUnitId = "ca-app-pub-4797364772307900/9861787926"
    static let mySetBannerUnitId = "ca-app-pub-4797364772307900/6182501598"
    static let toolsBannerUnitId = "ca-app-pub-4797364772307900/7218792223"
    static let nativeAdUnitId = "ca-app-pub-4797364772307900/3052836992"
    static let detailNativeAdUnitId = "ca-app-pub-4797364772307900/7840279766"
    static let interstitialUnitId = "ca-app-pub-4797364772307900/1062976209"
    static let rewardedUnitId = "ca-app-pub-4797364772307900/3695939059"
    #endif
}

/// バナー広告(高さ50固定・ナビバー直下・読み込み失敗時は畳む。DESIGN.md §4)
struct AdBannerView: View {
    let adUnitId: String
    @State private var isCollapsed = false

    var body: some View {
        // 広告非表示期間中はロードも表示もしない(画面設計§2 2026-08-29)
        if !AdFreeCenter.shared.isAdFree && !isCollapsed {
            BannerRepresentable(
                adUnitId: adUnitId,
                onFailure: { isCollapsed = true },
                onSuccess: { isCollapsed = false })
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(Color.mhBackgroundElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.mhHairline).frame(height: 1)
                }
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let adUnitId: String
    let onFailure: () -> Void
    let onSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure, onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitId
        banner.delegate = context.coordinator
        banner.backgroundColor = .clear
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        let onFailure: () -> Void
        let onSuccess: () -> Void

        init(onFailure: @escaping () -> Void, onSuccess: @escaping () -> Void) {
            self.onFailure = onFailure
            self.onSuccess = onSuccess
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onSuccess()
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onFailure()
        }
    }
}
