import Testing
import Foundation
@testable import DocketCore

/// A ticket from someone else's team, decoded like a Linear lookup result.
private func otherTicket(_ id: String, state: String = "In Review", assignee: String = "Someone") -> Ticket {
    let json = #"{"identifier":"\#(id)","title":"Their ticket","url":"https://linear.app/n8n/issue/\#(id)","branchName":"x","updatedAt":"2026-10-09T10:00:00Z","state":{"name":"\#(state)","type":"started"},"assignee":{"name":"\#(assignee)"}}"#
    return try! DocketJSON.decoder().decode(Ticket.self, from: Data(json.utf8))
}

@Suite("Linear context from branch names")
struct TicketContextTests {
    @Test("ticket IDs come from the branch's leading slug, else from the title")
    func parsing() {
        #expect(PullRequest.ticketID(branch: "node-5973-handle-inbound-media-handling") == "NODE-5973")
        #expect(PullRequest.ticketID(branch: "node-6037") == "NODE-6037")
        #expect(PullRequest.ticketID(branch: "BerniWittmann/doc-2359-document-browser") == "DOC-2359")
        #expect(PullRequest.ticketID(branch: "ops-247-limit-upload-size") == "OPS-247")
        for branch in ["review-39409", "cat-bot/run-36304979416-1", "fix/erpnext-node-create-update", "hackweek/n8nable-app-version", "main"] {
            #expect(PullRequest.ticketID(branch: branch) == nil, "\(branch)")
        }
        #expect(PullRequest.ticketID(title: "docs: Add Browser Use page for n8n Assistant (DOC-2359)") == "DOC-2359")
        #expect(PullRequest.ticketID(title: "fix(Linear Node): Add v2") == nil)
        #expect(Fixtures.pr(39409).ticketID == "NODE-5973")
    }

    @Test("someone else's PR shows the ticket its branch names, for context only")
    func contextTicket() {
        let input = InboxInput(viewer: Fixtures.viewer, pullRequests: Fixtures.pullRequests, tickets: Fixtures.tickets,
                               contextTickets: [otherTicket("NODE-5973")], workspaces: [], bots: .defaults)
        let review = Merge.items(input).first { $0.id == "gh:n8n-io/n8n#39409" }
        #expect(review?.contextTicket?.identifier == "NODE-5973")
        #expect(review?.contextTicket?.assignee == "Someone")
        #expect(review?.ticket == nil, "not my ticket, so it does not drive the item")
        #expect(review?.group == .reviews)
        #expect(PromptTemplate.fill("{ticket}", item: review!) == "NODE-5973")
    }

    @Test("my ticket also claims PRs whose branch names it, without a Linear attachment")
    func claimsByBranch() {
        var ticket = Fixtures.ticket("NODE-6114")
        ticket.attachmentURLs = []
        let items = Merge.items(Fixtures.input(tickets: [ticket], workspaces: []))
        #expect(items.first { $0.id == "linear:NODE-6114" }?.pullRequests.map(\.number) == [40339])
        #expect(!items.contains { $0.id == "gh:n8n-io/n8n#40339" })
    }

    @Test("workspaces join my ticket by the ID in their branch; others get it as context")
    func workspaces() {
        var mine = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        mine.branch = "refs/heads/doc-2049-a-different-slug"
        mine.agents = [AgentStatus(state: "waiting")]
        #expect(Merge.items(Fixtures.input(workspaces: [mine])).first { $0.id == "linear:DOC-2049" }?.workspace?.id == mine.id)

        var other = mine
        other.branch = "refs/heads/node-6142-ms-teams-handle-incoming-files"
        let input = InboxInput(viewer: Fixtures.viewer, pullRequests: [], tickets: [], contextTickets: [otherTicket("NODE-6142")],
                               workspaces: [other], bots: .defaults)
        let item = Merge.items(input).first
        #expect(item?.id.hasPrefix("orca:") == true)
        #expect(item?.contextTicket?.identifier == "NODE-6142")
        #expect(item?.title == "Their ticket")
    }

    @Test("the lookup asks for each identifier and skips unknown ones")
    func lookup() throws {
        let query = LinearSource.lookupQuery(["NODE-5973", "OPS-247"])
        #expect(query.contains(#"t0: issue(id: "NODE-5973")"#))
        #expect(query.contains(#"t1: issue(id: "OPS-247")"#))
        #expect(!query.contains("mutation"))

        let response = #"{"data":{"t0":{"identifier":"NODE-5973","title":"T","url":"u","branchName":"b","updatedAt":"2026-10-09T10:00:00.000Z","state":{"name":"Todo","type":"unstarted"},"assignee":null},"t1":null},"errors":[{"message":"Entity not found: Issue"}]}"#
        let tickets = try LinearSource.decodeLookup(Data(response.utf8))
        #expect(tickets.map(\.identifier) == ["NODE-5973"])
        #expect(tickets.first?.assignee == nil)
    }

    @MainActor
    @Test("the engine looks up branch tickets after GitHub and attaches them")
    func engine() async {
        let engine = InboxEngine(
            store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
            github: FakeGitHub(), linear: FakeLinear(known: [otherTicket("NODE-5973"), otherTicket("NODE-6037")]),
            linearKey: { "k" }, tickTickKey: { nil }, harness: FakeHarness(), now: { .iso("2026-10-09T10:00:00Z") })
        await engine.refreshAll()
        #expect(Set(engine.contextTickets.map(\.identifier)) == ["NODE-5973", "NODE-6037"])
        #expect(engine.contextTicketIDs.contains("NODE-4288"))
        #expect(!engine.contextTicketIDs.contains("NODE-5980"), "my own tickets are not looked up")
        #expect(engine.items.first { $0.id == "gh:n8n-io/n8n#39409" }?.contextTicket?.identifier == "NODE-5973")
    }
}
