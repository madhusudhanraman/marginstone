import Foundation
import MarginstoneCore

enum WebSource {
    static func lookup(_ value: String) async throws -> SourceMetadata {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(),
              host != "localhost", !host.hasSuffix(".local"), host != "::1",
              !host.hasPrefix("127."), !host.hasPrefix("10."), !host.hasPrefix("192.168."), !host.hasPrefix("169.254.") else {
            throw AppFailure(message: "Enter a public webpage link to look up its source.")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Marginstone/0.3 (reading source lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, [401, 403, 429].contains(http.statusCode) {
            throw AppFailure(message: "This website blocks automatic lookup. Enter the title and author here.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000,
              http.mimeType == "text/html" || http.mimeType == "application/xhtml+xml",
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AppFailure(message: "This page did not provide readable source details. You can fill them in below.")
        }
        var metadata = SourceMetadata.html(html)
        metadata.url = response.url?.absoluteString ?? value
        return metadata
    }
}
