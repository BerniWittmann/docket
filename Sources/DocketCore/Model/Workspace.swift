import Foundation

public struct AgentStatus: Hashable, Sendable, Decodable {
    /// Orca agent state: working, blocked, waiting, permission, done, idle, ...
    public var state: String
    /// `<tabId>:<leafId>` of the agent's terminal pane.
    public var paneKey: String?
    public var agentType: String?
    public var lastAssistantMessage: String?
    public var stateStartedAt: Date?
    public var updatedAt: Date?

    public var needsMe: Bool { ["blocked", "waiting", "permission", "awaiting"].contains(state) }
}

public struct Workspace: Hashable, Sendable, Identifiable, Decodable {
    public struct LinkedPR: Hashable, Sendable, Decodable { public var number: Int }

    public var worktreeId: String
    public var repo: String
    public var path: String
    public var branch: String
    public var displayName: String
    public var unread: Bool
    public var isArchived: Bool
    public var linkedPR: LinkedPR?
    public var linkedLinearIssue: String?
    public var lastActivityAt: Date?
    public var agents: [AgentStatus]

    public var id: String { worktreeId }
    public var shortBranch: String {
        branch.hasPrefix("refs/heads/") ? String(branch.dropFirst("refs/heads/".count)) : branch
    }
    /// The Linear ticket this workspace's branch names, by the `node-1234-slug` convention.
    public var ticketID: String? { PullRequest.ticketID(branch: shortBranch) }

    /// The most relevant agent: one that needs me, else the most recently updated.
    public var mainAgent: AgentStatus? {
        agents.first(where: \.needsMe)
            ?? agents.max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
    }

    private enum Keys: String, CodingKey {
        case worktreeId, repo, path, branch, displayName, unread, isArchived, linkedPR, linkedLinearIssue, lastActivityAt, agents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        worktreeId = try c.decode(String.self, forKey: .worktreeId)
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        branch = try c.decodeIfPresent(String.self, forKey: .branch) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        unread = try c.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        linkedPR = try? c.decodeIfPresent(LinkedPR.self, forKey: .linkedPR)
        linkedLinearIssue = try? c.decodeIfPresent(String.self, forKey: .linkedLinearIssue)
        lastActivityAt = try? c.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        agents = (try? c.decodeIfPresent([AgentStatus].self, forKey: .agents)) ?? []
    }
}
