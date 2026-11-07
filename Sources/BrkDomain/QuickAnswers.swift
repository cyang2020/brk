import BrkBase
import Foundation

/// Brk's own addition beyond Arc, in the manner of Raycast's calculator: an answer the command bar shows as you type,
/// expression and answer in one row, Return copies the answer. `BrowserCalculator` stays the plain arithmetic parser
/// and runs first; this reads what it refuses: percentages of a number, square roots, units and CSS lengths,
/// dates and times, currencies. Everything here is pure: the clock, the time zone, the locale and the rates come in.
public struct QuickAnswer: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case math, date, currency }
    public let kind: Kind
    /// What the row shows and Return copies: "3.048 m".
    public let answer: String
    /// The dimmed text after it: what was typed, with the rate's date for a currency.
    public let detail: String
    /// The text can only be this question ("10ft in m"), so the answer leads the rows. A word that is also an ordinary
    /// search ("today") has its row under the typed row, so Return still searches.
    public let leads: Bool
}

public struct QuickAnswerContext: Sendable {
    public var now: Instant
    public var timeZone: TimeZone
    public var locale: Locale
    public var rates: CurrencyRates?

    public init(now: Instant, timeZone: TimeZone, locale: Locale, rates: CurrencyRates? = nil) {
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.rates = rates
    }
}

public enum QuickAnswers {
    enum BareWord: String { case now, time, today, tomorrow, yesterday }
    enum DayCount: Equatable { case until, since }

    /// What a text asks, before any clock or rate is looked at. Nil for anything else, which stays an ordinary search.
    enum Question: Equatable {
        case bare(BareWord)
        case percent(Double, of: Double)
        case squareRoot(Double)
        case convert(Double, from: QuickUnit, to: QuickUnit)
        case currency(Double, from: String, to: String)
        case timespan(seconds: Double)
        case days(DayCount, day: Int, month: Int, year: Int?)
        case timeIn(TimeZone)
        case clock(hour: Int, minute: Int, from: TimeZone?, to: TimeZone)
    }

    public static func answer(_ text: String, _ context: QuickAnswerContext) -> QuickAnswer? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let question = question(typed) else { return nil }
        func dated(_ answer: String?) -> QuickAnswer? {
            answer.map { QuickAnswer(kind: .date, answer: $0, detail: typed, leads: leads(question)) }
        }
        func math(_ answer: String) -> QuickAnswer { QuickAnswer(kind: .math, answer: answer, detail: typed, leads: leads(question)) }
        switch question {
        case .bare(let word): return dated(bare(word, context))
        case .percent(let share, let whole): return math(number(share / 100 * whole))
        case .squareRoot(let value): return math(number(value.squareRoot()))
        case .convert(let amount, let from, let to): return math(number(to.fromBase(from.toBase(amount))) + " " + to.label)
        case .currency(let amount, let from, let to):
            guard let rates = context.rates, let converted = rates.convert(amount, from: from, to: to) else { return nil }
            return QuickAnswer(kind: .currency, answer: String(format: "%.2f", locale: posix, converted) + " " + to,
                               detail: typed + " · ECB " + rates.date, leads: true)
        case .timespan(let seconds): return math(timespan(seconds))
        case .days(let direction, let day, let month, let year): return dated(days(direction, day: day, month: month, year: year, context))
        case .timeIn(let zone): return dated(format(context.date, "EEE d MMM jmm", zone, context.locale))
        case .clock(let hour, let minute, let from, let to):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = from ?? context.timeZone
            var parts = calendar.dateComponents([.year, .month, .day], from: context.date)
            parts.hour = hour
            parts.minute = minute
            return dated(calendar.date(from: parts).map { format($0, "EEE jmm", to, context.locale) })
        }
    }

    /// The text can only be one of these questions (no bare words): the bar asks the search engine nothing about it
    /// and looks for no file with its name.
    public static func leads(_ text: String) -> Bool {
        question(text.trimmingCharacters(in: .whitespacesAndNewlines)).map(leads) ?? false
    }

    /// A currency question, whether or not any rates are known yet: only this asks for the rates.
    public static func asksCurrency(_ text: String) -> Bool {
        if case .currency? = question(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return true }
        return false
    }

    /// The answer depends on the time now.
    public static func usesClock(_ text: String) -> Bool {
        switch question(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case .bare?, .days?, .timeIn?, .clock?: true
        default: false
        }
    }

    private static func leads(_ question: Question) -> Bool {
        if case .bare = question { return false }
        return true
    }

    // MARK: Reading the text

    static func question(_ text: String) -> Question? {
        guard text.count <= 80 else { return nil }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        if words.count == 1, let word = BareWord(rawValue: first) { return .bare(word) }
        if first == "time", words.count >= 3, words[1] == "in" {
            return zone(words[2...].joined(separator: " ")).map { .timeIn($0) }
        }
        if first == "days", words.count >= 3 {
            let direction: DayCount? = switch words[1] { case "until", "till", "to": .until; case "since": .since; default: nil }
            guard let direction, let date = calendarDay(Array(words[2...])) else { return nil }
            return .days(direction, day: date.day, month: date.month, year: date.year)
        }
        if let math = percentOrRoot(words) { return math }
        for index in 1..<max(1, words.count - 1) where ["in", "to", "as"].contains(words[index]) {
            if let found = conversion(Array(words[..<index]), Array(words[(index + 1)...])) { return found }
        }
        for index in 1..<max(1, words.count - 1) where ["in", "to"].contains(words[index]) {
            if let found = clock(Array(words[..<index]), Array(words[(index + 1)...])) { return found }
        }
        return nil
    }

    private static func percentOrRoot(_ words: [String]) -> Question? {
        if let of = words.firstIndex(of: "of"), of > 0, of < words.count - 1, words.count <= 4 {
            let share = words[..<of].joined()
            if share.hasSuffix("%") || share.hasSuffix("percent"), let value = amount(share.replacingOccurrences(of: "percent", with: "").replacingOccurrences(of: "%", with: "")),
               let whole = amount(words[(of + 1)...].joined()) {
                return .percent(value, of: whole)
            }
        }
        if words.count == 4, words[0] == "square", words[1] == "root", words[2] == "of" { return amount(words[3]).map { .squareRoot($0) } }
        if words.count == 2, words[0] == "sqrt" { return amount(words[1]).map { .squareRoot($0) } }
        if words.count == 1, words[0].hasPrefix("sqrt("), words[0].hasSuffix(")") { return amount(String(words[0].dropFirst(5).dropLast())).map { .squareRoot($0) } }
        return nil
    }

    /// "145 mins to timespan", "100 usd in cny", "10ft in m": an amount and a unit, then what to turn it into.
    private static func conversion(_ left: [String], _ right: [String]) -> Question? {
        let joined = left.joined()
        let digits = joined.prefix { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        guard let value = amount(String(digits)) else { return nil }
        let from = String(joined.dropFirst(digits.count)), to = right.joined()
        guard !from.isEmpty, !to.isEmpty else { return nil }
        if to == "timespan" {
            guard let unit = QuickUnit.all.first(where: { $0.dimension == .time && $0.names.contains(from) }) else { return nil }
            return .timespan(seconds: unit.toBase(value))
        }
        let (fromCode, toCode) = (from.uppercased(), to.uppercased())
        if CurrencyRates.codes.contains(fromCode), CurrencyRates.codes.contains(toCode) { return .currency(value, from: fromCode, to: toCode) }
        // One name can mean two units ("pt": a pint and a point); the pair that shares a dimension decides.
        for a in QuickUnit.all where a.names.contains(from) {
            for b in QuickUnit.all where b.dimension == a.dimension && b.names.contains(to) {
                return .convert(value, from: a, to: b)
            }
        }
        return nil
    }

    /// "5pm ldn in sf", "17:00 in tokyo". Without a clock's am, pm or colon a number is no time ("5 in tokyo").
    private static func clock(_ left: [String], _ right: [String]) -> Question? {
        guard let target = zone(right.joined(separator: " ")), let first = left.first else { return nil }
        var rest = Array(left.dropFirst())
        var spoken = first
        if let next = rest.first, next == "am" || next == "pm" { spoken += next; rest.removeFirst() }
        guard let time = clockTime(spoken) else { return nil }
        if rest.isEmpty { return .clock(hour: time.hour, minute: time.minute, from: nil, to: target) }
        return zone(rest.joined(separator: " ")).map { .clock(hour: time.hour, minute: time.minute, from: $0, to: target) }
    }

    private static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        let meridiem = text.hasSuffix("am") ? "am" : text.hasSuffix("pm") ? "pm" : nil
        let digits = meridiem.map { _ in String(text.dropLast(2)) } ?? text
        let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), meridiem != nil || parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), parts[0].count <= 2 else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, parts.count == 1 || parts[1].count == 2, (0...59).contains(minute) else { return nil }
        switch meridiem {
        case "am": return (1...12).contains(hour) ? (hour % 12, minute) : nil
        case "pm": return (1...12).contains(hour) ? (hour % 12 + 12, minute) : nil
        default: return (0...23).contains(hour) ? (hour, minute) : nil
        }
    }

    /// A plain number: digits, a decimal point, thousands commas in the right places.
    private static func amount(_ text: String) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.count == 1 || !parts[1].contains(",") else { return nil }
        if parts[0].contains(",") {
            let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        return Double(text.replacingOccurrences(of: ",", with: "")).flatMap { $0.isFinite ? $0 : nil }
    }

    /// "31 mar", "mar 31", "31st march 2027", "march 31, 2027", "2027-03-31".
    private static func calendarDay(_ words: [String]) -> (day: Int, month: Int, year: Int?)? {
        let words = words.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
        if words.count == 1 {
            let parts = words[0].split(separator: "-").compactMap { Int($0) }
            return parts.count == 3 && (1...12).contains(parts[1]) && (1...31).contains(parts[2]) && parts[0] > 999 ? (parts[2], parts[1], parts[0]) : nil
        }
        guard (2...3).contains(words.count) else { return nil }
        let (a, b) = (words[0], words[1])
        let parsed: (Int, Int)? = if let month = month(a), let day = dayNumber(b) { (day, month) }
            else if let day = dayNumber(a), let month = month(b) { (day, month) }
            else { nil }
        guard let parsed else { return nil }
        if words.count == 3 {
            guard let year = Int(words[2]), year > 999 else { return nil }
            return (parsed.0, parsed.1, year)
        }
        return (parsed.0, parsed.1, nil)
    }

    private static func dayNumber(_ word: String) -> Int? {
        let digits = word.prefix { $0.isASCII && $0.isNumber }
        guard ["", "st", "nd", "rd", "th"].contains(String(word.dropFirst(digits.count))), let day = Int(digits), (1...31).contains(day) else { return nil }
        return day
    }

    private static func month(_ word: String) -> Int? {
        let names = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        guard word.count >= 3 else { return nil }
        // "sept" is the one common short form longer than three letters.
        if word == "sept" { return 9 }
        return names.firstIndex { $0 == word || ($0.prefix(3) == word) }.map { $0 + 1 }
    }

    // MARK: Time zones

    /// Names people use that the system's zone list does not spell ("Asia/Tokyo" gives "tokyo" by itself).
    private static let zoneAliases: [String: String] = [
        "ldn": "Europe/London", "uk": "Europe/London", "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles",
        "seattle": "America/Los_Angeles", "san diego": "America/Los_Angeles", "nyc": "America/New_York", "ny": "America/New_York", "boston": "America/New_York",
        "dc": "America/New_York", "washington": "America/New_York", "miami": "America/New_York", "austin": "America/Chicago", "dallas": "America/Chicago",
        "houston": "America/Chicago", "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai", "guangzhou": "Asia/Shanghai", "hangzhou": "Asia/Shanghai",
        "hk": "Asia/Hong_Kong", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "hanoi": "Asia/Ho_Chi_Minh", "sg": "Asia/Singapore", "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin",
        "barcelona": "Europe/Madrid", "milan": "Europe/Rome", "geneva": "Europe/Zurich", "utc": "UTC", "gmt": "GMT",
    ]

    /// The last part of every zone the system knows, lowercased with spaces: "new york", "buenos aires".
    private static let zoneCities: [String: String] = {
        var cities: [String: String] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            guard let last = id.split(separator: "/").last, id.contains("/") else { continue }
            cities[last.replacingOccurrences(of: "_", with: " ").lowercased()] = id
        }
        return cities
    }()

    static func zone(_ name: String) -> TimeZone? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if let id = zoneAliases[name] ?? zoneCities[name] { return TimeZone(identifier: id) }
        // "pst", "cet", "jst": the abbreviations the system knows.
        guard (2...4).contains(name.count), name.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return TimeZone.abbreviationDictionary[name.uppercased()].flatMap(TimeZone.init(identifier:))
    }

    // MARK: Answers

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Up to ten significant digits, no trailing zeros: 3.048, 0.6213711922.
    private static func number(_ value: Double) -> String {
        String(format: "%.10g", locale: posix, value == 0 ? 0 : value)
    }

    private static func format(_ date: Date, _ template: String, _ zone: TimeZone, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func bare(_ word: BareWord, _ context: QuickAnswerContext) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        func day(_ offset: Int) -> String? {
            calendar.date(byAdding: .day, value: offset, to: context.date).map { format($0, "EEEE d MMMM y", context.timeZone, context.locale) }
        }
        switch word {
        case .now: return format(context.date, "EEE d MMM y jmm", context.timeZone, context.locale)
        case .time: return format(context.date, "jmm", context.timeZone, context.locale)
        case .today: return day(0)
        case .tomorrow: return day(1)
        case .yesterday: return day(-1)
        }
    }

    private static func days(_ direction: DayCount, day: Int, month: Int, year: Int?, _ context: QuickAnswerContext) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        let today = calendar.startOfDay(for: context.date)
        func date(in year: Int) -> Date? {
            let parts = DateComponents(calendar: calendar, year: year, month: month, day: day)
            return parts.isValidDate ? parts.date : nil
        }
        var target = year.flatMap(date(in:))
        if year == nil {
            // The next time the day comes round (a 29 February can be years off), or the last time it was.
            let thisYear = calendar.component(.year, from: today), step = direction == .until ? 1 : -1
            for offset in 0...8 {
                guard let candidate = date(in: thisYear + offset * step) else { continue }
                if direction == .until ? candidate >= today : candidate <= today { target = candidate; break }
            }
        }
        guard let target, let count = calendar.dateComponents([.day], from: today, to: target).day else { return nil }
        let shown = direction == .until ? count : -count
        return shown == 1 || shown == -1 ? "\(shown) day" : "\(shown) days"
    }

    private static func timespan(_ seconds: Double) -> String {
        var left = Int(seconds.rounded())
        guard left > 0 else { return "0 seconds" }
        var parts: [String] = []
        for (size, name) in [(604_800, "week"), (86_400, "day"), (3_600, "hour"), (60, "minute"), (1, "second")] {
            let count = left / size
            left -= count * size
            if count > 0 { parts.append("\(count) \(name)\(count == 1 ? "" : "s")") }
        }
        return parts.joined(separator: " ")
    }
}

private extension QuickAnswerContext {
    var date: Date { Date(timeIntervalSince1970: Double(now.milliseconds) / 1000) }
}

/// A unit the bar converts: a linear step to its dimension's base (temperature also has an offset). CSS lengths are
/// lengths: 1in is 96px, 1rem and 1em are 16px.
struct QuickUnit: Equatable, Sendable {
    enum Dimension: Equatable, Sendable { case length, mass, volume, area, speed, data, time, temperature }
    let label: String
    let dimension: Dimension
    let names: Set<String>
    var factor: Double
    var offset: Double = 0

    func toBase(_ value: Double) -> Double { value * factor + offset }
    func fromBase(_ value: Double) -> Double { (value - offset) / factor }

    private init(_ label: String, _ dimension: Dimension, _ names: [String], _ factor: Double, offset: Double = 0) {
        self.label = label
        self.dimension = dimension
        self.names = Set(names)
        self.factor = factor
        self.offset = offset
    }

    static let all: [QuickUnit] = {
        let inch = 0.0254, px = inch / 96
        let litre = 1000.0, gallon = 3785.411784
        let kilo = 1000.0, kibi = 1024.0
        return [
            QuickUnit("mm", .length, ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], 0.001),
            QuickUnit("cm", .length, ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], 0.01),
            QuickUnit("m", .length, ["m", "meter", "meters", "metre", "metres"], 1),
            QuickUnit("km", .length, ["km", "kilometer", "kilometers", "kilometre", "kilometres"], 1000),
            QuickUnit("in", .length, ["in", "inch", "inches"], inch),
            QuickUnit("ft", .length, ["ft", "foot", "feet"], 0.3048),
            QuickUnit("yd", .length, ["yd", "yard", "yards"], 0.9144),
            QuickUnit("mi", .length, ["mi", "mile", "miles"], 1609.344),
            QuickUnit("nmi", .length, ["nmi"], 1852),
            QuickUnit("px", .length, ["px", "pixel", "pixels"], px),
            QuickUnit("rem", .length, ["rem"], 16 * px),
            QuickUnit("em", .length, ["em"], 16 * px),
            QuickUnit("pt", .length, ["pt", "point", "points"], inch / 72),
            QuickUnit("pc", .length, ["pc"], inch / 6),
            QuickUnit("mg", .mass, ["mg", "milligram", "milligrams"], 0.001),
            QuickUnit("g", .mass, ["g", "gram", "grams"], 1),
            QuickUnit("kg", .mass, ["kg", "kilo", "kilos", "kilogram", "kilograms"], 1000),
            QuickUnit("t", .mass, ["t", "tonne", "tonnes"], 1_000_000),
            QuickUnit("oz", .mass, ["oz", "ounce", "ounces"], 28.349523125),
            QuickUnit("lb", .mass, ["lb", "lbs", "pound", "pounds"], 453.59237),
            QuickUnit("st", .mass, ["st", "stone", "stones"], 6350.29318),
            QuickUnit("mL", .volume, ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], 1),
            QuickUnit("L", .volume, ["l", "liter", "liters", "litre", "litres"], litre),
            QuickUnit("tsp", .volume, ["tsp", "teaspoon", "teaspoons"], gallon / 768),
            QuickUnit("tbsp", .volume, ["tbsp", "tablespoon", "tablespoons"], gallon / 256),
            QuickUnit("fl oz", .volume, ["floz", "fluidounce", "fluidounces"], gallon / 128),
            QuickUnit("cups", .volume, ["cup", "cups"], gallon / 16),
            QuickUnit("pt", .volume, ["pt", "pint", "pints"], gallon / 8),
            QuickUnit("qt", .volume, ["qt", "quart", "quarts"], gallon / 4),
            QuickUnit("gal", .volume, ["gal", "gallon", "gallons"], gallon),
            QuickUnit("m²", .area, ["m2", "m²", "sqm"], 1),
            QuickUnit("km²", .area, ["km2", "km²", "sqkm"], 1_000_000),
            QuickUnit("ft²", .area, ["ft2", "ft²", "sqft"], 0.09290304),
            QuickUnit("acres", .area, ["acre", "acres"], 4046.8564224),
            QuickUnit("ha", .area, ["ha", "hectare", "hectares"], 10_000),
            QuickUnit("m/s", .speed, ["m/s", "mps"], 1),
            QuickUnit("km/h", .speed, ["km/h", "kmh", "kph"], 1000.0 / 3600),
            QuickUnit("mph", .speed, ["mph"], 1609.344 / 3600),
            QuickUnit("kn", .speed, ["kn", "knot", "knots"], 1852.0 / 3600),
            QuickUnit("B", .data, ["b", "byte", "bytes"], 1),
            QuickUnit("KB", .data, ["kb"], kilo),
            QuickUnit("MB", .data, ["mb"], kilo * kilo),
            QuickUnit("GB", .data, ["gb"], kilo * kilo * kilo),
            QuickUnit("TB", .data, ["tb"], kilo * kilo * kilo * kilo),
            QuickUnit("KiB", .data, ["kib"], kibi),
            QuickUnit("MiB", .data, ["mib"], kibi * kibi),
            QuickUnit("GiB", .data, ["gib"], kibi * kibi * kibi),
            QuickUnit("TiB", .data, ["tib"], kibi * kibi * kibi * kibi),
            QuickUnit("ms", .time, ["ms", "millisecond", "milliseconds"], 0.001),
            QuickUnit("s", .time, ["s", "sec", "secs", "second", "seconds"], 1),
            QuickUnit("min", .time, ["min", "mins", "minute", "minutes"], 60),
            QuickUnit("h", .time, ["h", "hr", "hrs", "hour", "hours"], 3600),
            QuickUnit("days", .time, ["d", "day", "days"], 86_400),
            QuickUnit("weeks", .time, ["w", "wk", "wks", "week", "weeks"], 604_800),
            QuickUnit("°C", .temperature, ["c", "°c", "celsius"], 1, offset: 273.15),
            QuickUnit("°F", .temperature, ["f", "°f", "fahrenheit"], 5.0 / 9, offset: 459.67 * 5 / 9),
            QuickUnit("K", .temperature, ["k", "kelvin"], 1),
        ]
    }()
}

/// Euro reference rates from the European Central Bank's daily file: free, no key, one small public file. BrkApp fetches
/// it at most once a day and only after a currency question; nothing about the user goes with the request.
public struct CurrencyRates: Sendable, Hashable, Codable {
    /// The day the rates are for, as the file writes it: "2026-11-06".
    public var date: String
    /// Units of each currency for one euro; "EUR" is 1.
    public var perEuro: [String: Double]

    public init(date: String, perEuro: [String: Double]) {
        self.date = date
        self.perEuro = perEuro
    }

    /// What the file lists, so that a question can be told from a search before any rates are known. A code the file
    /// has dropped simply gets no answer.
    static let codes: Set<String> = ["AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW",
                                     "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"]

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perEuro[from], let b = perEuro[to], a > 0 else { return nil }
        return amount / a * b
    }

    /// `<Cube time='2026-11-06'><Cube currency='USD' rate='1.1165'/>…`. Nil unless the file has a date and a rate.
    public static func parseECB(_ data: Data) -> CurrencyRates? {
        guard data.count <= 1 << 20 else { return nil }
        let reader = ECBReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let date = reader.date, !reader.rates.isEmpty else { return nil }
        return CurrencyRates(date: date, perEuro: reader.rates.merging(["EUR": 1]) { current, _ in current })
    }
}

private final class ECBReader: NSObject, XMLParserDelegate {
    var date: String?
    var rates: [String: Double] = [:]

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard element == "Cube" else { return }
        if let time = attributes["time"], time.count == 10, date == nil { date = time }
        if let code = attributes["currency"], code.count == 3, let rate = attributes["rate"].flatMap(Double.init), rate > 0, rate.isFinite { rates[code] = rate }
    }
}
