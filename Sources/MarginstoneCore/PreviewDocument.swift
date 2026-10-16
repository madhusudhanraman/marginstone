import Foundation

/// Keeps untouched Markdown byte-for-byte and edits only the selected text block.
public struct PreviewDocument {
    public struct Block: Identifiable {
        public let id = UUID()
        public let original: String
        public let prefix: String
        public let isQuote: Bool
        public var text: String
        private let initialText: String
        public init(_ raw: String) {
            original = raw
            isQuote = raw.hasPrefix("> ") || raw == ">" || raw.hasPrefix(">\n")
            let heading = raw.prefix(while: { $0 == "#" })
            prefix = !heading.isEmpty && raw.dropFirst(heading.count).hasPrefix(" ") ? String(heading) + " " : ""
            if isQuote {
                text = raw.components(separatedBy: .newlines).map { line in
                    line.hasPrefix("> ") ? String(line.dropFirst(2)) : (line == ">" ? "" : line)
                }.joined(separator: "\n")
            } else { text = String(raw.dropFirst(prefix.count)) }
            initialText = text
        }
        public var markdown: String {
            guard text != initialText else { return original }
            if isQuote { return text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") }
            return prefix + text
        }
    }
    public let header: String
    public var blocks: [Block]
    public init(_ markdown: String) {
        var body = markdown
        if markdown.hasPrefix("---\n"), let end = markdown.dropFirst(4).range(of: "\n---") {
            let after = end.upperBound
            let whitespace = markdown[after...].prefix(while: { $0 == "\n" || $0 == "\r" })
            let split = markdown.index(after, offsetBy: whitespace.count)
            header = String(markdown[..<split]); body = String(markdown[split...])
        } else { header = "" }
        blocks = body.components(separatedBy: "\n\n").map(Block.init)
    }
    public var markdown: String { header + blocks.map(\.markdown).joined(separator: "\n\n") }
}
