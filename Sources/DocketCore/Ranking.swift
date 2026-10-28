import Foundation

public enum Ranking {
    /// Urgency first, then the oldest wait first.
    public static func sorted(_ items: [WorkItem]) -> [WorkItem] {
        items.sorted { $0.need.ranks(before: $1.need) }
    }

    public static func grouped(_ items: [WorkItem]) -> [InboxGroup: [WorkItem]] {
        Dictionary(grouping: sorted(items), by: \.group)
    }
}
