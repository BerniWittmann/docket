import Testing
import Foundation
@testable import DocketCore

private let orcaPath = "/Applications/Orca.app/Contents/Resources/bin/orca"
private let n8nRepoID = "1551d537-6de8-460a-a7c1-4468342d6b07"

/// A fake Orca CLI answering from fixtures. `workspaces` replaces `worktree ps` when set.
private func fakeOrca(workspacesJSON: Data? = nil) -> FakeRunner {
    FakeRunner { args in
        switch Array(args.prefix(2)) {
        case ["worktree", "ps"]: workspacesJSON ?? Fixtures.data("orca-ps")
        case ["repo", "list"]: Fixtures.data("orca-repos")
        case ["terminal", "list"]: Data(#"{"ok":true,"result":{"terminals":[{"handle":"term_1","agentIdentity":"claude"}]}}"#.utf8)
        default: Data(#"{"ok":true,"result":{}}"#.utf8)
        }
    }
}

private func item(_ id: String, workspaces: [Workspace] = []) -> WorkItem {
    Merge.items(Fixtures.input(workspaces: workspaces)).first { $0.id == id }!
}

/// Runs Start work through the engine with a fake Orca CLI and returns the commands it ran.
@MainActor
private func startWork(_ item: WorkItem, runner: FakeRunner = fakeOrca(), settings: (inout Settings) -> Void = { _ in }) async -> [[String]] {
    let engine = InboxEngine(
        store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
        github: FakeGitHub(), linear: FakeLinear(), linearKey: { nil }, tickTickKey: { nil },
        harness: OrcaHarness(runner: runner, orcaPath: orcaPath), now: { .iso("2026-10-10T10:00:00Z") })
    engine.update(settings)
    await engine.refreshGitHub()
    await engine.startWork(item)
    #expect(engine.actionError == nil)
    return runner.calls.filter { !($0.contains("ps") || $0.contains("list")) }
}

@MainActor
@Suite("Harness and Orca adapter")
struct HarnessTests {
    @Test("fact 23–24: lists workspaces through orca worktree ps every 10 seconds")
    func list() async throws {
        #expect(InboxEngine.orcaInterval == 10)
        let runner = fakeOrca()
        let workspaces = try await OrcaHarness(runner: runner, orcaPath: orcaPath).listWorkspaces()
        #expect(workspaces.count == 19)
        #expect(runner.calls == [[orcaPath, "worktree", "ps", "--json"]])
    }

    @Test("fact 43: Orca not running surfaces as an Orca error only")
    func orcaDown() async {
        let runner = FakeRunner { _ in throw SourceError.message("Orca is not running") }
        let engine = InboxEngine(
            store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
            github: FakeGitHub(), linear: FakeLinear(), linearKey: { "k" }, tickTickKey: { nil },
            harness: OrcaHarness(runner: runner, orcaPath: orcaPath), now: { .iso("2026-10-09T10:00:00Z") })
        await engine.refreshAll()
        #expect(engine.status[.orca] == .error("Orca is not running"))
        #expect(engine.status[.github] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(engine.status[.linear] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(!engine.items.isEmpty)
        await #expect(throws: SourceError.message("Orca CLI not found")) {
            try await OrcaHarness(runner: runner, orcaPath: nil).listWorkspaces()
        }
    }

    @Test("fact 27–28: a review without a worktree gets review-<n>-<slug> from refs/pull/<n>/head and /pr-review")
    func newReview() async {
        let calls = await startWork(item("gh:n8n-io/n8n#39679"))
        #expect(calls == [
            ["/usr/bin/git", "-C", "/Users/me/DEV/n8n", "fetch", "origin", "+refs/pull/39679/head:refs/remotes/origin/pr/39679"],
            [orcaPath, "worktree", "create", "--repo", "id:\(n8nRepoID)", "--no-parent", "--json",
             "--name", "review-39679-scrubbed-title", "--base-branch", "origin/pr/39679", "--pr", "39679",
             "--agent", "claude", "--prompt", "/pr-review https://github.com/n8n-io/n8n/pull/39679", "--activate"],
        ])
    }

    @Test("fact 27–28: my PR with feedback reuses its linked worktree and starts /pr-review-feedback")
    func reuse() async {
        let ps = #"{"ok":true,"result":{"worktrees":[{"worktreeId":"r::/w","repo":"n8n","branch":"refs/heads/x","linkedPR":{"number":40697},"agents":[{"state":"done"}]}]}}"#
        let prs = Fixtures.pullRequests.map { $0.number == 40697 ? Fixtures.botFeedbackPR : $0 }
        let ticket = Merge.items(Fixtures.input(prs: prs, workspaces: [])).first { $0.id == "linear:NODE-5980" }!
        let calls = await startWork(ticket, runner: fakeOrca(workspacesJSON: Data(ps.utf8)))
        #expect(calls == [[orcaPath, "terminal", "create", "--worktree", "id:r::/w",
                           "--command", "claude '/pr-review-feedback https://github.com/n8n-io/n8n/pull/40697'", "--focus", "--json"]])
    }

    @Test("fact 27: my PR without a worktree is checked out on its head branch")
    func myPRNewWorktree() async {
        var pr = Fixtures.pr(40697)
        pr.headRef = "my-branch"
        let mine = Merge.items(Fixtures.input(prs: [pr], tickets: [], workspaces: [])).first!
        let calls = await startWork(mine)
        #expect(calls.first == ["/usr/bin/git", "-C", "/Users/me/DEV/n8n", "fetch", "origin", "+refs/heads/my-branch:refs/remotes/origin/my-branch"])
        #expect(calls.last?.contains("my-branch") == true)
        #expect(calls.last?.contains("origin/my-branch") == true)
        #expect(calls.last?.contains("--pr") == true)
    }

    @Test("fact 27–28: a Todo ticket gets a worktree on its branch name and /fix-ticket")
    func startTicket() async {
        let calls = await startWork(item("linear:DOC-2049")) { $0.ticketRepo = "n8n-io/n8n-docs" }
        let docsRepo = "id:" + (String(decoding: Fixtures.data("orca-repos"), as: UTF8.self)
            .components(separatedBy: "\"id\": \"").dropFirst().first { $0.contains("github.com/n8n-io/n8n-docs\"") }?
            .prefix(36) ?? "")
        #expect(calls == [[orcaPath, "worktree", "create", "--repo", docsRepo, "--no-parent", "--json",
                           "--name", "doc-2049-docs-for-community-issue-mcp-webhook-queue-mode", "--linear-issue", "DOC-2049",
                           "--agent", "claude", "--prompt", "/fix-ticket DOC-2049", "--activate"]])
    }

    @Test("Start work on a worktree whose agent is still running opens it instead of starting another")
    func busyWorktree() async throws {
        let ps = #"{"ok":true,"result":{"worktrees":[{"worktreeId":"r::/w","repo":"n8n","branch":"refs/heads/x","linkedPR":{"number":40697},"agents":[{"state":"working"}]}]}}"#
        let runner = fakeOrca(workspacesJSON: Data(ps.utf8))
        try await OrcaHarness(runner: runner, orcaPath: orcaPath)
            .startWork(WorkRef(repo: "n8n-io/n8n", prNumber: 40697, branch: "x"), agent: "claude", prompt: "/pr-review-feedback x")
        #expect(runner.calls.last == [orcaPath, "terminal", "switch", "--terminal", "term_1", "--json"])
        #expect(!runner.calls.contains { $0.contains("create") })
    }

    @Test("fact 41: Open in Orca jumps to the terminal of the agent that needs me")
    func openWaitingAgent() async throws {
        var ws = Fixtures.workspace(branch: "eng-slides-update")
        ws.agents = [AgentStatus(state: "working", paneKey: "tab-a:leaf-a"), AgentStatus(state: "waiting", paneKey: "tab-b:leaf-b")]
        let runner = FakeRunner { _ in
            Data(#"{"ok":true,"result":{"terminals":[{"handle":"term_a","agentIdentity":"claude","tabId":"tab-a","leafId":"leaf-a"},{"handle":"term_b","agentIdentity":"claude","tabId":"tab-b","leafId":"leaf-b"}]}}"#.utf8)
        }
        try await OrcaHarness(runner: runner, orcaPath: orcaPath).open(ws)
        #expect(runner.calls.last == [orcaPath, "terminal", "switch", "--terminal", "term_b", "--json"])
    }

    @Test("Start work types the prompt into an idle session of the same agent, keeping its context")
    func reuseSession() async throws {
        let ps = #"{"ok":true,"result":{"worktrees":[{"worktreeId":"r::/w","repo":"n8n","branch":"refs/heads/review-39409","linkedPR":{"number":39409},"agents":[{"state":"done","agentType":"claude","paneKey":"tab-a:leaf-a"}]}]}}"#
        let runner = FakeRunner { args in
            switch Array(args.prefix(2)) {
            case ["worktree", "ps"]: Data(ps.utf8)
            case ["terminal", "list"]: Data(#"{"ok":true,"result":{"terminals":[{"handle":"term_shell"},{"handle":"term_a","agentIdentity":"claude","tabId":"tab-a","leafId":"leaf-a"}]}}"#.utf8)
            default: Data(#"{"ok":true,"result":{}}"#.utf8)
            }
        }
        let ref = WorkRef(repo: "n8n-io/n8n", prNumber: 39409, branch: "review-39409", isReview: true)
        try await OrcaHarness(runner: runner, orcaPath: orcaPath).startWork(ref, agent: "claude", prompt: "/pr-review url")
        #expect(runner.calls.suffix(2) == [
            [orcaPath, "terminal", "send", "--terminal", "term_a", "--text", "/pr-review url", "--enter", "--json"],
            [orcaPath, "terminal", "switch", "--terminal", "term_a", "--json"],
        ])
        #expect(!runner.calls.contains { $0.contains("create") })
    }

    @Test("work plans: create, open, send into a session, or start a new one")
    func plans() {
        var ws = Fixtures.workspace(branch: "eng-slides-update")
        #expect(WorkPlan(workspace: nil, agent: "claude", prompt: "p") == .create)
        ws.agents = []
        #expect(WorkPlan(workspace: ws, agent: "claude", prompt: "p") == .newTerminal)
        #expect(WorkPlan(workspace: ws, agent: "claude", prompt: nil) == .open, "Continue just opens")
        #expect(WorkPlan(workspace: ws, agent: nil, prompt: nil) == .nothing, "Prepare leaves existing worktrees alone")
        ws.agents = [AgentStatus(state: "done", paneKey: "t:l", agentType: "claude")]
        #expect(WorkPlan(workspace: ws, agent: "claude", prompt: "p") == .send(paneKey: "t:l"))
        #expect(WorkPlan(workspace: ws, agent: "codex", prompt: "p") == .newTerminal, "only the same agent's session is reused")
        ws.agents.append(AgentStatus(state: "working", paneKey: "t:m", agentType: "claude"))
        #expect(WorkPlan(workspace: ws, agent: "claude", prompt: "p") == .open, "never interrupt a running agent")
    }

    @Test("fact 29: Continue opens the existing worktree without a prompt")
    func continueExisting() async {
        var ticket = Fixtures.ticket("NODE-5980")
        ticket.attachmentURLs = []
        let continued = Merge.items(Fixtures.input(prs: Fixtures.pullRequests.filter { $0.ticketID != "NODE-5980" }, tickets: [ticket])).first { $0.id == "linear:NODE-5980" }!
        #expect(continued.need.kind == .continueTicket)
        let calls = await startWork(continued)
        #expect(calls == [[orcaPath, "terminal", "switch", "--terminal", "term_1", "--json"]])
    }

    @Test("fact 29: Continue without a worktree starts one with the continue prompt")
    func continueNew() async {
        var ticket = Fixtures.ticket("NODE-5980")
        ticket.attachmentURLs = []
        let continued = Merge.items(Fixtures.input(prs: Fixtures.pullRequests.filter { $0.ticketID != "NODE-5980" }, tickets: [ticket], workspaces: [])).first { $0.id == "linear:NODE-5980" }!
        let noWorktrees = fakeOrca(workspacesJSON: Data(#"{"ok":true,"result":{"worktrees":[]}}"#.utf8))
        let calls = await startWork(continued, runner: noWorktrees)
        let create = calls.last ?? []
        #expect(create.contains("--linear-issue"))
        #expect(create.contains("Continue NODE-5980: check the branch and the ticket, then propose the next step"))
    }

    @Test("fact 30: the agent and prompt per kind come from Settings")
    func customPrompt() async {
        let calls = await startWork(item("gh:n8n-io/n8n#39679")) {
            $0.work[WorkKind.review.rawValue] = WorkSetting(agent: "codex", prompt: "Review {repo}#{number}")
        }
        #expect(calls.last?.suffix(5) == ["--agent", "codex", "--prompt", "Review n8n-io/n8n#39679", "--activate"])
    }

    @Test("fact 31: Prepare creates worktrees without an agent, only inside work hours")
    func prepare() async throws {
        for (time, expected) in [("2026-10-09T10:00:00Z", 1), ("2026-10-09T20:00:00Z", 0), ("2026-10-10T10:00:00Z", 0)] {
            let runner = fakeOrca()
            let engine = InboxEngine(
                store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                github: FakeGitHub(), linear: FakeLinear(), linearKey: { nil }, tickTickKey: { nil },
                harness: OrcaHarness(runner: runner, orcaPath: orcaPath), now: { .iso(time) })
            engine.update { $0.work[WorkKind.review.rawValue]?.automation = .prepare; $0.workHours.start = 0; $0.workHours.end = 19 * 60 }
            await engine.refreshAll()
            try await Task.sleep(for: .milliseconds(200))
            let creates = runner.calls.filter { $0.contains("create") }
            #expect(creates.count == (expected == 1 ? 2 : 0), "\(time)")
            #expect(creates.allSatisfy { !$0.contains("--agent") && !$0.contains("--prompt") })
            #expect(Set(creates.compactMap { call in call.firstIndex(of: "--name").map { call[$0 + 1] } }) == (expected == 1 ? ["review-39679-scrubbed-title", "review-39409-scrubbed-title"] : []))

            await engine.refreshAll()
            try await Task.sleep(for: .milliseconds(200))
            #expect(runner.calls.filter { $0.contains("create") }.count == creates.count, "prepares each item once")
        }
    }

    @Test("review worktrees get a readable slug, and old ones without it still match")
    func reviewBranches() {
        #expect(PullRequest.slug("feat(core): Handle inbound media handling for whatsapp") == "handle-inbound-media-handling")
        #expect(PullRequest.slug("fix(ERPNext Node): Create/Update crash with a raw TypeError") == "create-update-crash-with-a-raw")
        #expect(PullRequest.slug("feat!: Overhaul MCP tool permissions for Agents") == "overhaul-mcp-tool-permissions")
        #expect(PullRequest.slug("chore: Lint rule: reject hardcoded IDs") == "lint-rule-reject-hardcoded-ids")
        #expect(PullRequest.slug("Supercalifragilisticexpialidociousandmorewords") == "supercalifragilisticexpialidoc")
        var pr = Fixtures.pr(39409)
        pr.title = "feat(core): Handle inbound media handling for whatsapp"
        #expect(pr.reviewBranch == "review-39409-handle-inbound-media-handling")

        var old = Fixtures.workspace(branch: "orca-pixel-art-plugin")
        old.branch = "refs/heads/review-39409"
        var new = old
        new.branch = "refs/heads/review-39409-handle-inbound-media-handling"
        let ref = WorkRef(repo: "n8n-io/n8n", prNumber: 39409, branch: pr.reviewBranch, isReview: true)
        #expect(ref.find(in: [old])?.id == old.id)
        #expect(ref.find(in: [new])?.id == new.id)
        #expect(!PullRequest.isReviewBranch("review-394090", number: 39409))
    }

    @Test("prompts are shell-quoted for an existing worktree")
    func quoting() {
        #expect(OrcaHarness.shellQuote("it's $HOME") == #"'it'\''s $HOME'"#)
    }
}
