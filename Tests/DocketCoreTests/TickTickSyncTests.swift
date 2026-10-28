import Testing
import Foundation
@testable import DocketCore

/// An in-memory TickTick that records every write.
final class FakeTickTick: TickTickSyncing, @unchecked Sendable {
    var tasks: [Todo] = []
    var writes: [String] = []

    func todos(token: String) async throws -> [Todo] { tasks.filter { $0.status == 0 } }
    func lists(token: String) async throws -> [TickTickList] { [TickTickList(id: "L", name: "Work")] }
    func create(title: String, content: String, listID: String, due: Date, token: String) async throws -> Todo {
        let todo = Todo(id: "t\(tasks.count)", projectId: listID, title: title, content: content, dueDate: due)
        tasks.append(todo)
        writes.append("create \(title)")
        return todo
    }
    func setDue(_ due: Date, title: String?, taskID: String, listID: String, token: String) async throws {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { throw TickTickError.notFound }
        if let title { tasks[i].title = title }
        tasks[i].dueDate = due
        tasks[i].status = 0
        writes.append("due \(taskID)")
    }
    func complete(taskID: String, listID: String, token: String) async throws {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { throw TickTickError.notFound }
        tasks[i].status = 2
        writes.append("complete \(taskID)")
    }
}

private let now = Date.iso("2026-10-09T10:00:00Z")
private let today = Calendar.current.startOfDay(for: now)
private let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!

private func item(_ group: InboxGroup, id: String = "gh:n8n-io/n8n#40339") -> WorkItem {
    let pr = Fixtures.pr(40339)
    let need = Need(group: group, urgency: .waiting, headline: "x", since: now, url: pr.url)
    return WorkItem(id: id, title: pr.title, ticket: nil, contextTicket: nil, pullRequests: [pr], workspace: nil,
                    need: need, group: group, lastActivity: nil, fingerprint: "f")
}

private func ops(_ items: [WorkItem], _ state: LocalState = LocalState()) -> [TickTickSync.Op] {
    TickTickSync.operations(items: items, state: state, now: now)
}

private let docketTitle = TickTickSync.title(item(.myPRs))

private func synced(due: Date?) -> LocalState {
    var state = LocalState()
    state.tickTick["gh:n8n-io/n8n#40339"] = SyncedTask(taskID: "t1", listID: "L", due: due, title: docketTitle)
    return state
}

@Suite("TickTick sync")
struct TickTickSyncTests {
    @Test("a task links by PR URL, PR shorthand or ticket ID in its title or content")
    func references() {
        #expect(Todo(id: "1", projectId: "L", title: "check NODE-6181 #docket").references == ["NODE-6181"])
        #expect(Todo(id: "1", projectId: "L", title: "x", content: "https://github.com/n8n-io/n8n/pull/41054").references == ["n8n#41054"])
        #expect(Todo(id: "1", projectId: "L", title: "look at n8n-io/n8n#41054 and n8n#40322").references == ["n8n#41054", "n8n#40322"])
        #expect(Todo(id: "1", projectId: "L", title: "buy milk").references.isEmpty)
    }

    @Test("linked tasks join their item; others are to-dos, snoozed when due after today")
    func linking() {
        var input = Fixtures.input()
        input.now = now
        input.todos = [Todo(id: "a", projectId: "L", title: "ping about n8n#40339"),
                       Todo(id: "b", projectId: "L", title: "buy milk", dueDate: today),
                       Todo(id: "c", projectId: "L", title: "dentist", dueDate: nextWeek),
                       Todo(id: "d", projectId: "L", title: "untagged and unlinked", tags: [])]
        let items = Merge.items(input)
        #expect(items.first { $0.pullRequests.contains { $0.number == 40339 } }?.todo?.id == "a")
        #expect(items.first { $0.id == "todo:b" }?.group == .todos)
        #expect(items.first { $0.id == "todo:c" }?.group == .snoozed)
        #expect(items.first { $0.id == "todo:a" } == nil)
        #expect(items.first { $0.id == "todo:d" } == nil, "untagged tasks only count when they link")
    }

    @Test("needs me → a new task due today with the links; nothing more while it stays so")
    func create() {
        #expect(ops([item(.myPRs)]) == [.create(itemID: "gh:n8n-io/n8n#40339", title: docketTitle,
                                                content: Fixtures.pr(40339).url, due: today)])
        #expect(ops([item(.myPRs)], synced(due: today)).isEmpty)
        #expect(ops([item(.waiting)]).isEmpty, "nothing is created for items that wait on others")
    }

    @Test("titles start with the action and drop the conventional-commit prefix; a new action renames Docket's task, not the user's")
    func titles() {
        var pr = item(.myPRs)
        pr.title = "feat(editor): Set up Microsoft Teams again (no-changelog)"
        pr.need.headline = "Address feedback"
        #expect(TickTickSync.title(pr) == "Address feedback: Set up Microsoft Teams again")
        #expect(ops([pr], synced(due: today)) == [.setDue(itemID: pr.id, task: SyncedTask(taskID: "t1", listID: "L", due: today, title: docketTitle),
                                                          due: today, title: "Address feedback: Set up Microsoft Teams again")])
        var adopted = synced(due: today)
        adopted.tickTick[pr.id]?.adopted = true
        #expect(ops([pr], adopted).isEmpty)
    }

    @Test("waiting or gone → completed; needs me again → the same task reopens, due today")
    func completeAndReopen() {
        let task = SyncedTask(taskID: "t1", listID: "L", due: today, title: docketTitle)
        #expect(ops([item(.waiting)], synced(due: today)) == [.complete(itemID: "gh:n8n-io/n8n#40339", task: task)])
        #expect(ops([], synced(due: today)) == [.complete(itemID: "gh:n8n-io/n8n#40339", task: task)])
        #expect(ops([item(.waiting)], synced(due: nil)).isEmpty)
        #expect(ops([item(.myPRs)], synced(due: nil)) == [.setDue(itemID: "gh:n8n-io/n8n#40339", task: SyncedTask(taskID: "t1", listID: "L", due: nil, title: docketTitle), due: today, title: docketTitle)])
    }

    @Test("snooze moves the due date; waking early brings it back to today; overdue dates stay")
    func snooze() {
        var state = synced(due: today)
        state.marks["gh:n8n-io/n8n#40339"] = .init(mark: .snoozed(until: nextWeek.addingTimeInterval(8 * 3600)), fingerprint: "f")
        #expect(ops([item(.snoozed)], state) == [.setDue(itemID: "gh:n8n-io/n8n#40339", task: SyncedTask(taskID: "t1", listID: "L", due: today, title: docketTitle), due: nextWeek, title: docketTitle)])
        #expect(ops([item(.myPRs)], synced(due: nextWeek)).map(\.itemID) == ["gh:n8n-io/n8n#40339"])
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        #expect(ops([item(.myPRs)], synced(due: yesterday)).isEmpty, "a task completed or re-dated in TickTick is left alone")
    }

    @Test("a #docket task the user made for an item is adopted instead of creating another")
    func adopt() {
        var linked = item(.myPRs)
        linked.todo = Todo(id: "u1", projectId: "P", title: "n8n#40339", dueDate: nextWeek)
        #expect(ops([linked]) == [.adopt(itemID: linked.id, task: SyncedTask(taskID: "u1", listID: "P", due: nextWeek, adopted: true))])
        linked.todo?.dueDate = nil
        #expect(ops([linked]).count == 2, "an undated task is adopted and given today")
        #expect(ops([item(.myPRs, id: "orca:w"), item(.todos, id: "todo:x")]).isEmpty, "agent-only items and to-dos are not mirrored")
    }

    @MainActor
    @Test("the engine mirrors items, reads them back linked, and never writes after a failed source")
    func engine() async throws {
        let tickTick = FakeTickTick()
        let engine = InboxEngine(store: LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                                 github: FakeGitHub(result: .failure(.message("down"))), linear: FakeLinear(), linearKey: { nil },
                                 tickTick: tickTick, tickTickKey: { "token" }, harness: FakeHarness(), now: { now })
        engine.update { $0.tickTickListID = "L" }
        await engine.refreshTickTick()
        await engine.refreshLinear()
        await engine.refreshGitHub()
        try await Task.sleep(for: .milliseconds(100))
        #expect(tickTick.writes.isEmpty, "GitHub failed, so nothing is written")

        engine.githubSource = FakeGitHub()
        await engine.refreshGitHub()
        for _ in 0..<50 where engine.todos.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let needing = engine.items.filter { !$0.id.hasPrefix("orca:") && ![.waiting, .waitingForInput, .snoozed, .todos].contains($0.group) }
        #expect(!needing.isEmpty)
        #expect(tickTick.writes.count == needing.count)
        #expect(needing.allSatisfy { engine.state.tickTick[$0.id] != nil })
        #expect(engine.items.allSatisfy { $0.group != .todos }, "the mirrored tasks link back to their items")

        let first = try #require(needing.first)
        engine.mark(first, .done)
        for _ in 0..<50 where !tickTick.writes.contains(where: { $0.hasPrefix("complete") }) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(tickTick.writes.last == "complete \(engine.state.tickTick[first.id]?.taskID ?? "")")
    }
}

@Suite("TickTick source, live")
struct TickTickLiveTests {
    @Test("live: create, re-date, complete and reopen a task",
          .enabled(if: ProcessInfo.processInfo.environment["DOCKET_LIVE"] == "1" && ProcessInfo.processInfo.environment["TICKTICK_TOKEN"] != nil))
    func roundTrip() async throws {
        let token = ProcessInfo.processInfo.environment["TICKTICK_TOKEN"]!
        let source = TickTickSource()
        let lists = try await source.lists(token: token)
        let list = try #require(lists.first { $0.id == ProcessInfo.processInfo.environment["TICKTICK_LIST"] } ?? lists.first)
        let task = try await source.create(title: "Docket live test", content: "https://github.com/n8n-io/n8n/pull/1", listID: list.id, due: today, token: token)
        #expect(try await source.todos(token: token).map(\.id).contains(task.id))
        try await source.setDue(nextWeek, title: "Docket live test, renamed", taskID: task.id, listID: list.id, token: token)
        try await source.complete(taskID: task.id, listID: list.id, token: token)
        #expect(try await !source.todos(token: token).map(\.id).contains(task.id))
        try await source.setDue(today, title: nil, taskID: task.id, listID: list.id, token: token)
        let open = try await source.todos(token: token)
        let reopened = try #require(open.first { $0.id == task.id }, "update with status 0 reopens")
        #expect(Calendar.current.isDate(reopened.dueDate ?? .distantPast, inSameDayAs: today))
        try await source.complete(taskID: task.id, listID: list.id, token: token)
    }
}
