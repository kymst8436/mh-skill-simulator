import SwiftUI

/// 広告非表示ボタンの自作アイコン(「AD」バッジにバツ印を重ねた見た目)
struct AdFreeIcon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("AD")
                .font(.system(size: 9, weight: .heavy))
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(lineWidth: 1.3)
                )
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .heavy))
                .offset(x: 13, y: 8)
        }
        .frame(width: 26, height: 21, alignment: .topLeading)
    }
}

/// 検索タブ左上の広告非表示ボタン(画面設計§2 2026-08-29追加)
struct AdFreeToolbarButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { button }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { button }
        }
    }

    private var button: some View {
        Button(action: action) {
            AdFreeIcon()
                .foregroundStyle(Color.mhAccent)
        }
        .accessibilityLabel("広告を非表示にする")
    }
}

/// 広告非表示sheet(画面設計§2 2026-08-29追加)。
/// リワード広告1回=8時間の全広告非表示。3回分までスタック可(最大24時間)
struct AdFreeSheetView: View {
    @State private var rewarded = RewardedAdController()
    private let center = AdFreeCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MHCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("リワード広告を再生することで8時間の間全ての広告が非表示となります。")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.mhTextPrimary)
                            Text("報酬は3回分までスタックでき、最大24時間まで延長できます。")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.mhTextSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    remainingCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if rewarded.phase == .failed {
                        failedRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 24)
            }
            playButtonBar
        }
        .background(Color.mhBackgroundElevated)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium])
        .task { rewarded.loadIfNeeded() }
    }

    private var header: some View {
        Text("広告の非表示")
            .font(MHFont.screenTitle)
            .tracking(1.5)
            .foregroundStyle(Color.mhTitleGold)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    /// 非表示期間中の残り時間表示(1分ごとに更新)
    @ViewBuilder
    private var remainingCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if let remaining = center.remaining(now: timeline.date) {
                MHCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.mhAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全ての広告を非表示中")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.mhTextPrimary)
                            Text("残り \(Self.remainingText(remaining))")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.mhTextSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
        }
    }

    private var failedRow: some View {
        HStack(spacing: 8) {
            Text("広告を読み込めませんでした")
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextSecondary)
            Button("再試行") { rewarded.retryLoad() }
                .font(.system(size: 13))
                .foregroundStyle(Color.mhAccent)
        }
    }

    private var playButtonBar: some View {
        // 上限判定も1分ごとに再評価(時間経過で上限を割ったらボタンを再度有効化)
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            playButtonBarContent(atLimit: center.isAtStackLimit(now: timeline.date))
        }
    }

    private func playButtonBarContent(atLimit: Bool) -> some View {
        VStack(spacing: 6) {
            MHPrimaryButton(
                title: "再生して全ての広告を非表示",
                isEnabled: rewarded.phase == .ready && !atLimit,
                isRunning: rewarded.phase == .loading || rewarded.phase == .presenting
            ) {
                rewarded.present { AdFreeCenter.shared.grantReward() }
            }
            if atLimit {
                Text("非表示時間が上限(24時間)に達しています")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mhTextTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mhBackgroundElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairlineFaint).frame(height: 1)
        }
    }

    /// 残り時間の表示文字列(例「7時間59分」。分は切り上げで0分を出さない)
    private static func remainingText(_ remaining: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(remaining / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }
}
