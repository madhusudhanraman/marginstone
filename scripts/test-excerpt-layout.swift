import Foundation

@main struct ExcerptLayoutChecks {
    static func main() {
        precondition(ExcerptLayout.reflow("A copied line\ncontinues here.") == "A copied line continues here.")
        precondition(ExcerptLayout.reflow("First paragraph\ncontinues.\n\nSecond paragraph\ncontinues.") == "First paragraph continues.\n\nSecond paragraph continues.")
        precondition(ExcerptLayout.reflow("First\r\nline\r\n \t\r\nSecond") == "First line\n\nSecond")
        precondition(ExcerptLayout.reflow("First\u{2028}line\u{2029}Second") == "First line\n\nSecond")
        precondition(ExcerptLayout.reflow("Already one paragraph.") == "Already one paragraph.")
        print("Copied-line reflow and paragraph preservation checks passed.")
    }
}
