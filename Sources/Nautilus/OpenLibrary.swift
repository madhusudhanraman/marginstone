import Foundation
import NautilusCore
struct WorkResult: Decodable, Identifiable {
    var key: String; var title: String; var author_name: [String]?; var cover_i: Int?; var first_publish_year: Int?
    var id: String { key }
    var coverURL: URL? { cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg") } }
}
struct EditionResult: Decodable, Identifiable {
    var key: String; var title: String; var publish_date: String?; var publishers: [String]?; var covers: [Int]?; var isbn_13: [String]?; var isbn_10: [String]?
    var id: String { key }
    var label: String { [publish_date, publishers?.first, (isbn_13 ?? isbn_10)?.first].compactMap { $0 }.joined(separator: " · ") }
    var cover: String { covers?.first(where: { $0 > 0 }).map { "https://covers.openlibrary.org/b/id/\($0)-L.jpg" } ?? "" }
}
enum OpenLibrary {
    private struct Search: Decodable { var docs: [WorkResult] }
    private struct Editions: Decodable { var entries: [EditionResult] }
    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("Marginstone/0.3 (personal Field Notes reading app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppFailure(message: "Open Library could not complete the request. You can still create the page manually.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func search(title: String, author: String) async throws -> [WorkResult] {
        var url = URLComponents(string: "https://openlibrary.org/search.json")!
        url.queryItems = [URLQueryItem(name: "title", value: PublicationYear.baseTitle(title)), URLQueryItem(name: "author", value: author), URLQueryItem(name: "limit", value: "12"), URLQueryItem(name: "fields", value: "key,title,author_name,cover_i,first_publish_year")]
        url.queryItems?.removeAll { $0.name == "author" && ($0.value ?? "").isEmpty }
        let result: Search = try await get(url.url!)
        if result.docs.isEmpty && !author.isEmpty {
            url.queryItems = [URLQueryItem(name: "q", value: PublicationYear.baseTitle(title) + " " + (author.split(separator: " ").last.map(String.init) ?? author)), URLQueryItem(name: "limit", value: "12"), URLQueryItem(name: "fields", value: "key,title,author_name,cover_i,first_publish_year")]
            let fallback: Search = try await get(url.url!)
            return fallback.docs
        }
        return result.docs
    }
    static func publicationYear(title: String, author: String) async throws -> Int? {
        if let year = PublicationYear.fromTitle(title) { return year }
        let works = try await search(title: title, author: author)
        if let year = matchingYear(works: works, title: title, author: author) { return year }
        // Translated titles may be indexed only on an edition, while the work
        // carries the original-language title and first publication year.
        guard !author.isEmpty else { return nil }
        var years = Set<Int>()
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        for work in works.prefix(4) where (work.author_name ?? []).contains(where: { PublicationYear.normalized($0) == PublicationYear.normalized(author) }) {
            try Task.checkCancellation()
            guard let year = work.first_publish_year, (1...currentYear).contains(year) else { continue }
            let entries = try await editions(work: work)
            if entries.contains(where: { PublicationYear.normalized($0.title) == PublicationYear.normalized(PublicationYear.baseTitle(title)) }) { years.insert(year) }
        }
        return years.min()
    }
    static func matchingYear(works: [WorkResult], title: String, author: String) -> Int? {
        let cleanTitle = PublicationYear.normalized(PublicationYear.baseTitle(title))
        let cleanAuthor = PublicationYear.normalized(author)
        let matches = works.filter { work in
            PublicationYear.normalized(work.title) == cleanTitle &&
            (cleanAuthor.isEmpty || (work.author_name ?? []).contains { PublicationYear.normalized($0) == cleanAuthor })
        }
        if cleanAuthor.isEmpty {
            let authors = Set(matches.map { ($0.author_name ?? []).map(PublicationYear.normalized).sorted().joined(separator: "|") })
            guard authors.count == 1, authors.first != "" else { return nil }
        }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let years = Set(matches.compactMap(\.first_publish_year).filter { (1...currentYear).contains($0) })
        return years.min()
    }
    static func editions(work: WorkResult, offset: Int = 0) async throws -> [EditionResult] {
        guard work.key.range(of: #"^/works/OL[0-9]+W$"#, options: .regularExpression) != nil else { throw AppFailure(message: "Unexpected book identifier.") }
        let url = URL(string: "https://openlibrary.org\(work.key)/editions.json?limit=50&offset=\(offset)")!
        let result: Editions = try await get(url); return result.entries
    }
}
