import Foundation

@main
private struct DictationTextChecks {
    static func main() {
        let cases: [(String, String, String)] = [
            ("", "Explain quantum physics simply", "Explain quantum physics simply"),
            ("Please explain", "this image for me", "Please explain this image for me"),
            ("Please explain ", " this image for me\n", "Please explain this image for me"),
            ("First line\n", "Second line", "First line\nSecond line"),
            ("Keep this draft", " \n ", "Keep this draft"),
            ("Keep  spacing", "exactly", "Keep  spacing exactly"),
            ("\u{0627}\u{0634}\u{0631}\u{062D}", "\u{0647}\u{0630}\u{0647} \u{0627}\u{0644}\u{0635}\u{0648}\u{0631}\u{0629}", "\u{0627}\u{0634}\u{0631}\u{062D} \u{0647}\u{0630}\u{0647} \u{0627}\u{0644}\u{0635}\u{0648}\u{0631}\u{0629}"),
            ("Kan du", "hj\u{00E4}lpa mig?", "Kan du hj\u{00E4}lpa mig?"),
            ("Emoji \u{1F600}", "still works", "Emoji \u{1F600} still works")
        ]
        for (existing, transcript, expected) in cases {
            precondition(DictationText.appending(transcript, to: existing) == expected, "Dictation append changed the draft unexpectedly")
        }
        print("PASS \(cases.count) dictation append cases, including Arabic and Swedish")
    }
}
