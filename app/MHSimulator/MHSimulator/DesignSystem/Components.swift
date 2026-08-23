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

/// チップ等を折り返して並べる簡易フローレイアウト(SE幅での横はみ出し防止)
struct MHFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), origins)
    }
}

/// ナビバー用テキストボタン(DESIGN.md §5。OS標準のガラスカプセルは使わない)
struct MHToolbarButton: ToolbarContent {
    let title: String
    var placement: ToolbarItemPlacement = .topBarTrailing
    var isEnabled: Bool = true
    var isProminent: Bool = false
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) { button }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { button }
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: isProminent ? .semibold : .regular))
                .foregroundStyle(Color.mhAccent)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// カスタム戻るボタン(無地シェブロン。DESIGN.md §5)。
/// 使う画面では .navigationBarBackButtonHidden(true) とセットで指定する
struct MHBackButton: ToolbarContent {
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
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mhAccent)
        }
    }
}

/// 標準戻るボタン非表示でもエッジスワイプバックを維持する(DESIGN.md §5 MHBackButton)
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// アプリのタブ
enum MHTab: Hashable {
    case search, charms, info
}

/// 自作タブバー(全幅フラット。OS標準TabBarは使わない。DESIGN.md §4)
struct MHTabBar: View {
    @Binding var selection: MHTab

    var body: some View {
        HStack(spacing: 0) {
            item(.search, icon: "magnifyingglass", label: "検索")
            item(.charms, icon: "seal", label: "護石")
            item(.info, icon: "info.circle", label: "情報")
        }
        .padding(.top, 7)
        .padding(.bottom, 2)
        .background(Color.mhBackgroundElevated.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mhHairline).frame(height: 1)
        }
    }

    private func item(_ tab: MHTab, icon: String, label: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selection == tab ? Color.mhAccent : Color.mhTextTertiary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

/// 武器種の横スクロールチップリスト(検索条件・武器選択の上部)。
/// 抽出アイコン導入(Phase 5-2)までは武器種名のテキストチップで表現する
struct WeaponKindChips: View {
    /// アーティア(カスタム武器)枠のチップ識別子
    static let artianKind = "artian"

    /// 現在選択中の武器種(nil = 未選択)
    var selectedKind: String?
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "アーティア", kind: Self.artianKind, isSelected: selectedKind == Self.artianKind)
                ForEach(MHFormat.weaponKinds, id: \.self) { kind in
                    chip(label: MHFormat.weaponKindLabel(kind), kind: kind, isSelected: selectedKind == kind)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(label: String, kind: String, isSelected: Bool) -> some View {
        Button {
            onTap(kind)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.mhAccentSoft : Color.mhTextSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isSelected ? Color.mhAccentWash : Color.mhSurface)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(isSelected ? Color.mhAccentDim : Color.mhHairline, lineWidth: 1)
                )
        }
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
