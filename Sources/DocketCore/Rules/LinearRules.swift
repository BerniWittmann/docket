import Foundation

public enum LinearRules {
    /// The ticket's own need, given the PRs attached to it. Nil when an open PR drives the item.
    public static func need(for ticket: Ticket, attached: [PullRequest], waitingStates: [String] = Settings.defaultWaitingStates) -> Need? {
        guard ticket.isOpen else { return nil }
        if !attached.isEmpty {
            guard !attached.contains(where: { $0.state == .open }) else { return nil }
            if attached.contains(where: { $0.state == .merged }) {
                return Need(group: .tickets, urgency: .closeTicket, headline: "Close \(ticket.identifier)",
                            since: ticket.updatedAt, url: ticket.url)
            }
        }
        return fallback(for: ticket, waitingStates: waitingStates)
    }

    /// Start a Todo ticket, continue a started one, or park it while its state waits on someone else.
    public static func fallback(for ticket: Ticket, waitingStates: [String] = Settings.defaultWaitingStates) -> Need {
        if waitingStates.contains(where: { $0.caseInsensitiveCompare(ticket.state.name) == .orderedSame }) {
            return Need(group: .waitingForInput, urgency: .waitingForInput, headline: ticket.state.name,
                        since: ticket.updatedAt, url: ticket.url)
        }
        return ticket.state.type == "unstarted"
            ? Need(group: .tickets, urgency: .startTicket, headline: "Start \(ticket.identifier)",
                   since: ticket.updatedAt, kind: .startTicket, url: ticket.url)
            : Need(group: .tickets, urgency: .continueTicket, headline: "Continue \(ticket.identifier)",
                   since: ticket.updatedAt, kind: .continueTicket, url: ticket.url)
    }
}
