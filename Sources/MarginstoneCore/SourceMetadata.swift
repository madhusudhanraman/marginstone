import Foundation

public struct SourceMetadata: Equatable, Sendable {
    public var title: String = ""
    public var author: String = ""
    public var url: String = ""
    public init() {}
    public static func html(_ html: String) -> SourceMetadata {
        func captures(_ pattern: String, _ text: String) -> [[String]] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            let ns = text as NSString
            return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) } }
        }
        func decode(_ text: String) -> String {
            var out = text.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            for match in captures(#"&#(x[0-9a-f]+|[0-9]+);"#, out).reversed() {
                let n = match[1].lowercased(); let value = n.hasPrefix("x") ? UInt32(n.dropFirst(), radix: 16) : UInt32(n)
                if let value, let scalar = UnicodeScalar(value) { out = out.replacingOccurrences(of: match[0], with: String(scalar)) }
            }
            return out.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func attrs(_ tag: String) -> [String: String] {
            var result: [String: String] = [:]
            for a in captures(#"([a-z_:][a-z0-9_:\-]*)\s*=\s*(["'])(.*?)\2"#, tag) { result[a[1].lowercased()] = decode(a[3]) }
            return result
        }
        var meta: [String: String] = [:]
        for tag in captures(#"<meta\b[^>]*>"#, html) {
            let a = attrs(tag[0]); if let key = a["property"] ?? a["name"], let value = a["content"], !value.isEmpty { meta[key.lowercased()] = value }
        }
        var result = SourceMetadata()
        result.title = meta["og:title"] ?? meta["twitter:title"] ?? meta["citation_title"] ?? meta["dc.title"] ?? ""
        result.author = meta["author"] ?? meta["citation_author"] ?? meta["dc.creator"] ?? meta["article:author"] ?? ""
        if result.author.hasPrefix("http") { result.author = "" }
        result.url = meta["og:url"] ?? ""
        for tag in captures(#"<link\b[^>]*>"#, html) {
            let a = attrs(tag[0]); if a["rel"]?.lowercased().split(separator: " ").contains("canonical") == true, let url = a["href"] { result.url = url; break }
        }
        if result.url.isEmpty { result.url = captures(#"(?:^|[\r\n])SourceURL:\s*(https?://[^\r\n]+)"#, html).first.map { decode($0[1]) } ?? "" }
        func authorNames(_ value: Any?) -> [String] {
            if let s = value as? String { return [s] }
            if let a = value as? [Any] { return a.flatMap { authorNames($0) } }
            if let d = value as? [String: Any], let name = d["name"] as? String { return [name] }
            return []
        }
        func inspect(_ value: Any) {
            if let array = value as? [Any] { array.forEach(inspect); return }
            guard let d = value as? [String: Any] else { return }
            let types = (d["@type"] as? [String]) ?? (d["@type"] as? String).map { [$0] } ?? []
            if types.contains(where: { ["Article", "NewsArticle", "BlogPosting", "Book", "ScholarlyArticle"].contains($0) }) {
                if result.title.isEmpty { result.title = d["headline"] as? String ?? d["name"] as? String ?? "" }
                if result.author.isEmpty { result.author = authorNames(d["author"]).joined(separator: ", ") }
            }
            if let graph = d["@graph"] { inspect(graph) }
        }
        for script in captures(#"(<script\b[^>]*>)(.*?)</script>"#, html) {
            if attrs(script[1])["type"]?.lowercased() == "application/ld+json", let data = script[2].data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) { inspect(json) }
        }
        if result.author.isEmpty {
            for tag in ["a", "span", "div", "p"].flatMap({ element in captures("<(" + element + #")\b([^>]*)>(.*?)</\1>"#, html) }) {
                let attributes = attrs(tag[2])
                let rel = (attributes["rel"] ?? "").lowercased().split(separator: " ")
                let classes = (attributes["class"] ?? "").lowercased().split(separator: " ")
                guard rel.contains("author") || attributes["itemprop"] == "author" || classes.contains("author-name") || classes.contains("byline-author") else { continue }
                let stripped = tag[3].replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                let name = decode(stripped).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").replacingOccurrences(of: #"^By\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                if !name.isEmpty && name.count <= 150 && !name.contains("http") { result.author = name; break }
            }
        }
        if result.title.isEmpty { result.title = captures(#"<title\b[^>]*>(.*?)</title>"#, html).first.map { decode($0[1]) } ?? "" }
        result.title = String(result.title.prefix(500)); result.author = String(result.author.prefix(500))
        return result
    }
}
