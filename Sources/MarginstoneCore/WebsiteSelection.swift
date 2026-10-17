import Foundation

public enum WebsiteSelection {
    public static func restored(_ saved: [UUID]?, passages: [SavedPassage]) -> Set<UUID> {
        Set(saved ?? passages.filter { $0.written }.map { $0.id })
    }

    public static func pending(_ passages: [SavedPassage], selected: Set<UUID>) -> [SavedPassage] {
        passages.filter { !$0.written && $0.sourcePath != nil && selected.contains($0.id) }
    }
}
