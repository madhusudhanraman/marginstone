import AppKit
import CoreImage

enum Companion: String, CaseIterable, Identifiable {
    case nautilus, leaf, ammonite, brachiopod, fern
    var id: String { rawValue }
    var name: String {
        switch self {
        case .nautilus: return "Nautilus"
        case .leaf: return "Leaf"
        case .ammonite: return "Ammonite"
        case .brachiopod: return "Brachiopod"
        case .fern: return "Fern"
        }
    }
    static var selected: Companion { Companion(rawValue: UserDefaults.standard.string(forKey: "companion") ?? "") ?? .nautilus }
    var image: NSImage? {
        AppResources.bundle.url(forResource: rawValue, withExtension: "png", subdirectory: "Resources").flatMap { NSImage(contentsOf: $0) }
    }
}
