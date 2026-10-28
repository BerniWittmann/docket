import Foundation

public struct InboxEvent: Hashable, Sendable {
    public var kind: EventKind
    public var itemID: String
    public var title: String
    public var body: String
    /// Agent events carry their workspace for the Open in Orca action.
    public var workspaceID: String?

    /// One notification per item, event and state of activity.
    public static func key(_ item: WorkItem, _ kind: EventKind) -> String { "\(item.id)|\(kind.rawValue)|\(item.fingerprint)" }
}

public enum NotificationFilter {
    /// The events to deliver now: toggled on, inside work hours, not silenced and not sent before.
    /// Delivered keys are recorded in `state.notified`.
    public static func events(for items: [WorkItem], settings: Settings, state: inout LocalState, now: Date,
                              calendar: Calendar = .current) -> [InboxEvent] {
        guard settings.workHours.contains(now, calendar: calendar) else { return [] }
        var events: [InboxEvent] = []
        for item in items {
            guard let kind = item.need.event, settings.notifies(kind), !state.isSilenced(item, now: now) else { continue }
            guard state.notified.insert(InboxEvent.key(item, kind)).inserted else { continue }
            events.append(InboxEvent(kind: kind, itemID: item.id, title: item.need.headline, body: item.title,
                                     workspaceID: kind == .agentNeedsMe || kind == .agentResultUnread ? item.workspace?.id : nil))
        }
        return events
    }
}
