import XCTest
@testable import NautilusCore
final class CaptureTests: XCTestCase {
    func testBooksCitationSeparatesPassageAndSource() {
        let raw = "“The paragraph.”\r\n\r\nExcerpt From\r\nHerzog\r\nSaul Bellow\r\nThis material may be protected by copyright."
        let hint = CitationParser.books(raw)
        XCTAssertEqual(hint?.title, "Herzog"); XCTAssertEqual(hint?.author, "Saul Bellow")
        XCTAssertEqual(hint?.passage, "“The paragraph.”")
    }
    func testNoSourceGuessFromPlainText() { XCTAssertNil(CitationParser.books("Herzog thought about many things.")) }
    func testInlineCitationStillProducesCandidate() {
        XCTAssertEqual(CitationParser.books("Quote\nExcerpt From: Herzog\nSaul Bellow")?.title, "Herzog")
    }
    func testPublishedReviewAndConcurrentEditsSurviveMerge() {
        let book = BookSource(path: "_posts/2026-10-16-herzog.md", title: "Herzog", author: "Bellow")
        let passage = SavedPassage(payload: CapturePayload(text: "Line 1\n\nLine 2"), sourcePath: book.path)
        let block = Markdown.block(passage, text: passage.payload.text)
        let draft = Markdown.append(block, to: "OLD REVIEW\n\n## Excerpts\n")
        let result = Markdown.merge(draft: draft, published: "NEW REVIEW with manual edits.\n\n## Excerpts\n\n> Existing quotation.\n")
        XCTAssertTrue(result.hasPrefix("NEW REVIEW with manual edits.")); XCTAssertTrue(result.contains("> Existing quotation."))
        XCTAssertTrue(result.contains("> Line 1\n> \n> Line 2")); XCTAssertFalse(result.contains("OLD REVIEW"))
        XCTAssertEqual(Markdown.merge(draft: draft, published: result), result)
    }
    func testJournalRoundTripRetainsOriginalPayload() throws {
        let payload = CapturePayload(text: "<script>$HOME `touch /tmp/no`\n“Exact words.”", url: "https://example.com", types: ["public.utf8-plain-text"])
        let p = SavedPassage(payload: payload, sourcePath: nil)
        let copy = try JSONDecoder().decode(SavedPassage.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(copy.payload.text, p.payload.text); XCTAssertNil(copy.sourcePath)
    }
    func testPathsAndFrontMatter() {
        XCTAssertFalse(Markdown.safePath("_posts/../../evil.md")); XCTAssertFalse(Markdown.safePath("_posts/.hidden.md"))
        XCTAssertFalse(Markdown.safePath("_posts/a\\b.md")); XCTAssertTrue(Markdown.safePath("_posts/2026-10-16-book.md"))
        let book = BookSource(path: "_posts/2026-10-16-book.md", title: "A \"Book\": Title", author: "A\nB")
        XCTAssertEqual(Markdown.source(path: book.path, text: Markdown.page(book, date: "2026-10-16")), book)
        let existing = "---\ntitle: Herzog (1964)\nauthor: Saul Bellow\ncategories:\n  - Books\n---\nReview."
        XCTAssertEqual(Markdown.source(path: book.path, text: existing)?.author, "Saul Bellow")
    }
}
