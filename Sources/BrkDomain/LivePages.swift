import BrkBase
import Foundation

// Live AI pages (docs/design/ai-native.md, 会自己更新的 AI 页面; docs/design/ai-live-pages.md): a kept page that refreshes
// its data on a schedule, saves what the user ticks and notes inside it, and can show in Today on chosen weekdays only.
// The page's shape is fixed when it is made: the data a refresh writes and what the page saves are checked against it,
// and the addresses a refresh may read are the ones the page listed then.

/// When a kept page refreshes its data. Slots are in the user's local time.
public enum AIPageSchedule: Hashable, Sendable, Codable {
    /// At the start of every hour.
    case hourly
    case daily(hour: Int, minute: Int)
    /// `weekday` as `Calendar` numbers it: 1 is Sunday, 2 Monday, … 7 Saturday.
    case weekly(weekday: Int, hour: Int, minute: Int)

    /// The latest slot at or before `now`. A page whose last run is before it is due.
    public func latestSlot(atOrBefore now: Instant, calendar: Calendar) -> Instant {
        let date = Date(timeIntervalSince1970: Double(now.milliseconds) / 1000)
        func instant(_ date: Date) -> Instant { Instant(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded(.down))) }
        switch self {
        case .hourly:
            let parts = calendar.dateComponents([.era, .year, .month, .day, .hour], from: date)
            return calendar.date(from: parts).map(instant) ?? now
        case .daily(let hour, let minute):
            guard var slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { return now }
            if slot > date { slot = calendar.date(byAdding: .day, value: -1, to: slot) ?? slot }
            return instant(slot)
        case .weekly(let weekday, let hour, let minute):
            for back in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: date),
                      let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
                if calendar.component(.weekday, from: slot) == weekday, slot <= date { return instant(slot) }
            }
            return now
        }
    }

    /// Due when a slot has passed since the last run. However many slots were missed (Brk was not running), this is one
    /// run: the run takes the latest slot.
    public func isDue(lastRun: Instant, now: Instant, calendar: Calendar) -> Bool {
        latestSlot(atOrBefore: now, calendar: calendar) > lastRun
    }

    public var isValid: Bool {
        switch self {
        case .hourly: true
        case .daily(let hour, let minute): (0...23).contains(hour) && (0...59).contains(minute)
        case .weekly(let weekday, let hour, let minute): (1...7).contains(weekday) && (0...23).contains(hour) && (0...59).contains(minute)
        }
    }

    /// The menu's words: "Every Hour", "Every Day at 9:00", "Every Monday at 9:00".
    public var title: String {
        func time(_ hour: Int, _ minute: Int) -> String { "\(hour):" + (minute < 10 ? "0\(minute)" : "\(minute)") }
        switch self {
        case .hourly: return "Every Hour"
        case .daily(let hour, let minute): return "Every Day at \(time(hour, minute))"
        case .weekly(let weekday, let hour, let minute): return "Every \(AIPageWeekdays.name(weekday)) at \(time(hour, minute))"
        }
    }

    /// The same in a sentence: "every hour", "every day at 9:00", "every Monday at 9:00".
    public var phrase: String {
        switch self {
        case .hourly: "every hour"
        case .daily: "every day" + title.dropFirst("Every Day".count)
        case .weekly: "every" + title.dropFirst("Every".count)
        }
    }

    /// The presets the row's menu offers.
    public static let presets: [AIPageSchedule] = [.hourly, .daily(hour: 9, minute: 0), .weekly(weekday: 2, hour: 9, minute: 0)]
}

/// Days of the week as `Calendar` numbers them (1 Sunday … 7 Saturday), in the order a week reads (Monday first).
public enum AIPageWeekdays {
    public static let order = [2, 3, 4, 5, 6, 7, 1]
    public static let weekdays: [Int] = [2, 3, 4, 5, 6]
    public static let weekend: [Int] = [7, 1]
    private static let names = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"]
    public static func name(_ day: Int) -> String { names[day] ?? "Monday" }
    /// "monday", "Mon", "周一" or "星期一" to 2.
    public static func parse(_ text: String) -> Int? {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        for (day, name) in names where name.lowercased() == lower || name.lowercased().prefix(3) == lower { return day }
        let chinese = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        for prefix in ["周", "星期", "礼拜"] where lower.hasPrefix(prefix) {
            if let day = chinese[String(lower.dropFirst(prefix.count))] { return day }
        }
        return nil
    }
    /// A sorted, unique list of valid days, nil for every day (all seven, or none given).
    public static func normalized(_ days: [Int]?) -> [Int]? {
        guard let days else { return nil }
        let valid = Set(days.filter { (1...7).contains($0) })
        guard !valid.isEmpty, valid.count < 7 else { return nil }
        return order.filter(valid.contains)
    }
    /// "Weekdays", "Weekends", "Monday", "Mon, Wed, Fri".
    public static func title(_ days: [Int]?) -> String {
        guard let days = normalized(days) else { return "Every Day" }
        if days == weekdays { return "Weekdays" }
        if Set(days) == Set(weekend) { return "Weekends" }
        if days.count == 1 { return name(days[0]) }
        return days.map { String(name($0).prefix(3)) }.joined(separator: ", ")
    }
}

/// Which model a refresh runs on: the small model of the basic features (the default), or the conversation's own.
public enum AIPageRefreshModel: String, Hashable, Sendable, Codable { case basic, conversation }

/// How the last refresh ended.
public struct AIPageRefreshOutcome: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// New data was written and it differs from what the page had.
        case updated
        /// The agent finished without new data, or wrote the same data.
        case unchanged
        /// The agent or a read failed, or the agent refused; nothing changed.
        case failed
        /// The injection check flagged something the refresh read: the refresh stopped and nothing changed.
        case flagged
    }
    public var kind: Kind
    public var at: Instant
    /// Why, in a few words, for a failure or a flag.
    public var detail: String?
    public init(kind: Kind, at: Instant, detail: String? = nil) { self.kind = kind; self.at = at; self.detail = detail }
}

/// A kept page's schedule, model, weekdays and what its last refresh did.
public struct AIPageLive: Hashable, Sendable, Codable {
    public var schedule: AIPageSchedule?
    public var model: AIPageRefreshModel?
    /// The days its row shows in Today; nil every day.
    public var weekdays: [Int]?
    /// When the last refresh started, or when the schedule was set: the slot it covers.
    public var lastRun: Instant?
    public var outcome: AIPageRefreshOutcome?
    /// When a refresh last changed the data, and when the user last looked at the page.
    public var changedAt: Instant?
    public var seenAt: Instant?
    public init(schedule: AIPageSchedule? = nil, model: AIPageRefreshModel? = nil, weekdays: [Int]? = nil) {
        self.schedule = schedule; self.model = model; self.weekdays = weekdays
    }
    public var refreshModel: AIPageRefreshModel { model ?? .basic }
    /// Data changed since the user last looked.
    public var unseenChange: Bool { changedAt.map { $0 > (seenAt ?? Instant(milliseconds: 0)) } ?? false }
    /// The last refresh was stopped or failed and the user has not looked since.
    public var unseenProblem: Bool {
        guard let outcome, outcome.kind == .flagged || outcome.kind == .failed else { return false }
        return outcome.at > (seenAt ?? Instant(milliseconds: 0))
    }
}

/// A change to a kept page from its row's menu or the agent's `brk_page_save`.
public enum AIPageLiveChange: Hashable, Sendable, Codable {
    case schedule(AIPageSchedule?)
    case weekdays([Int]?)
    case model(AIPageRefreshModel)
    case refreshNow
}

/// What the sidebar row of a live page shows at its trailing end.
public enum LivePageMark: String, Hashable, Sendable, Codable {
    /// A refresh changed the data since the user last looked: a dot.
    case changed
    /// The last refresh was stopped by the injection check, or failed: a warning sign.
    case attention
}

/// One refresh, as the app runs it (`Effect.aiRefreshPage`).
public struct AIPageRefreshRun: Hashable, Sendable {
    public let run: AIRequestID
    public let page: AIPageID
    public let conversation: AIRequestID
    public let profile: ProfileID
    /// A standard window of the page's profile: the refresh's reads load there, out of sight.
    public let window: WindowID
    public let agent: AIProviderKind
    /// The model to run; nil: the agent's own default.
    public let model: String?
    public let effort: String?
    public let title: String
    public let data: String?
    public let saved: String?
    /// The data's shape, as JSON Schema text.
    public let schema: String
    /// The addresses the page was made from: the only ones the refresh may load.
    public let sources: [URL]
    /// The conversation so far, as text.
    public let history: String
    public init(run: AIRequestID, page: AIPageID, conversation: AIRequestID, profile: ProfileID, window: WindowID, agent: AIProviderKind, model: String?,
                effort: String?, title: String, data: String?, saved: String?, schema: String, sources: [URL], history: String) {
        self.run = run; self.page = page; self.conversation = conversation; self.profile = profile; self.window = window; self.agent = agent
        self.model = model; self.effort = effort; self.title = title; self.data = data; self.saved = saved; self.schema = schema
        self.sources = sources; self.history = history
    }
}

/// What a running refresh reports (`SystemEvent.aiPageRefresh`).
public enum AIPageRefreshEvent: Hashable, Sendable {
    /// `brk_page_update_data` passed its checks in the tool service: the page's new data, as JSON text.
    case data(String)
    case finished(AIPageRefreshOutcome.Kind, detail: String?)
}

public extension AIPageLimits {
    /// What a page saves of its own (ticks, notes), as JSON text.
    static let saved = 64_000
    /// A declared shape, as JSON text.
    static let schema = 20_000
    /// Addresses a page may list as its sources.
    static let sources = 20
    /// Saves a page may make in a minute; more are refused until the minute is over.
    static let savesPerMinute = 60
}

/// The data shapes pages declare, a small part of JSON Schema: `type` (one name or a list), `properties`, `required`,
/// `additionalProperties` (false or a shape), `items`, `enum`, `minimum`, `maximum`, `maxLength`, `minItems`,
/// `maxItems`. Other keywords are ignored. Values are what JSONSerialization makes.
public enum AIPageShape {
    /// Any JSON object: what a page that declared no save shape may save.
    public static var anyObject: [String: Any] { ["type": "object"] }

    /// Parses JSON text into an object; nil for anything else.
    public static func object(_ text: String?) -> [String: Any]? {
        guard let text, let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        return value
    }

    /// JSON text of `value`, keys sorted, so equal data compares equal.
    public static func text(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `text` normalized (keys sorted), when it is a JSON object.
    public static func normalized(_ text: String) -> String? { object(text).flatMap(self.text) }

    /// Why a declared shape cannot be used, nil when it can: an object, at most `AIPageLimits.schema` bytes, nested at
    /// most 16 deep, with known type names.
    public static func shapeProblem(_ schema: [String: Any]) -> String? {
        guard let text = text(schema), text.utf8.count <= AIPageLimits.schema else { return "the shape must be a JSON object of at most \(AIPageLimits.schema) bytes" }
        func walk(_ value: Any, depth: Int) -> String? {
            guard depth <= 16 else { return "the shape is nested too deep" }
            guard let schema = value as? [String: Any] else { return "each shape is an object" }
            if let type = schema["type"] {
                let names = (type as? [Any] ?? [type]).compactMap { $0 as? String }
                guard !names.isEmpty, names.allSatisfy(typeNames.contains) else { return "unknown type \(type)" }
            }
            for (_, child) in schema["properties"] as? [String: Any] ?? [:] { if let problem = walk(child, depth: depth + 1) { return problem } }
            if let items = schema["items"], let problem = walk(items, depth: depth + 1) { return problem }
            if let extra = schema["additionalProperties"] as? [String: Any], let problem = walk(extra, depth: depth + 1) { return problem }
            return nil
        }
        return walk(schema, depth: 0)
    }
    private static let typeNames: Set<String> = ["object", "array", "string", "number", "integer", "boolean", "null"]

    /// Why `value` does not fit `schema`, nil when it does. `path` names the place in the message ("data.items[2].price").
    public static func problem(_ value: Any, _ schema: [String: Any], path: String = "data") -> String? {
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { equal($0, value) }) { return "\(path) is not one of the allowed values" }
        if let type = schema["type"] {
            let names = (type as? [Any] ?? [type]).compactMap { $0 as? String }
            guard names.contains(where: { matches(value, $0) }) else { return "\(path) must be \(names.joined(separator: " or "))" }
        }
        if let number = value as? NSNumber, !isBool(number) {
            if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, number.doubleValue < minimum { return "\(path) is below \(minimum)" }
            if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, number.doubleValue > maximum { return "\(path) is above \(maximum)" }
        }
        if let string = value as? String, let most = (schema["maxLength"] as? NSNumber)?.intValue, string.count > most { return "\(path) is longer than \(most) characters" }
        if let array = value as? [Any] {
            if let most = (schema["maxItems"] as? NSNumber)?.intValue, array.count > most { return "\(path) has more than \(most) items" }
            if let least = (schema["minItems"] as? NSNumber)?.intValue, array.count < least { return "\(path) has fewer than \(least) items" }
            if let items = schema["items"] as? [String: Any] {
                for (index, element) in array.enumerated() { if let problem = problem(element, items, path: "\(path)[\(index)]") { return problem } }
            }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for key in (schema["required"] as? [Any] ?? []).compactMap({ $0 as? String }) where object[key] == nil { return "\(path).\(key) is missing" }
            for key in object.keys.sorted() {
                if let child = properties[key] as? [String: Any] {
                    if let problem = problem(object[key]!, child, path: "\(path).\(key)") { return problem }
                } else if let extra = schema["additionalProperties"] {
                    if (extra as? NSNumber).map({ isBool($0) && !$0.boolValue }) == true { return "\(path).\(key) is not in the page's shape" }
                    if let extra = extra as? [String: Any], let problem = problem(object[key]!, extra, path: "\(path).\(key)") { return problem }
                }
            }
        }
        return nil
    }

    /// A shape for data the page gave without declaring one: the same types, every key it had required, extra keys
    /// allowed. A null says nothing about the type, so it allows anything.
    public static func infer(_ value: Any) -> [String: Any] {
        switch value {
        case let object as [String: Any]:
            return ["type": "object", "properties": object.mapValues(infer), "required": object.keys.sorted()]
        case let array as [Any]:
            let shapes = array.map(infer)
            guard var items = shapes.first else { return ["type": "array"] }
            for shape in shapes.dropFirst() { items = merge(items, shape) }
            return ["type": "array", "items": items]
        case is String: return ["type": "string"]
        case let number as NSNumber: return ["type": isBool(number) ? "boolean" : "number"]
        default: return [:]
        }
    }

    /// One shape that both fit: objects keep the keys both have as required; differing types allow both.
    private static func merge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        if a.isEmpty || b.isEmpty { return [:] }
        guard a["type"] as? String == b["type"] as? String else {
            let names = Set([a["type"], b["type"]].compactMap { $0 as? String })
            return ["type": names.sorted()]
        }
        if a["type"] as? String == "object" {
            let pa = a["properties"] as? [String: Any] ?? [:], pb = b["properties"] as? [String: Any] ?? [:]
            var properties: [String: Any] = [:]
            for key in Set(pa.keys).union(pb.keys) {
                switch (pa[key] as? [String: Any], pb[key] as? [String: Any]) {
                case let (x?, y?): properties[key] = merge(x, y)
                case let (x?, nil): properties[key] = x
                case let (nil, y?): properties[key] = y
                default: break
                }
            }
            let required = Set((a["required"] as? [String]) ?? []).intersection((b["required"] as? [String]) ?? [])
            return ["type": "object", "properties": properties, "required": required.sorted()]
        }
        if a["type"] as? String == "array", let x = a["items"] as? [String: Any], let y = b["items"] as? [String: Any] {
            return ["type": "array", "items": merge(x, y)]
        }
        return a
    }

    private static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }

    private static func matches(_ value: Any, _ type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return (value as? NSNumber).map(isBool) == true
        case "number": return (value as? NSNumber).map { !isBool($0) } == true
        case "integer": return (value as? NSNumber).map { !isBool($0) && $0.doubleValue == $0.doubleValue.rounded() } == true
        case "null": return value is NSNull
        default: return false
        }
    }

    private static func equal(_ a: Any, _ b: Any) -> Bool {
        guard let x = text(["v": a]), let y = text(["v": b]) else { return false }
        return x == y
    }

    /// Checks JSON text a page or a refresh sends: an object within `limit` bytes that fits `schema`. Returns the
    /// normalized text, or why it was refused.
    public static func check(_ text: String, schema: [String: Any], limit: Int) -> Result<String, ShapeRefusal> {
        guard text.utf8.count <= limit else { return .failure(ShapeRefusal(message: "it is larger than \(limit) bytes")) }
        guard let value = object(text) else { return .failure(ShapeRefusal(message: "it is not a JSON object")) }
        if let problem = problem(value, schema) { return .failure(ShapeRefusal(message: problem)) }
        guard let normalized = self.text(value), normalized.utf8.count <= limit else { return .failure(ShapeRefusal(message: "it is larger than \(limit) bytes")) }
        return .success(normalized)
    }

    public struct ShapeRefusal: Error, Equatable { public let message: String }
}

extension AIPageRecord {
    /// The shape a refresh must keep: the one the page declared, else the one its first data had.
    public var dataShape: [String: Any]? {
        if let declared = AIPageShape.object(schema) { return declared }
        return AIPageShape.object(data).map(AIPageShape.infer)
    }
    /// The shape the page's own saves must keep.
    public var saveShape: [String: Any] { AIPageShape.object(saveSchema) ?? AIPageShape.anyObject }
    public var liveState: AIPageLive { live ?? AIPageLive() }
}
