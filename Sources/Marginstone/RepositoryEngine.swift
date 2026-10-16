import Foundation
import MarginstoneCore

struct AppFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
actor RepositoryEngine {
    private var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    private func run(_ arguments: [String]) throws -> String {
        guard let helper = AppResources.bundle.url(forResource: "repository", withExtension: "sh", subdirectory: "Resources") else { throw AppFailure(message: "The repository helper is missing from the app.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper.path] + arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw AppFailure(message: String(output.suffix(3000))) }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func saveDiagnostics(_ text: String) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nautilus")
        try? text.write(to: folder.appendingPathComponent("publication-diagnostics.txt"), atomically: true, encoding: .utf8)
    }
    func checkUpload(repo: String, branch: String) throws {
        do { _ = try run(["check-upload", repo, branch]) }
        catch {
            saveDiagnostics(error.localizedDescription)
            throw AppFailure(message: "GitHub connection needs attention. Your excerpts are safe. Use Connect GitHub… in Settings before publishing.")
        }
    }
    func connectGitHub(repo: String, branch: String, token: String) throws {
        let remote = try run(["remote", repo])
        guard let url = URL(string: remote), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil else {
            throw AppFailure(message: "This connection option requires an HTTPS github.com remote. SSH repositories can use their existing SSH setup.")
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.split(separator: "/").count == 2, !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else { throw AppFailure(message: "Enter a valid GitHub access token.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo, "-c", "credential.helper=", "-c", "credential.helper=osxkeychain", "credential", "approve"]
        let input = Pipe(); let output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("protocol=https\nhost=github.com\npath=\(path)\nusername=x-access-token\npassword=\(token)\n\n".utf8))
        try input.fileHandleForWriting.close()
        _ = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppFailure(message: "Could not save the connection in macOS Keychain.") }
        _ = try run(["configure-keychain", repo])
        try checkUpload(repo: repo, branch: branch)
    }
    func connect(repo: String, tree: String) throws -> (String, [BookSource]) {
        let result = try run(["setup", repo, tree])
        guard let branch = result.components(separatedBy: .newlines).last(where: { $0.hasPrefix("MARGINSTONE_BRANCH=") })?.dropFirst("MARGINSTONE_BRANCH=".count) else { throw AppFailure(message: result) }
        let folder = URL(fileURLWithPath: tree).appendingPathComponent("_posts")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let books = files.filter { $0.pathExtension == "md" }.compactMap { file -> BookSource? in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return Markdown.source(path: "_posts/" + file.lastPathComponent, text: text)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return (String(branch), books)
    }
    func create(book: BookSource, tree: String, push: Bool) throws -> String? {
        guard Markdown.safePath(book.path) else { throw AppFailure(message: "Invalid post filename.") }
        let path = URL(fileURLWithPath: tree).appendingPathComponent(book.path)
        try checkPath(path, root: URL(fileURLWithPath: tree))
        let missing = !FileManager.default.fileExists(atPath: path.path)
        if missing {
            try Markdown.page(book, date: String(book.path.dropFirst(7).prefix(10))).write(to: path, atomically: true, encoding: .utf8)
        }
        // Recover an empty-page creation interrupted before its first commit.
        let page = try String(contentsOf: path, encoding: .utf8)
        if missing || (page.contains("nautilus_edition:") && Markdown.blocks(page).isEmpty) {
            _ = try run(["commit", tree, book.path])
            if push {
                do { _ = try run(["push-drafts", tree]) }
                catch { return "Book page created locally; GitHub sync needs attention: \(error.localizedDescription)" }
            }
            return "Book draft ready: \(book.path)"
        }
        return nil
    }
    func write(_ p: SavedPassage, book: BookSource, tree: String, push: Bool) throws -> String? {
        guard Markdown.safePath(book.path) else { throw AppFailure(message: "Invalid post filename.") }
        let path = URL(fileURLWithPath: tree).appendingPathComponent(book.path)
        // Refuse symlinks so repository content cannot redirect a write outside _posts.
        try checkPath(path, root: URL(fileURLWithPath: tree))
        let exists = FileManager.default.fileExists(atPath: path.path)
        let original = exists ? try String(contentsOf: path, encoding: .utf8) : Markdown.page(book, date: String(book.path.dropFirst(7).prefix(10)))
        let marker = "<!-- nautilus:\(p.id.uuidString) -->"
        if !original.contains(marker) {
            let hint = CitationParser.books(p.payload.text)
            let text = p.editedText ?? hint?.passage ?? p.payload.text
            let updated = Markdown.append(Markdown.block(p, text: text), to: original)
            if updated != original {
                try Markdown.updatingModifiedDate(updated, date: today).write(to: path, atomically: true, encoding: .utf8)
            }
        }
        _ = try run(["commit", tree, book.path])
        if push {
            do { _ = try run(["push-drafts", tree]) }
            catch { return "Saved to the draft branch on this Mac. GitHub sync needs attention: \(error.localizedDescription)" }
        }
        return nil
    }
    func updateCover(book: BookSource, tree: String, push: Bool) throws {
        let path = URL(fileURLWithPath: tree).appendingPathComponent(book.path)
        try checkPath(path, root: URL(fileURLWithPath: tree))
        let original = try String(contentsOf: path, encoding: .utf8)
        let updated = Markdown.updatingCover(original, cover: book.cover)
        if updated != original {
            try Markdown.updatingModifiedDate(updated, date: today).write(to: path, atomically: true, encoding: .utf8)
            _ = try run(["commit", tree, book.path])
            if push { _ = try run(["push-drafts", tree]) }
        }
    }
    func loadPost(book: BookSource, repo: String, tree: String, edited: Bool) throws -> PostDocument {
        let root = URL(fileURLWithPath: tree)
        let draftURL = root.appendingPathComponent(book.path)
        try checkPath(draftURL, root: root)
        let raw = try String(contentsOf: draftURL, encoding: .utf8)
        let publishedURL = URL(fileURLWithPath: repo).appendingPathComponent(book.path)
        try checkPath(publishedURL, root: URL(fileURLWithPath: repo))
        let published = FileManager.default.fileExists(atPath: publishedURL.path) ? try String(contentsOf: publishedURL, encoding: .utf8) : nil
        let text = Markdown.publication(draft: raw, published: edited ? nil : published, date: today)
        return PostDocument(text: text, draftSnapshot: raw, published: published)
    }
    func savePost(book: BookSource, document: PostDocument, text: String, tree: String) throws {
        guard Markdown.source(path: book.path, text: text) != nil else {
            throw AppFailure(message: "Keep the post’s header, title, and source type. The draft has not been changed.")
        }
        let path = URL(fileURLWithPath: tree).appendingPathComponent(book.path)
        try checkPath(path, root: URL(fileURLWithPath: tree))
        guard try String(contentsOf: path, encoding: .utf8) == document.draftSnapshot else {
            throw AppFailure(message: "The draft changed while this editor was open. Cancel and reopen it to load the latest version.")
        }
        if text != document.text {
            let updated = Markdown.updatingModifiedDate(text, date: today)
            try updated.write(to: path, atomically: true, encoding: .utf8)
            _ = try run(["commit", tree, book.path])
        }
    }
    func sync(tree: String) throws { _ = try run(["push-drafts", tree]) }
    func publish(book: BookSource, repo: String, tree: String, branch: String, baseline: PostEditBaseline? = nil) throws {
        try checkUpload(repo: repo, branch: branch)
        do { _ = try run(["check-publish", repo, branch, book.path]) }
        catch {
            saveDiagnostics(error.localizedDescription)
            throw AppFailure(message: "The website checkout needs attention before publishing. Your draft is safe. In GitHub Desktop, review any pending commits and pull or push as needed, then retry.")
        }
        let head = try run(["head", repo])
        let destination = URL(fileURLWithPath: repo).appendingPathComponent(book.path)
        try checkPath(destination, root: URL(fileURLWithPath: repo))
        let draftURL = URL(fileURLWithPath: tree).appendingPathComponent(book.path)
        try checkPath(draftURL, root: URL(fileURLWithPath: tree))
        let draft = try String(contentsOf: draftURL, encoding: .utf8)
        let existing = FileManager.default.fileExists(atPath: destination.path) ? try String(contentsOf: destination, encoding: .utf8) : nil
        var merged: String
        if let baseline {
            let edited = Markdown.publication(draft: draft, published: nil, date: today)
            guard existing == baseline.published || existing == edited else {
                throw AppFailure(message: "The website post changed after you started editing. Your draft is safe. Review both versions before publishing; Marginstone will not overwrite those changes.")
            }
            merged = edited
        } else { merged = Markdown.publication(draft: draft, published: existing, date: today) }
        if !book.cover.isEmpty {
            let withCover = Markdown.updatingCover(merged, cover: book.cover)
            if withCover != merged { merged = Markdown.updatingModifiedDate(withCover, date: today) }
        }
        try merged.write(to: destination, atomically: true, encoding: .utf8)
        do { _ = try run(["publish", repo, branch, book.path, head]) }
        catch {
            let detail = error.localizedDescription
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nautilus")
            try? detail.write(to: folder.appendingPathComponent("publication-diagnostics.txt"), atomically: true, encoding: .utf8)
            throw AppFailure(message: "Publication did not finish. Your post is saved locally. Check your GitHub connection in Settings, then retry. Technical details are in the collection folder.")
        }
    }
    private func checkPath(_ path: URL, root: URL) throws {
        let expected = root.resolvingSymlinksInPath().appendingPathComponent("_posts").path
        guard root.appendingPathComponent("_posts").resolvingSymlinksInPath().path == expected,
              path.resolvingSymlinksInPath().deletingLastPathComponent().path == expected else { throw AppFailure(message: "The post or _posts folder is a symbolic link. Choose a normal repository folder.") }
    }
}
