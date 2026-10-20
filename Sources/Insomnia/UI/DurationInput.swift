import Foundation

/// The three pills in the menu bar, as data. Pure: no clocks, no UI.
///
/// Each field is `nil` while it still shows its placeholder. Digits are
/// appended one at a time by the key monitor; a field never holds more than
/// two digits and never exceeds its ceiling, so what is on screen is always
/// a value the session can use.
struct DurationInput: Equatable, Sendable {
    enum Field: Int, CaseIterable, Sendable {
        case days
        case hours
        case minutes

        var placeholder: String {
            switch self {
            case .days: return "Gün"
            case .hours: return "Saat"
            case .minutes: return "Dakika"
            }
        }

        /// Tooltip on the "?" badge.
        var help: String {
            switch self {
            case .days: return "En fazla \(DurationInput.maxDays) gün"
            case .hours: return "0\u{2013}\(DurationInput.maxHours)"
            case .minutes: return "0\u{2013}\(DurationInput.maxMinutes)"
            }
        }

        var maximum: Int {
            switch self {
            case .days: return DurationInput.maxDays
            case .hours: return DurationInput.maxHours
            case .minutes: return DurationInput.maxMinutes
            }
        }

        var next: Field {
            Field(rawValue: (rawValue + 1) % Field.allCases.count)!
        }

        var previous: Field {
            Field(rawValue: (rawValue + Field.allCases.count - 1) % Field.allCases.count)!
        }
    }

    static let maxDays = 30
    static let maxHours = 23
    static let maxMinutes = 59
    /// Every field is two digits wide at most.
    static let maxDigits = 2

    var days: Int?
    var hours: Int?
    var minutes: Int?

    init(days: Int? = nil, hours: Int? = nil, minutes: Int? = nil) {
        self.days = days
        self.hours = hours
        self.minutes = minutes
    }

    subscript(field: Field) -> Int? {
        get {
            switch field {
            case .days: return days
            case .hours: return hours
            case .minutes: return minutes
            }
        }
        set {
            switch field {
            case .days: days = newValue
            case .hours: hours = newValue
            case .minutes: minutes = newValue
            }
        }
    }

    // MARK: Validation

    /// True while every pill still shows its placeholder.
    var isEmpty: Bool { days == nil && hours == nil && minutes == nil }

    func isValid(_ field: Field) -> Bool {
        guard let v = self[field] else { return true }
        return v >= 0 && v <= field.maximum
    }

    /// Every field in range and at least one non-zero.
    var isValid: Bool {
        Field.allCases.allSatisfy(isValid) && (total ?? 0) > 0
    }

    /// Seconds represented, or nil when a field is out of range or nothing
    /// non-zero has been entered.
    var total: TimeInterval? {
        guard Field.allCases.allSatisfy(isValid) else { return nil }
        let d: Int = (days ?? 0) * 86_400
        let h: Int = (hours ?? 0) * 3_600
        let m: Int = (minutes ?? 0) * 60
        let seconds = TimeInterval(d + h + m)
        return seconds > 0 ? seconds : nil
    }

    // MARK: Presets

    /// Fill the pills from a preset. Seconds are floored to the minute; fields
    /// that would be zero stay empty so the pills read like the chip did
    /// ("2sa" fills only Saat). Values beyond 30 days are clamped.
    static func from(seconds: TimeInterval) -> DurationInput {
        let totalMinutes = min(max(Int(seconds / 60), 0), maxDays * 24 * 60)
        let d = totalMinutes / (24 * 60)
        let h = (totalMinutes % (24 * 60)) / 60
        let m = totalMinutes % 60
        return DurationInput(days: d > 0 ? d : nil, hours: h > 0 ? h : nil, minutes: m > 0 ? m : nil)
    }

    // MARK: Editing

    /// Text shown in the pill, nil while it shows its placeholder.
    func text(for field: Field) -> String? {
        self[field].map(String.init)
    }

    /// True when another digit could still be typed into `field`.
    func canAcceptDigit(in field: Field) -> Bool {
        guard let v = self[field] else { return true }
        return String(v).count < DurationInput.maxDigits && v * 10 <= field.maximum
    }

    /// Append a digit (0...9) to `field`. Returns false, leaving the value
    /// alone, when the field is full or the result would exceed its ceiling.
    @discardableResult
    mutating func append(digit: Int, to field: Field) -> Bool {
        guard (0...9).contains(digit) else { return false }
        let current = self[field]
        if current == 0 && digit == 0 { return false }
        if let c = current, String(c).count >= DurationInput.maxDigits { return false }
        let proposed = (current ?? 0) * 10 + digit
        guard proposed <= field.maximum else { return false }
        self[field] = proposed
        return true
    }

    /// Remove the last digit of `field`. Returns false when it was already
    /// empty, so the caller can move focus to the previous pill instead.
    @discardableResult
    mutating func backspace(_ field: Field) -> Bool {
        guard let v = self[field] else { return false }
        let shorter = v / 10
        self[field] = (v < 10) ? nil : shorter
        return true
    }

    mutating func clear(_ field: Field) {
        self[field] = nil
    }

    mutating func clearAll() {
        days = nil
        hours = nil
        minutes = nil
    }
}

/// Parses the short durations typed into settings: Turkish units ("30dk",
/// "2sa", "1sa30dk", "3g", also spelled out: "30 dakika", "2 saat",
/// "3 gün") and the English ones ("30m", "2h", "1h30m", "3d").
enum DurationParser {
    /// Seconds per unit. A unit is the whole run of letters after a
    /// number, so a multi-letter unit is matched as a whole, before any
    /// single letter: "30dk" is minutes, never days.
    private static let unitSeconds: [String: Int] = [
        "g": 86_400, "gün": 86_400, "d": 86_400,
        "sa": 3_600, "saat": 3_600, "h": 3_600,
        "dk": 60, "dakika": 60, "m": 60,
    ]

    /// Seconds, or nil when the text is not a duration. Bare numbers are minutes.
    static func seconds(from text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // "İ" lowercases to "i" plus a combining dot: "DAKİKA" is "dakika".
            .replacingOccurrences(of: "i\u{0307}", with: "i")
        guard !trimmed.isEmpty else { return nil }
        if let bare = Int(trimmed) {
            guard bare > 0 else { return nil }
            let (seconds, overflow) = bare.multipliedReportingOverflow(by: 60)
            return overflow ? nil : TimeInterval(seconds)
        }
        var total = 0
        var number = ""
        var unit = ""
        var sawUnit = false
        /// Adds `number` in `unit` to the total; false rejects the text.
        func addUnit() -> Bool {
            guard let n = Int(number), let multiplier = unitSeconds[unit] else { return false }
            // Reject rather than trap on absurd values.
            let (seconds, mulOverflow) = n.multipliedReportingOverflow(by: multiplier)
            guard !mulOverflow else { return false }
            let (sum, addOverflow) = total.addingReportingOverflow(seconds)
            guard !addOverflow else { return false }
            total = sum
            number = ""
            unit = ""
            sawUnit = true
            return true
        }
        for ch in trimmed {
            if ch.isNumber || ch == " " {
                // A digit or a space ends the unit before it.
                if !unit.isEmpty, !addUnit() { return nil }
                if ch.isNumber { number.append(ch) }
            } else {
                unit.append(ch)
            }
        }
        if !unit.isEmpty, !addUnit() { return nil }
        guard number.isEmpty, sawUnit, total > 0 else { return nil }
        return TimeInterval(total)
    }
}

/// Saved by name ("days", "hours", "minutes") so config.json stays readable
/// and does not depend on the order of the cases.
extension DurationInput.Field: Codable {
    private var name: String {
        switch self {
        case .days: "days"
        case .hours: "hours"
        case .minutes: "minutes"
        }
    }

    init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let field = Self.allCases.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown field \(name)"))
        }
        self = field
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
