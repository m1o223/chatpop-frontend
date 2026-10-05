import Foundation

enum DictationText {
    static func appending(_ transcript: String, to existing: String) -> String {
        let addition = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return existing }
        guard let last = existing.last else { return addition }
        // Preserve the original draft, including deliberate spaces and line breaks.
        let separator = last.isWhitespace ? "" : " "
        return existing + separator + addition
    }
}
