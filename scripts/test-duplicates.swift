import Foundation

@main struct DuplicateRegression {
    static func main() {
        let a = SavedPassage(payload: CapturePayload(text: "First line\n\nSecond line"), sourcePath: "_posts/book.md")
        let b = SavedPassage(payload: a.payload, sourcePath: a.sourcePath)
        let c = SavedPassage(payload: CapturePayload(text: "A different passage"), sourcePath: a.sourcePath)
        let first = Markdown.block(a, text: a.payload.text)
        let duplicate = Markdown.block(b, text: b.payload.text)
        let different = Markdown.block(c, text: c.payload.text)
        let review = "---\ntitle: Book\n---\nMy edited review.\n\n> A manual quotation.\n\n## Excerpts\n\n"
        let draft = review + first + "\n\n" + duplicate + "\n\n" + different + "\n"
        precondition(Markdown.append(duplicate, to: review + first) == review + first)
        let merged = Markdown.merge(draft: draft, published: review + first + "\n\n" + duplicate)
        precondition(merged.hasPrefix(review))
        precondition(Markdown.blocks(merged).count == 2)
        precondition(merged.contains(first) && merged.contains(different) && !merged.contains(duplicate))
        precondition(Markdown.merge(draft: draft, published: merged) == merged)
        precondition(Markdown.blocks(Markdown.merge(draft: draft, published: nil)).count == 2)
        let newBook = Markdown.page(BookSource(path: "_posts/new.md", title: "New book", author: "New author"), date: "2026-10-16")
        let newDraft = Markdown.append(first, to: newBook)
        let publication = Markdown.merge(draft: newDraft, published: nil)
        precondition(Markdown.blocks(publication).count == 1)
        precondition(Markdown.merge(draft: newDraft, published: publication) == publication)
        let clean = Markdown.publication(draft: draft, published: review + first + "\n\n" + duplicate, date: "2026-10-16")
        precondition(!clean.contains("<!-- nautilus:") && !clean.contains("<!-- /nautilus:"))
        precondition(clean.contains("last_modified_at: 2026-10-16") && clean.contains("My edited review."))
        precondition(clean.components(separatedBy: "> First line").count == 2)
        precondition(Markdown.publication(draft: draft, published: clean, date: "2026-10-17") == clean)
        let old = "---\ntitle: Book\ndate: 2020-01-01\nlast_modified_at: 2020-02-01\n---\nReview"
        let updated = Markdown.updatingModifiedDate(old, date: "2026-10-16")
        precondition(updated.contains("date: 2020-01-01") && !updated.contains("2020-02-01"))
        precondition(updated.contains("last_modified_at: 2026-10-16"))
        let edited = "Corrected first line\n\nCorrected second line"
        let withMarkers = Markdown.editingExcerpt(in: review + first, passage: a, text: edited)!
        precondition(withMarkers.contains("Corrected first line") && !withMarkers.contains("> First line"))
        let plain = Markdown.publication(draft: review + first, published: nil, date: "2026-10-16")
        let corrected = Markdown.editingExcerpt(in: plain, passage: a, text: edited)!
        precondition(corrected.contains("Corrected first line") && corrected.contains("My edited review."))
        precondition(Markdown.editingExcerpt(in: review, passage: a, text: edited) == nil)
        var editedCapture = a
        editedCapture.editedText = edited
        let decoded = try! JSONDecoder().decode(SavedPassage.self, from: JSONEncoder().encode(editedCapture))
        precondition(decoded.displayText == edited && decoded.payload.text == a.payload.text)
        let legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        let legacyData = try! JSONSerialization.data(withJSONObject: legacy.filter { $0.key != "editedText" })
        let legacyCapture = try! JSONDecoder().decode(SavedPassage.self, from: legacyData)
        precondition(legacyCapture.editedText == nil && legacyCapture.displayText == a.payload.text)
        let visualSource = "---\ntitle: Book\ncover: https://example.com/cover.jpg\n---\n\n## Excerpts\n\n> **A quote**\n> \n> A second paragraph.\n\nUnchanged *review*.\n"
        var visual = PreviewDocument(visualSource)
        precondition(visual.markdown == visualSource)
        let quoteIndex = visual.blocks.firstIndex(where: { $0.isQuote })!
        visual.blocks[quoteIndex].text = "Edited **quote**\n\nSecond paragraph."
        precondition(visual.markdown.contains("> Edited **quote**\n> \n> Second paragraph."))
        precondition(visual.markdown.hasPrefix(visual.header) && visual.markdown.contains("Unchanged *review*."))
        let headingIndex = visual.blocks.firstIndex(where: { !$0.prefix.isEmpty })!
        visual.blocks[headingIndex].text = "My excerpts"
        precondition(visual.markdown.contains("## My excerpts"))
        let markedRemoval = Markdown.removingExcerpt(in: review + first + "\n\n" + different, passage: a)!
        precondition(!markedRemoval.contains(first) && markedRemoval.contains(different) && markedRemoval.hasPrefix(review))
        let cleanRemoval = Markdown.removingExcerpt(in: plain, passage: a)!
        precondition(!cleanRemoval.contains("> First line") && cleanRemoval.contains("My edited review."))
        precondition(Markdown.removingExcerpt(in: review, passage: a) == nil)
        let shortQuote = SavedPassage(payload: CapturePayload(text: "A short quote"), sourcePath: nil)
        precondition(Markdown.removingExcerpt(in: "> A short quote with more words", passage: shortQuote) == nil)
        precondition(Markdown.removingExcerpt(in: "> A short quote\n\n> A short quote", passage: shortQuote) == nil)
        let retitled = Markdown.updatingHeader(visualSource, key: "title", value: "A \"new\" title: notes")
        precondition(Markdown.headerValue(retitled, key: "title") == "A \"new\" title: notes")
        precondition(retitled.contains("cover: https://example.com/cover.jpg") && retitled.contains("Unchanged *review*."))
        precondition(Markdown.headerValue(Markdown.updatingHeader(retitled, key: "author", value: "New Author"), key: "author") == "New Author")
        print("Duplicate and new-book publication regression checks passed.")
    }
}
