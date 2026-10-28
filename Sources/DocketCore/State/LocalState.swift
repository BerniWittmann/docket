import Foundation

public struct LocalState: Codable, Equatable, Sendable {
    public enum Mark: Codable, Equatable, Sendable {
        case snoozed(until: Date), done, notMine
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var mark: Mark
        /// The item's fingerprint when it was marked. New activity changes it.
        public var fingerprint: String
    }

    public var marks: [String: Entry] = [:]
    /// De-duplication keys of sent notifications.
    public var notified: Set<String> = []
    /// Items whose worktree Prepare already created.
    public var prepared: Set<String> = []
    /// The TickTick task each item is mirrored to.
    public var tickTick: [String: SyncedTask] = [:]

    public init() {}

    public func snoozedUntil(_ itemID: String) -> Date? {
        if case .snoozed(let until)? = marks[itemID]?.mark { until } else { nil }
    }

    public mutating func mark(_ item: WorkItem, _ mark: Mark) {
        marks[item.id] = Entry(mark: mark, fingerprint: item.fingerprint)
    }

    /// Hides done and not-mine items, moves snoozed ones to Snoozed, and drops marks that
    /// new activity or an expired snooze ended.
    public mutating func apply(to items: [WorkItem], now: Date = .now) -> [WorkItem] {
        items.compactMap { item in
            guard let entry = marks[item.id] else { return item }
            let fresh = entry.fingerprint == item.fingerprint
            switch entry.mark {
            case .notMine:
                return nil
            case .done where fresh:
                return nil
            case .snoozed(let until) where fresh && until > now:
                var snoozed = item
                snoozed.group = .snoozed
                return snoozed
            default:
                marks[item.id] = nil
                return item
            }
        }
    }

    /// Snoozed, done and not-mine items stay silent.
    public func isSilenced(_ item: WorkItem, now: Date = .now) -> Bool {
        guard let entry = marks[item.id] else { return false }
        switch entry.mark {
        case .notMine: return true
        case .done: return entry.fingerprint == item.fingerprint
        case .snoozed(let until): return entry.fingerprint == item.fingerprint && until > now
        }
    }
}

public struct SyncedTask: Codable, Equatable, Sendable {
    public var taskID: String
    public var listID: String
    /// The due day Docket last set, or nil once Docket completed the task.
    public var due: Date?
    /// The title Docket last set. Docket renames its own tasks when the action changes.
    public var title: String?
    /// The user made this task; Docket moves its date but keeps its title.
    public var adopted: Bool?
}
