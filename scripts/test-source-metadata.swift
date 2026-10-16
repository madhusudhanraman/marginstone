import Foundation
@main struct SourceMetadataChecks {
    static func main() throws {
        let meta = SourceMetadata.html("""
        <title>Fallback</title><meta content='An essay &amp; a thought' property='og:title'>
        <meta name="author" content="A. Writer"><link href="https://example.com/essay" rel="canonical">
        """)
        precondition(meta.title == "An essay & a thought" && meta.author == "A. Writer" && meta.url == "https://example.com/essay")
        let json = SourceMetadata.html("""
        <script type='application/ld+json'>{"@graph":[{"@type":"WebSite","name":"Not the article"},{"@type":"Article","headline":"Real article","author":[{"@type":"Person","name":"One Author"},{"name":"Two Author"}]}]}</script>
        """)
        precondition(json.title == "Real article" && json.author == "One Author, Two Author")
        let fragment = SourceMetadata.html("<p>Selection with <a href='https://wrong.example'>a reference link</a></p>")
        precondition(fragment.url.isEmpty && fragment.author.isEmpty && fragment.title.isEmpty)
        precondition(SourceMetadata.html("SourceURL:https://example.com/origin\r\n<p>Text</p>").url == "https://example.com/origin")
        precondition(SourceMetadata.html("<title>Words &#x2014; &#8217; text</title>").title == "Words — ’ text")
        let payload = CapturePayload(text: "Original passage")
        let roundTrip = try JSONDecoder().decode(CapturePayload.self, from: JSONEncoder().encode(payload))
        precondition(roundTrip.sourceTitle == nil && roundTrip.text == "Original passage")
        let legacy = Data(#"{"text":"Old quote","url":"","types":[],"sourceApp":""}"#.utf8)
        let old = try JSONDecoder().decode(CapturePayload.self, from: legacy)
        precondition(old.sourceHTML == nil)
        let link = URL(string: "marginstone://capture?text=C%2B%2B+%26+space&url=https%3A%2F%2Fexample.test%2F%3Fq%3Da%2Bb&title=Test+title")!
        precondition(WebCapture.payload(from: link)?.text == "C++ & space")
        precondition(WebCapture.payload(from: link)?.sourceTitle == "Test title")
        precondition(WebCapture.payload(from: link)?.url == "https://example.test/?q=a+b")
        precondition(WebCapture.payload(from: URL(string: "marginstone://capture?url=file:///tmp/no")!) == nil)
        precondition(SourceMetadata.html("<article><div><a rel='author' href='/authors/test'>By Test Writer</a></div></article>").author == "Test Writer")
        precondition(SourceMetadata.html("<p>Somebody mentions Test Writer here.</p>").author.isEmpty)
        precondition(SourceMetadata.html("<span class='author-name'>Another Writer</span>").author == "Another Writer")
        let article = BookSource(path: "_posts/test.md", title: "An essay", author: "Test Writer", kind: "article")
        let articlePage = Markdown.page(article, date: "2026-10-17")
        precondition(articlePage.contains("categories: [Articles]") && !articlePage.contains("book_author:"))
        precondition(Markdown.source(path: article.path, text: articlePage)?.kind == "article")
        let legacySource = try JSONDecoder().decode(BookSource.self, from: Data(#"{"path":"_posts/old.md","title":"Old book","author":"A Writer","cover":"","edition":""}"#.utf8))
        precondition(legacySource.kind == nil && Markdown.page(legacySource, date: "2026-10-17").contains("categories: [Books]"))
        print("Source metadata, article/book types, browser decoding and legacy capture checks passed.")
    }
}
