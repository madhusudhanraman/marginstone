import Foundation

public struct BookSource: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var author: String
    public var cover: String
    public var edition: String
    public var kind: String?
    public init(path: String, title: String, author: String = "", cover: String = "", edition: String = "", kind: String? = nil) {
        self.path = path; self.title = title; self.author = author; self.cover = cover; self.edition = edition; self.kind = kind == "book" ? nil : kind
    }
}
public struct CapturePayload: Codable, Sendable {
    public var text: String
    public var url: String
    public var types: [String]
    public var sourceTitle: String?
    public var sourceAuthor: String?
    public var sourceHTML: String?
    public var sourceApp: String
    public init(text: String, url: String = "", types: [String] = [], sourceApp: String = "") {
        self.text = text; self.url = url; self.types = types; self.sourceApp = sourceApp
    }
}
public struct SavedPassage: Codable, Identifiable, Sendable {
    public var id: UUID
    public var payload: CapturePayload
    public var sourcePath: String?
    public var capturedAt: Date
    public var editedText: String?
    public var displayText: String { editedText ?? CitationParser.books(payload.text)?.passage ?? payload.text }
    public var written: Bool
    public init(payload: CapturePayload, sourcePath: String?) {
        self.id = UUID(); self.payload = payload; self.sourcePath = sourcePath; self.capturedAt = Date(); self.written = false
    }
}
public struct PostEditBaseline: Codable, Sendable {
    public var published: String?
    public init(published: String?) { self.published = published }
}
public struct PostDocument: Sendable {
    public var text: String
    public var draftSnapshot: String
    public var published: String?
    public init(text: String, draftSnapshot: String, published: String?) {
        self.text = text; self.draftSnapshot = draftSnapshot; self.published = published
    }
}
public struct SourceHint: Equatable, Sendable {
    public var title: String
    public var author: String
    public var passage: String
    public init(title: String, author: String, passage: String) { self.title = title; self.author = author; self.passage = passage }
}
public enum CitationParser {
    // Keep the original payload in the journal; strip a citation only after a source is confirmed.
    public static func books(_ raw: String) -> SourceHint? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let marker = normalized.range(of: #"(?im)^\s*Excerpt\s+From\s*:?\s*"#, options: .regularExpression) else { return nil }
        let tail = String(normalized[marker.upperBound...])
        let lines = tail.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let citation = lines.prefix { !$0.localizedCaseInsensitiveContains("protected by copyright") && !$0.lowercased().hasPrefix("http") && $0 != "Apple Books" && $0 != "iBooks." }
        guard let title = citation.first, title.count < 400 else { return nil }
        let passage = String(normalized[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !passage.isEmpty else { return nil }
        return SourceHint(title: title, author: citation.dropFirst().first ?? "", passage: passage)
    }
}
public enum Markdown {
    public static func safePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0] == "_posts" && !parts[1].hasPrefix(".") && !parts[1].contains("\\") && path.hasSuffix(".md") && !path.contains("\n")
    }
    public static func slug(_ value: String) -> String {
        let latin = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let s = latin.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(s.prefix(90)).isEmpty ? UUID().uuidString.lowercased() : String(s.prefix(90))
    }
    public static func quote(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
    public static func page(_ book: BookSource, date: String) -> String {
        let year = PublicationYear.fromTitle(book.title).map { "year: \($0)\n" } ?? ""
        let kind = book.kind ?? "book"
        let category = kind == "article" ? "Articles" : kind == "other" ? "Excerpts" : "Books"
        let bookAuthor = kind == "book" ? "book_author: \(quote(book.author))\n" : ""
        return "---\ntitle: \(quote(book.title))\n\(year)date: \(date)\nlast_modified_at: \(date)\ncategories: [\(category)]\nsource_kind: \(quote(kind))\nauthor: \(quote(book.author))\n\(bookAuthor)cover: \(quote(book.cover))\nnautilus_edition: \(quote(book.edition))\n---\n\n## Excerpts\n"
    }
    public static func block(_ p: SavedPassage, text: String) -> String {
        let literal = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let quoted = literal.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
        let link = p.payload.url.hasPrefix("https://") || p.payload.url.hasPrefix("http://") ? "\n\nSource: <" + p.payload.url.replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "\n", with: "") + ">" : ""
        return "<!-- nautilus:\(p.id.uuidString) -->\n\(quoted)\(link)\n<!-- /nautilus:\(p.id.uuidString) -->"
    }
    public static func append(_ block: String, to original: String) -> String {
        if original.contains(block) || blocks(original).contains(where: { blockContent($0) == blockContent(block) }) { return original }
        var page = original
        if !page.contains("## Excerpts") { page += "\n\n## Excerpts\n" }
        return page.trimmingCharacters(in: .newlines) + "\n\n" + block + "\n"
    }
    public static func blocks(_ text: String) -> [String] {
        let pattern = #"(?s)<!-- nautilus:([A-Fa-f0-9-]+) -->.*?<!-- /nautilus:\1 -->"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    private static func blockContent(_ block: String) -> String {
        block.components(separatedBy: .newlines).dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func uniqueBlocks(_ text: String) -> String {
        // Remove only repeated app-generated blocks. Leave manual quotations,
        // front matter, and review text untouched; retain the first capture ID.
        var seen = Set<String>()
        var result = text
        for block in blocks(text) {
            if !seen.insert(blockContent(block)).inserted,
               let range = result.range(of: block) { result.removeSubrange(range) }
        }
        return result
    }
    public static func merge(draft: String, published: String?) -> String {
        guard let published else { return uniqueBlocks(draft) }
        var result = uniqueBlocks(published)
        for block in blocks(draft) {
            let marker = block.components(separatedBy: .newlines)[0]
            if !result.contains(marker) && !result.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).joined(separator: "\n").contains(blockContent(block)) { result = append(block, to: result) }
        }
        return result
    }
    public static func updatingModifiedDate(_ text: String, date: String) -> String {
        guard text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return text }
        let start = text.index(text.startIndex, offsetBy: 4)
        let header = String(text[start..<end.lowerBound])
        var lines = header.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.hasPrefix("last_modified_at:") }) {
            lines[index] = "last_modified_at: \(date)"
        } else { lines.append("last_modified_at: \(date)") }
        return "---\n" + lines.joined(separator: "\n") + text[end.lowerBound...]
    }
    public static func removingExcerpt(in post: String, passage: SavedPassage) -> String? {
        if let block = blocks(post).first(where: { $0.hasPrefix("<!-- nautilus:\(passage.id.uuidString) -->") }),
           let range = post.range(of: block) { return post.replacingCharacters(in: range, with: "") }
        let body = block(passage, text: passage.displayText).components(separatedBy: .newlines).dropFirst().dropLast().joined(separator: "\n")
        let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: body) + "(?=\n|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: post, range: NSRange(post.startIndex..., in: post))
        guard matches.count == 1, let range = Range(matches[0].range, in: post) else { return nil }
        return post.replacingCharacters(in: range, with: "")
    }
    public static func editingExcerpt(in post: String, passage: SavedPassage, text: String) -> String? {
        let oldBlock = block(passage, text: passage.displayText)
        let newBlock = block(passage, text: text)
        // Prefer capture identity in drafts, then the exact quote in marker-free posts.
        if let old = blocks(post).first(where: { $0.hasPrefix("<!-- nautilus:\(passage.id.uuidString) -->") }),
           let range = post.range(of: old) { return post.replacingCharacters(in: range, with: newBlock) }
        func body(_ value: String) -> String { value.components(separatedBy: .newlines).dropFirst().dropLast().joined(separator: "\n") }
        let oldBody = body(oldBlock)
        if let range = post.range(of: oldBody) { return post.replacingCharacters(in: range, with: body(newBlock)) }
        return nil
    }
    public static func headerValue(_ text: String, key: String) -> String? {
        guard text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return nil }
        let start = text.index(text.startIndex, offsetBy: 4)
        guard let line = text[start..<end.lowerBound].components(separatedBy: .newlines).first(where: { $0.hasPrefix(key + ":") }) else { return nil }
        let value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        if let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) { return decoded }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return value
    }
    public static func updatingHeader(_ text: String, key: String, value: String) -> String {
        guard ["title", "author", "book_author"].contains(key), text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return text }
        let start = text.index(text.startIndex, offsetBy: 4)
        var lines = text[start..<end.lowerBound].components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.hasPrefix(key + ":") }) { lines[index] = key + ": " + quote(value) }
        else { lines.append(key + ": " + quote(value)) }
        return "---\n" + lines.joined(separator: "\n") + text[end.lowerBound...]
    }
    public static func updatingPublicationYear(_ text: String, year: Int) -> String {
        guard text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return text }
        let start = text.index(text.startIndex, offsetBy: 4)
        var lines = text[start..<end.lowerBound].components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.hasPrefix("year:") }) { lines[index] = "year: \(year)" }
        else { lines.append("year: \(year)") }
        return "---\n" + lines.joined(separator: "\n") + text[end.lowerBound...]
    }
    public static func updatingCover(_ text: String, cover: String) -> String {
        guard text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return text }
        let start = text.index(text.startIndex, offsetBy: 4)
        var lines = text[start..<end.lowerBound].components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: { $0.hasPrefix("cover:") }) { lines[index] = "cover: " + quote(cover) }
        else { lines.append("cover: " + quote(cover)) }
        return "---\n" + lines.joined(separator: "\n") + text[end.lowerBound...]
    }
    public static func publication(draft: String, published: String?, date: String) -> String {
        let merged = merge(draft: draft, published: published)
        // Capture IDs belong only in the local draft, never the website post.
        let clean = merged.replacingOccurrences(
            of: #"(?m)^<!-- /?nautilus:[A-Fa-f0-9-]+ -->\n?"#,
            with: "", options: .regularExpression)
        return clean == published ? clean : updatingModifiedDate(clean, date: date)
    }
    public static func source(path: String, text: String) -> BookSource? {
        guard safePath(path), text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
        var fields: [String: String] = [:]
        for line in header.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) { value = decoded }
            else if value.hasPrefix("'"), value.hasSuffix("'") { value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
            fields[key] = value
        }
        guard let title = fields["title"], !title.isEmpty else { return nil }
        // Include book posts, even when the category is represented as a YAML list.
        guard header.localizedCaseInsensitiveContains("books") || fields["book_author"] != nil || ["article", "other"].contains(fields["source_kind"] ?? "") else { return nil }
        return BookSource(path: path, title: title, author: fields["book_author"] ?? fields["author"] ?? "", cover: fields["cover"] ?? "", edition: fields["nautilus_edition"] ?? "", kind: fields["source_kind"])
    }
}
