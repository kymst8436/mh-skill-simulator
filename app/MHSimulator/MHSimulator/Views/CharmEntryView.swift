import SwiftUI
import MHSimulatorCore

/// 護石入力sheet(画面設計4.7)。段階的に有効化される規則ベース入力補助
struct CharmEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let dependencies: AppDependencies
    let onSaved: () -> Void
    @State private var viewModel: CharmEntryViewModel
    @State private var showsDiscardDialog = false
    @State private var showsDuplicateAlert = false

    init(dependencies: AppDependencies, target: CharmEntryTarget, onSaved: @escaping () -> Void) {
        self.dependencies = dependencies
        self.onSaved = onSaved
        _viewModel = State(initialValue: CharmEntryViewModel(dependencies: dependencies, target: target))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mhBackground.ignoresSafeArea()
                if viewModel.rulesUnavailable {
                    MHEmptyState(
                        systemImage: "exclamationmark.triangle",
                        title: "護石データを更新してください")
                } else {
                    form
                }
            }
            .mhNavigationTitle(viewModel.isEditing ? "護石を編集" : "護石を登録")
            .toolbar {
                MHToolbarButton(title: "キャンセル", placement: .topBarLeading) {
                    if viewModel.isDirty { showsDiscardDialog = true } else { dismiss() }
                }
                MHToolbarButton(title: "保存", isEnabled: viewModel.canSave, isProminent: true) {
                    attemptSave()
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isDirty)
        .presentationDragIndicator(.visible)
        .confirmationDialog("入力内容を破棄しますか?", isPresented: $showsDiscardDialog, titleVisibility: .visible) {
            Button("破棄", role: .destructive) { dismiss() }
            Button("続ける", role: .cancel) {}
        }
        .alert("同じ護石が登録済みです", isPresented: $showsDuplicateAlert) {
            Button("登録する") { performSave() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("同じ護石を複数所持している場合はそのまま登録できます")
        }
    }

    private func attemptSave() {
        if viewModel.hasDuplicate() {
            showsDuplicateAlert = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        if viewModel.save() {
            onSaved()
            dismiss()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 入場モーション: セクション単位(DESIGN.md §7.5)
                Group {
                    MHSectionHeader(title: "スキル")
                        .padding(.top, 16)
                    MHCard {
                        VStack(spacing: 0) {
                            skillRow(position: 0, label: "スキル1", entry: viewModel.skill1, enabled: true, allowsNone: false)
                            separator
                            skillRow(position: 1, label: "スキル2", entry: viewModel.skill2, enabled: viewModel.skill1 != nil, allowsNone: true)
                            separator
                            skillRow(position: 2, label: "スキル3", entry: viewModel.skill3, enabled: viewModel.skill2 != nil, allowsNone: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    note("抽選規則上あり得る組み合わせだけが選べます")
                }
                .mhEntrance(0)

                Group {
                    MHSectionHeader(title: "スロット・レア度")
                        .padding(.top, 20)
                    MHCard {
                        slotSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    note("スキル構成から自動で候補を絞り込みます")
                }
                .mhEntrance(1)

                Group {
                    MHSectionHeader(title: "メモ")
                        .padding(.top, 20)
                    MHCard {
                        TextField("", text: $viewModel.memo,
                                  prompt: Text("メモ(任意)").foregroundStyle(Color.mhTextTertiary))
                            .font(.system(size: 16))
                            .foregroundStyle(Color.mhTextPrimary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .onChange(of: viewModel.memo) { _, newValue in
                                if newValue.count > 100 {
                                    viewModel.memo = String(newValue.prefix(100))
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .mhEntrance(2)

                if let message = viewModel.saveErrorMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mhDestructive)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.mhTextTertiary)
            .padding(.horizontal, 32)
            .padding(.top, 6)
    }

    private func skillRow(position: Int, label: String, entry: CharmRules.GroupEntry?, enabled: Bool, allowsNone: Bool) -> some View {
        NavigationLink {
            CharmSkillCandidateView(
                viewModel: viewModel, position: position, title: label, allowsNone: allowsNone)
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mhTextTertiary)
                    .frame(width: 62, alignment: .leading)
                Text(viewModel.entryLabel(entry))
                    .font(.system(size: 16))
                    .foregroundStyle(entry == nil ? Color.mhTextTertiary : Color.mhTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mhTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    @ViewBuilder
    private var slotSection: some View {
        let candidates = viewModel.slotCandidates
        if candidates.isEmpty {
            Text(viewModel.skill1 == nil
                 ? "スキル1を選択してください"
                 : "この構成の護石はありません。スキル2・3も選択してください")
                .font(.system(size: 13))
                .foregroundStyle(Color.mhTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                    let isSelected = viewModel.selectedSlot == candidate
                    Button {
                        viewModel.selectedSlot = candidate
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .stroke(isSelected ? Color.clear : Color.mhHairline, lineWidth: 1.5)
                                if isSelected {
                                    Circle().fill(Color.mhAccent)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.mhBackground)
                                }
                            }
                            .frame(width: 22, height: 22)
                            RarityBadge(rarity: candidate.rarity)
                            Text(viewModel.slotLabel(candidate))
                                .font(.system(size: 16))
                                .foregroundStyle(Color.mhTextPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(isSelected ? Color.mhAccentWash : .clear)
                    }
                    if index < candidates.count - 1 { separator }
                }
            }
        }
    }
}

/// スキル候補の選択リスト(sheet内push)
struct CharmSkillCandidateView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: CharmEntryViewModel
    let position: Int
    let title: String
    let allowsNone: Bool
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Color.mhBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                    .padding(16)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if allowsNone && searchText.isEmpty {
                            candidateRow(nil)
                            separator
                        }
                        ForEach(filteredCandidates, id: \.self) { entry in
                            candidateRow(entry)
                            separator
                        }
                    }
                }
            }
        }
        .mhNavigationTitle(title)
        .navigationBarBackButtonHidden(true)
        .toolbar { MHBackButton { dismiss() } }
    }

    private var filteredCandidates: [CharmRules.GroupEntry] {
        viewModel.candidates(forPosition: position)
            .filter { viewModel.skillName($0.skillId).mhContains(searchText) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.mhTextTertiary)
            TextField("", text: $searchText,
                      prompt: Text("スキル名で検索").foregroundStyle(Color.mhTextTertiary))
                .font(.system(size: 16))
                .foregroundStyle(Color.mhTextPrimary)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.mhSurfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.mhHairline, lineWidth: 1))
    }

    private var separator: some View {
        Rectangle().fill(Color.mhHairlineFaint).frame(height: 1).padding(.leading, 16)
    }

    private func candidateRow(_ entry: CharmRules.GroupEntry?) -> some View {
        let current: CharmRules.GroupEntry? = switch position {
        case 0: viewModel.skill1
        case 1: viewModel.skill2
        default: viewModel.skill3
        }
        let isSelected = current == entry
        return Button {
            viewModel.select(position: position, entry: entry)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.mhAccent)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 18, height: 18)
                Text(viewModel.entryLabel(entry))
                    .font(.system(size: 16))
                    .foregroundStyle(entry == nil ? Color.mhTextTertiary : Color.mhTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(isSelected ? Color.mhAccentWash : .clear)
        }
    }
}
