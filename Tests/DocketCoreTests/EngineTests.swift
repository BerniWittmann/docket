import Testing
import Foundation
@testable import DocketCore

struct FakeGitHub: GitHubFetching {
    var result: Result<GitHubInbox, SourceError> = .success(Fixtures.github)
    func fetch(scope: String, extraURLs: [String]) async throws -> GitHubInbox { try result.get() }
}

/// A harness with fixed workspaces that records nothing.
struct FakeHarness: Harness {
    var workspaces: [Workspace] = []
    func listWorkspaces() async throws -> [Workspace] { workspaces }
    func findWorkspace(for ref: WorkRef) async throws -> Workspace? { ref.find(in: workspaces) }
    func startWork(_ ref: WorkRef, agent: String?, prompt: String?) async throws {}
    func open(_ workspace: Workspace) async throws {}
}

@MainActor
func makeEngine(github: GitHubFetching = FakeGitHub()) -> InboxEngine {
    InboxEngine(store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                github: github, linear: FakeLinear(), linearKey: { nil }, tickTickKey: { nil }, harness: FakeHarness(), now: { .iso("2026-10-09T10:00:00Z") })
}

@MainActor
@Suite("Inbox engine")
struct EngineTests {
    @Test("fact 9: GitHub polls every 2 minutes, and refresh fetches immediately")
    func refresh() async {
        #expect(InboxEngine.githubInterval == 120)
        let engine = makeEngine()
        #expect(engine.items.isEmpty)
        await engine.refreshAll()
        #expect(engine.status[.github] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(engine.items(in: .reviews).map(\.need.headline).first == "Review #39679")
    }

    @Test("facts 33–35: marks hide or move items and persist")
    func marks() async {
        let engine = makeEngine()
        await engine.refreshAll()
        let review = engine.items(in: .reviews)[0]
        engine.mark(review, .snoozed(until: .distantFuture))
        #expect(engine.items(in: .snoozed).map(\.id) == [review.id])
        engine.mark(review, .done)
        #expect(!engine.items.contains { $0.id == review.id })
        #expect(engine.store.loadState().marks[review.id]?.mark == .done)
    }
}

struct FakeLinear: LinearFetching {
    var result: Result<LinearInbox, SourceError> = .success(try! LinearSource.decodeIssues(Fixtures.data("linear-issues")))
    var known: [Ticket] = []
    func fetch(key: String) async throws -> LinearInbox { try result.get() }
    func lookup(identifiers: [String], key: String) async throws -> [Ticket] { known.filter { identifiers.contains($0.identifier) } }
}

/// Remembers the extra URLs it was asked for.
final class RecordingGitHub: GitHubFetching, @unchecked Sendable {
    var extraURLs: [[String]] = []
    func fetch(scope: String, extraURLs: [String]) async throws -> GitHubInbox {
        self.extraURLs.append(extraURLs)
        return Fixtures.github
    }
}

@MainActor
@Suite("Inbox engine with Linear")
struct LinearEngineTests {
    func engine(github: GitHubFetching = FakeGitHub(), linear: LinearFetching = FakeLinear(), key: String? = "lin_api_test") -> InboxEngine {
        InboxEngine(store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                    github: github, linear: linear, linearKey: { key }, tickTickKey: { nil }, harness: FakeHarness(), now: { .iso("2026-10-09T10:00:00Z") })
    }

    @Test("fact 19–20: tickets merge with their PRs")
    func merged() async {
        let engine = engine()
        await engine.refreshAll()
        #expect(engine.status[.linear] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(engine.items(in: .tickets).last?.id == "linear:DOC-2049")
        #expect(engine.items(in: .myPRs).contains { $0.id == "linear:NODE-5980" })
    }

    @Test("fact 43: an invalid Linear key shows a Linear error while GitHub keeps working")
    func linearFails() async {
        let engine = engine(linear: FakeLinear(result: .failure(.message("Authentication required, not authenticated"))))
        await engine.refreshAll()
        #expect(engine.status[.linear]?.errorMessage == "Authentication required, not authenticated")
        #expect(engine.status[.github] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(!engine.items(in: .reviews).isEmpty)
    }

    @Test("fact 43: gh logged out shows a GitHub error while Linear keeps working")
    func githubFails() async {
        let engine = engine(github: FakeGitHub(result: .failure(.message("not logged in"))))
        await engine.refreshAll()
        #expect(engine.status[.github] == .error("not logged in"))
        #expect(engine.status[.linear] == .ok(.iso("2026-10-09T10:00:00Z")))
        #expect(engine.items(in: .tickets).contains { $0.id == "linear:DOC-2049" })
    }

    @Test("fact 42: without a Linear key the app works with GitHub only")
    func skipped() async {
        let engine = engine(key: nil)
        await engine.refreshAll()
        #expect(engine.status[.linear] == .notConnected)
        #expect(!engine.items(in: .reviews).isEmpty)
    }

    @Test("PRs attached to tickets are looked up by URL on every GitHub poll")
    func attachedLookups() async {
        let github = RecordingGitHub()
        let engine = engine(github: github)
        await engine.refreshAll()
        await engine.refreshGitHub()
        #expect(github.extraURLs.last?.contains("https://github.com/n8n-io/n8n/pull/36223") == true)
        #expect(github.extraURLs.last?.count == 6)
    }

    @Test("the Linear request posts a read-only query with the raw key")
    func request() {
        let request = LinearSource.request(LinearSource.query, key: " lin_api_x \n")
        #expect(request.url == LinearSource.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_x")
        #expect(!LinearSource.query.contains("mutation"))
    }
}
