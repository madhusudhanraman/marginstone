import Foundation
import MarginstoneCore
struct AppFailure: LocalizedError { var message: String; var errorDescription: String? { message } }
@main struct YearCheck {
 static func main() async throws {
  precondition(PublicationYear.title("Stoner", year: 1965) == "Stoner (1965)")
  precondition(PublicationYear.title("Stoner (1965)", year: 2000) == "Stoner (1965)")
  let fixture = Data(#"[{"key":"/works/OL1W","title":"Same title","author_name":["First Author"],"first_publish_year":1950},{"key":"/works/OL2W","title":"Same title","author_name":["Other Author"],"first_publish_year":1980}]"#.utf8)
  let works = try JSONDecoder().decode([WorkResult].self, from: fixture)
  precondition(OpenLibrary.matchingYear(works: works, title: "Same title", author: "") == nil)
  precondition(OpenLibrary.matchingYear(works: works, title: "Same title", author: "First Author") == 1950)
  let culture = try await OpenLibrary.publicationYear(title: "Culture and Value", author: "Ludwig Wittgenstein")
  precondition(culture == 1977)
  print("Live translated-title lookup: Culture and Value (\(culture!))")
  let stoner = try await OpenLibrary.publicationYear(title: "Stoner", author: "John Williams")
  precondition(stoner == 1965)
  print("Live lookup: Stoner (\(stoner!)); title-only ambiguity checks passed.")
 }
}
