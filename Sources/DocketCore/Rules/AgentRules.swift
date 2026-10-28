import Foundation

public enum AgentRules {
    /// - Parameter matched: whether the workspace belongs to a ticket or PR item.
    ///   Unmatched workspaces also show while their agent is working.
    public static func need(for workspace: Workspace, matched: Bool) -> Need? {
        if let agent = workspace.agents.first(where: \.needsMe) {
            return Need(group: .agents, urgency: .agentNeedsMe, headline: "Agent \(agent.state)",
                        since: agent.stateStartedAt ?? workspace.lastActivityAt ?? .now, event: .agentNeedsMe)
        }
        let working = workspace.agents.first { $0.state == "working" }
        if workspace.unread && working == nil {
            return Need(group: .agents, urgency: .agentResult, headline: "Check agent result",
                        since: workspace.mainAgent?.stateStartedAt ?? workspace.lastActivityAt ?? .now, event: .agentResultUnread)
        }
        if !matched, let working {
            return Need(group: .agents, urgency: .agentWorking, headline: "Agent working",
                        since: working.stateStartedAt ?? workspace.lastActivityAt ?? .now)
        }
        return nil
    }
}
