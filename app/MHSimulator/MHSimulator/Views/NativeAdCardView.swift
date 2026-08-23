import SwiftUI
import GoogleMobileAds
import Observation

/// ネイティブ広告のローダ(1スロット=1広告。読み込み失敗時は畳む)
@Observable
final class NativeAdBox: NSObject, NativeAdLoaderDelegate {
    private(set) var nativeAd: NativeAd?
    private(set) var failed = false
    private var adLoader: AdLoader?

    func loadIfNeeded() {
        guard adLoader == nil else { return }
        let loader = AdLoader(
            adUnitID: AdConfig.nativeAdUnitId,
            rootViewController: nil,
            adTypes: [.native],
            options: nil)
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
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
    @State private var box = NativeAdBox()

    var body: some View {
        // 空表示でもonAppearが発火するよう、常に幅を持つコンテナにする
        VStack(spacing: 0) {
            if let ad = box.nativeAd {
                MHCard {
                    NativeAdRepresentable(nativeAd: ad)
                        .frame(maxWidth: .infinity)
                        .frame(height: 290)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { box.loadIfNeeded() }
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

        let cta = UIButton(type: .system)
        cta.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cta.setTitleColor(UIColor(Color.mhOnAccent), for: .normal)
        cta.backgroundColor = UIColor(Color.mhAccent)
        cta.layer.cornerRadius = 2
        cta.isUserInteractionEnabled = false  // タップはNativeAdViewが処理する

        for view in [badge, headline, body, media, cta] {
            view.translatesAutoresizingMaskIntoConstraints = false
            adView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            badge.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            badge.widthAnchor.constraint(equalToConstant: 34),
            badge.heightAnchor.constraint(equalToConstant: 16),

            headline.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            headline.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            headline.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),

            media.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 10),
            media.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            media.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            media.heightAnchor.constraint(equalToConstant: 150),

            body.topAnchor.constraint(equalTo: media.bottomAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),

            cta.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            cta.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            cta.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            cta.heightAnchor.constraint(equalToConstant: 40),
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
            cta.setTitle(nativeAd.callToAction, for: .normal)
        }
        adView.nativeAd = nativeAd
    }
}
