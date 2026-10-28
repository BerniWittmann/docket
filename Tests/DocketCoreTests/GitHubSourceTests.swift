import Testing
import Foundation
@testable import DocketCore

/// Records every call and answers with canned output.
final class FakeRunner: ProcessRunning, @unchecked Sendable {
    var calls: [[String]] = []
    var respond: ([String]) throws -> Data

    init(respond: @escaping ([String]) throws -> Data = { _ in Data() }) { self.respond = respond }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        calls.append([executable] + arguments)
        return try respond(arguments)
    }
}

@Suite("GitHub source")
struct GitHubSourceTests {
    @Test("fact 7–8: queries gh api graphql scoped to the watched repos, plus extra PR lookups")
    func arguments() async throws {
        let runner = FakeRunner { _ in Fixtures.data("github-inbox") }
        let source = GitHubSource(runner: runner, ghPath: "/opt/homebrew/bin/gh")
        let inbox = try await source.fetch(scope: "org:n8n-io", extraURLs: ["https://github.com/n8n-io/n8n/pull/1"])
        #expect(inbox.pullRequests.count == 14)

        let call = try #require(runner.calls.first)
        #expect(Array(call.prefix(3)) == ["/opt/homebrew/bin/gh", "api", "graphql"])
        #expect(call.contains("authored=is:pr is:open archived:false org:n8n-io author:@me"))
        #expect(call.contains("requested=is:pr is:open archived:false org:n8n-io user-review-requested:@me"))
        #expect(call.contains("u0=https://github.com/n8n-io/n8n/pull/1"))
        #expect(call.contains { $0.contains("pr0: resource(url: $u0)") })
        #expect(!call.contains { $0.localizedCaseInsensitiveContains("mutation") }, "fact 32: read only")
    }

    @Test("fact 43: a gh failure surfaces as a source error")
    func failure() async {
        let runner = FakeRunner { _ in throw SourceError.message("You are not logged into any GitHub hosts. To log in, run: gh auth login") }
        await #expect(throws: SourceError.self) {
            try await GitHubSource(runner: runner, ghPath: "/bin/gh").fetch(scope: "org:n8n-io", extraURLs: [])
        }
        await #expect(throws: SourceError.message("gh is not installed")) {
            try await GitHubSource(runner: runner, ghPath: nil).fetch(scope: "org:n8n-io", extraURLs: [])
        }
        #expect(throws: SourceError.message("Bad credentials")) {
            try GitHubInbox.decode(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8))
        }
    }

    @Test("the real process runner returns stdout and reports failures")
    func processRunner() async throws {
        let out = try await ProcessRunner().run("/bin/echo", ["hi"], timeout: 5)
        #expect(String(decoding: out, as: UTF8.self) == "hi\n")
        await #expect(throws: SourceError.self) { try await ProcessRunner().run("/bin/sh", ["-c", "echo nope >&2; exit 3"], timeout: 5) }
        await #expect(throws: SourceError.message("sleep timed out")) { try await ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.2) }
    }

    @Test("live: records a real GitHub response", .enabled(if: ProcessInfo.processInfo.environment["DOCKET_LIVE"] == "1"))
    func live() async throws {
        let source = GitHubSource()
        let gh = try #require(source.ghPath)
        let data = try await ProcessRunner().run(gh, GitHubSource.arguments(scope: Settings().searchScope, extraURLs: ["https://github.com/n8n-io/n8n/pull/36223"]), timeout: 60)
        let inbox = try GitHubInbox.decode(data)
        #expect(!inbox.viewer.isEmpty)
        #expect(inbox.pullRequests.contains { $0.number == 36223 })
        if let out = ProcessInfo.processInfo.environment["DOCKET_RECORD"] { try data.write(to: URL(fileURLWithPath: out)) }
        print("LIVE viewer=\(inbox.viewer) prs=\(inbox.pullRequests.count)")
    }
}
