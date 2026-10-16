import Foundation

struct CoverOption: Identifiable {
    var id: String { imageURL }
    var title: String
    var detail: String
    var imageURL: String
    var sourceURL: String
}
enum BookCovers {
    static func goodreads(title: String, author: String) async throws -> [CoverOption] {
        var url = URLComponents(string: "https://www.goodreads.com/search")!
        url.queryItems = [URLQueryItem(name: "q", value: title + " " + author)]
        var request = URLRequest(url: url.url!, timeoutInterval: 25)
        request.setValue("Marginstone/0.3 (personal book cover selection)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { throw AppFailure(message: "Goodreads search is unavailable. Open Library results are still available.") }
        return parseGoodreads(html)
    }
    static func parseGoodreads(_ html: String) -> [CoverOption] {
        func matches(_ pattern: String, _ text: String) -> [[String]] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
            let ns = text as NSString
            return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
                (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
            }
        }
        func decode(_ text: String) -> String {
            text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        }
        var seen = Set<String>()
        return matches(#"<tr\b[^>]*>.*?</tr>"#, html).compactMap { row in
            guard let tag = matches(#"<img\b[^>]*class="[^"]*bookCover[^"]*"[^>]*>"#, row[0]).first?[0],
                  let image = matches(#"src="([^"]+)""#, tag).first?[1],
                  let title = matches(#"alt="([^"]+)""#, tag).first?[1],
                  let link = matches(#"class="bookTitle"[^>]*href="([^"]+)""#, row[0]).first?[1],
                  let url = URL(string: decode(image)), url.scheme == "https",
                  ["i.gr-assets.com", "images.gr-assets.com", "m.media-amazon.com"].contains(url.host ?? ""),
                  seen.insert(image).inserted else { return nil }
            let author = matches(#"class="authorName"[^>]*>.*?<span[^>]*>(.*?)</span>"#, row[0]).first?[1] ?? ""
            // Goodreads supplies a thumbnail size suffix; removing it requests the original cover.
            let full = decode(image).replacingOccurrences(of: #"\._S[XY]\d+_\."#, with: ".", options: .regularExpression)
            return CoverOption(title: decode(title), detail: "Goodreads · " + decode(author), imageURL: full,
                               sourceURL: "https://www.goodreads.com" + decode(link))
        }
    }
}
