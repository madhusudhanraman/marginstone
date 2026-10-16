import Foundation

public enum PublicationYear {
    public static func fromTitle(_ title: String) -> Int? {
        guard let range = title.range(of: #"\([0-9]{4}\)\s*$"#, options: .regularExpression) else { return nil }
        return Int(title[range].filter(\.isNumber))
    }
    public static func baseTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*\([0-9]{4}\)\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func title(_ title: String, year: Int) -> String {
        guard fromTitle(title) == nil else { return title }
        return baseTitle(title) + " (\(year))"
    }
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter { $0.isLetter || $0.isNumber }
    }
}
