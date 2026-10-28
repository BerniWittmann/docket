import Foundation

public enum ThemeName: String, Codable, CaseIterable, Sendable, Identifiable {
    case nord, n8n
    public var id: String { rawValue }
    public var title: String { self == .nord ? "Nord" : "n8n" }
}

public enum Automation: String, Codable, CaseIterable, Sendable, Identifiable {
    case manual, prepare
    public var id: String { rawValue }
    public var title: String { self == .manual ? "Manual" : "Prepare" }
}

public struct WorkSetting: Codable, Equatable, Sendable {
    public var agent: String
    public var prompt: String
    public var automation: Automation

    public init(agent: String = "claude", prompt: String, automation: Automation = .manual) {
        self.agent = agent
        self.prompt = prompt
        self.automation = automation
    }
}

public struct Settings: Codable, Equatable, Sendable {
    /// `owner/*` watches a whole org, `owner/repo` a single repo.
    public var repos = ["n8n-io/*"]
    public var bots = BotLists.defaults
    public var workHours = WorkHours()
    public var notifications: [String: Bool] = Settings.defaultNotifications
    public var work: [String: WorkSetting] = Settings.defaultWork
    /// Linear states that wait on someone else. Tickets in them go to Waiting for input.
    public var waitingStates = Settings.defaultWaitingStates
    /// The repo a ticket's worktree is created in when no PR tells otherwise.
    public var ticketRepo = "n8n-io/n8n"
    /// The TickTick list mirrored tasks go into. Nothing is created until one is picked.
    public var tickTickListID: String?
    public var theme = ThemeName.nord
    public var orcaPath: String?
    public var launchAtLogin = false
    public var onboarded = false

    public init() {}

    public static let defaultWaitingStates = ["Waiting for input"]

    public static let defaultNotifications: [String: Bool] = [
        EventKind.agentNeedsMe.rawValue: true,
        EventKind.agentResultUnread.rawValue: true,
        EventKind.newReview.rawValue: true,
        EventKind.humanFeedback.rawValue: true,
        EventKind.reviewBotFeedback.rawValue: true,
        EventKind.ciFailed.rawValue: false,
        EventKind.readyToMerge.rawValue: false,
    ]

    public static let defaultWork: [String: WorkSetting] = [
        WorkKind.review.rawValue: WorkSetting(prompt: "/pr-review {url}"),
        WorkKind.feedback.rawValue: WorkSetting(prompt: "/pr-review-feedback {url}"),
        WorkKind.fixCI.rawValue: WorkSetting(prompt: "/pr-review-feedback {url}"),
        WorkKind.resolveConflict.rawValue: WorkSetting(prompt: "/pr-review-feedback {url}"),
        WorkKind.startTicket.rawValue: WorkSetting(prompt: "/fix-ticket {ticket}"),
        WorkKind.continueTicket.rawValue: WorkSetting(prompt: "Continue {ticket}: check the branch and the ticket, then propose the next step"),
    ]

    public func notifies(_ event: EventKind) -> Bool {
        notifications[event.rawValue] ?? Self.defaultNotifications[event.rawValue] ?? false
    }

    public func work(_ kind: WorkKind) -> WorkSetting {
        work[kind.rawValue] ?? Self.defaultWork[kind.rawValue]!
    }

    /// The GitHub search qualifiers for the watched repos and orgs.
    public var searchScope: String {
        repos.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { repo in
            repo.hasSuffix("/*") || !repo.contains("/") ? "org:\(repo.replacingOccurrences(of: "/*", with: ""))" : "repo:\(repo)"
        }.joined(separator: " ")
    }
}
