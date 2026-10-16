import AppKit
import CoreImage

enum SystemIcons {
    static func grey(_ image: NSImage) -> NSImage {
        guard let data = image.tiffRepresentation, let input = CIImage(data: data),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
    static func dock(_ artwork: NSImage) -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
            NSColor(white: 0.49, alpha: 1).setFill(); tile.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: NSColor(white: 0.62, alpha: 1), ending: NSColor(white: 0.40, alpha: 1))?.draw(in: tile, angle: -90)
            NSColor.white.withAlphaComponent(0.45).setStroke(); tile.lineWidth = 3; tile.stroke()
            let scale = min(640 / artwork.size.width, 640 / artwork.size.height)
            let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
            grey(artwork).draw(in: NSRect(x: (1024-size.width)/2, y: (1024-size.height)/2, width: size.width, height: size.height))
            return true
        }
    }
    static func menu(_ artwork: NSImage) -> NSImage? {
        // Preserve the companion's pigment pattern as a monochrome glyph,
        // removing the pale paper fill so the menu bar does not get a solid blob.
        let side = 128
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side*4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let scale = min(126/artwork.size.width, 126/artwork.size.height)
        let size = NSSize(width: artwork.size.width*scale, height: artwork.size.height*scale)
        artwork.draw(in: NSRect(x: (128-size.width)/2, y: (128-size.height)/2, width: size.width, height: size.height))
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let pixels = bitmap.bitmapData else { return nil }
        for y in 0..<side { for x in 0..<side {
            let offset = y*bitmap.bytesPerRow + x*4
            let alpha = CGFloat(pixels[offset+3])/255
            let luminance = (0.299*CGFloat(pixels[offset]) + 0.587*CGFloat(pixels[offset+1]) + 0.114*CGFloat(pixels[offset+2])) / max(1, alpha*255)
            let coverage = alpha * min(1, max(0, (0.82-luminance)*3))
            pixels[offset] = 0; pixels[offset+1] = 0; pixels[offset+2] = 0
            pixels[offset+3] = UInt8(coverage*255)
        } }
        let image = NSImage(size: NSSize(width: 22, height: 22)); image.addRepresentation(bitmap); image.isTemplate = true
        return image
    }
}
