import AppKit
import SwiftUI
import MarginstoneCore

// SDK 27 also exports a State macro, whose plugin may be absent from the
// standalone Command Line Tools. Refer to the existing generic wrapper type
// through a distinct name so this code does not request macro expansion.
private typealias LocalViewState<Value> = SwiftUI.State<Value>

extension Color {
    static let paper = Color(red: 245.0/255, green: 241.0/255, blue: 232.0/255)
    static let ink = Color(red: 29.0/255, green: 27.0/255, blue: 25.0/255)
    static let oxide = Color(red: 155.0/255, green: 61.0/255, blue: 47.0/255)
}
private extension BookSource {
    var authorTitle: String { author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : "\(author) — \(title)" }
    var dropdownTitle: String { authorSortKey.isEmpty ? title : "\(authorSortKey) — \(title)" }
    var authorSortKey: String {
        let clean = author.trimmingCharacters(in: .whitespacesAndNewlines)
        // Also accept bibliographic author strings already written Last, First.
        if let comma = clean.firstIndex(of: ",") { return String(clean[..<comma]) }
        return clean.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
    }
}
private func booksByAuthor(_ books: [BookSource]) -> [BookSource] {
    books.sorted { lhs, rhs in
        let lastName = lhs.authorSortKey.localizedStandardCompare(rhs.authorSortKey)
        if lastName != .orderedSame { return lastName == .orderedAscending }
        let author = lhs.author.localizedStandardCompare(rhs.author)
        if author != .orderedSame { return author == .orderedAscending }
        let title = lhs.title.localizedStandardCompare(rhs.title)
        return title == .orderedSame ? lhs.path < rhs.path : title == .orderedAscending
    }
}
@MainActor
struct LibraryView: View {
    @ObservedObject var model: AppModel
    var showCompanion: () -> Void
    @LocalViewState private var search = ""
    @LocalViewState private var selecting: SavedPassage?
    @LocalViewState private var inspecting: SavedPassage?
    @LocalViewState private var selectedPath = ""
    @LocalViewState private var creating = false
    @LocalViewState private var editingPassage: SavedPassage?
    @LocalViewState private var editingPost: BookSource?
    @LocalViewState private var savedNotice = ""
    private var selectedBook: BookSource? { model.sources.first { $0.path == selectedPath } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                if let image = model.companion.image {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 112, height: 112)
                        .accessibilityLabel(model.companion.name)
                }
                HStack(spacing: 10) {
                    VStack(spacing: 12) {
                        SourceFilter(selection: $selectedPath, sources: booksByAuthor(model.sources))
                            .frame(maxWidth: .infinity).frame(height: 28)
                        TextField("Search excerpts", text: $search).textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity).frame(height: 28)
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Spacer()
                            Button { creating = true } label: { Image(systemName: "plus") }.help("Add a source").accessibilityLabel("Add a source")
                            Button { model.showingSettings = true } label: { Image(systemName: "gearshape") }.help("Settings").accessibilityLabel("Settings")
                        }.frame(height: 28)
                        Button("Export…") { model.saveToFile(sourcePath: selectedPath.isEmpty ? nil : selectedPath) }.disabled(model.passages.isEmpty).frame(height: 28)
                    }.fixedSize(horizontal: true, vertical: false)
                }.frame(maxWidth: .infinity)

            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.passages.isEmpty {
                        Text("Select a passage and drop it onto your companion. You can also right-click the companion and choose Capture clipboard.")
                            .font(.system(size: 20, design: .serif)).lineSpacing(6).padding(.vertical, 45)
                    }
                    ForEach(model.passages.filter { p in
                        (selectedPath.isEmpty || p.sourcePath == selectedPath) &&
                        (search.isEmpty || (p.displayText + " " + (model.sources.first { $0.path == p.sourcePath }.map { $0.authorTitle } ?? "")).localizedCaseInsensitiveContains(search))
                    }) { passage in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if passage.sourcePath == nil {
                                    Button("Unknown source · Add details…") { selecting = passage }.buttonStyle(.plain).foregroundColor(.oxide).disabled(model.busy)
                                } else {
                                    Text(model.sources.first { $0.path == passage.sourcePath }?.dropdownTitle ?? "Unknown source").foregroundColor(.oxide)
                                }
                                Spacer()
                                Text(passage.capturedAt, style: .date).foregroundColor(.secondary)
                                Menu {
                                    Button("Edit excerpt…") { editingPassage = passage }
                                    Button("Choose source…") { selecting = passage }
                                    Button("Original excerpt") { inspecting = passage }
                                    if !model.repo.isEmpty, model.sources.contains(where: { $0.path == passage.sourcePath }) {
                                        Button(passage.written ? "Edit website post…" : "Add excerpt to website post…") {
                                            Task {
                                                do { editingPost = try await model.prepareWebsitePost(for: passage) }
                                                catch is CancellationError { }
                                                catch { model.error = error.localizedDescription }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Delete excerpt…", role: .destructive) { model.requestDeletePassage(passage) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Excerpt actions").accessibilityLabel("Excerpt actions").disabled(model.busy)
                            }.font(.system(size: 11))
                            Button { editingPassage = passage } label: {
                                JustifiedExcerpt(text: passage.displayText)
                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }.buttonStyle(.plain).disabled(model.busy).help("Click to edit excerpt")
                        }.padding(19).background(Color.white.opacity(0.55)).cornerRadius(7)
                    }
                }
            }
            if model.busy {
                HStack { ProgressView().controlSize(.small); Text("Saving…").font(.caption).foregroundColor(.secondary) }
            } else if !savedNotice.isEmpty { Text(savedNotice).font(.caption).foregroundColor(.secondary) }
        }.padding(25).frame(minWidth: 680, minHeight: 560).background(Color.paper).foregroundColor(.ink).tint(.oxide).preferredColorScheme(.light)
        .onAppear { showPending() }
        .onChange(of: selectedPath) { model.activePath = $0.isEmpty ? nil : $0 }
        .onChange(of: model.choosingSource) { if $0 { showPending() } }
        .onChange(of: model.status) { status in
            guard ["Saved to ", "Saved locally", "Passage saved", "Cover saved", "Excerpt edits saved"].contains(where: { status.hasPrefix($0) }) else { return }
            savedNotice = model.passages.first.map { passage in
                passage.sourcePath.flatMap { path in model.sources.first { $0.path == path }.map { "Saved to " + $0.title } } ?? "Saved locally"
            } ?? ""
        }
        .task(id: savedNotice) {
            guard !savedNotice.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { savedNotice = "" }
        }
        .sheet(isPresented: $model.showingSettings) { CollectionSettings(model: model, showCompanion: showCompanion) }
        .sheet(item: $selecting, onDismiss: { model.choosingSource = false }) { passage in SourcePicker(model: model, passage: passage) }
        .sheet(item: $editingPassage) { passage in ExcerptEditor(model: model, passage: passage) }
        .sheet(item: $editingPost) { book in PostEditor(model: model, book: book) }
        .sheet(isPresented: $creating) { SourcePicker(model: model, passage: nil) }
        .sheet(item: $inspecting) { passage in CaptureDetails(passage: passage, source: model.sources.first { $0.path == passage.sourcePath }) }
        .alert("Marginstone", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if !model.pending.isEmpty && !model.repo.isEmpty && !model.needsWebsiteAccess {
                Button("Retry saving") { model.error = nil; model.flush() }
            }
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func showPending() { if model.choosingSource, selecting == nil { selecting = model.unassigned.first } }
}

// Native popup fills the same flexible column as Search instead of centering
// an intrinsic-width SwiftUI picker inside a wider frame.
@MainActor
private struct SourceFilter: NSViewRepresentable {
    @Binding var selection: String
    var sources: [BookSource]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.font = .systemFont(ofSize: 13)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("Source")
        button.target = context.coordinator; button.action = #selector(Coordinator.changed(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let entries = [("", "All excerpts")] + sources.map { ($0.path, $0.dropdownTitle) }
        if button.itemArray.map({ $0.representedObject as? String ?? "" }) != entries.map({ $0.0 }) || button.itemTitles != entries.map({ $0.1 }) {
            button.removeAllItems()
            for (path, title) in entries {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = path
                item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor(red: 155.0/255, green: 61.0/255, blue: 47.0/255, alpha: 1)])
                button.menu?.addItem(item)
            }
        }
        button.selectItem(at: entries.firstIndex(where: { $0.0 == selection }) ?? 0)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SourceFilter
        init(_ parent: SourceFilter) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) { parent.selection = sender.selectedItem?.representedObject as? String ?? "" }
    }
}

@MainActor
struct CollectionSettings: View {
    @ObservedObject var model: AppModel
    var showCompanion: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Settings").font(.title2); Spacer(); Button("Done") { dismiss() } }
            VStack(alignment: .leading, spacing: 12) {
                Text("Companion").font(.headline)
                    HStack(spacing: 0) {
                        ForEach(Companion.allCases) { companion in
                            Button {
                                model.companion = companion
                                showCompanion()
                            } label: {
                                VStack(spacing: 7) {
                                    Group {
                                        if let image = companion.image {
                                            Image(nsImage: image).resizable().scaledToFit()
                                        }
                                    }.frame(width: 66, height: 66).padding(8)
                                        .background(model.companion == companion ? Color.oxide.opacity(0.06) : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.companion == companion ? Color.oxide : Color.clear, lineWidth: 2))
                                    Text(companion.name).font(.system(size: 12))
                                        .foregroundColor(model.companion == companion ? .oxide : .ink)
                                }
                            }.buttonStyle(.plain).help(companion.name)
                                .accessibilityLabel(companion.name)
                                .accessibilityValue(model.companion == companion ? "Selected" : "Not selected")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Toggle("Loiter in corner", isOn: $model.movesSideToSide).toggleStyle(.button).controlSize(.small)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture").font(.headline)
                Toggle("Use the selected source for text without a citation", isOn: $model.pinSource).disabled(model.currentSource == nil)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Save").font(.headline)
                Text("Your captures are saved on this Mac.").font(.system(size: 13)).foregroundColor(.secondary)
                Button("Export excerpts…") { model.saveToFile() }.disabled(model.passages.isEmpty)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Website").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    if model.repo.isEmpty {
                        Text("Publish excerpts to your website.").font(.system(size: 13)).foregroundColor(.secondary)
                        Button("Choose website folder…", action: model.chooseRepository).disabled(model.busy)
                    } else {
                        if model.needsWebsiteAccess {
                            Text("Your website folder is saved. Restore access to use it.").font(.system(size: 13)).foregroundColor(.secondary)
                            Button("Restore access to website folder…", action: model.chooseRepository).disabled(model.busy)
                        } else {
                            if model.githubConnected {
                                HStack(spacing: 6) {
                                    Text("GitHub")
                                    Spacer()
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundColor(.oxide)
                                    Text("Connected").foregroundColor(.secondary)
                                }
                            } else {
                                Button("Connect GitHub…", action: model.connectGitHub).disabled(model.busy)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Folder")
                            Text(URL(fileURLWithPath: model.repo).lastPathComponent)
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }.font(.system(size: 12)).foregroundColor(.secondary).help(model.repo)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }


        }.font(.system(size: 13)).padding(24).frame(width: 560).background(Color.paper).foregroundColor(.ink).tint(.oxide).preferredColorScheme(.light)
        .task { await model.checkGitHubConnection() }
    }
}

@MainActor
struct SourcePicker: View {
    @ObservedObject var model: AppModel
    let passage: SavedPassage?
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var existing = ""
    @LocalViewState private var title = ""
    @LocalViewState private var author = ""
    @LocalViewState private var cover = ""
    @LocalViewState private var edition = ""
    @LocalViewState private var works: [WorkResult] = []
    @LocalViewState private var editions: [EditionResult] = []
    @LocalViewState private var selectedWork: WorkResult?
    @LocalViewState private var loading = false
    @LocalViewState private var message = ""
    @LocalViewState private var offset = 0
    @LocalViewState private var choosingCover = false
    @LocalViewState private var sourceURL = ""
    @LocalViewState private var creatingSource = false
    @LocalViewState private var findingYear = false
    @LocalViewState private var sourceKind = "other"
    var body: some View {
        sourceForm
            .sheet(isPresented: $choosingCover) { CoverPicker(title: title, author: author) { cover = $0 } }
            .onAppear(perform: prepareSource)
            .onChange(of: sourceURL) { value in
                if !value.isEmpty && sourceKind == "other" { sourceKind = "article" }
            }
            .task(id: publicationLookupKey) { await lookupPublicationYear() }
            .task { await lookupInitialMetadata() }
    }
    private var publicationLookupKey: String {
        [sourceKind, PublicationYear.baseTitle(title), author].joined(separator: "\n")
    }
    private var sourceForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(passage == nil ? "Add a source" : "Add source").font(.system(size: 26, design: .serif))
                Spacer()
                Button("Later") { dismiss() }
            }
            Text(passage == nil ? "Keep passages from the same book or essay together." : "Your passage is saved locally. Choose its source below.")
                .font(.system(size: 12)).foregroundColor(.secondary)
            if passage != nil && !model.sources.isEmpty {
                existingSourceFields
                Divider()
            }
            if passage == nil {
                newSourceFields
            } else {
                DisclosureGroup("Add source details…", isExpanded: $creatingSource) { newSourceFields }
            }
        }.padding(25).frame(width: 660).background(Color.paper).foregroundColor(.ink).tint(.oxide).preferredColorScheme(.light)
    }
    private var existingSourceFields: some View {
        HStack {
            Picker("Source", selection: $existing) {
                Text("Choose a source…").tag("")
                ForEach(booksByAuthor(model.sources)) { Text($0.dropdownTitle).tag($0.path) }
            }
            Button("Use this source", action: useExistingSource).disabled(existing.isEmpty)
        }
    }
    private func useExistingSource() {
        guard let passage, let source = model.sources.first(where: { $0.path == existing }) else { return }
        model.assign(passage.id, to: source); dismiss()
    }
    private func prepareSource() {
        if let passage, let hint = CitationParser.books(passage.payload.text) {
            title = hint.title; author = hint.author; sourceKind = "book"
        }
        if let passage {
            if title.isEmpty { title = passage.payload.sourceTitle ?? "" }
            if author.isEmpty { author = passage.payload.sourceAuthor ?? "" }
            sourceURL = passage.payload.url
            creatingSource = !title.isEmpty || !sourceURL.isEmpty
            if !sourceURL.isEmpty && CitationParser.books(passage.payload.text) == nil { sourceKind = "article" }
        }
        existing = passage?.sourcePath ?? ""
    }
    private func lookupPublicationYear() async {
        guard sourceKind == "book", title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              PublicationYear.fromTitle(title) == nil else { return }
        let requestedTitle = title; let requestedAuthor = author
        findingYear = true; defer { findingYear = false }
        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            if let year = try await OpenLibrary.publicationYear(title: requestedTitle, author: requestedAuthor),
               !Task.isCancelled, title == requestedTitle, author == requestedAuthor {
                title = PublicationYear.title(title, year: year)
            }
        } catch { }
    }
    private func lookupInitialMetadata() async {
        guard let passage, !passage.payload.url.isEmpty, CitationParser.books(passage.payload.text) == nil else { return }
        let missingTitle = passage.payload.sourceTitle?.isEmpty != false
        let missingAuthor = passage.payload.sourceAuthor?.isEmpty != false
        guard missingTitle || missingAuthor else { return }
        await lookUpSource(passage)
    }
    private var newSourceFields: some View {
        VStack(alignment: .leading, spacing: 15) {
            if CitationParser.books(passage?.payload.text ?? "") == nil {
                HStack {
                    TextField("Webpage link (if it wasn't included)", text: $sourceURL).textFieldStyle(.roundedBorder)
                    Button("Find source details") { Task { await lookUpSource(passage) } }.disabled(loading || sourceURL.isEmpty)
                }
            }
            Picker("Source type", selection: $sourceKind) {
                Text("Article or webpage").tag("article")
                Text("Book").tag("book")
                Text("Other / unknown").tag("other")
            }.pickerStyle(.segmented)

            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder)
            TextField("Author (optional)", text: $author).textFieldStyle(.roundedBorder)
            if sourceKind == "book" { bookSourceFields }
            if sourceKind != "book" && !message.isEmpty { Text(message).font(.caption).foregroundColor(.secondary) }
            HStack {
                Spacer()
                Button(passage == nil ? "Add source" : "Save source") {
                    let enteredTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanTitle = enteredTitle.isEmpty ? (URL(string: sourceURL)?.host ?? "Unknown source") : enteredTitle
                    let source = BookSource(path: model.newPath(title: cleanTitle, author: author), title: cleanTitle, author: author, cover: sourceKind == "book" ? cover : "", edition: sourceKind == "book" ? edition : "", kind: sourceKind)
                    if let passage {
                        do { try model.setCaptureSource(passage.id, title: cleanTitle, author: author, url: sourceURL); model.assign(passage.id, to: source); dismiss() }
                        catch { message = error.localizedDescription }
                    } else { model.createSource(source); dismiss() }
                }.disabled(sourceKind == "book" && findingYear)
            }
        }
    }
    private var bookSourceFields: some View {
        VStack(alignment: .leading, spacing: 15) {
            if findingYear { Text("Looking up first publication year…").font(.caption).foregroundColor(.secondary) }
            HStack {
                Button("Find books & editions", action: search).disabled(loading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if loading { ProgressView().controlSize(.small) }
                Text(message).font(.system(size: 11)).foregroundColor(.secondary)
            }
            if !works.isEmpty || !editions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if selectedWork == nil {
                            ForEach(works) { work in
                                Button { loadEditions(work) } label: {
                                    HStack { coverImage(work.coverURL); VStack(alignment: .leading) { Text(work.title); Text((work.author_name ?? []).joined(separator: ", ")).font(.system(size: 11)).foregroundColor(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.padding(7)
                                }.buttonStyle(.plain)
                            }
                        } else {
                            Button("← Book results") { selectedWork = nil; editions = [] }
                            ForEach(editions) { item in
                                Button {
                                    cover = item.cover; edition = item.key + " · " + item.label
                                    message = "Edition selected."
                                } label: {
                                    HStack { coverImage(URL(string: item.cover)); VStack(alignment: .leading) { Text(item.title); Text(item.label).font(.system(size: 11)).foregroundColor(.secondary) }; Spacer(); if edition.hasPrefix(item.key + " ·") { Image(systemName: "checkmark.circle.fill").foregroundColor(.oxide) } }.padding(7)
                                }.buttonStyle(.plain)
                            }
                            Button("More editions") { if let selectedWork { offset += 50; loadEditions(selectedWork, more: true) } }.disabled(loading)
                        }
                    }
                }.frame(height: 220).background(Color.white.opacity(0.4)).cornerRadius(6)
            }
            HStack {
                if !cover.isEmpty { coverImage(URL(string: cover)); Text("Cover selected").font(.caption) }
                Button("Choose cover from the internet…") { choosingCover = true }.disabled(title.isEmpty)
            }
            DisclosureGroup("Advanced: custom cover URL") {
                TextField("Cover URL", text: $cover).textFieldStyle(.roundedBorder)
            }
            if !edition.isEmpty { Text(edition).font(.system(size: 10)).foregroundColor(.secondary) }
        }
    }
    private func lookUpSource(_ passage: SavedPassage?) async {
        loading = true; defer { loading = false }
        do {
            let metadata: SourceMetadata
            if let passage { metadata = try await model.lookupSource(passage, url: sourceURL) }
            else { metadata = try await WebSource.lookup(sourceURL) }
            if title.isEmpty { title = metadata.title }
            if author.isEmpty { author = metadata.author }
            creatingSource = true
            message = metadata.title.isEmpty ? "Fill in any missing source details." : "Source details found. Please confirm them."
        } catch { message = error.localizedDescription; creatingSource = true }
    }
    private func coverImage(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "book.closed").foregroundColor(.secondary) }.frame(width: 42, height: 60)
    }
    private func search() {
        loading = true; message = "Searching…"; selectedWork = nil; editions = []
        Task {
            defer { loading = false }
            do { works = try await OpenLibrary.search(title: title, author: author); message = works.isEmpty ? "No results. You can still create the page." : "Choose a book to see its editions." }
            catch { message = error.localizedDescription }
        }
    }
    private func loadEditions(_ work: WorkResult, more: Bool = false) {
        loading = true; selectedWork = work
        if !more { editions = []; offset = 0; title = work.first_publish_year.map { PublicationYear.title(work.title, year: $0) } ?? work.title; author = (work.author_name ?? []).joined(separator: ", ") }
        Task {
            defer { loading = false }
            do { let next = try await OpenLibrary.editions(work: work, offset: offset); editions += next; message = next.isEmpty ? "No more editions found." : "Choose your edition and cover." }
            catch { message = error.localizedDescription }
        }
    }
}
@MainActor
struct CaptureDetails: View {
    let passage: SavedPassage
    let source: BookSource?
    @Environment(\.dismiss) private var dismiss
    private var citation: SourceHint? { CitationParser.books(passage.payload.text) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Original excerpt").font(.system(size: 25, design: .serif))
            if let title = source?.title ?? citation?.title ?? passage.payload.sourceTitle, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let author = source?.author ?? citation?.author ?? passage.payload.sourceAuthor, !author.isEmpty {
                Text(author).font(.subheadline).foregroundColor(.secondary)
            }
            Text(passage.capturedAt, style: .date).font(.caption).foregroundColor(.secondary)
            ScrollView {
                Text(citation?.passage ?? passage.payload.text)
                    .font(.system(size: 17, design: .serif)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 330)
            HStack {
                if let url = URL(string: passage.payload.url), ["https", "http", "ibooks", "books"].contains(url.scheme?.lowercased() ?? "") {
                    Link("Open source", destination: url)
                }
                Spacer(); Button("Done") { dismiss() }
            }
        }.padding(25).frame(width: 620).background(Color.paper).foregroundColor(.ink).preferredColorScheme(.light)
    }
}

@MainActor
struct CoverPicker: View {
    let title: String
    let author: String
    var choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var options: [CoverOption] = []
    @LocalViewState private var loading = true
    @LocalViewState private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Choose a cover").font(.title2); Spacer(); Button("Cancel") { dismiss() } }
            Text(author + " — " + title).font(.headline)
            Text("Choose the edition you recognise. Searches use Open Library and Goodreads.").font(.caption)
            if loading { ProgressView("Finding covers…") }
            if !message.isEmpty { Text(message).font(.caption) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 18) {
                    ForEach(options) { option in
                        VStack(spacing: 6) {
                            Button {
                                choose(option.imageURL); dismiss()
                            } label: {
                                VStack {
                                    AsyncImage(url: URL(string: option.imageURL)) { phase in
                                        if let image = phase.image { image.resizable().scaledToFit() }
                                        else { Image(systemName: "book.closed").foregroundColor(.secondary) }
                                    }.frame(width: 110, height: 155)
                                    Text(option.title).lineLimit(2)
                                    Text(option.detail).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity).padding(8)
                            }.buttonStyle(.plain)
                            if let url = URL(string: option.sourceURL) { Link("View edition", destination: url).font(.caption) }
                        }
                    }
                }
            }.frame(height: 380)
        }.padding(24).frame(width: 680).background(Color.paper).foregroundColor(.ink).tint(.oxide).preferredColorScheme(.light)
        .task { await load() }
    }
    private func load() async {
        defer { loading = false }
        async let open: [WorkResult]? = try? OpenLibrary.search(title: title, author: author)
        async let good: [CoverOption]? = try? BookCovers.goodreads(title: title, author: author)
        let (works, goodreads) = await (open, good)
        var all = (works ?? []).compactMap { work -> CoverOption? in
            guard let cover = work.coverURL else { return nil }
            return CoverOption(title: work.title, detail: "Open Library · " + (work.author_name ?? []).joined(separator: ", "), imageURL: cover.absoluteString.replacingOccurrences(of: "-M.jpg", with: "-L.jpg"), sourceURL: "https://openlibrary.org" + work.key)
        }
        all += goodreads ?? []
        var seen = Set<String>()
        options = all.filter { seen.insert($0.imageURL).inserted }
        if options.isEmpty { message = "No covers returned. Check your connection or try another title in the book form." }
        else if goodreads == nil || works == nil { message = "One source is unavailable; showing covers from the other source." }
    }
}

@MainActor
struct ExcerptEditor: View {
    @ObservedObject var model: AppModel
    let passage: SavedPassage
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var text = ""
    @LocalViewState private var saving = false
    @LocalViewState private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit excerpt").font(.title2)
            Text("Edits save locally. Your original copied text stays in Original excerpt.").font(.caption)
            TextEditor(text: $text).font(.system(size: 16, design: .serif)).frame(height: 340)
            if !error.isEmpty { Text(error).foregroundColor(.oxide).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.disabled(saving)
                Spacer()
                Button(saving ? "Saving…" : "Save draft") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await model.editPassage(passage, text: text); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 650).background(Color.paper).foregroundColor(.ink).preferredColorScheme(.light)
        .onAppear { text = passage.displayText }.interactiveDismissDisabled(saving)
    }
}
@MainActor
struct PostEditor: View {
    @ObservedObject var model: AppModel
    let book: BookSource
    @Environment(\.dismiss) private var dismiss
    @LocalViewState private var document: PostDocument?
    @LocalViewState private var text = ""
    @LocalViewState private var preview = true
    @LocalViewState private var editingDetails = false
    @LocalViewState private var choosingPostCover = false
    @LocalViewState private var findingPostYear = false
    @LocalViewState private var saving = false
    @LocalViewState private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Markdown.headerValue(text, key: "title") ?? book.title).font(.title2)
                Spacer()
                Button("Edit details") { editingDetails.toggle() }.disabled(document == nil)
                Menu { Toggle("Edit Markdown", isOn: Binding(get: { !preview }, set: { preview = !$0 })) } label: { Image(systemName: "ellipsis") }.fixedSize()
            }
            if editingDetails {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.caption).foregroundColor(.secondary)
                TextField("Post title", text: titleBinding).textFieldStyle(.roundedBorder)
                Text("Author").font(.caption).foregroundColor(.secondary)
                TextField("Book author", text: authorBinding).textFieldStyle(.roundedBorder)
                Button("Choose cover…") { choosingPostCover = true }
            }.disabled(document == nil)
            }
            Text("Click the text to edit. Changes stay local until you publish.").font(.caption).foregroundColor(.secondary)
            if document == nil && error.isEmpty { ProgressView("Loading post…") }
            if findingPostYear { Text("Finding first publication year…").font(.caption).foregroundColor(.secondary) }
            if preview {
                ScrollView {
                    EditablePostPreview(markdown: $text).padding()
                }.frame(height: 430).background(Color.white)
            } else {
                TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).frame(height: 430)
            }
            if !error.isEmpty {
                Text(error).font(.caption).foregroundColor(.oxide)
                if !model.pending.isEmpty && !model.needsWebsiteAccess {
                    Button("Retry saving") { error = ""; model.flush() }.disabled(model.busy)
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.disabled(saving)
                Spacer()
                Button("Publish…") {
                    guard let document else { return }; saving = true
                    Task {
                        defer { saving = false }
                        do {
                            try await model.savePost(book, document: document, text: text)
                            let current = model.sources.first { $0.path == book.path } ?? book
                            let reloaded = try await model.loadPost(current)
                            self.document = reloaded; text = reloaded.text
                            model.publish(current) { self.error = $0 }
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving || findingPostYear || model.busy || document == nil)
                Button(saving ? "Saving…" : "Save draft") {
                    guard let document else { return }; saving = true
                    Task {
                        defer { saving = false }
                        do { try await model.savePost(book, document: document, text: text); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving || findingPostYear || document == nil || text.isEmpty)
            }
        }.padding(24).frame(width: 760).background(Color.paper).foregroundColor(.ink).preferredColorScheme(.light)
        .sheet(isPresented: $choosingPostCover) {
            CoverPicker(title: Markdown.headerValue(text, key: "title") ?? book.title, author: authorBinding.wrappedValue) { url in
                text = Markdown.updatingCover(text, cover: url)
            }
        }
        .task(id: PublicationYear.baseTitle(titleBinding.wrappedValue) + "\n" + authorBinding.wrappedValue) {
            let title = titleBinding.wrappedValue; let author = authorBinding.wrappedValue
            guard (book.kind ?? "book") == "book", document != nil, title.count >= 2, PublicationYear.fromTitle(title) == nil else { return }
            findingPostYear = true; defer { findingPostYear = false }
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                if let year = try await OpenLibrary.publicationYear(title: title, author: author),
                   !Task.isCancelled, titleBinding.wrappedValue == title, authorBinding.wrappedValue == author {
                    titleBinding.wrappedValue = PublicationYear.title(title, year: year)
                    text = Markdown.updatingPublicationYear(text, year: year)
                }
            } catch { }
        }
        .task {
            do { let loaded = try await model.loadPost(book); document = loaded; text = loaded.text }
            catch { self.error = error.localizedDescription }
        }.interactiveDismissDisabled(saving || model.busy)
    }
    private var titleBinding: Binding<String> {
        Binding(get: { Markdown.headerValue(text, key: "title") ?? "" }, set: { text = Markdown.updatingHeader(text, key: "title", value: $0) })
    }
    private var authorBinding: Binding<String> {
        Binding(get: { Markdown.headerValue(text, key: "book_author") ?? Markdown.headerValue(text, key: "author") ?? "" }, set: {
            text = Markdown.updatingHeader(text, key: "author", value: $0)
            if (book.kind ?? "book") == "book" { text = Markdown.updatingHeader(text, key: "book_author", value: $0) }
        })
    }
    private var previewBody: String {
        var body = text
        if body.hasPrefix("---\n"), let end = body.dropFirst(4).range(of: "\n---") {
            body = String(body[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body
    }
}

private struct EditablePostPreview: View {
    @Binding var markdown: String
    @LocalViewState private var document = PreviewDocument("")
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($document.blocks) { $block in
                if !block.original.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        if block.isQuote { Rectangle().fill(Color.oxide).frame(width: 3) }
                        VisualTextBlock(markdown: $block.text, heading: !block.prefix.isEmpty)
                            .frame(height: height(block.text, heading: !block.prefix.isEmpty))
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { document = PreviewDocument(markdown) }
        .onChange(of: document.markdown) { markdown = $0 }
        .onChange(of: markdown) { if $0 != document.markdown { document = PreviewDocument($0) } }
    }
    private func height(_ text: String, heading: Bool) -> CGFloat {
        let font = heading ? NSFont.systemFont(ofSize: 22) : NSFont(name: "Georgia", size: 17) ?? .systemFont(ofSize: 17)
        let plain = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) } ?? text
        return max(38, (plain as NSString).boundingRect(with: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height + 24)
    }
}

private struct VisualTextBlock: NSViewRepresentable {
    @Binding var markdown: String
    var heading: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isRichText = true; view.isEditable = true; view.isSelectable = true
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 4, height: 4)
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.setAccessibilityLabel(heading ? "Edit heading" : "Edit paragraph or quotation")
        context.coordinator.render(view)
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastMarkdown != markdown { context.coordinator.render(view) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VisualTextBlock
        var lastMarkdown = ""
        init(_ parent: VisualTextBlock) { self.parent = parent }
        func render(_ view: NSTextView) {
            let output = NSMutableAttributedString(string: "")
            let source = (try? AttributedString(markdown: parent.markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(parent.markdown)
            for run in source.runs {
                var font = parent.heading ? NSFont.systemFont(ofSize: 22, weight: .semibold) : NSFont(name: "Georgia", size: 17) ?? .systemFont(ofSize: 17)
                let intent = run.inlinePresentationIntent ?? []
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) { font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular) }
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
                if let link = run.link { attrs[.link] = link }
                output.append(NSAttributedString(string: String(source[run.range].characters), attributes: attrs))
            }
            view.textStorage?.setAttributedString(output)
            view.typingAttributes = [.font: parent.heading ? NSFont.systemFont(ofSize: 22, weight: .semibold) : NSFont(name: "Georgia", size: 17) ?? .systemFont(ofSize: 17), .foregroundColor: NSColor.textColor]
            lastMarkdown = parent.markdown
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let storage = view.textStorage else { return }
            var result = ""
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
                var part = (storage.string as NSString).substring(with: range)
                let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 17)
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.fixedPitchFontMask) { part = "`" + part + "`" }
                else {
                    if traits.contains(.italicFontMask) { part = "*" + part + "*" }
                    if !parent.heading && traits.contains(.boldFontMask) { part = "**" + part + "**" }
                }
                if let url = attributes[.link] { part = "[" + part + "](" + String(describing: url) + ")" }
                result += part
            }
            lastMarkdown = result
            parent.markdown = result
        }
    }
}
