import Foundation
import NaturalLanguage

/// What language a page's text is in, for pages that declare none (Arc: Chromium's own detection, which also lets the
/// declared language win). Below these bounds the sample does not say, and the page gets no Translation Available.
enum PageLanguage {
    /// A heading or a few menu words are no evidence: Chromium's detector also wants a real run of text.
    static let minimumLetters = 40
    /// Only a clear answer: a wrong "Translation Available" on the user's own language is worse than none.
    static let minimumConfidence = 0.85

    /// The sample's language as a BCP 47 code ("fr", "zh-Hans"); nil when it is short, has no letters or is unclear.
    static func recognize(_ sample: String) -> String? {
        guard sample.unicodeScalars.lazy.filter(CharacterSet.letters.contains).count >= minimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined, confidence >= minimumConfidence else { return nil }
        return language.rawValue
    }
}
