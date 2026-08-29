import Foundation

/// bundled.db が保持するマスタデータの言語(スキーマv2)。
/// UIのローカライズとは独立にDB列の選択を表す。rawValueはBCP 47タグ。
public enum DataLanguage: String, CaseIterable, Sendable {
    case ja
    case en
    case fr
    case de
    case es
    case ptBR = "pt-BR"
    case ko

    /// SQLite列サフィックス(tools/convert/convert.py の LANGUAGES と一致させる)
    var columnSuffix: String {
        switch self {
        case .ja: "Ja"
        case .en: "En"
        case .fr: "Fr"
        case .de: "De"
        case .es: "Es"
        case .ptBR: "PtBr"
        case .ko: "Ko"
        }
    }

    /// アプリの言語設定(Bundle.preferredLocalizationsの先頭など)から解決する。
    /// 地域付きタグ(en-US等)は言語部分で照合し、未対応言語は英語に落とす
    /// (UI側も同じ言語集合のため、日本語UIのときだけjaになる)。
    public static func resolve(localeIdentifier: String) -> DataLanguage {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        if let exact = DataLanguage(rawValue: normalized) {
            return exact
        }
        let languageCode = normalized.split(separator: "-").first.map(String.init) ?? normalized
        switch languageCode {
        case "ja": return .ja
        case "fr": return .fr
        case "de": return .de
        case "es": return .es
        case "pt": return .ptBR
        case "ko": return .ko
        default: return .en
        }
    }
}
