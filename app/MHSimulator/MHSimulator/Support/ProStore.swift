import Foundation
import Observation
import StoreKit

/// Pro版(買い切りIAP)の購入状態管理(2026-08-29追加)。
/// 特典: マイセット上限なし・全広告非表示(左上の広告非表示アイコンも不要になるため非表示)。
/// 起動時はUserDefaultsのキャッシュで即時反映し、StoreKitの現在の権利で検証して上書きする
@Observable
final class ProStore {
    static let shared = ProStore()

    static let productId = "com.yssdev.MHSimulator.Pro"
    /// 無料版のマイセット保存上限(Pro版は無制限)
    static let freeMySetLimit = 5

    private static let purchasedKey = "pro.purchased"

    enum Phase {
        case idle
        case purchasing
        case restoring
    }

    #if DEBUG
    /// 開発者ツールのPro状態モード(DEBUGビルド限定。本番ビルドにはこの型ごと存在しない)
    enum DebugProMode: String, CaseIterable {
        /// StoreKitの購入状態をそのまま参照(本番と同じ動作)
        case storeKit
        /// StoreKitによらずPro版として動作
        case forcePro
        /// StoreKitによらず無料版として動作
        case forceFree
    }

    private static let debugProModeKey = "debug.proMode"

    var debugProMode: DebugProMode = .storeKit {
        didSet { UserDefaults.standard.set(debugProMode.rawValue, forKey: Self.debugProModeKey) }
    }
    #endif

    /// Pro版が有効か。本番ビルドではStoreKit由来のentitledProのみを参照する
    /// (DEBUGビルドでは開発者ツールの上書きを反映)
    var isPro: Bool {
        #if DEBUG
        switch debugProMode {
        case .forcePro: return true
        case .forceFree: return false
        case .storeKit: break
        }
        #endif
        return entitledPro
    }

    /// StoreKitの購入状態(キャッシュ+検証結果)
    private(set) var entitledPro: Bool
    private(set) var phase: Phase = .idle
    private(set) var product: Product?
    var purchaseErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        entitledPro = UserDefaults.standard.bool(forKey: Self.purchasedKey)
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: Self.debugProModeKey),
           let mode = DebugProMode(rawValue: raw) {
            debugProMode = mode
        }
        #endif
        // 返金(失効)や別端末での購入・承認待ち完了はここで反映される
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = update,
                      transaction.productID == Self.productId else { continue }
                setPro(transaction.revocationDate == nil)
                await transaction.finish()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProductIfNeeded()
        }
    }

    /// 現在の権利からisProを更新する。権利が見つからない場合はキャッシュを維持する
    /// (オフライン起動でPro機能を失わないため。失効はTransaction.updatesの失効通知で反映)
    func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productID == Self.productId else { continue }
            setPro(transaction.revocationDate == nil)
            return
        }
    }

    /// 商品情報(価格表示用)。購入UI表示時と購入直前に呼ぶ
    func loadProductIfNeeded() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productId]).first
    }

    func purchase() async {
        // 判定は実際の購入状態(entitledPro)で行う。DEBUGの上書き中でも二重購入を防ぐ
        guard phase == .idle, !entitledPro else { return }
        phase = .purchasing
        defer { phase = .idle }
        await loadProductIfNeeded()
        guard let product else {
            purchaseErrorMessage = "商品情報を取得できませんでした。通信環境をご確認のうえ再度お試しください"
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseErrorMessage = "購入を確認できませんでした。購入の復元をお試しください"
                    return
                }
                setPro(true)
                await transaction.finish()
            case .userCancelled, .pending:
                // 承認待ち(ファミリー共有の承認等)はTransaction.updatesで反映される
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = "購入処理に失敗しました。時間をおいて再度お試しください"
        }
    }

    func restore() async {
        guard phase == .idle else { return }
        phase = .restoring
        defer { phase = .idle }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !entitledPro {
                purchaseErrorMessage = "復元できる購入が見つかりませんでした"
            }
        } catch {
            if case StoreKitError.userCancelled = error { return }
            purchaseErrorMessage = "購入の復元に失敗しました。時間をおいて再度お試しください"
        }
    }

    private func setPro(_ value: Bool) {
        entitledPro = value
        UserDefaults.standard.set(value, forKey: Self.purchasedKey)
    }
}

/// プライバシーポリシー・利用規約のリンク先(作成中。公開後にURL文字列を入れるだけで有効になる)
enum LegalLinks {
    static let privacyPolicy = ""  // 例: "https://example.com/privacy"
    static let termsOfUse = ""  // 例: "https://example.com/terms"

    static var privacyPolicyURL: URL? { URL(string: privacyPolicy) }
    static var termsOfUseURL: URL? { URL(string: termsOfUse) }
}
