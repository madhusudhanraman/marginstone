import Foundation

public enum WebCapture {
    public static func payload(from url: URL) -> CapturePayload? {
        guard url.scheme == "marginstone", url.host == "capture", url.absoluteString.utf8.count <= 200_000,
              // URLSearchParams uses form encoding: + means space, %2B means +.
              let parts = URLComponents(string: url.absoluteString.replacingOccurrences(of: "+", with: "%20")) else { return nil }
        func value(_ key: String) -> String { parts.queryItems?.first { $0.name == key }?.value ?? "" }
        let sourceURL = value("url")
        guard let page = URL(string: sourceURL), ["https", "http"].contains(page.scheme ?? ""), page.host != nil else { return nil }
        var payload = CapturePayload(text: value("text"), url: sourceURL, types: ["marginstone.web-selection"], sourceApp: "Web browser")
        payload.sourceTitle = String(value("title").prefix(500)); payload.sourceAuthor = String(value("author").prefix(500))
        return payload
    }
}
