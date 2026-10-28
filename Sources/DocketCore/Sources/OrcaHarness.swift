import Foundation

/// Drives Orca through its CLI. The CLI's JSON is not a stable API, so decoding is lenient.
public struct OrcaHarness: Harness {
    public static let bundledCLI = "/Applications/Orca.app/Contents/Resources/bin/orca"

    public var runner: ProcessRunning
    public var orcaPath: String?

    public init(runner: ProcessRunning = ProcessRunner(), orcaPath: String? = OrcaHarness.locate()) {
        self.runner = runner
        self.orcaPath = orcaPath
    }

    public static func locate(configured: String? = nil) -> String? {
        [configured, bundledCLI, ProcessRunner.locate("orca")].compactMap { $0 }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func listWorkspaces() async throws -> [Workspace] {
        try Self.decodeWorkspaces(try await orca(["worktree", "ps", "--json"]))
    }

    public func findWorkspace(for ref: WorkRef) async throws -> Workspace? {
        ref.find(in: try await listWorkspaces())
    }

    public func startWork(_ ref: WorkRef, agent: String?, prompt: String?) async throws {
        if let workspace = try await findWorkspace(for: ref) {
            switch WorkPlan(workspace: workspace, agent: agent, prompt: prompt) {
            case .open:
                try await open(workspace)
            case .send(let paneKey):
                if let terminal = try await terminals(of: workspace).first(where: { $0.paneKey == paneKey }) {
                    _ = try await orca(["terminal", "send", "--terminal", terminal.handle, "--text", prompt ?? "", "--enter", "--json"])
                    _ = try await orca(["terminal", "switch", "--terminal", terminal.handle, "--json"])
                } else {
                    try await newAgentTerminal(in: workspace, agent: agent ?? "", prompt: prompt ?? "")
                }
            case .newTerminal:
                try await newAgentTerminal(in: workspace, agent: agent ?? "", prompt: prompt ?? "")
            case .nothing, .create:
                break
            }
            return
        }
        let repo = try await repo(for: ref.repo)
        var create = ["worktree", "create", "--repo", "id:\(repo.id)", "--no-parent", "--json"]
        if let number = ref.prNumber {
            let base = ref.isReview ? "pr/\(number)" : (ref.branch ?? "")
            let refspec = ref.isReview ? "+refs/pull/\(number)/head:refs/remotes/origin/pr/\(number)" : "+refs/heads/\(base):refs/remotes/origin/\(base)"
            _ = try await runner.run("/usr/bin/git", ["-C", repo.path, "fetch", "origin", refspec], timeout: 120)
            create += ["--name", ref.branch ?? "pr-\(number)", "--base-branch", "origin/\(base)", "--pr", String(number)]
        } else if let branch = ref.branch, !branch.isEmpty {
            create += ["--name", branch]
        }
        if let ticket = ref.ticket { create += ["--linear-issue", ticket] }
        if let agent {
            create += ["--agent", agent]
            if let prompt { create += ["--prompt", prompt] }
            create.append("--activate")
        }
        _ = try await orca(create)
    }

    /// Brings the terminal of the agent that needs me (else the first agent's) to the front, or opens a new one.
    /// Brings the terminal of the agent that needs me (else the first agent's) to the front, or opens a new one.
    public func open(_ workspace: Workspace) async throws {
        let terminals = try await terminals(of: workspace)
        let pane = workspace.mainAgent?.paneKey
        if let terminal = terminals.first(where: { pane != nil && $0.paneKey == pane })
            ?? terminals.first(where: { $0.agentIdentity != nil }) ?? terminals.first {
            _ = try await orca(["terminal", "switch", "--terminal", terminal.handle, "--json"])
        } else {
            _ = try await orca(["terminal", "create", "--worktree", "id:\(workspace.worktreeId)", "--focus", "--json"])
        }
    }

    struct Terminal: Decodable {
        var handle: String
        var agentIdentity: String?
        var tabId: String?
        var leafId: String?
        var paneKey: String { "\(tabId ?? ""):\(leafId ?? "")" }
    }

    func terminals(of workspace: Workspace) async throws -> [Terminal] {
        struct Response: Decodable { struct Result: Decodable { var terminals: [Terminal] }; var result: Result? }
        let data = try await orca(["terminal", "list", "--worktree", "id:\(workspace.worktreeId)", "--json"])
        return (try? DocketJSON.decoder().decode(Response.self, from: data))?.result?.terminals ?? []
    }

    func newAgentTerminal(in workspace: Workspace, agent: String, prompt: String) async throws {
        _ = try await orca(["terminal", "create", "--worktree", "id:\(workspace.worktreeId)",
                            "--command", "\(agent) \(Self.shellQuote(prompt))", "--focus", "--json"])
    }

    struct Repo: Decodable {
        struct Remote: Decodable { var canonicalKey: String? }
        var id: String
        var path: String
        var displayName: String?
        var gitRemoteIdentity: Remote?
    }

    /// The Orca repo for `owner/repo`, matched by its GitHub remote.
    func repo(for nameWithOwner: String) async throws -> Repo {
        struct Response: Decodable { struct Result: Decodable { var repos: [Repo] }; var result: Result? }
        let repos = (try DocketJSON.decoder().decode(Response.self, from: try await orca(["repo", "list", "--json"]))).result?.repos ?? []
        let key = "github.com/\(nameWithOwner)".lowercased()
        guard let repo = repos.first(where: { $0.gitRemoteIdentity?.canonicalKey?.lowercased() == key }) else {
            throw SourceError.message("Orca has no repo for \(nameWithOwner). Add it in Orca first.")
        }
        return repo
    }

    func orca(_ arguments: [String]) async throws -> Data {
        guard let orcaPath else { throw SourceError.message("Orca CLI not found") }
        return try await runner.run(orcaPath, arguments, timeout: 60)
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Decodes `orca worktree ps --json`. Unknown or broken entries are skipped.
    public static func decodeWorkspaces(_ data: Data) throws -> [Workspace] {
        struct Lenient: Decodable {
            var value: Workspace?
            init(from decoder: Decoder) throws { value = try? Workspace(from: decoder) }
        }
        struct Response: Decodable {
            struct Result: Decodable { var worktrees: [Lenient] }
            struct Failure: Decodable { var message: String? }
            var ok: Bool?
            var result: Result?
            var error: Failure?
        }
        let response = try DocketJSON.decoder().decode(Response.self, from: data)
        guard let result = response.result else {
            throw SourceError.message(response.error?.message ?? "Unexpected Orca response")
        }
        return result.worktrees.compactMap(\.value)
    }
}
