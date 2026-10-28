import Foundation

/// Mirrors the items that need me into TickTick.
///
/// | Item now              | Task                     |
/// |-----------------------|--------------------------|
/// | needs me              | open, due today          |
/// | snoozed               | open, due the snooze day |
/// | waiting, done or gone | completed                |
///
/// Only transitions write: a task the user completes or re-dates in TickTick stays so until the item changes.
public enum TickTickSync {
    public enum Op: Equatable, Sendable {
        case create(itemID: String, title: String, content: String, due: Date)
        /// Takes over a #docket task the user made for this item.
        case adopt(itemID: String, task: SyncedTask)
        /// Sets the due date (reopening the task) and, for tasks Docket made, the title.
        case setDue(itemID: String, task: SyncedTask, due: Date, title: String? = nil)
        case complete(itemID: String, task: SyncedTask)

        public var itemID: String {
            switch self {
            case .create(let id, _, _, _), .adopt(let id, _), .setDue(let id, _, _, _), .complete(let id, _): id
            }
        }
    }

    static let resting: Set<InboxGroup> = [.waiting, .waitingForInput]

    public static func operations(items: [WorkItem], state: LocalState, now: Date, calendar: Calendar = .current) -> [Op] {
        let today = calendar.startOfDay(for: now)
        var ops: [Op] = []
        var seen = Set<String>()
        for item in items where !item.id.hasPrefix("orca:") && !item.id.hasPrefix("todo:") {
            seen.insert(item.id)
            let stored = state.tickTick[item.id]
            let due: Date? = if item.group == .snoozed {
                state.snoozedUntil(item.id).map { calendar.startOfDay(for: $0) }
            } else if resting.contains(item.group) {
                nil
            } else {
                // Keeps an overdue date, but pulls a snooze date forward when activity wakes the item early.
                stored?.due.map { min($0, today) } ?? today
            }
            switch (stored, due) {
            case (nil, let due?):
                if let todo = item.todo {
                    let task = SyncedTask(taskID: todo.id, listID: todo.projectId, due: todo.dueDate.map { calendar.startOfDay(for: $0) }, adopted: true)
                    ops.append(.adopt(itemID: item.id, task: task))
                    if item.group == .snoozed || todo.dueDate == nil { ops.append(.setDue(itemID: item.id, task: task, due: due)) }
                } else {
                    let urls = item.pullRequests.map(\.url) + [item.linkedTicket?.url].compactMap { $0 }
                    ops.append(.create(itemID: item.id, title: title(item), content: urls.joined(separator: "\n"), due: due))
                }
            case (let task?, let due?) where task.due != due || (task.adopted != true && task.title != title(item)):
                ops.append(.setDue(itemID: item.id, task: task, due: due, title: task.adopted == true ? nil : title(item)))
            case (let task?, nil) where task.due != nil:
                ops.append(.complete(itemID: item.id, task: task))
            default:
                break
            }
        }
        for (id, task) in state.tickTick.sorted(by: { $0.key < $1.key }) where !seen.contains(id) && task.due != nil {
            ops.append(.complete(itemID: id, task: task))
        }
        return ops
    }

    /// The action first, then the title without its conventional-commit prefix: "Address feedback: Set up Microsoft Teams again".
    public static func title(_ item: WorkItem) -> String {
        let name = item.title
            .replacing(/^\w+(\([^)]*\))?!?:\s*/, with: "")
            .replacing(/\s*\(no-changelog\)\s*$/.ignoresCase(), with: "")
        return "\(item.need.headline): \(name)"
    }

    /// Forgets completed tasks of items that are gone for good. Done items keep theirs, to reopen on new activity.
    public static func prune(_ state: inout LocalState, items: [WorkItem]) {
        let present = Set(items.map(\.id))
        state.tickTick = state.tickTick.filter { present.contains($0.key) || $0.value.due != nil || state.marks[$0.key] != nil }
    }
}
