import SwiftUI
import MHSimulatorCore

/// 情報タブ(画面設計4.8)
struct InfoView: View {
    let dependencies: AppDependencies

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
                        MHSectionHeader(title: "このアプリについて")
                            .padding(.top, 20)
                        MHCard {
                            VStack(spacing: 0) {
                                infoRow("バージョン", appVersion)
                                separator
                                infoRow("ゲームデータ", String(dependencies.master.sourceCommit.prefix(7)))
                                separator
                                infoRow("護石規則データ", dependencies.master.charmRulesVersion)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 7)

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

                        Text("本アプリは非公式のファンメイドアプリです")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mhTextTertiary)
                            .padding(.horizontal, 32)
                            .padding(.top, 10)
                    }
                    .padding(.bottom, 24)
                }
            }
            .mhNavigationTitle("情報")
            .safeAreaInset(edge: .bottom) { AdBannerView() }
        }
    }

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
                    section("著作権について", """
                    本アプリは非公式のファンメイドアプリです。株式会社カプコンおよび関連会社とは一切関係ありません。
                    ゲームデータ・アイコン等のゲーム由来コンテンツの著作権は株式会社カプコンに帰属します。
                    権利者からの申し立てがあった場合、本アプリは速やかに公開を停止します。
                    """)
                    section("データ出典", """
                    データ: mhdb-wilds-data (LartTyler) を加工して使用
                    https://github.com/LartTyler/mhdb-wilds-data
                    """)
                    section("鑑定護石の抽選規則データについて", """
                    出現パターンはコミュニティの解析情報をもとに構成しています。実際のゲーム内容と異なる場合があります。
                    """)
                    section("免責", """
                    本アプリの利用により生じたいかなる損害についても、開発者は責任を負いません。
                    """)
                }
                .padding(16)
            }
        }
        .mhNavigationTitle("権利表記")
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
