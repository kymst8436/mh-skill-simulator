import SwiftUI
import MHSimulatorCore

/// 情報タブ(画面設計4.8)
struct InfoView: View {
    let dependencies: AppDependencies
    private let proStore = ProStore.shared

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Pro版へのアップグレード導線(情報タブ最上部に強調カードで表示。2026-08-29追加)
                        proCard
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .mhEntrance(0)

                        supportSection
                            .mhEntrance(1)

                        Group {
                            MHSectionHeader(title: String(localized: "このアプリについて"))
                                .padding(.top, 20)
                            MHCard {
                                VStack(spacing: 0) {
                                    infoRow(String(localized: "バージョン"), appVersion)
                                    separator
                                    infoRow(String(localized: "ゲームデータ"), String(dependencies.master.sourceCommit.prefix(7)))
                                    separator
                                    infoRow(String(localized: "護石規則データ"), dependencies.master.charmRulesVersion)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 7)
                        }
                        .mhEntrance(2)

                        MHCard {
                            NavigationLink {
                                CreditsView()
                            } label: {
                                HStack {
                                    Text("権利表記・クレジット")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.mhTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.mhTextTertiary)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .mhEntrance(3)

                        Text("本アプリは非公式のファンメイドアプリです")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .padding(.horizontal, 32)
                            .padding(.top, 10)
                            .mhEntrance(4)

                        #if DEBUG
                        developerSection
                            .mhEntrance(5)
                        #endif
                    }
                    .padding(.bottom, 24)
                }
            }
            .mhNavigationTitle(String(localized: "情報"))
        }
    }

    // MARK: - お問合せ・レビュー

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("機能追加・改善要望・不具合報告はこちらから")
                .font(.system(size: 12))
                .foregroundStyle(Color.mhTextTertiary)
                .padding(.horizontal, 32)
                .padding(.top, 20)
            MHCard {
                VStack(spacing: 0) {
                    linkRow(String(localized: "お問合せ"), url: SupportLinks.contactURL)
                    separator
                    linkRow(String(localized: "レビューを書く"), url: SupportLinks.writeReviewURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
        }
    }

    /// 外部リンク行。URL未設定の間は「準備中」表示になる(LegalLinksと同じ方式)
    @ViewBuilder
    private func linkRow(_ title: String, url: URL?) -> some View {
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

    /// Pro版アップグレードの強調カード(アンバー面の縁取り+ウォッシュ背景で通常カードより目立たせる)
    private var proCard: some View {
        NavigationLink {
            ProPurchaseView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: proStore.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.mhAccent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(proStore.isPro
                        ? String(localized: "Pro版をご利用中")
                        : String(localized: "Pro版にアップグレード"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mhTitleGold)
                    Text(proStore.isPro
                        ? String(localized: "マイセット上限なし・全ての広告が非表示")
                        : String(localized: "マイセット上限なし・全ての広告が非表示に"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mhAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.mhAccentWash)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.mhAccentDim, lineWidth: 1)
            )
        }
    }

    #if DEBUG
    /// 開発者ツール(DEBUGビルド限定。本番ビルドにはセクションごと存在せず、常にStoreKitの購入状態が参照される)
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MHSectionHeader(title: "開発者ツール(デバッグビルドのみ)")
                .padding(.top, 28)
            MHCard {
                VStack(spacing: 0) {
                    debugModeRow("StoreKitの購入状態を参照", mode: .storeKit)
                    separator
                    debugModeRow("Pro版として動作", mode: .forcePro)
                    separator
                    debugModeRow("無料版として動作", mode: .forceFree)
                    separator
                    infoRow("StoreKit購入状態", proStore.entitledPro ? "Pro版" : "未購入")
                    separator
                    coachMarkResetRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            Text("本番ビルドではこの設定は存在せず、常にStoreKitの購入状態のみが参照されます")
                .font(.system(size: 11))
                .foregroundStyle(Color.mhTextTertiary)
                .padding(.horizontal, 32)
                .padding(.top, 6)
        }
    }

    /// コーチマーク表示済みフラグを消す(該当タブを開き直すと再表示される)
    private var coachMarkResetRow: some View {
        Button {
            CoachMarkCenter.shared.resetAll()
        } label: {
            HStack {
                Text("コーチマークをリセット")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func debugModeRow(_ title: String, mode: ProStore.DebugProMode) -> some View {
        Button {
            proStore.debugProMode = mode
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhTextPrimary)
                Spacer()
                if proStore.debugProMode == mode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mhAccent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
    #endif

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

/// 権利表記(画面設計4.9。文言は2026-08-23決定)
struct CreditsView: View {
    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(String(localized: "著作権について"), String(localized: """
                    本アプリは非公式のファンメイドアプリです。ゲームの開発元・販売元および関連会社とは一切関係ありません。
                    ゲームデータ・アイコン等のゲーム由来コンテンツの著作権は各権利者に帰属します。
                    権利者からの申し立てがあった場合、本アプリは速やかに公開を停止します。
                    """))
                    .mhEntrance(0)
                    section(String(localized: "データ出典"), String(localized: """
                    データ: mhdb-wilds-data (LartTyler) を加工して使用
                    https://github.com/LartTyler/mhdb-wilds-data
                    """))
                    .mhEntrance(1)
                    section(String(localized: "鑑定護石の抽選規則データについて"), String(localized: """
                    出現パターンはコミュニティの解析情報をもとに構成しています。実際のゲーム内容と異なる場合があります。
                    """))
                    .mhEntrance(2)
                    section(String(localized: "アイコン素材"), String(localized: """
                    武器種・防具部位・護石アイコン: MHW_Icons_SVG (OthelloRhin, MIT License) を配色変更のうえ使用
                    https://github.com/OthelloRhin/MHW_Icons_SVG
                    """))
                    .mhEntrance(3)
                    section(String(localized: "免責"), String(localized: """
                    本アプリの利用により生じたいかなる損害についても、開発者は責任を負いません。
                    """))
                    .mhEntrance(4)
                }
                .padding(16)
            }
        }
        .mhNavigationTitle(String(localized: "権利表記"))
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.mhTextPrimary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Color.mhTextSecondary)
                .lineSpacing(4)
        }
    }
}
