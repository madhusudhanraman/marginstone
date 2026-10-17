import Foundation

@main struct WebsiteSelectionChecks {
    static func main() throws {
        let source = "_posts/example.md"
        let local = SavedPassage(payload: CapturePayload(text: "Local fixture"), sourcePath: source)
        let chosen = SavedPassage(payload: CapturePayload(text: "Chosen fixture"), sourcePath: source)
        var existing = SavedPassage(payload: CapturePayload(text: "Existing fixture"), sourcePath: source)
        existing.written = true
        let all = [local, chosen, existing]
        // Upgrades preserve existing drafts but never opt unsaved captures in.
        let restored = WebsiteSelection.restored(nil, passages: all)
        precondition(restored == [existing.id])
        precondition(WebsiteSelection.pending(all, selected: restored).isEmpty)
        // Choosing one excerpt does not include other excerpts from that source.
        let selected = restored.union([chosen.id])
        precondition(WebsiteSelection.pending(all, selected: selected).map { $0.id } == [chosen.id])
        let data = try JSONEncoder().encode(Array(selected))
        let reloaded = WebsiteSelection.restored(try JSONDecoder().decode([UUID].self, from: data), passages: all)
        precondition(reloaded == selected)
        precondition(WebsiteSelection.restored([], passages: all).isEmpty)
        print("Explicit website selection and upgrade checks passed.")
    }
}
