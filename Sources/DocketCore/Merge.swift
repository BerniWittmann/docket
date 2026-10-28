import Foundation

public struct InboxInput: Sendable {
    public var viewer: String?
    public var pullRequests: [PullRequest]
    public var tickets: [Ticket]
    /// Tickets named by PR branches that are not mine.
    public var contextTickets: [Ticket]
    public var workspaces: [Workspace]
    public var bots: BotLists
    /// Open #docket tasks from TickTick.
    public var todos: [Todo] = []
    /// Today ends at the next midnight; to-dos due later count as snoozed.
    public var now = Date.now
    public var waitingStates = Settings.defaultWaitingStates

    public init(viewer: String?, pullRequests: [PullRequest], tickets: [Ticket], contextTickets: [Ticket] = [],
                workspaces: [Workspace], bots: BotLists) {
        self.viewer = viewer
        self.pullRequests = pullRequests
        self.tickets = tickets
        self.contextTickets = contextTickets
        self.workspaces = workspaces
        self.bots = bots
    }
}

public enum Merge {
    /// Merges PRs, tickets and workspaces into work items. Local state is applied later.
    public static func items(_ input: InboxInput) -> [WorkItem] {
        let viewer = input.viewer ?? ""
        var claimed = Set<String>()
        var drafts: [Draft] = []

        for ticket in input.tickets where ticket.isOpen {
            let urls = Set(ticket.attachmentURLs.map(normalize))
            let prs = input.pullRequests.filter { urls.contains(normalize($0.url)) || $0.ticketID == ticket.identifier }
            claimed.formUnion(prs.map(\.id))
            drafts.append(Draft(id: "linear:\(ticket.identifier)", ticket: ticket, contextTicket: nil, prs: prs))
        }
        for pr in input.pullRequests where !claimed.contains(pr.id) && pr.state == .open {
            claimed.insert(pr.id)
            var draft = Draft(id: "gh:\(pr.id)", ticket: nil, contextTicket: nil, prs: [pr])
            draft.contextTicket = input.contextTickets.first { $0.identifier == pr.ticketID }
            drafts.append(draft)
        }

        var unmatched: [Workspace] = []
        for workspace in input.workspaces where !workspace.isArchived {
            if let index = match(workspace, in: drafts) {
                if drafts[index].workspace.map({ AgentRules.need(for: $0, matched: true) == nil }) ?? true {
                    drafts[index].workspace = workspace
                }
            } else {
                unmatched.append(workspace)
            }
        }

        var items = drafts.compactMap { $0.item(viewer: viewer, bots: input.bots, waitingStates: input.waitingStates) }
        for workspace in unmatched {
            guard let need = AgentRules.need(for: workspace, matched: false) else { continue }
            let context = input.contextTickets.first { $0.identifier == workspace.ticketID }
            items.append(WorkItem(
                id: "orca:\(workspace.worktreeId)",
                title: context?.title ?? "\(workspace.repo) · \(workspace.shortBranch.isEmpty ? workspace.displayName : workspace.shortBranch)",
                ticket: nil, contextTicket: context,
                pullRequests: [], workspace: workspace, need: need, group: need.group,
                lastActivity: nil, fingerprint: fingerprint(workspace)
            ))
        }
        return link(input.todos, to: items, now: input.now)
    }

    /// A task joins the first item it names. Unlinked #docket tasks become to-dos of their own; other tasks are dropped.
    static func link(_ todos: [Todo], to items: [WorkItem], now: Date) -> [WorkItem] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        var items = items
        for todo in todos {
            let refs = todo.references
            if let i = items.firstIndex(where: { $0.todo == nil && !$0.references.isDisjoint(with: refs) }) {
                items[i].todo = todo
                continue
            }
            guard todo.isTagged else { continue }
            let need = Need(group: .todos, urgency: .todo, headline: "To-do", since: todo.dueDate ?? .distantFuture, url: todo.url)
            items.append(WorkItem(id: "todo:\(todo.id)", title: todo.title, ticket: nil, contextTicket: nil, pullRequests: [],
                                  workspace: nil, need: need, group: (todo.dueDate ?? now) >= tomorrow ? .snoozed : .todos, lastActivity: nil,
                                  fingerprint: "todo:\(todo.id):\(todo.dueDate?.timeIntervalSince1970 ?? 0)", todo: todo))
        }
        return items
    }

    /// A workspace attaches by linked PR, then by linked ticket, then by branch (a PR's head or its `review-<n>[-slug]` branch),
    /// then by the ticket its branch names.
    static func match(_ ws: Workspace, in drafts: [Draft]) -> Int? {
        if let number = ws.linkedPR?.number,
           let i = drafts.firstIndex(where: { $0.prs.contains { $0.number == number && $0.repoName == ws.repo } }) {
            return i
        }
        if let issue = ws.linkedLinearIssue, let i = drafts.firstIndex(where: { ($0.ticket ?? $0.contextTicket)?.identifier == issue }) {
            return i
        }
        let branch = ws.shortBranch
        guard !branch.isEmpty else { return nil }
        return drafts.firstIndex { d in
            d.prs.contains { ($0.headRef == branch || PullRequest.isReviewBranch(branch, number: $0.number)) && $0.repoName == ws.repo }
                || d.ticket?.branchName == branch
        } ?? drafts.firstIndex { d in ws.ticketID != nil && d.ticket?.identifier == ws.ticketID }
    }

    static func normalize(_ url: String) -> String {
        url.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func fingerprint(_ ws: Workspace) -> String {
        let agent = ws.mainAgent
        return "ws:\(agent?.state ?? "-"):\(agent?.stateStartedAt?.timeIntervalSince1970 ?? 0):\(ws.unread)"
    }

    struct Draft {
        var id: String
        var ticket: Ticket?
        var contextTicket: Ticket?
        var prs: [PullRequest]
        var workspace: Workspace?

        func item(viewer: String, bots: BotLists, waitingStates: [String]) -> WorkItem? {
            var needs = prs.compactMap { GitHubRules.need(for: $0, viewer: viewer, bots: bots) }
            if let ticket, let need = LinearRules.need(for: ticket, attached: prs, waitingStates: waitingStates) { needs.append(need) }
            if let workspace, let need = AgentRules.need(for: workspace, matched: true) {
                needs.append(Need(group: need.group, urgency: need.urgency, headline: need.headline, since: need.since,
                                  kind: need.kind, event: need.event, url: prs.first(where: { $0.state == .open })?.url ?? ticket?.url))
            }
            if needs.isEmpty, let ticket { needs.append(LinearRules.fallback(for: ticket, waitingStates: waitingStates)) }
            guard let need = needs.min(by: { $0.ranks(before: $1) }) else { return nil }

            let activity = prs.compactMap { GitHubRules.latestActivity($0, bots: bots) }.max { $0.at < $1.at }
            var parts = prs.map { "\($0.id):\(GitHubRules.latestActivity($0, bots: bots)?.at.timeIntervalSince1970 ?? 0):\($0.state.rawValue)" }
            if let ticket { parts.append("\(ticket.identifier):\(ticket.state.type)") }
            if let workspace { parts.append(Merge.fingerprint(workspace)) }
            return WorkItem(
                id: id, title: ticket?.title ?? prs.first?.title ?? id, ticket: ticket, contextTicket: contextTicket, pullRequests: prs,
                workspace: workspace, need: need, group: need.group, lastActivity: activity,
                fingerprint: ([need.headline] + parts).joined(separator: "|")
            )
        }
    }
}
