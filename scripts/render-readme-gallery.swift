import AppKit

// Render existing companion assets into a shared layout. Separate label colours
// keep the transparent gallery readable in GitHub's light and dark themes.
@main struct RenderGallery {
    static func main() throws {
        let names = [("nautilus", "Nautilus"), ("leaf", "Leaf"), ("ammonite", "Ammonite"), ("brachiopod", "Brachiopod"), ("fern", "Fern")]
        for dark in [false, true] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 620, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 12000, bitsPerPixel: 32),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not render gallery") }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            for (index, entry) in names.enumerated() {
                guard let source = NSImage(contentsOfFile: "Sources/Marginstone/Resources/" + entry.0 + ".png") else { fatalError("Missing artwork") }
                let scale = min(480/source.size.width, 480/source.size.height)
                let size = NSSize(width: source.size.width*scale, height: source.size.height*scale)
                source.draw(in: NSRect(x: CGFloat(index*600+60)+(480-size.width)/2, y: 120+(480-size.height)/2, width: size.width, height: size.height))
                let colour = dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.27, alpha: 1)
                let label = NSAttributedString(string: entry.1, attributes: [.font: NSFont.systemFont(ofSize: 50), .foregroundColor: colour])
                label.draw(at: NSPoint(x: CGFloat(index*600+300)-label.size().width/2, y: 22))
            }
            context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
            let file = "docs/companions-" + (dark ? "dark" : "light") + ".png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
        }
        print("Rendered full-width companion galleries for light and dark themes")
    }
}
