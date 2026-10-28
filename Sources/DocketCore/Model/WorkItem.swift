import Foundation

public enum InboxGroup: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case agents, reviews, myPRs, tickets, todos, waiting, snoozed, waitingForInput

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .agents: "Agents need me"
        case .reviews: "Reviews"
        case .myPRs: "My PRs"
        case .tickets: "Tickets"
        case .todos: "To-dos"
        case .waiting: "Waiting"
        case .snoozed: "Snoozed"
        case .waitingForInput: "Waiting for input"
        }
    }
}

/// The kind of work Start work launches. Each has its own agent, prompt and automation setting.
public enum WorkKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case review, feedback, fixCI, resolveConflict, startTicket, continueTicket

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .review: "Review"
        case .feedback: "Address feedback"
        case .fixCI: "Fix CI"
        case .resolveConflict: "Resolve conflict"
        case .startTicket: "Start ticket"
        case .continueTicket: "Continue ticket"
        }
    }
}

public enum EventKind: String, CaseIterable, Codable, Hashable, Sendable {
    case agentNeedsMe, agentResultUnread, newReview, humanFeedback, reviewBotFeedback, ciFailed, readyToMerge
}

/// What one part of an item (a PR, a ticket or a workspace) asks of me.
public struct Need: Hashable, Sendable {
    public enum Urgency: Int, Comparable, Sendable {
        case agentNeedsMe = 0, agentResult, agentWorking
        case reReview = 10, review
        case feedback = 20, conflict, ciFailed, readyToMerge
        case continueTicket = 30, closeTicket, startTicket = 39
        case waiting = 40
        /// A #docket task from TickTick that names no PR or ticket.
        case todo = 45
        /// My ticket is parked in a Linear state that waits on someone else.
        case waitingForInput = 50

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var group: InboxGroup
    public var urgency: Urgency
    public var headline: String
    /// When the wait began. Older waits rank first.
    public var since: Date
    public var kind: WorkKind?
    public var event: EventKind?
    /// The link this need is about (a PR or ticket URL).
    public var url: String?

    /// Urgency first, then the oldest wait first.
    public func ranks(before other: Need) -> Bool {
        urgency != other.urgency ? urgency < other.urgency : since < other.since
    }
}

public struct Activity: Hashable, Sendable {
    public var author: String
    public var at: Date
    public var summary: String
}

public struct WorkItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// One of my assigned tickets, which drives the item.
    public var ticket: Ticket?
    /// Someone else's ticket, named by the PR's branch. Shown for context only.
    public var contextTicket: Ticket?
    public var pullRequests: [PullRequest]
    public var workspace: Workspace?
    public var need: Need
    /// The displayed group; differs from `need.group` when the item is snoozed.
    public var group: InboxGroup
    public var lastActivity: Activity?
    /// Changes whenever relevant new activity arrives. Wakes snoozes and clears done.
    public var fingerprint: String
    /// The #docket TickTick task that names this item, or the task itself for a to-do.
    public var todo: Todo? = nil

    public var linkedTicket: Ticket? { ticket ?? contextTicket }

    public var url: String? { need.url ?? pullRequests.first?.url ?? ticket?.url }
    public var primaryPR: PullRequest? { pullRequests.first { $0.url == need.url } ?? pullRequests.first { $0.state == .open } }
}
