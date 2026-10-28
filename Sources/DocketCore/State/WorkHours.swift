import Foundation

public struct WorkHours: Codable, Equatable, Sendable {
    /// Calendar weekdays: 1 is Sunday, 2 is Monday … 7 is Saturday.
    public var days: Set<Int> = [2, 3, 4, 5, 6]
    /// Minutes after midnight.
    public var start = 8 * 60
    public var end = 18 * 60

    public init() {}

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return days.contains(parts.weekday ?? 0) && minute >= start && minute < end
    }

    /// Work start on the first work day strictly after `date`'s day.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<7 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            if days.contains(calendar.component(.weekday, from: day)) || days.isEmpty { break }
        }
        return calendar.date(byAdding: .minute, value: start, to: day)!
    }
}

public enum SnoozeOption: Hashable, Sendable {
    case oneHour, tomorrow, nextWeek, until(Date)

    public static let presets: [SnoozeOption] = [.oneHour, .tomorrow, .nextWeek]

    public var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .tomorrow: "Tomorrow at work start"
        case .nextWeek: "Next week"
        case .until(let date): date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    public func date(from now: Date, hours: WorkHours, calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .tomorrow:
            let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
            return calendar.date(byAdding: .minute, value: hours.start, to: tomorrow)!
        case .nextWeek:
            let monday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
            return calendar.date(byAdding: .minute, value: hours.start, to: calendar.startOfDay(for: monday))!
        case .until(let date):
            return date
        }
    }
}
