import Testing
import Foundation
@testable import DocketCore

private func items(prs: [PullRequest]? = nil, tickets: [Ticket]? = nil, workspaces: [Workspace]? = nil) -> [WorkItem] {
    Merge.items(Fixtures.input(prs: prs, tickets: tickets, workspaces: workspaces))
}
private func item(_ id: String, in list: [WorkItem]) -> WorkItem? { list.first { $0.id == id } }

@Suite("Linear rules and merging")
struct MergeTests {
    @Test("fact 19: open tickets show; Todo ranks last; backlog, done and canceled are hidden")
    func tickets() {
        let all = items()
        let tickets = Ranking.grouped(all)[.tickets] ?? []
        #expect(tickets.last?.id == "linear:DOC-2049")
        #expect(tickets.last?.need.headline == "Start DOC-2049")

        for type in ["backlog", "completed", "canceled", "triage"] {
            var ticket = Fixtures.ticket("DOC-2049")
            ticket.state.type = type
            #expect(item("linear:DOC-2049", in: items(tickets: [ticket])) == nil, "\(type) should be hidden")
        }
    }

    @Test("fact 20: a ticket and its attached PRs are one item in the group of the most urgent part")
    func ticketOwnsPRs() {
        let all = items()
        let teams = item("linear:NODE-5980", in: all)
        #expect(Set(teams?.pullRequests.map(\.number) ?? []) == [40696, 40697])
        #expect(teams?.group == .myPRs)
        #expect(teams?.need.headline == "Fix CI")
        #expect(item("gh:n8n-io/n8n#40697", in: all) == nil)
        #expect(item("gh:n8n-io/n8n#40696", in: all) == nil)

        #expect(item("linear:NODE-6114", in: all)?.group == .waiting)
        #expect(item("linear:NODE-5998", in: all)?.need.headline == "Re-review requested from @user-2")
    }

    @Test("fact 21: a ticket without a PR shows Start (Todo) or Continue (started)")
    func startContinue() {
        #expect(item("linear:DOC-2049", in: items())?.need.headline == "Start DOC-2049")
        #expect(item("linear:DOC-2049", in: items())?.need.kind == .startTicket)

        var ticket = Fixtures.ticket("NODE-5980")
        ticket.attachmentURLs = []
        let continued = item("linear:NODE-5980", in: items(prs: Fixtures.pullRequests.filter { $0.ticketID != "NODE-5980" }, tickets: [ticket], workspaces: []))
        #expect(continued?.need.headline == "Continue NODE-5980")
        #expect(continued?.need.kind == .continueTicket)
        #expect(continued?.group == .tickets)
    }

    @Test("a ticket waiting for input goes to Waiting for input when nothing else needs me")
    func waitingForInput() {
        let parked = item("linear:NODE-5750", in: items())
        #expect(parked?.group == .waitingForInput)
        #expect(parked?.need.headline == "Waiting for input")
        #expect(parked?.need.kind == nil)
        #expect(parked?.pullRequests.map(\.number) == [36223])

        var pr = Fixtures.pr(36223)
        pr.requestedReviewers.append(Fixtures.viewer)
        let review = item("linear:NODE-5750", in: items(prs: Fixtures.pullRequests.filter { $0.number != 36223 } + [pr]))
        #expect(review?.group == .reviews, "a review request on its PR comes first")
        #expect(review?.need.headline == "Re-review #36223")
    }

    @Test("waiting-for-input states are configurable")
    func waitingStates() {
        var input = Fixtures.input()
        input.waitingStates = ["Blocked externally"]
        #expect(Merge.items(input).first { $0.id == "linear:NODE-5750" }?.need.headline == "Continue NODE-5750")
        var ticket = Fixtures.ticket("NODE-5980")
        ticket.state.name = "blocked EXTERNALLY"
        input.tickets = [ticket]
        input.pullRequests = []
        #expect(Merge.items(input).first?.group == .waitingForInput)
    }

    @Test("fact 22: a ticket whose PR merged while it is open shows Close with the ticket link")
    func close() {
        var pr = Fixtures.pr(40322)
        pr.state = .merged
        let prs = Fixtures.pullRequests.filter { $0.number != 40322 } + [pr]
        let close = item("linear:NODE-5998", in: items(prs: prs, workspaces: []))
        #expect(close?.need.headline == "Close NODE-5998")
        #expect(close?.group == .tickets)
        #expect(close?.need.kind == nil, "no Start work and no Linear write")
        #expect(close?.url == Fixtures.ticket("NODE-5998").url)
    }

    @Test("fact 24: a blocked or waiting agent puts its item in Agents need me")
    func agentNeedsMe() {
        for state in ["blocked", "waiting", "permission"] {
            var ws = Fixtures.workspace(branch: "node-6114-ms-teams-show-upload-instructions-when-the-app-package-is")
            ws.agents = [AgentStatus(state: state, stateStartedAt: .iso("2026-10-09T09:00:00Z"))]
            let agentItem = item("linear:NODE-6114", in: items(workspaces: [ws]))
            #expect(agentItem?.group == .agents)
            #expect(agentItem?.need.event == .agentNeedsMe)
            #expect(agentItem?.workspace?.id == ws.id)
            #expect(agentItem?.url == Fixtures.pr(40339).url)
        }
    }

    @Test("fact 25: a finished agent with an unread result → Check agent result")
    func agentResult() {
        var ws = Fixtures.workspace(branch: "node-6037")
        ws.unread = true
        #expect(item("gh:n8n-io/n8n#39878", in: items(workspaces: [ws]))?.need.headline == "Check agent result")

        var done = Fixtures.workspace(branch: "node-5998-ms-teams-use-icon-from-agent-in-manifest")
        done.agents = [AgentStatus(state: "done")]
        done.unread = true
        let checked = item("linear:NODE-5998", in: items(workspaces: [done]))
        #expect(checked?.need.headline == "Check agent result")
        #expect(checked?.group == .agents)
    }

    @Test("fact 26: an unmatched workspace with a working agent or unread result shows, labelled repo · branch")
    func unmatched() {
        let all = items()
        let docket = all.first { $0.id.hasPrefix("orca:") && $0.workspace?.repo == "Docket" }
        #expect(docket?.group == .agents)

        var ws = Fixtures.workspace(branch: "automation-mining")
        #expect(items(workspaces: [ws]).allSatisfy { !$0.id.hasPrefix("orca:") }, "a done, read agent is idle")
        ws.unread = true
        let shown = items(workspaces: [ws]).first { $0.id.hasPrefix("orca:") }
        #expect(shown?.title == "n8n · automation-mining")
        #expect(shown?.need.headline == "Check agent result")
    }

    @Test("workspaces attach by linked PR, then linked ticket, then branch")
    func matchingOrder() {
        var byPR = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        byPR.linkedPR = .init(number: 40339)
        #expect(item("linear:NODE-6114", in: items(workspaces: [byPR]))?.workspace?.id == byPR.id)

        var byTicket = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        byTicket.linkedLinearIssue = "DOC-2049"
        #expect(item("linear:DOC-2049", in: items(workspaces: [byTicket]))?.workspace?.id == byTicket.id)

        var byBranch = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        byBranch.branch = "refs/heads/doc-2049-docs-for-community-issue-mcp-webhook-queue-mode"
        #expect(item("linear:DOC-2049", in: items(workspaces: [byBranch]))?.workspace?.id == byBranch.id)

        #expect(item("linear:NODE-5980", in: items())?.workspace?.linkedLinearIssue == "NODE-5980")

        var review = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        review.branch = "refs/heads/review-39679"
        #expect(item("gh:n8n-io/n8n#39679", in: items(workspaces: [review]))?.workspace?.id == review.id, "a review worktree without its PR link")
    }

    @Test("fact 4: urgency first, then the oldest wait first")
    func ranking() {
        let grouped = Ranking.grouped(items())
        #expect(grouped[.reviews]?.map(\.need.headline) == ["Review #39679", "Review #39409"])
        for list in grouped.values {
            for (a, b) in zip(list, list.dropFirst()) {
                #expect(a.need.urgency < b.need.urgency || (a.need.urgency == b.need.urgency && a.need.since <= b.need.since))
            }
        }
    }

    @Test("the fingerprint changes with new relevant activity only")
    func fingerprint() {
        let before = item("linear:NODE-6114", in: items())!.fingerprint
        var pr = Fixtures.pr(40339)
        pr.events.append(PREvent(kind: .comment, actor: Person(login: "codecov", isBot: true), at: .iso("2026-10-09T10:00:00Z")))
        let prs = Fixtures.pullRequests.filter { $0.number != 40339 } + [pr]
        #expect(item("linear:NODE-6114", in: items(prs: prs))!.fingerprint == before)

        pr.events.append(PREvent(kind: .commit, actor: nil, at: .iso("2026-10-09T11:00:00Z")))
        #expect(item("linear:NODE-6114", in: items(prs: Fixtures.pullRequests.filter { $0.number != 40339 } + [pr]))!.fingerprint != before)
    }
}
