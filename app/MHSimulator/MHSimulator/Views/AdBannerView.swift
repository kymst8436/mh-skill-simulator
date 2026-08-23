import SwiftUI
import GoogleMobileAds

/// 広告設定(画面設計§2。タブごとにユニットを分ける。2026-08-24ユーザー発行)
enum AdConfig {
    #if DEBUG
    // 開発中はGoogle公式テストユニット(本番ユニットへの誤クリック防止)
    static let searchBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    static let charmBannerUnitId = "ca-app-pub-3940256099942544/2934735716"
    #else
    static let searchBannerUnitId = "ca-app-pub-4797364772307900/3487951268"
    static let charmBannerUnitId = "ca-app-pub-4797364772307900/9861787926"
    #endif
}

/// バナー広告(高さ50固定・ナビバー直下・読み込み失敗時は畳む。DESIGN.md §4)
struct AdBannerView: View {
    let adUnitId: String
    @State private var isCollapsed = false

    var body: some View {
        if !isCollapsed {
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
