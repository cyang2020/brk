import Foundation

/// A bounded arithmetic parser. No JavaScript, shell or general-purpose expression evaluator is involved.
public enum BrowserCalculator {
    public static func result(_ text: String) -> String? {
        guard text.contains(where: { "+-*/×÷^%".contains($0) }) else { return nil }
        return forced(text)
    }

    /// `result` without asking for an operator: under the `calc` prefix a plain number is an answer too.
    public static func forced(_ text: String) -> String? {
        guard text.count <= 160 else { return nil }
        var parser = Parser(characters: Array(text.filter { !$0.isWhitespace }))
        guard let value = parser.sum(), parser.index == parser.characters.count, value.isFinite, abs(value) < 1e100 else { return nil }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        mutating func take(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1; return true
        }
        mutating func sum() -> Double? {
            guard var result = product() else { return nil }
            while index < characters.count {
                if take("+") { guard let next = product() else { return nil }; result += next }
                else if take("-") { guard let next = product() else { return nil }; result -= next }
                else { break }
            }
            return result
        }
        mutating func product() -> Double? {
            guard var result = unary() else { return nil }
            while index < characters.count {
                if take("*") || take("×") { guard let next = unary() else { return nil }; result *= next }
                else if take("/") || take("÷") { guard let next = unary(), next != 0 else { return nil }; result /= next }
                else { break }
            }
            return result
        }
        mutating func power() -> Double? {
            guard var result = atom() else { return nil }
            if take("^") { guard let next = unary() else { return nil }; result = pow(result, next) }
            return result
        }
        mutating func unary() -> Double? {
            if take("+") { return unary() }
            if take("-") { return unary().map { -$0 } }
            return power()
        }
        mutating func atom() -> Double? {
            var result: Double
            if take("(") {
                guard let inner = sum(), take(")") else { return nil }; result = inner
            } else {
                let start = index
                while index < characters.count, characters[index].isASCII, characters[index].isNumber || characters[index] == "." { index += 1 }
                guard start != index, let number = Double(String(characters[start..<index])) else { return nil }; result = number
            }
            if take("%") { result /= 100 }
            return result
        }
    }
}
