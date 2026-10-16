import AppKit
import MarginstoneCore

enum CaptureReader {
    static let supported: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html]
    static func read(_ board: NSPasteboard) throws -> CapturePayload {
        var text = board.string(forType: .string)
        if text == nil {
            for (type, format) in [(NSPasteboard.PasteboardType.rtf, NSAttributedString.DocumentType.rtf), (.rtfd, .rtfd), (.html, .html)] {
                if let data = board.data(forType: type), data.count <= 2_000_000,
                   let attributed = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) {
                    text = attributed.string; break
                }
            }
        }
        guard let raw = text, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure(message: "No readable text arrived. In Books, copy the passage, then choose Capture Clipboard from the Marginstone menu.") }
        guard raw.utf8.count <= 2_000_000 else { throw AppFailure(message: "Choose a passage smaller than 2 MB.") }
        var payload = CapturePayload(text: raw, url: board.string(forType: .URL) ?? "", types: (board.types ?? []).map(\.rawValue), sourceApp: board.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) ?? "")
        var html = board.string(forType: .html)
        if let data = board.data(forType: NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")), data.count <= 2_000_000,
           let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let main = archive["WebMainResource"] as? [String: Any] {
            if payload.url.isEmpty { payload.url = main["WebResourceURL"] as? String ?? "" }
            if html == nil, let data = main["WebResourceData"] as? Data { html = String(data: data, encoding: .utf8) }
        }
        if let html, html.utf8.count <= 2_000_000 {
            payload.sourceHTML = html
            let metadata = SourceMetadata.html(html)
            payload.sourceTitle = metadata.title; payload.sourceAuthor = metadata.author
            if payload.url.isEmpty, let url = URL(string: metadata.url), ["http", "https"].contains(url.scheme ?? "") { payload.url = url.absoluteString }
        }
        if let hint = CitationParser.books(raw) { payload.sourceTitle = hint.title; payload.sourceAuthor = hint.author }
        return payload
    }
}
