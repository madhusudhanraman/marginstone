import AppKit
import MarginstoneCore

struct AppFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
@main struct PDFCaptureChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("\u{FFFC}", forType: .string)
        do { _ = try CaptureReader.read(board); preconditionFailure("Object placeholder accepted") }
        catch is AppFailure { }
        let fixture = "A quiet companion preserves reading passages."
        let image = NSImage(size: NSSize(width: 1000, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 160).fill()
        (fixture as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
        image.unlockFocus()
        board.clearContents()
        board.setString("\u{FFFC}", forType: .string)
        board.setData(image.tiffRepresentation!, forType: .tiff)
        do { _ = try CaptureReader.read(board); preconditionFailure("Clipboard screenshot accepted as an excerpt") }
        catch is AppFailure { }
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 1000, height: 160))
        view.image = image
        board.clearContents(); board.setData(view.dataWithPDF(inside: view.bounds), forType: .pdf)
        let pdfResult = try CaptureReader.read(board)
        precondition(pdfResult.text.contains("quiet companion"))
        board.clearContents(); board.setString("Plain text wins", forType: .string)
        board.setData(image.tiffRepresentation!, forType: .tiff)
        let plainResult = try CaptureReader.read(board)
        precondition(plainResult.text == "Plain text wins")
        print("Object and screenshot rejection, scanned PDF OCR and plain-text precedence passed.")
    }
}
