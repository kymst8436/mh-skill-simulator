import SwiftUI
import Combine
import GoogleMobileAds
import Observation

/// ネイティブ広告のローダ(1スロット=1広告。読み込み失敗時は畳む)
@Observable
final class NativeAdBox: NSObject, NativeAdLoaderDelegate {
    private(set) var nativeAd: NativeAd?
    private(set) var failed = false
    private var adLoader: AdLoader?

    func loadIfNeeded(adUnitId: String) {
        guard adLoader == nil else { return }
        let loader = AdLoader(
            adUnitID: adUnitId,
            rootViewController: nil,
            adTypes: [.native],
            options: nil)
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    /// 定期更新(表示中の広告がある場合のみ。ロード中・失敗時は触らない)
    func refreshIfDisplayed(adUnitId: String) {
        guard nativeAd != nil else { return }
        adLoader = nil
        loadIfNeeded(adUnitId: adUnitId)
    }

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        self.nativeAd = nativeAd
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        failed = true
    }
}

/// 検索結果一覧に挟むネイティブ広告カード(画面設計§2。2026-08-24追加)。
/// 読み込み完了までは何も表示せず、失敗時はスロットごと畳む
struct NativeAdSlot: View {
    /// 広告ユニット(既定は検索結果一覧用。装備詳細は detailNativeAdUnitId を渡す)
    var adUnitId: String = AdConfig.nativeAdUnitId
    @State private var box = NativeAdBox()
    @Environment(\.scenePhase) private var scenePhase

    /// 定期更新の間隔(2026-08-24決定。バナー公式レンジ30〜120sより保守的)
    private static let refreshInterval: TimeInterval = 90

    var body: some View {
        // 空表示でもonAppearが発火するよう、常に幅を持つコンテナにする
        VStack(spacing: 0) {
            if let ad = box.nativeAd {
                MHCard {
                    NativeAdRepresentable(nativeAd: ad)
                        .frame(maxWidth: .infinity)
                        .frame(height: 144)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { box.loadIfNeeded(adUnitId: adUnitId) }
        .task {
            // 定期更新。taskは非表示化で自動キャンセルされるため、
            // 「画面に見えている間だけ」が構造的に保証される(無効インプレッション対策)。
            // アプリが前面でない間(scenePhase != .active)は更新しない
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled, scenePhase == .active else { continue }
                box.refreshIfDisplayed(adUnitId: adUnitId)
            }
        }
    }
}

/// GADネイティブ広告のUIKitレイアウト(DESIGN.mdトークンに合わせた暗色カード)
private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        let badge = UILabel()
        badge.text = "広告"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = UIColor(Color.mhBackground)
        badge.backgroundColor = UIColor(Color.mhTextTertiary)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 2
        badge.clipsToBounds = true

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 15, weight: .semibold)
        headline.textColor = UIColor(Color.mhTextPrimary)
        headline.numberOfLines = 1

        let body = UILabel()
        body.font = .systemFont(ofSize: 12)
        body.textColor = UIColor(Color.mhTextSecondary)
        body.numberOfLines = 2

        let media = MediaView()
        media.clipsToBounds = true
        media.contentMode = .scaleAspectFill
        media.layer.cornerRadius = 2

        var ctaConfig = UIButton.Configuration.filled()
        ctaConfig.baseBackgroundColor = UIColor(Color.mhAccent)
        ctaConfig.baseForegroundColor = UIColor(Color.mhOnAccent)
        ctaConfig.background.cornerRadius = 2
        ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let cta = UIButton(configuration: ctaConfig)
        cta.isUserInteractionEnabled = false  // タップはNativeAdViewが処理する

        for view in [badge, headline, body, media, cta] {
            view.translatesAutoresizingMaskIntoConstraints = false
            adView.addSubview(view)
        }

        // 結果カードに馴染むコンパクト横並び(左: メディア100pt角 / 右: バッジ+見出し・本文・CTA)
        NSLayoutConstraint.activate([
            media.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            media.centerYAnchor.constraint(equalTo: adView.centerYAnchor),
            media.widthAnchor.constraint(equalToConstant: 120),
            media.heightAnchor.constraint(equalToConstant: 120),

            badge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            badge.leadingAnchor.constraint(equalTo: media.trailingAnchor, constant: 12),
            badge.widthAnchor.constraint(equalToConstant: 34),
            badge.heightAnchor.constraint(equalToConstant: 16),

            headline.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            headline.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            headline.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),

            body.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: media.trailingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),

            cta.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
            cta.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            cta.heightAnchor.constraint(equalToConstant: 28),
        ])

        adView.headlineView = headline
        adView.bodyView = body
        adView.mediaView = media
        adView.callToActionView = cta
        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = nativeAd.headline
        (adView.bodyView as? UILabel)?.text = nativeAd.body
        adView.mediaView?.mediaContent = nativeAd.mediaContent
        if let cta = adView.callToActionView as? UIButton {
            cta.configuration?.title = nativeAd.callToAction
            cta.configuration?.attributedTitle = AttributedString(
                nativeAd.callToAction ?? "",
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]))
        }
        adView.nativeAd = nativeAd
    }
}
