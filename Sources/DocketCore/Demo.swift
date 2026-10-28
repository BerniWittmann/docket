import Foundation

/// Made-up sources for `Docket --demo`, used for screenshots. Nothing is read from or written to real services.
public enum Demo {
    public static let viewer = "you"

    @MainActor
    public static func engine() -> InboxEngine {
        let store = LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: "docket-demo-\(UUID().uuidString)"))
        let engine = InboxEngine(store: store, github: GitHub(), linear: Linear(), linearKey: { "demo" },
                                 tickTick: TickTick(), tickTickKey: { "demo" }, harness: Orca())
        engine.update {
            $0.onboarded = true
            $0.tickTickListID = "demo"
        }
        return engine
    }

    // MARK: Sources

    struct GitHub: GitHubFetching {
        func fetch(scope: String, extraURLs: [String]) async throws -> GitHubInbox {
            try GitHubInbox.decode(json(["data": ["viewer": ["login": viewer], "prs": ["nodes": pullRequests()]]]))
        }
    }

    struct Linear: LinearFetching {
        func fetch(key: String) async throws -> LinearInbox {
            try LinearSource.decodeIssues(json(["data": ["viewer": ["name": "You", "assignedIssues": ["nodes": tickets()]]]]))
        }
        func lookup(identifiers: [String], key: String) async throws -> [Ticket] {
            let others = [ticket("WEB-420", "Snap nodes to a grid while dragging", "In Progress", "started", days: 1, assignee: "Maya")]
            return try LinearSource.decodeIssues(json(["data": ["viewer": ["name": "You", "assignedIssues": ["nodes": others]]]]))
                .tickets.filter { identifiers.contains($0.identifier) }
        }
    }

    struct Orca: Harness {
        func listWorkspaces() async throws -> [Workspace] {
            try OrcaHarness.decodeWorkspaces(json(["ok": true, "result": ["worktrees": workspaces()]]))
        }
        func findWorkspace(for ref: WorkRef) async throws -> Workspace? { ref.find(in: try await listWorkspaces()) }
        func startWork(_ ref: WorkRef, agent: String?, prompt: String?) async throws {}
        func open(_ workspace: Workspace) async throws {}
    }

    final class TickTick: TickTickSyncing, @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [Todo] = [
            Todo(id: "d1", projectId: "demo", title: "Prepare the sprint demo", dueDate: day(0)),
            Todo(id: "d2", projectId: "demo", title: "Send feedback on the onboarding copy", dueDate: day(0)),
            Todo(id: "d3", projectId: "demo", title: "Book the team offsite venue", dueDate: day(6)),
        ]

        func todos(token: String) async throws -> [Todo] { lock.withLock { tasks.filter { $0.status == 0 } } }
        func lists(token: String) async throws -> [TickTickList] { [TickTickList(id: "demo", name: "Work")] }
        func create(title: String, content: String, listID: String, due: Date, token: String) async throws -> Todo {
            lock.withLock {
                let todo = Todo(id: "c\(tasks.count)", projectId: listID, title: title, content: content, dueDate: due)
                tasks.append(todo)
                return todo
            }
        }
        func setDue(_ due: Date, title: String?, taskID: String, listID: String, token: String) async throws {
            lock.withLock {
                guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
                tasks[i].dueDate = due
                tasks[i].status = 0
                if let title { tasks[i].title = title }
            }
        }
        func complete(taskID: String, listID: String, token: String) async throws {
            lock.withLock { if let i = tasks.firstIndex(where: { $0.id == taskID }) { tasks[i].status = 2 } }
        }
    }

    // MARK: Data

    static func pullRequests() -> [[String: Any]] {
        [
            pr("web", 1287, "feat(editor): Keyboard shortcuts for the command palette", branch: "web-398-command-palette-shortcuts",
               decision: "CHANGES_REQUESTED", reviews: [review("maya", "CHANGES_REQUESTED", hours: 2)],
               threads: [thread("maya", hours: 2), thread("jonas", hours: 1)], pushed: 20),
            pr("api", 1301, "fix(search): Rate-limit the public search endpoint", branch: "web-405-rate-limit-search", checks: "FAILURE", pushed: 3),
            pr("web", 1290, "refactor: Move date helpers into a shared package", branch: "shared-date-helpers", mergeable: "CONFLICTING", pushed: 26),
            pr("web", 1279, "feat: Inline previews for linked issues", branch: "web-371-inline-issue-previews",
               decision: "APPROVED", reviews: [review("sam", "APPROVED", hours: 6)], pushed: 5),
            pr("docs", 88, "docs: Explain the new sharing settings", branch: "sharing-settings-docs", requested: ["sam"], pushed: 5),
            pr("web", 1302, "feat(canvas): Snap nodes to a grid while dragging", author: "maya", branch: "web-420-snap-to-grid",
               requested: [viewer], pushed: 1),
            pr("api", 1296, "fix: Retry webhook deliveries with backoff", author: "jonas", branch: "retry-webhooks",
               requested: [viewer], pushed: 6),
            pr("web", 1270, "feat(auth): Sign in with passkeys", author: "lena", branch: "passkeys",
               requested: [viewer], reviews: [review(viewer, "CHANGES_REQUESTED", hours: 28)], rerequested: 2, pushed: 3),
        ]
    }

    static func tickets() -> [[String: Any]] {
        [
            ticket("WEB-412", "Let people export dashboards as PDF", "Todo", "unstarted", days: 1),
            ticket("WEB-398", "Keyboard shortcuts for the command palette", "In Progress", "started", days: 0, prs: ["web#1287"]),
            ticket("WEB-405", "Rate-limit the public search endpoint", "In Progress", "started", days: 0, prs: ["api#1301"]),
            ticket("WEB-371", "Inline previews for linked issues", "Review", "started", days: 2, prs: ["web#1279"]),
            ticket("WEB-377", "Dark mode for email templates", "Waiting for input", "started", days: 3),
            ticket("WEB-415", "Clean up unused feature flags", "Todo", "unstarted", days: 4),
        ]
    }

    static func workspaces() -> [[String: Any]] {
        [
            workspace("web", "web-398-command-palette-shortcuts", "Command palette shortcuts", agent: "waiting", agentType: "claude", minutes: 4, issue: "WEB-398"),
            workspace("web", "review-1302-snap-nodes-to-a-grid-while", "Review #1302", agent: "done", agentType: "codex", minutes: 12, pr: 1302, unread: true),
            workspace("api", "spike-offline-sync", "Spike: offline sync", agent: "working", agentType: "claude", minutes: 25),
        ]
    }

    // MARK: Builders

    static func pr(_ repo: String, _ number: Int, _ title: String, author: String = viewer, branch: String,
                   decision: String = "REVIEW_REQUIRED", mergeable: String = "MERGEABLE", checks: String = "SUCCESS",
                   requested: [String] = [], reviews: [[String: Any]] = [], threads: [[String: Any]] = [],
                   rerequested: Double? = nil, pushed: Double) -> [String: Any] {
        var timeline: [[String: Any]] = [["__typename": "PullRequestCommit", "commit": ["committedDate": iso(hours: pushed)]]]
        if let rerequested { timeline.append(["__typename": "ReviewRequestedEvent", "createdAt": iso(hours: rerequested), "requestedReviewer": ["__typename": "User", "login": viewer]]) }
        timeline += reviews.map { ["__typename": "PullRequestReview", "author": $0["author"]!, "submittedAt": $0["submittedAt"]!, "state": $0["state"]!] }
        return [
            "number": number, "title": title, "url": "https://github.com/acme/\(repo)/pull/\(number)",
            "isDraft": false, "state": "OPEN", "createdAt": iso(hours: 72), "updatedAt": iso(hours: min(pushed, 1)),
            "headRefName": branch, "repository": ["name": repo, "nameWithOwner": "acme/\(repo)"],
            "author": ["__typename": "User", "login": author], "reviewDecision": decision, "mergeable": mergeable,
            "reviewRequests": ["nodes": requested.map { ["requestedReviewer": ["__typename": "User", "login": $0]] }],
            "latestReviews": ["nodes": reviews], "reviewThreads": ["nodes": threads],
            "commits": ["nodes": [["commit": ["committedDate": iso(hours: pushed), "statusCheckRollup": ["state": checks]]]]],
            "timelineItems": ["nodes": timeline],
        ]
    }

    static func review(_ login: String, _ state: String, hours: Double) -> [String: Any] {
        ["author": ["__typename": "User", "login": login], "state": state, "submittedAt": iso(hours: hours)]
    }

    static func thread(_ login: String, hours: Double) -> [String: Any] {
        ["isResolved": false, "comments": ["nodes": [["author": ["__typename": "User", "login": login], "createdAt": iso(hours: hours)]]]]
    }

    static func ticket(_ id: String, _ title: String, _ state: String, _ type: String, days: Double,
                       prs: [String] = [], assignee: String = "You") -> [String: Any] {
        let slug = id.lowercased() + "-" + PullRequest.slug(title)
        return [
            "identifier": id, "title": title, "url": "https://linear.app/acme/issue/\(id)/\(slug)", "branchName": slug,
            "updatedAt": iso(hours: days * 24 + 1), "state": ["name": state, "type": type], "assignee": ["name": assignee],
            "attachments": ["nodes": prs.map { ref -> [String: Any] in
                let parts = ref.split(separator: "#")
                return ["url": "https://github.com/acme/\(parts[0])/pull/\(parts[1])"]
            }],
        ]
    }

    static func workspace(_ repo: String, _ branch: String, _ name: String, agent: String, agentType: String,
                          minutes: Double, issue: String? = nil, pr: Int? = nil, unread: Bool = false) -> [String: Any] {
        let at = Date.now.addingTimeInterval(-minutes * 60).timeIntervalSince1970 * 1000
        var ws: [String: Any] = [
            "worktreeId": "demo::\(branch)", "repo": repo, "path": "/Users/you/workspaces/\(repo)/\(branch)",
            "branch": "refs/heads/\(branch)", "displayName": name, "unread": unread, "isArchived": false, "lastActivityAt": at,
            "agents": [["paneKey": "demo:\(branch)", "state": agent, "agentType": agentType, "stateStartedAt": at, "updatedAt": at]],
        ]
        if let issue { ws["linkedLinearIssue"] = issue }
        if let pr { ws["linkedPR"] = ["number": pr] }
        return ws
    }

    static func iso(hours: Double) -> String { Date.now.addingTimeInterval(-hours * 3600).formatted(.iso8601) }
    static func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))! }
    static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
}
