import AppKit
import Combine
import UniformTypeIdentifiers
import NautilusCore

private struct Journal: Codable {
    var version = 1
    var repo = ""
    var branch = ""
    var sources: [BookSource] = []
    var passages: [SavedPassage] = []
    var activePath: String?
    var pinSource = false
    var autoSync = false
    var sourceAliases: [String: String]?
    var postEdits: [String: PostEditBaseline]?
    var websiteBookmark: Data?
}
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var passages: [SavedPassage] = []
    @Published private(set) var sources: [BookSource] = []
    @Published private(set) var repo = ""
    @Published private(set) var branch = ""
    @Published var activePath: String? { didSet { saveSettings() } }
    @Published var pinSource = false { didSet { saveSettings() } }
    @Published var status = "Choose your Field Notes repository to begin."
    @Published var error: String?
    @Published var choosingSource = false
    @Published var busy = false
    @Published var showingSettings = false
    @Published var companion = Companion.selected {
        didSet {
            UserDefaults.standard.set(companion.rawValue, forKey: "companion")
            companionChanged?(companion)
        }
    }
    @Published var movesSideToSide = UserDefaults.standard.object(forKey: "movesSideToSide") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(movesSideToSide, forKey: "movesSideToSide")
            movementChanged?(movesSideToSide)
        }
    }
    var movementChanged: ((Bool) -> Void)?
    var companionChanged: ((Companion) -> Void)?
    var openCollection: (() -> Void)?
    var captured: (() -> Void)?
    private let engine = RepositoryEngine()
    private let support: URL
    private let journal: URL
    private var canWrite = true
    private var loading = true
    private var sourceAliases: [String: String] = [:]
    private var postEdits: [String: PostEditBaseline] = [:]
    private var queue: Task<Void, Never>?
    private var websiteBookmark: Data?
    private var accessedWebsite: URL?
    var tree: String { support.appendingPathComponent("Drafts").path }
    var currentSource: BookSource? { sources.first { $0.path == activePath } }
    var unassigned: [SavedPassage] { passages.filter { $0.sourcePath == nil } }
    var pending: [SavedPassage] { passages.filter { !$0.written && $0.sourcePath != nil } }
    init() {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nautilus")
        journal = support.appendingPathComponent("collection.json")
        if FileManager.default.fileExists(atPath: journal.path) {
            do {
                let state = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journal))
                guard state.version == 1 else { throw AppFailure(message: "This collection uses a newer format.") }
                repo = state.repo; branch = state.branch; sources = state.sources; passages = state.passages
                sourceAliases = state.sourceAliases ?? [:]; postEdits = state.postEdits ?? [:]
                websiteBookmark = state.websiteBookmark
                activePath = state.activePath; pinSource = state.pinSource
                status = repo.isEmpty ? "Choose your Field Notes repository." : "Collection restored. Connecting to your drafts…"
            } catch { canWrite = false; self.error = "Your saved collection could not be read. It has been left untouched: \(error.localizedDescription)" }
        }
        loading = false
    }
    func restoreConnection() {
        guard !repo.isEmpty, canWrite else { return }
        guard let bookmark = websiteBookmark else {
            status = "Choose your website folder once more to remember access. Your captures are safe."
            return
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { throw AppFailure(message: "Choose your website folder again to restore access.") }
            accessedWebsite = url
            if stale { websiteBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            connect(url.resolvingSymlinksInPath().path)
        } catch {
            status = "Website folder access needs renewing. Your captures are safe."
        }
    }
    var needsWebsiteAccess: Bool { !repo.isEmpty && accessedWebsite == nil }

    private func persist() throws {
        guard canWrite else { throw AppFailure(message: "The collection is read-only because its saved file could not be read.") }
        let state = Journal(repo: repo, branch: branch, sources: sources, passages: passages, activePath: activePath, pinSource: pinSource, autoSync: false, sourceAliases: sourceAliases, postEdits: postEdits, websiteBookmark: websiteBookmark)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: journal, options: .atomic)
    }
    private func saveSettings() { guard !loading else { return }; do { try persist() } catch { self.error = error.localizedDescription } }
    func chooseRepository() {
        guard !busy else { return }
        let picker = NSOpenPanel(); picker.title = "Choose your Field Notes repository"
        picker.message = "Choose your website folder containing _posts. Marginstone searches this repository for existing book pages; it does not search other folders."
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        let path = url.resolvingSymlinksInPath().path
        guard repo.isEmpty || repo == path else { error = "This collection is already connected to \(repo). Select that checkout; multiple website repositories are not supported yet."; return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let previous = accessedWebsite { previous.stopAccessingSecurityScopedResource() }
            _ = url.startAccessingSecurityScopedResource()
            accessedWebsite = url; websiteBookmark = bookmark
            try persist()
            connect(path)
        } catch { self.error = "Could not remember website folder access. Please select the folder again." }
    }
    private func connect(_ path: String) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let (publicationBranch, imported) = try await engine.connect(repo: path, tree: tree)
                repo = path; branch = publicationBranch
                var all = Dictionary(uniqueKeysWithValues: imported.map { ($0.path, $0) })
                for source in sources where all[source.path] == nil { all[source.path] = source }
                sources = all.values.sorted { $0.title < $1.title }
                for index in passages.indices where passages[index].sourcePath == nil {
                    if let hint = CitationParser.books(passages[index].payload.text) {
                        passages[index].sourcePath = matchingSource(hint)
                    }
                }
                try persist()
                choosingSource = !unassigned.isEmpty
                status = "Connected · \(sources.count) book pages found · drafts save separately from the website."
                flush()
            } catch { self.error = error.localizedDescription; status = "Connection needs attention. Captures remain saved locally." }
        }
    }
    @discardableResult func receive(_ payload: CapturePayload) throws -> UUID {
        guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure(message: "The passage was empty.") }
        guard payload.text.utf8.count <= 2_000_000 else { throw AppFailure(message: "Choose a shorter passage (under 2 MB).") }
        var destination: String?
        if let hint = CitationParser.books(payload.text) {
            destination = matchingSource(hint)
        } else if let mapped = sourceAliases["url\n" + payload.url], !payload.url.isEmpty, sources.contains(where: { $0.path == mapped }) {
            destination = mapped
        } else if let title = payload.sourceTitle, !title.isEmpty {
            destination = matchingSource(SourceHint(title: title, author: payload.sourceAuthor ?? "", passage: payload.text))
        } else if pinSource, payload.url.isEmpty, payload.sourceTitle?.isEmpty != false, let currentSource { destination = currentSource.path }
        if let existing = passages.first(where: {
            $0.sourcePath == destination && $0.payload.text == payload.text && $0.payload.url == payload.url
        }) {
            status = "This passage is already saved. No duplicate was added."
            if existing.sourcePath == nil { choosingSource = true; openCollection?() }
            return existing.id
        }
        let passage = SavedPassage(payload: payload, sourcePath: destination)
        passages.insert(passage, at: 0)
        do { try persist() } catch { passages.removeAll { $0.id == passage.id }; throw error }
        if destination == nil {
            status = "Passage saved. Choose its book or source."
            choosingSource = true; openCollection?()
        } else { status = repo.isEmpty ? "Saved locally" : "Saved locally. Updating the book’s draft…"; flush() }
        return passage.id
    }
    func showWebCaptureHelp() {
        do {
            guard let page = AppResources.bundle.url(forResource: "web-capture", withExtension: "html", subdirectory: "Resources"),
                  let artwork = AppResources.bundle.url(forResource: companion.rawValue, withExtension: "png", subdirectory: "Resources") else { throw AppFailure(message: "Browser setup is missing. Reinstall Marginstone.") }
            let folder = support.appendingPathComponent("BrowserSetup")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(contentsOf: artwork).write(to: folder.appendingPathComponent("companion.png"), options: .atomic)
            let destination = folder.appendingPathComponent("index.html")
            try Data(contentsOf: page).write(to: destination, options: .atomic)
            NSWorkspace.shared.open(destination)
        } catch { self.error = error.localizedDescription }
    }
    func captureClipboard() {
        do { _ = try receive(CaptureReader.read(.general)); captured?() }
        catch { self.error = error.localizedDescription; openCollection?() }
    }
    func lookupSource(_ passage: SavedPassage, url: String? = nil) async throws -> SourceMetadata {
        let value = url ?? passage.payload.url
        let metadata = try await WebSource.lookup(value)
        guard let index = passages.firstIndex(where: { $0.id == passage.id }) else { return metadata }
        let old = passages[index]
        passages[index].payload.url = value
        if passages[index].payload.sourceTitle?.isEmpty != false { passages[index].payload.sourceTitle = metadata.title }
        if passages[index].payload.sourceAuthor?.isEmpty != false { passages[index].payload.sourceAuthor = metadata.author }
        do { try persist() } catch { passages[index] = old; throw error }
        return metadata
    }
    func setCaptureSource(_ id: UUID, title: String, author: String, url: String) throws {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        let old = passages[index]
        passages[index].payload.sourceTitle = title
        passages[index].payload.sourceAuthor = author
        passages[index].payload.url = url
        do { try persist() } catch { passages[index] = old; throw error }
    }
    func createSource(_ source: BookSource) {
        let before = sources
        sources.append(source); sources.sort { $0.title < $1.title }
        do { try persist(); activePath = source.path; flush() }
        catch { sources = before; self.error = error.localizedDescription }
    }
    func assign(_ id: UUID, to source: BookSource) {
        guard let index = passages.firstIndex(where: { $0.id == id }) else { return }
        let old = passages[index]; let oldSources = sources; let oldAliases = sourceAliases
        if !sources.contains(where: { $0.path == source.path }) { sources.append(source); sources.sort { $0.title < $1.title } }
        passages[index].sourcePath = source.path
        if let hint = CitationParser.books(passages[index].payload.text) { sourceAliases[hintKey(hint)] = source.path }
        if !passages[index].payload.url.isEmpty { sourceAliases["url\n" + passages[index].payload.url] = source.path }
        do { try persist(); activePath = source.path; choosingSource = false; flush() }
        catch { passages[index] = old; sources = oldSources; sourceAliases = oldAliases; self.error = error.localizedDescription }
    }
    func flush() {
        guard !repo.isEmpty, !needsWebsiteAccess else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            busy = true; defer { busy = false }
            for book in sources {
                do {
                    if let warning = try await engine.create(book: book, tree: tree, push: false) { status = warning }
                } catch { self.error = error.localizedDescription; return }
            }
            for passage in pending.reversed() {
                guard let source = sources.first(where: { $0.path == passage.sourcePath }) else { continue }
                do {
                    let warning = try await engine.write(passage, book: source, tree: tree, push: false)
                    if let index = passages.firstIndex(where: { $0.id == passage.id }) { passages[index].written = true }
                    try persist()
                    status = warning ?? "Saved to \(source.path)"
                } catch { self.error = error.localizedDescription; status = "Passage retained locally; retry saving when ready."; break }
            }
        }
    }
    func updateCover(_ source: BookSource, cover: String) {
        guard !busy, let index = sources.firstIndex(where: { $0.path == source.path }) else { return }
        let old = sources[index]
        sources[index].cover = cover
        do { try persist() } catch { sources[index] = old; self.error = error.localizedDescription; return }
        guard !repo.isEmpty, !needsWebsiteAccess else { return }
        let book = sources[index]
        busy = true
        Task {
            defer { busy = false }
            do {
                try await engine.updateCover(book: book, tree: tree, push: false)
                status = "Cover saved to the local draft. Publish separately to update the website."
            } catch { self.error = error.localizedDescription }
        }
    }
    func loadPost(_ book: BookSource) async throws -> PostDocument {
        guard !needsWebsiteAccess else { throw AppFailure(message: "Allow access to your website folder in Settings first. Your captures are safe.") }
        return try await engine.loadPost(book: book, repo: repo, tree: tree, edited: postEdits[book.path] != nil)
    }
    func savePost(_ book: BookSource, document: PostDocument, text: String) async throws {
        guard !busy else { throw AppFailure(message: "Wait for the current save to finish.") }
        guard text != document.text else { return }
        busy = true; defer { busy = false }
        // Record the publication baseline before touching the draft, so a retry
        // or restart retains the overwrite protection even if a Git commit fails.
        let previousBaseline = postEdits[book.path]
        if previousBaseline == nil { postEdits[book.path] = PostEditBaseline(published: document.published) }
        try persist()
        do { try await engine.savePost(book: book, document: document, text: text, tree: tree) }
        catch {
            if let current = try? await engine.loadPost(book: book, repo: repo, tree: tree, edited: true), current.draftSnapshot == document.draftSnapshot {
                postEdits[book.path] = previousBaseline
                try? persist()
            }
            throw error
        }
        if let updated = Markdown.source(path: book.path, text: text), let index = sources.firstIndex(where: { $0.path == book.path }) { sources[index] = updated }
        try persist()
        status = "Post changes saved to the local draft. Publish separately to upload."
    }
    func editPassage(_ passage: SavedPassage, text: String) async throws {
        guard !busy else { throw AppFailure(message: "Wait for the current save to finish.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 2_000_000 else { throw AppFailure(message: "Enter a passage between 1 byte and 2 MB.") }
        guard let index = passages.firstIndex(where: { $0.id == passage.id }), passages[index].displayText == passage.displayText else { throw AppFailure(message: "This excerpt changed. Reopen the editor.") }
        if text == passage.displayText { return }
        if !repo.isEmpty, let book = sources.first(where: { $0.path == passage.sourcePath }) {
            let document = try await loadPost(book)
            guard let updated = Markdown.editingExcerpt(in: document.text, passage: passage, text: text) else {
                throw AppFailure(message: "This excerpt was changed in the full post. Use View & edit post to edit that version.")
            }
            try await savePost(book, document: document, text: updated)
        }
        guard let savedIndex = passages.firstIndex(where: { $0.id == passage.id }) else { throw AppFailure(message: "The excerpt is no longer in the collection.") }
        let previous = passages[savedIndex]
        passages[savedIndex].editedText = text
        do { try persist() } catch { passages[savedIndex] = previous; throw error }
        status = "Excerpt edits saved locally. The original copy remains in Original excerpt."
    }
    func requestDeletePassage(_ passage: SavedPassage) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this excerpt?"
        if !repo.isEmpty { alert.informativeText = "Your live website won’t change." }
        alert.addButton(withTitle: "Delete excerpt")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do { try await deletePassage(passage) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func deletePassage(_ passage: SavedPassage) async throws {
        guard !busy, passages.contains(where: { $0.id == passage.id }) else { return }
        // Back up the complete journal before changing either the draft or capture.
        let backup = support.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("delete-" + passage.id.uuidString + "-" + UUID().uuidString + ".json")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: journal, to: backup)
        if !repo.isEmpty, let book = sources.first(where: { $0.path == passage.sourcePath }) {
            let document: PostDocument?
            if passage.written { document = try await loadPost(book) }
            else { document = try? await loadPost(book) }
            if let document {
                if let updated = Markdown.removingExcerpt(in: document.text, passage: passage) {
                    try await savePost(book, document: document, text: updated)
                } else if passage.written {
                    throw AppFailure(message: "The quote was changed in the full post or matches more than one quotation. Use View & edit post to remove it safely. The capture has not been deleted.")
                }
            }
        }
        let before = passages
        passages.removeAll { $0.id == passage.id }
        do { try persist() } catch { passages = before; throw error }
        if unassigned.isEmpty { choosingSource = false }
        status = "Excerpt deleted locally. A recovery backup is in the collection folder. Website changes require Publish."
    }
    func connectGitHub() {
        guard !busy, !repo.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Connect GitHub"
        alert.informativeText = "Create a fine-grained token for this website repository with Contents: Read and write. Paste it below to save it in macOS Keychain. Connecting tests access without uploading your posts."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "GitHub access token"; alert.accessoryView = field
        alert.addButton(withTitle: "Connect"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Create token…")
        while true {
            let response = alert.runModal()
            if response == .alertThirdButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://github.com/settings/personal-access-tokens/new")!); continue
            }
            guard response == .alertFirstButtonReturn else { return }
            break
        }
        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); field.stringValue = ""
        busy = true
        Task {
            defer { busy = false }
            do {
                try await engine.connectGitHub(repo: repo, branch: branch, token: token)
                let done = NSAlert(); done.messageText = "GitHub connected"; done.informativeText = "Nothing was uploaded. Use Publish when you’re ready."; done.runModal()
            } catch { self.error = error.localizedDescription }
        }
    }
    func publish(_ book: BookSource, onError: ((String) -> Void)? = nil) {
        guard !busy else { return }
        guard !needsWebsiteAccess else {
            let message = "Allow access to your website folder in Settings before publishing."
            if let onError { onError(message) } else { error = message }; return
        }
        guard pending.isEmpty else {
            let message = "Some excerpts still need saving to the post. Choose Retry saving, then publish again."
            if let onError { onError(message) } else { error = message }
            return
        }
        let alert = NSAlert(); alert.messageText = "Publish \(book.title)?"
        alert.informativeText = "This uploads changes to GitHub using the Git credentials configured on this Mac. It adds the captured excerpts to \(book.path) on \(branch), commits that post, and pushes it to your repository. Your website’s normal deployment will then run. Existing review text is preserved."
        alert.addButton(withTitle: "Publish"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await engine.publish(book: book, repo: repo, tree: tree, branch: branch, baseline: postEdits[book.path]); postEdits.removeValue(forKey: book.path); try persist(); status = "Published \(book.title). GitHub is building the website." }
            catch { if let onError { onError(error.localizedDescription) } else { self.error = error.localizedDescription } }
        }
    }
    private func matchingSource(_ hint: SourceHint) -> String? {
        if let mapped = sourceAliases[hintKey(hint)], sources.contains(where: { $0.path == mapped }) { return mapped }
        func normalized(_ value: String, title: Bool = false) -> String {
            let text = title ? value.replacingOccurrences(of: #"\s*\(\d{4}\)\s*$"#, with: "", options: .regularExpression) : value
            return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let matches = sources.filter {
            normalized($0.title, title: true) == normalized(hint.title, title: true) &&
            (hint.author.isEmpty || normalized($0.author) == normalized(hint.author))
        }
        return matches.count == 1 ? matches[0].path : nil
    }
    private func hintKey(_ hint: SourceHint) -> String { (hint.title + "\n" + hint.author).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    func newPath(title: String, author: String) -> String {
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd"; format.locale = Locale(identifier: "en_US_POSIX")
        let stem = "_posts/\(format.string(from: Date()))-\(Markdown.slug(author + " " + title))"
        var path = stem + ".md"; var n = 2
        while sources.contains(where: { $0.path == path }) || FileManager.default.fileExists(atPath: URL(fileURLWithPath: tree).appendingPathComponent(path).path) { path = stem + "-\(n).md"; n += 1 }
        return path
    }
    func revealDraft() { NSWorkspace.shared.open(URL(fileURLWithPath: tree).appendingPathComponent("_posts")) }
    func saveToFile(sourcePath: String? = nil) {
        let panel = NSSavePanel()
        panel.title = "Save excerpts"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        if let path = sourcePath, let book = sources.first(where: { $0.path == path }) {
            panel.nameFieldStringValue = Markdown.slug(book.title) + ".md"
        } else { panel.nameFieldStringValue = "marginstone-excerpts.md" }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = MarkdownExport.document(passages: passages, sources: sources, sourcePath: sourcePath)
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = "Saved to " + url.lastPathComponent
        } catch { self.error = error.localizedDescription }
    }
    func revealCollection() { NSWorkspace.shared.open(support) }
}
