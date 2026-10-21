import Foundation
import SwiftUI
import Translation

enum HermesNoticeJapanese {
    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
    }

    static func level(_ level: String) -> String {
        switch level {
        case "WARNING": return "警告"
        case "ERROR": return "エラー"
        case "CRITICAL": return "重大なエラー"
        default: return "通知"
        }
    }

    static func displayLevel(for notice: HermesNotice) -> String {
        notice.message.contains("No messaging platforms enabled") ? "案内" : level(notice.level)
    }

    static func knownTranslation(for notice: HermesNotice) -> String? {
        let source = notice.message.lowercased()
        if source.contains("no messaging platforms enabled") {
            return "Telegramなどのメッセージ連携は未設定です。Gatewayは起動を続けます。連携を使わない場合、対応は不要です。"
        }
        if source.contains("named custom provider") && source.contains("no resolvable api_key") {
            return "ローカルOllamaにAPIキーが未設定でした。認証不要の接続にはダミー値を設定できます。"
        }
        if source.contains("ssh password authentication is enabled") {
            return "SSHのパスワード認証が有効です。使わない場合はmacOSの「リモートログイン」をオフにしてください。"
        }
        return nil
    }

    static func fallback(for notice: HermesNotice) -> String {
        if let known = knownTranslation(for: notice) { return known }
        let source = notice.message.lowercased()
        if source.contains("permission denied") { return "権限がないため、Hermesの処理を実行できませんでした。" }
        if source.contains("timed out") || source.contains("timeout") { return "Hermesの処理がタイムアウトしました。" }
        if source.contains("rate limit") { return "モデルの利用制限に達しました。" }
        if source.contains("config.yaml") { return "Hermesの設定に問題があります。設定ファイルを確認してください。" }
        if source.contains("connection refused") || source.contains("failed to connect") {
            return "接続先に到達できませんでした。Hermesとモデルの接続状態を確認してください。"
        }
        return "Hermesで\(level(notice.level))が発生しました。詳細はHermesのエラーログを確認してください。"
    }
}

@available(macOS 15.0, *)
struct JapaneseNoticeRow: View {
    let notice: HermesNotice
    @State private var japaneseText = "日本語に翻訳中…"
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(HermesNoticeJapanese.displayLevel(for: notice))  \(notice.time)")
                .font(.caption2).foregroundStyle(.orange)
            Text(japaneseText).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            DisclosureGroup("原文を表示", isExpanded: $showOriginal) {
                Text(notice.message).font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .translationTask(source: Locale.Language(identifier: "en"),
                         target: Locale.Language(identifier: "ja")) { session in
            if let known = HermesNoticeJapanese.knownTranslation(for: notice) {
                japaneseText = known
                return
            }
            if HermesNoticeJapanese.containsJapanese(notice.message) {
                japaneseText = notice.message
                return
            }
            do {
                let response = try await session.translate(notice.message)
                japaneseText = response.targetText.isEmpty
                    ? HermesNoticeJapanese.fallback(for: notice) : response.targetText
            } catch {
                japaneseText = HermesNoticeJapanese.fallback(for: notice)
            }
        }
    }
}
