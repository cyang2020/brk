import BrkBase
import Foundation

/// Supported iCalendar subset: nonrecurring VEVENTs with explicit end and UTC or TZID date-times.
/// Unsupported recurrence is rejected rather than presented as a complete calendar.
public enum CalendarFile {
    public static func meetings(_ data: Data) throws -> [CalendarMeeting] {
        guard data.count <= 2_000_000, let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else { throw CocoaError(.fileReadCorruptFile) }
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var fields: [String: (String, String)] = [:]
        var out: [CalendarMeeting] = []
        func date(_ field: (String, String)?) -> Instant? {
            guard let (key, value) = field else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            if value.hasSuffix("Z") {
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            } else if let zone = key.components(separatedBy: "TZID=").last, zone != key, let tz = TimeZone(identifier: zone) {
                formatter.timeZone = tz
                formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            } else { return nil }
            return formatter.date(from: value).map { Instant(milliseconds: Int64($0.timeIntervalSince1970 * 1000)) }
        }
        for raw in unfolded.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line == "BEGIN:VEVENT" { fields = [:]; continue }
            if line == "END:VEVENT" {
                guard fields["RRULE"] == nil, fields["RDATE"] == nil else { throw CocoaError(.featureUnsupported) }
                guard fields["STATUS"]?.1 != "CANCELLED", let start = date(fields["DTSTART"]), let end = date(fields["DTEND"]), end > start,
                      let value = fields["URL"]?.1 ?? fields["LOCATION"]?.1,
                      let url = URL(string: value), url.scheme == "https" else { continue }
                out.append(CalendarMeeting(title: fields["SUMMARY"]?.1 ?? "Meeting", url: url, start: start, end: end))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let name = String(key.split(separator: ";")[0])
            fields[name] = (key, String(line[line.index(after: colon)...]).replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\n", with: " "))
        }
        return out.sorted { $0.start < $1.start }
    }
}
