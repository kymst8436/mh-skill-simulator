import SwiftUI

/// 初回起動時コーチマークの表示(暗転+対象くり抜き+説明カード)。
/// MainTabView最上位のZStackに重ね、ナビバー・タブバーごと覆って操作をブロックする
struct CoachMarkOverlay: View {
    private let center = CoachMarkCenter.shared

    var body: some View {
        if let step = center.currentStep {
            GeometryReader { proxy in
                let bounds = proxy.frame(in: .global)
                let target = highlightRect(for: step.id, in: bounds)
                ZStack {
                    Color.black.opacity(0.6)
                        .reverseMask {
                            if let target {
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: target.width, height: target.height)
                                    .position(x: target.midX, y: target.midY)
                            }
                        }
                    if let target {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mhAccent, lineWidth: 2)
                            .frame(width: target.width, height: target.height)
                            .position(x: target.midX, y: target.midY)
                    }
                    card(step: step, target: target, in: bounds)
                }
                .contentShape(Rectangle())
                .onTapGesture { center.advance() }
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// 対象枠(global)を余白付きでオーバーレイのローカル座標へ変換する
    private func highlightRect(for id: CoachMarkID, in bounds: CGRect) -> CGRect? {
        guard let frame = center.frames[id], !frame.isEmpty else { return nil }
        return frame
            .insetBy(dx: -6, dy: -6)
            .offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            .intersection(CGRect(origin: .zero, size: bounds.size))
    }

    /// 説明カード。対象が画面上半分なら下に、下半分なら上に出す
    private func card(step: CoachMarkStep, target: CGRect?, in bounds: CGRect) -> some View {
        let placesBelow = (target?.midY ?? bounds.height / 2) < bounds.height * 0.5
        return VStack(alignment: .leading, spacing: 14) {
            Text(step.text)
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                Text(verbatim: "\(center.stepIndex + 1) / \(center.steps.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mhTextTertiary)
                Spacer()
                if !center.isLastStep {
                    Button {
                        center.finish()
                    } label: {
                        Text("スキップ")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mhTextSecondary)
                    }
                }
                Button {
                    center.advance()
                } label: {
                    Text(center.isLastStep ? String(localized: "完了") : String(localized: "次へ"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mhOnAccent)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 34)
                        .background(Color.mhAccent, in: Capsule())
                }
            }
        }
        .padding(16)
        .background(Color.mhBackgroundElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.mhHairlineFaint, lineWidth: 1))
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placesBelow ? .top : .bottom)
        .padding(.top, placesBelow ? (target?.maxY ?? 0) + 16 : 0)
        .padding(.bottom, placesBelow ? 0 : bounds.height - (target?.minY ?? bounds.height) + 16)
    }
}
