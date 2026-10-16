import AppKit
@main struct RenderIcon {
 static func main() throws {
  guard CommandLine.arguments.count == 3, let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
        let tiff = SystemIcons.dock(source).tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
  try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
 }
}
