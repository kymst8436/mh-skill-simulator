import SwiftUI
import StoreKit

/// Pro版の購入画面(2026-08-29追加)。情報タブからのpushと、マイセット上限アラートからのsheetの両方で使う。
/// sheetで出す場合はNavigationStackで包む
struct ProPurchaseView: View {
    private let store = ProStore.shared

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MHSectionHeader(title: String(localized: "Pro版でできること"))
                            .padding(.top, 20)
                        benefitsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 7)
                            .mhEntrance(0)

                        if store.isPro {
                            purchasedCard
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .mhEntrance(1)
                        }

                        legalSection
                            .mhEntrance(2)

                        restoreRow
                            .padding(.top, 14)
                            .mhEntrance(3)
                    }
                    .padding(.bottom, 24)
                }
                if !store.isPro {
                    purchaseBar
                }
            }
        }
        .mhNavigationTitle(String(localized: "Pro版"))
        .task { await store.loadProductIfNeeded() }
        .alert(
            store.purchaseErrorMessage ?? "",
            isPresented: Binding(
                get: { store.purchaseErrorMessage != nil },
                set: { if !$0 { store.purchaseErrorMessage = nil } })
        ) {
            Button("OK") {}
        }
    }

    // MARK: - 特典

    private var benefitsCard: some View {
        MHCard {
            VStack(spacing: 0) {
                benefitRow(
                    systemImage: "bookmark.fill",
                    title: String(localized: "マイセットの上限なし"),
                    detail: String(localized: "無料版の上限\(ProStore.freeMySetLimit)個の制限なく保存できます"))
                separator
                benefitRow(
                    systemImage: "checkmark.seal.fill",
                    title: String(localized: "全ての広告が非表示"),
                    detail: String(localized: "バナー・検索時・装備詳細の広告が表示されなくなり、左上の広告非表示ボタンも不要になります"))
            }
        }
    }

    private func benefitRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.mhAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mhTextPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var purchasedCard: some View {
        MHCard {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.mhAccent)
                Text("Pro版をご利用中です")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
            }
            .padding(14)
        }
    }

    // MARK: - 規約リンク(作成中。LegalLinksにURLを入れると開けるようになる)

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MHSectionHeader(title: String(localized: "規約"))
                .padding(.top, 20)
            MHCard {
                VStack(spacing: 0) {
                    legalRow(String(localized: "プライバシーポリシー"), url: LegalLinks.privacyPolicyURL)
                    separator
                    legalRow(String(localized: "利用規約"), url: LegalLinks.termsOfUseURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
        }
    }

    @ViewBuilder
    private func legalRow(_ title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mhTextPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mhTextTertiary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
        } else {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextSecondary)
                Spacer()
                Text("準備中")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
        }
    }

    // MARK: - 購入・復元

    private var restoreRow: some View {
        HStack {
            Spacer()
            Button {
                Task { await store.restore() }
            } label: {
                if store.phase == .restoring {
                    ProgressView().tint(Color.mhAccent)
                } else {
                    Text("購入を復元")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mhAccent)
                }
            }
            .disabled(store.phase != .idle)
            Spacer()
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 6) {
            MHPrimaryButton(
                title: purchaseButtonTitle,
                isEnabled: store.phase == .idle,
                isRunning: store.phase == .purchasing
            ) {
                Task { await store.purchase() }
            }
            Text("お支払いは1回のみです(買い切り)")
                .font(.system(size: 12))
                .foregroundStyle(Color.mhTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackgroundElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    private var purchaseButtonTitle: String {
        if let price = store.product?.displayPrice {
            return String(localized: "Pro版を購入 \(price)")
        }
        return String(localized: "Pro版を購入")
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }
}
