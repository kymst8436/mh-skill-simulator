import SwiftUI

// 共通コンポーネント(Docs/DESIGN.md §5)。画面ローカルでの再実装をしないこと。

/// ナビゲーションタイトル(菱形モチーフ+明朝)。モチーフはここ以外に置かない(§1-2)
struct MHScreenTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(Color.mhAccent)
                .frame(width: 6, height: 6)
                .rotationEffect(.degrees(45))
            Text(title)
                .font(MHFont.screenTitle)
                .tracking(1.5)
                .foregroundStyle(Color.mhTitleGold)
        }
    }
}

extension View {
    /// 画面タイトルの標準設定。inline表示+MHScreenTitle
    func mhNavigationTitle(_ title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MHScreenTitle(title: title)
                }
            }
    }
}

/// カード面(mhSurface+ヘアライン枠+角丸2)
struct MHCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color.mhSurface)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.mhHairline, lineWidth: 1)
            )
    }
}

/// 主ボタン(高さ50・アンバー面・明朝ラベル)。無効時はopacity 0.35(§6)
struct MHPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isRunning: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isRunning {
                    ProgressView().tint(Color.mhOnAccent)
                } else {
                    Text(title)
                        .font(MHFont.button)
                        .tracking(3)
                        .foregroundStyle(Color.mhOnAccent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.mhAccent)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .disabled(!isEnabled || isRunning)
        .opacity(isEnabled || isRunning ? 1 : 0.35)
    }
}

/// レア度バッジ「R<n>」(§5)
struct RarityBadge: View {
    let rarity: Int

    var body: some View {
        Text("R\(rarity)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.mhBackground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.mhRarity(rarity))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// スキルチップ(枠のみ・塗りなし)。isCondition=trueで条件スキル強調
struct SkillChip: View {
    let text: String
    var isCondition: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(isCondition ? Color.mhAccentSoft : Color.mhTextSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isCondition ? Color.mhAccentDim : Color.mhHairline, lineWidth: 1)
            )
    }
}

/// セクション見出し(右端にアクションを置ける)
struct MHSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12))
                .tracking(1)
                .foregroundStyle(Color.mhTextTertiary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhAccent)
            }
        }
        .padding(.horizontal, 32)
    }
}

/// −/+の正方ボタン(iOS標準Stepperは使わない。DESIGN.md §5)
struct MHStepper: View {
    var canDecrement: Bool
    var canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            stepButton("minus", enabled: canDecrement, action: onDecrement)
            stepButton("plus", enabled: canIncrement, action: onIncrement)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.mhTextSecondary)
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.mhHairline, lineWidth: 1)
                )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// 空状態(アイコン+見出し+誘導文+主アクション)。DESIGN.md §5
struct MHEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.mhTextTertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mhTextPrimary)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mhAccent)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
