import Foundation
public enum MarkdownExport {
    public static func document(passages: [SavedPassage], sources: [BookSource], sourcePath: String? = nil) -> String {
        let selected = passages.filter { sourcePath == nil || $0.sourcePath == sourcePath }
        func heading(_ value: String) -> String { value.components(separatedBy: .newlines).joined(separator: " ") }
        var result = "# Marginstone excerpts\n"
        let capturedPaths: [String] = selected.compactMap { $0.sourcePath }
        let uniquePaths = Set<String>(capturedPaths)
        func sortKey(for path: String) -> String {
            guard let source = sources.first(where: { $0.path == path }) else { return path }
            return source.author + source.title
        }
        let paths: [String] = uniquePaths.sorted { (left: String, right: String) -> Bool in
            let leftKey = sortKey(for: left)
            let rightKey = sortKey(for: right)
            let comparison = leftKey.localizedStandardCompare(rightKey)
            return comparison == .orderedSame ? left < right : comparison == .orderedAscending
        }
        let groups: [String?] = paths.map { Optional($0) } + (selected.contains { $0.sourcePath == nil } ? [nil] : [])
        for path in groups {
            let source = sources.first { $0.path == path }
            result += "\n## " + heading(source?.title ?? "Unassigned excerpts") + "\n"
            if let author = source?.author, !author.isEmpty { result += "\n" + heading(author) + "\n" }
            for passage in selected.filter({ $0.sourcePath == path }).reversed() {
                let block = Markdown.block(passage, text: passage.displayText)
                let plain = block.components(separatedBy: .newlines).dropFirst().dropLast().joined(separator: "\n")
                result += "\n" + plain + "\n"
            }
        }
        return result
    }
}
