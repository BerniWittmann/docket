import Testing
import Foundation
@testable import DocketCore

/// A second real recording, taken after a re-requested reviewer asked a question on #40322 and I replied,
/// while an agent waited for input in an unmatched workspace.
private let inbox = try! GitHubInbox.decode(Fixtures.data("github-inbox-later"))
private let workspaces = try! OrcaHarness.decodeWorkspaces(Fixtures.data("orca-ps-later"))
private let items = Merge.items(InboxInput(viewer: inbox.viewer, pullRequests: inbox.pullRequests,
                                           tickets: Fixtures.tickets, workspaces: workspaces, bots: .defaults))
private func item(_ id: String) -> WorkItem? { items.first { $0.id == id } }

@Suite("Later real snapshot")
struct LaterSnapshotTests {
    @Test("fact 12–13: a re-requested reviewer's question needs me until I reply")
    func questionThenReply() {
        let replied = item("linear:NODE-5998")
        #expect(replied?.group == .waiting, "I replied after the question")
        #expect(replied?.need.headline == "Re-review requested from @user-2")
        #expect(replied?.workspace?.linkedPR?.number == 40322)

        var pr = inbox.pullRequests.first { $0.number == 40322 }!
        pr.events.removeLast()
        let asked = GitHubRules.need(for: pr, viewer: inbox.viewer, bots: .defaults)
        #expect(asked?.headline == "Address feedback")
        #expect(asked?.event == .humanFeedback)
    }

    @Test("fact 24 + 26: a waiting agent in an unmatched workspace is in Agents need me")
    func waitingAgent() {
        let docket = items.first { $0.workspace?.repo == "Docket" }
        #expect(docket?.group == .agents)
        #expect(docket?.need.headline == "Agent waiting")
        #expect(docket?.need.event == .agentNeedsMe)
        #expect(docket?.title == "Docket · main")
    }

    @Test("idle and done-and-read workspaces add nothing on their own")
    func idle() {
        let shown = Set(items.compactMap { $0.workspace?.id })
        for workspace in workspaces where !workspace.unread && !workspace.agents.contains(where: { $0.needsMe || $0.state == "working" }) {
            #expect(!items.contains { $0.id == "orca:\(workspace.worktreeId)" }, "\(workspace.shortBranch)")
        }
        #expect(!shown.isEmpty)
    }

    @Test("fact 19: the real Linear recording decodes my open tickets")
    func linear() throws {
        let linear = try LinearSource.decodeIssues(Fixtures.data("linear-issues"))
        #expect(linear.viewerName == "Viewer")
        #expect(linear.tickets.map(\.identifier).sorted() == ["DOC-2049", "DOC-2359", "NODE-5750", "NODE-5980", "NODE-5998", "NODE-6114"])
        #expect(linear.tickets.allSatisfy { $0.isOpen })
    }
}
