import Foundation

/// What Start work needs to find or create a workspace.
public struct WorkRef: Hashable, Sendable {
    /// `owner/repo` the work happens in.
    public var repo: String
    public var prNumber: Int?
    /// The branch to work on: a PR's head branch or a ticket's branch name.
    public var branch: String?
    public var ticket: String?
    /// Whether the PR is someone else's, which gets a `review-<n>-<slug>` worktree.
    public var isReview: Bool

    public init(repo: String, prNumber: Int? = nil, branch: String? = nil, ticket: String? = nil, isReview: Bool = false) {
        self.repo = repo
        self.prNumber = prNumber
        self.branch = branch
        self.ticket = ticket
        self.isReview = isReview
    }

    /// The ref for an item's work, or nil when there is nothing to check out.
    public init?(item: WorkItem, viewer: String?, ticketRepo: String) {
        if let pr = item.primaryPR {
            let isReview = pr.author?.login != viewer
            self.init(repo: pr.repo, prNumber: pr.number, branch: isReview ? pr.reviewBranch : pr.headRef,
                      ticket: item.linkedTicket?.identifier, isReview: isReview)
        } else if let ticket = item.ticket {
            self.init(repo: ticketRepo, branch: ticket.branchName, ticket: ticket.identifier)
        } else {
            return nil
        }
    }

    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// Linked PR first, then linked ticket, then branch.
    public func find(in workspaces: [Workspace]) -> Workspace? {
        let live = workspaces.filter { !$0.isArchived }
        if let prNumber, let ws = live.first(where: { $0.linkedPR?.number == prNumber && $0.repo == repoName }) { return ws }
        if let ticket, let ws = live.first(where: { $0.linkedLinearIssue == ticket }) { return ws }
        if let branch, !branch.isEmpty, let ws = live.first(where: { $0.shortBranch == branch && $0.repo == repoName }) { return ws }
        if isReview, let prNumber,
           let ws = live.first(where: { PullRequest.isReviewBranch($0.shortBranch, number: prNumber) && $0.repo == repoName }) { return ws }
        return nil
    }
}

/// Where agents run. v1 ships only Orca.
public protocol Harness: Sendable {
    func listWorkspaces() async throws -> [Workspace]
    func findWorkspace(for ref: WorkRef) async throws -> Workspace?
    /// Reuses the ref's workspace or creates one, then starts `agent` with `prompt`.
    /// A nil agent prepares the workspace only. A nil prompt on an existing workspace just opens it.
    func startWork(_ ref: WorkRef, agent: String?, prompt: String?) async throws
    func open(_ workspace: Workspace) async throws
}

/// What Start work does with a workspace. The harness acts on it and the UI describes it.
public enum WorkPlan: Equatable, Sendable {
    /// No workspace yet: create one and start the agent there.
    case create
    /// Bring the workspace to the front without a new prompt.
    case open
    /// Type the prompt into the idle agent session in this pane, keeping its context.
    case send(paneKey: String)
    /// Start a new agent session in the workspace.
    case newTerminal
    /// Prepare on an existing workspace: nothing to do.
    case nothing

    public init(workspace: Workspace?, agent: String?, prompt: String?) {
        guard let workspace else { self = .create; return }
        guard let agent else { self = .nothing; return }
        if prompt == nil || workspace.agents.contains(where: { !["done", "idle"].contains($0.state) }) {
            self = .open
        } else if let session = workspace.agents.last(where: { $0.agentType == agent && $0.paneKey != nil }) {
            self = .send(paneKey: session.paneKey!)
        } else {
            self = .newTerminal
        }
    }
}
