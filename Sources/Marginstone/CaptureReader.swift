import AppKit
import MarginstoneCore
import PDFKit
import Vision

enum CaptureReader {
    static let supported: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html, .pdf]
    private static func readable(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{FFFD}", with: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }
    static func read(_ board: NSPasteboard) throws -> CapturePayload {
        var text = readable(board.string(forType: .string))
        var attachments: [NSTextAttachment] = []
        if text == nil {
            for (type, format) in [(NSPasteboard.PasteboardType.rtf, NSAttributedString.DocumentType.rtf), (.rtfd, .rtfd), (.html, .html)] {
                if let data = board.data(forType: type), data.count <= 2_000_000,
                   let attributed = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) {
                    if let words = readable(attributed.string) { text = words; break }
                    attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                        if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
                    }
                }
            }
        }
        if text == nil, let data = board.data(forType: .pdf) {
            text = try pdfText(data)
        }
        if text == nil {
            var parts: [String] = []
            for attachment in attachments.prefix(10) {
                if let data = attachment.fileWrapper?.regularFileContents, data.count <= 20_000_000 {
                    if data.starts(with: Data("%PDF-".utf8)), let words = try pdfText(data) { parts.append(words) }
                    else if let image = NSImage(data: data), let words = try recognize(image) { parts.append(words) }
                } else if let image = attachment.image, let words = try recognize(image) { parts.append(words) }
            }
            text = readable(parts.joined(separator: "\n\n"))
        }
        guard let raw = readable(text) else {
            throw AppFailure(message: "No copied text was found. Select the passage, press ⌘C, then double-click the companion. Selecting text alone does not copy it. Clipboard screenshots are not captured automatically.")
        }
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
    private static func pdfText(_ data: Data) throws -> String? {
        guard data.count <= 20_000_000, let pdf = PDFDocument(data: data) else { return nil }
        guard pdf.pageCount <= 10 else { throw AppFailure(message: "Copy a smaller PDF selection (up to 10 pages).") }
        var parts: [String] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            if let text = readable(page.string) { parts.append(text) }
            else if let text = try recognize(page.thumbnail(of: NSSize(width: 2000, height: 2000), for: .mediaBox)) { parts.append(text) }
        }
        return readable(parts.joined(separator: "\n\n"))
    }

    private static func recognize(_ image: NSImage) throws -> String? {
        var bounds = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &bounds, context: nil, hints: nil),
              cgImage.width <= 12000, cgImage.height <= 12000 else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return readable((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
    }

}
