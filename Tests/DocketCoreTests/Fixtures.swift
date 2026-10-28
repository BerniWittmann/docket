import Foundation
@testable import DocketCore

enum Fixtures {
    static let viewer = "BerniWittmann"

    static func data(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    static var github: GitHubInbox { try! GitHubInbox.decode(data("github-inbox")) }
    static var pullRequests: [PullRequest] { github.pullRequests }
    static var tickets: [Ticket] { try! LinearSource.decodeIssues(data("linear-issues")).tickets }
    static var workspaces: [Workspace] { try! OrcaHarness.decodeWorkspaces(data("orca-ps")) }

    static func pr(_ number: Int) -> PullRequest { pullRequests.first { $0.number == number }! }
    /// 40697 with cubic's unresolved threads newer than my last push.
    static var botFeedbackPR: PullRequest {
        var pr = pr(40697)
        let after = (pr.events.map(\.at) + [pr.updatedAt]).max()!.addingTimeInterval(60)
        pr.threads = pr.threads.map { var t = $0; t.lastAt = after; return t }
        return pr
    }
    static func ticket(_ id: String) -> Ticket { tickets.first { $0.identifier == id }! }
    static func workspace(branch: String) -> Workspace { workspaces.first { $0.shortBranch == branch }! }

    static func input(prs: [PullRequest]? = nil, tickets: [Ticket]? = nil, workspaces: [Workspace]? = nil) -> InboxInput {
        InboxInput(viewer: viewer, pullRequests: prs ?? pullRequests, tickets: tickets ?? self.tickets,
                   workspaces: workspaces ?? self.workspaces, bots: .defaults)
    }
}

extension Date {
    static func iso(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }
}
