import Foundation

public enum ExcerptLayout {
    /// Reflow copied line wraps without changing the stored original or paragraphs.
    public static func reflow(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
        return normalized.replacingOccurrences(of: #"\n[ \t]+\n"#, with: "\n\n", options: .regularExpression)
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }.joined(separator: "\n\n")
    }
}
