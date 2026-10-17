import AppKit
import SwiftUI
import MarginstoneCore

/// Native paragraph layout supplies justification, including natural last lines.
@MainActor
struct JustifiedExcerpt: NSViewRepresentable {
    let text: String

    final class Label: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Label {
        let label = Label(wrappingLabelWithString: "")
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: Label, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 5
        paragraph.hyphenationFactor = 0.5
        let font = NSFont.systemFont(ofSize: 18)
        let serif = font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 18) } ?? font
        label.attributedStringValue = NSAttributedString(string: ExcerptLayout.reflow(text), attributes: [
            .font: serif,
            .foregroundColor: NSColor(srgbRed: 29.0/255, green: 27.0/255, blue: 25.0/255, alpha: 1),
            .paragraphStyle: paragraph
        ])
        label.setAccessibilityLabel(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Label, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        nsView.preferredMaxLayoutWidth = width
        let size = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: width, height: ceil(size.height))
    }
}
