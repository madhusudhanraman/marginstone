import AppKit
@main struct Check {
 static func main() throws {
  let names = ["nautilus", "leaf", "ammonite", "brachiopod", "fern"]
  let preview = NSImage(size: NSSize(width: 1000, height: 310), flipped: false) { _ in
   NSColor(white: 0.5, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1000, height: 310).fill()
   for (index,name) in names.enumerated() {
    let image = NSImage(contentsOfFile: "Sources/Marginstone/Resources/"+name+".png")!
    let dock = SystemIcons.dock(image); let menu = SystemIcons.menu(image)!
    precondition(menu.isTemplate && menu.size.width == 22)
    dock.draw(in: NSRect(x: index*200, y: 90, width: 200, height: 200))
    menu.isTemplate = false
    menu.draw(in: NSRect(x: index*200+82, y: 35, width: 36, height: 36))
   }
   return true
  }
  let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/marginstone-system-icons.png"))
  print("PASS: all five Dock tiles and template menu icons rendered")
 }
}
