import Foundation

/// Existing collections retain their location, including Git's worktree metadata.
/// New installations use the current application name.
enum AppStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory(in: base)
    }

    static func directory(in base: URL) -> URL {
        let current = base.appendingPathComponent("Marginstone")
        let legacy = base.appendingPathComponent("Nautilus")
        // Prefer an existing collection over an empty folder left by setup.
        for folder in [current, legacy] {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("collection.json").path) {
                return folder
            }
        }
        // Moving a Git worktree with a plain file move would break its metadata.
        if FileManager.default.fileExists(atPath: legacy.appendingPathComponent("Drafts/.git").path) {
            return legacy
        }
        return current
    }
}
