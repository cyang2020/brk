import AppKit
import Foundation
import PDFKit

/// What the file index reads of a file: the start of its text, cleaned, for the local search model. Measured on 27 real
/// documents and 30 paraphrased queries (~/brk-evidence/local-models-quality): the file's name alone put the right file
/// in the first three for 15 of 30 queries, its name and first 800 characters for 30. Read on this Mac only.
enum FileText {
    /// Characters kept: the model reads about this much of a document in one vector (`LocalEmbedder.maxCharacters` cuts
    /// at 900 with the name in front).
    static let keep = 800

    /// Plain text and source code, read as UTF-8.
    static let plain: Set<String> = [
        "txt", "text", "md", "markdown", "rst", "org", "tex", "csv", "tsv", "json", "yaml", "yml", "toml", "xml", "log",
        "swift", "py", "js", "mjs", "ts", "tsx", "jsx", "go", "rs", "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt",
        "rb", "php", "sh", "zsh", "bash", "sql", "css", "scss", "lua", "r", "scala", "dart", "cs", "ex", "exs", "hs",
    ]
    /// Read through the text system (the same reader as TextEdit). HTML is left out: its reader needs the main thread.
    static let rich: Set<String> = ["rtf", "doc", "docx", "odt"]
    static let pdf: Set<String> = ["pdf"]

    /// Size caps: past these a file is listed by name only (Spotlight's name match still finds it).
    static func readable(_ path: String, size: Int) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if plain.contains(ext) { return size <= 2_000_000 }
        if rich.contains(ext) { return size <= 20_000_000 }
        if pdf.contains(ext) { return size <= 60_000_000 }
        return false
    }

    /// The first `keep` characters of the file's text, whitespace folded; nil when it cannot be read (no permission,
    /// not text, damaged).
    static func read(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        var text: String?
        if plain.contains(ext) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 65_536) else { return nil }
            text = String(decoding: data, as: UTF8.self)
            if ext == "md" || ext == "markdown", let body = text { text = withoutFrontMatter(body) }
        } else if rich.contains(ext) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        } else if pdf.contains(ext) {
            guard let document = PDFDocument(url: url) else { return nil }
            text = (0..<min(document.pageCount, 2)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        }
        guard let folded = text.map(fold), !folded.isEmpty else { return nil }
        return String(folded.prefix(keep))
    }

    static func fold(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{0}" }).joined(separator: " ")
    }

    /// A Markdown file's YAML header (`---` … `---`) says how to publish it, not what it is about.
    static func withoutFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { return text }
        return String(text[end.upperBound...])
    }
}
