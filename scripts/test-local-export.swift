import Foundation
@main struct LocalExportCheck {
 static func main() {
  let book = BookSource(path: "_posts/a.md", title: "Culture and Value (1977)", author: "Ludwig Wittgenstein")
  let other = BookSource(path: "_posts/b.md", title: "Another book", author: "Another Author")
  var edited = SavedPassage(payload: CapturePayload(text: "Original text", url: "https://example.com/source"), sourcePath: book.path)
  edited.editedText = "Edited text\n\nA second paragraph"
  let second = SavedPassage(payload: CapturePayload(text: "Other source text"), sourcePath: other.path)
  let unassigned = SavedPassage(payload: CapturePayload(text: "Unassigned text"), sourcePath: nil)
  let captures = [unassigned, second, edited]
  let all = MarkdownExport.document(passages: captures, sources: [book, other])
  precondition(all.contains("Ludwig Wittgenstein") && all.contains("Culture and Value (1977)"))
  precondition(all.contains("> Edited text\n> \n> A second paragraph"))
  precondition(all.contains("https://example.com/source") && all.contains("Unassigned text"))
  precondition(!all.contains("nautilus:") && !all.contains("Original text"))
  let selected = MarkdownExport.document(passages: captures, sources: [book, other], sourcePath: book.path)
  precondition(selected.contains("Edited text") && !selected.contains("Other source text") && !selected.contains("Unassigned text"))
  print("Local Markdown export checks passed.")
 }
}
