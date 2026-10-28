import Testing
import Foundation
@testable import DocketCore

@Suite("Orca harness, live")
struct LiveHarnessTests {
    /// Set DOCKET_LIVE_REVIEW=<owner/repo#number> to start a real review in Orca, twice.
    @Test("starts and then reuses a review worktree", .enabled(if: ProcessInfo.processInfo.environment["DOCKET_LIVE_REVIEW"] != nil))
    func review() async throws {
        let spec = ProcessInfo.processInfo.environment["DOCKET_LIVE_REVIEW"]!.split(separator: "#")
        let repo = String(spec[0]), number = Int(spec[1])!
        let harness = OrcaHarness()
        let ref = WorkRef(repo: repo, prNumber: number, branch: "review-\(number)", isReview: true)
        let prompt = "/pr-review https://github.com/\(repo)/pull/\(number)"
        try await harness.startWork(ref, agent: "claude", prompt: prompt)
        let created = try #require(try await harness.findWorkspace(for: ref))
        print("LIVE created \(created.worktreeId) branch=\(created.shortBranch) pr=\(String(describing: created.linkedPR))")

        let before = try await harness.listWorkspaces().count
        try await harness.startWork(ref, agent: "claude", prompt: prompt)
        #expect(try await harness.listWorkspaces().count == before, "reused, not created again")
    }
}
