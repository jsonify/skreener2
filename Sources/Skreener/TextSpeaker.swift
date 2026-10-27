import AVFoundation
import NaturalLanguage

/// Reads text aloud for the Capture Text scratch pad (#268), with a voice that matches the text's language.
@MainActor
final class TextSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    /// Called on the main actor when the speech ends, whether it finished or was stopped.
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // No matching voice: leave the default one.
        if let code = TextSpeaker.voiceLanguage(for: text), let voice = AVSpeechSynthesisVoice(language: code) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    // The callbacks may arrive off the main thread, so hop to the main actor.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in onFinish?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in onFinish?() }
    }

    /// What to read: the selection if it holds any text, otherwise the whole text; nil if there is nothing to read.
    nonisolated static func textToSpeak(_ text: String, selection: NSRange) -> String? {
        let ns = text as NSString
        if selection.length > 0, NSMaxRange(selection) <= ns.length {
            let selected = ns.substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty { return selected }
        }
        let all = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.isEmpty ? nil : all
    }

    /// The language code for `AVSpeechSynthesisVoice(language:)` that matches `text`, or nil if it can't be guessed.
    nonisolated static func voiceLanguage(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return voiceLanguage(for: recognizer.dominantLanguage)
    }

    /// Maps a language guess to a voice language code: Chinese scripts get a region, the rest keep their code.
    nonisolated static func voiceLanguage(for language: NLLanguage?) -> String? {
        guard let language, language != .undetermined else { return nil }
        switch language {
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        default: return language.rawValue
        }
    }
}
