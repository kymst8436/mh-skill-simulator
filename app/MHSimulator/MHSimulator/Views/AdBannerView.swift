import SwiftUI
import GoogleMobileAds

/// 広告設定
enum AdConfig {
    /// バナー広告ユニットID。
    /// TODO: AdMobコンソールでバナーユニットを作成したら本番IDに差し替える。
    /// 現在はGoogle公式のテスト用バナーユニット(必ずテスト広告が返る)
    static let bannerAdUnitId = "ca-app-pub-3940256099942544/2934735716"
}

/// バナー広告(高さ50固定・読み込み失敗時は畳む。画面設計§2・DESIGN.md §5)
struct AdBannerView: View {
    @State private var isCollapsed = false

    var body: some View {
        if !isCollapsed {
            BannerRepresentable(onFailure: { isCollapsed = true },
                                onSuccess: { isCollapsed = false })
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(Color.mhBackgroundElevated)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.mhHairline).frame(height: 1)
                }
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {
    let onFailure: () -> Void
    let onSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure, onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerAdUnitId
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
