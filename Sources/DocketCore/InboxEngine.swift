import Foundation
import Observation

public enum SourceKind: String, CaseIterable, Sendable, Identifiable {
    case github, linear, tickTick, orca
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .github: "GitHub"
        case .linear: "Linear"
        case .tickTick: "TickTick"
        case .orca: "Orca"
        }
    }
}

/// Merges the sources into ranked work items and applies local state.
@MainActor
@Observable
public final class InboxEngine {
    public private(set) var settings: Settings
    public private(set) var state: LocalState
    public private(set) var status: [SourceKind: SourceStatus] = [:]
    public private(set) var items: [WorkItem] = []
    public private(set) var github: GitHubInbox?
    public private(set) var linear: LinearInbox?
    /// Other people's tickets named by PR branches.
    public private(set) var contextTickets: [Ticket] = []
    @ObservationIgnored private var lookedUp: Set<String> = []
    public private(set) var workspaces: [Workspace] = []
    /// Open #docket tasks.
    public private(set) var todos: [Todo] = []
    /// The last Start work or harness failure, for the UI to show.
    public var actionError: String?

    @ObservationIgnored public var githubSource: GitHubFetching
    @ObservationIgnored public var linearSource: LinearFetching
    @ObservationIgnored public var linearKey: @Sendable () -> String?
    @ObservationIgnored public var tickTickSource: TickTickSyncing
    @ObservationIgnored public var tickTickKey: @Sendable () -> String?
    @ObservationIgnored public var harness: Harness
    /// Receives new notification events.
    @ObservationIgnored public var deliver: (@MainActor ([InboxEvent]) -> Void)?
    /// On the very first run, existing events are recorded without notifying.
    @ObservationIgnored var seeding: Bool
    @ObservationIgnored let store: LocalStore
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var pollers: [Task<Void, Never>] = []
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var syncAgain = false

    public init(store: LocalStore = LocalStore(), github: GitHubFetching = GitHubSource(),
                linear: LinearFetching = LinearSource(), linearKey: @escaping @Sendable () -> String? = { Keychain.read() },
                tickTick: TickTickSyncing = TickTickSource(),
                tickTickKey: @escaping @Sendable () -> String? = { Keychain.read(service: Keychain.tickTickService) },
                harness: Harness = OrcaHarness(), now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.githubSource = github
        self.linearSource = linear
        self.linearKey = linearKey
        self.tickTickSource = tickTick
        self.tickTickKey = tickTickKey
        self.harness = harness
        self.now = now
        seeding = store.isFirstRun
        settings = store.loadSettings()
        state = store.loadState()
        status = [.github: .loading, .linear: .loading, .tickTick: .loading, .orca: .loading]
        applyOrcaPath()
    }

    public func items(in group: InboxGroup) -> [WorkItem] {
        Ranking.sorted(items.filter { $0.group == group })
    }

    // MARK: Polling

    public static let githubInterval: TimeInterval = 120
    public static let linearInterval: TimeInterval = 120
    public static let tickTickInterval: TimeInterval = 120
    public static let orcaInterval: TimeInterval = 10

    public func start() {
        guard pollers.isEmpty else { return }
        pollers = [Task { [weak self] in
            // Concurrently, so a slow source does not hold up the others.
            async let orca: Void? = self?.refreshOrca()
            async let linear: Void? = self?.refreshLinear()
            async let github: Void? = self?.refreshGitHub()
            async let tickTick: Void? = self?.refreshTickTick()
            _ = await (orca, linear, github, tickTick)
            self?.seeding = false
            self?.pollers += [
                self?.poll(every: Self.linearInterval) { await $0.refreshLinear() },
                self?.poll(every: Self.githubInterval) { await $0.refreshGitHub() },
                self?.poll(every: Self.tickTickInterval) { await $0.refreshTickTick() },
                self?.poll(every: Self.orcaInterval) { await $0.refreshOrca() },
            ].compactMap { $0 }
        }]
    }

    public func stop() {
        pollers.forEach { $0.cancel() }
        pollers = []
    }

    public func refreshAll() async {
        await refreshOrca()
        await refreshLinear()
        await refreshGitHub()
        await refreshTickTick()
    }

    private func poll(every interval: TimeInterval, _ body: @escaping @MainActor (InboxEngine) async -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                await body(self)
            }
        }
    }

    public func refreshGitHub() async {
        do {
            github = try await githubSource.fetch(scope: settings.searchScope, extraURLs: attachedPRURLs)
            status[.github] = .ok(now())
        } catch {
            status[.github] = .error(error.localizedDescription)
        }
        recompute()
        if !Set(contextTicketIDs).isSubset(of: lookedUp) { await refreshContextTickets() }
    }

    public func refreshLinear() async {
        // Off the main actor: the Keychain may show an access prompt and block the caller.
        let readKey = linearKey
        guard let key = await Task.detached(operation: { readKey() }).value else {
            linear = nil
            status[.linear] = .notConnected
            recompute()
            return
        }
        do {
            linear = try await linearSource.fetch(key: key)
            status[.linear] = .ok(now())
            await refreshContextTickets(key: key)
        } catch {
            status[.linear] = .error(error.localizedDescription)
        }
        recompute()
        let known = Set(github?.pullRequests.map { Merge.normalize($0.url) } ?? [])
        if github != nil && !attachedPRURLs.allSatisfy({ known.contains(Merge.normalize($0)) }) { await refreshGitHub() }
    }

    public func refreshOrca() async {
        do {
            workspaces = try await harness.listWorkspaces()
            status[.orca] = .ok(now())
        } catch {
            status[.orca] = .error(error.localizedDescription)
        }
        recompute()
        if !Set(contextTicketIDs).isSubset(of: lookedUp) { await refreshContextTickets() }
    }

    public func refreshTickTick() async {
        let readKey = tickTickKey
        guard let token = await Task.detached(operation: { readKey() }).value else {
            todos = []
            status[.tickTick] = .notConnected
            recompute()
            return
        }
        do {
            todos = try await tickTickSource.todos(token: token)
            status[.tickTick] = .ok(now())
        } catch {
            status[.tickTick] = .error(error.localizedDescription)
        }
        recompute()
    }

    /// Ticket IDs in PR and workspace branches that are not my tickets.
    var contextTicketIDs: [String] {
        let mine = Set(linear?.tickets.map(\.identifier) ?? [])
        let named = (github?.pullRequests ?? []).compactMap(\.ticketID) + workspaces.compactMap(\.ticketID)
        return Array(Set(named).subtracting(mine)).sorted()
    }

    /// Looks up the tickets other people's PRs name. A failure leaves the items without context and is not an error state.
    func refreshContextTickets(key: String? = nil) async {
        let ids = contextTicketIDs
        let readKey = linearKey
        guard !ids.isEmpty, let key = await Task.detached(operation: { key ?? readKey() }).value else { return }
        lookedUp.formUnion(ids)
        if let tickets = try? await linearSource.lookup(identifiers: ids, key: key) {
            contextTickets = tickets
            recompute()
        }
    }

    /// PRs attached to my tickets. GitHub looks them up by URL, since search misses merged PRs and PRs that are not mine.
    var attachedPRURLs: [String] {
        let attached = (linear?.tickets ?? []).flatMap(\.attachmentURLs).filter { $0.contains("github.com/") && $0.contains("/pull/") }
        return Array(Set(attached)).sorted()
    }

    // MARK: Items

    func recompute() {
        var input = InboxInput(viewer: github?.viewer, pullRequests: github?.pullRequests ?? [],
                               tickets: linear?.tickets ?? [], contextTickets: contextTickets,
                               workspaces: workspaces, bots: settings.bots)
        input.waitingStates = settings.waitingStates
        input.todos = todos
        input.now = now()
        let before = state
        items = state.apply(to: Merge.items(input), now: now())
        if seeding {
            for item in items { if let kind = item.need.event { state.notified.insert(InboxEvent.key(item, kind)) } }
        } else {
            let events = NotificationFilter.events(for: items, settings: settings, state: &state, now: now())
            if !events.isEmpty { deliver?(events) }
        }
        if state != before { saveState() }
        prepareNewItems()
        scheduleSync()
    }

    // MARK: TickTick

    /// Runs one sync at a time; changes that arrive meanwhile run another round.
    func scheduleSync() {
        guard !syncing else { syncAgain = true; return }
        syncing = true
        Task {
            repeat {
                syncAgain = false
                await syncTickTick()
            } while syncAgain
            syncing = false
        }
    }

    /// Writes only after every source answered, so items missing because of an outage never complete tasks.
    var canSync: Bool {
        guard settings.tickTickListID != nil, case .ok = status[.tickTick], case .ok = status[.github] else { return false }
        switch status[.linear] {
        case .ok, .notConnected: return true
        default: return false
        }
    }

    func syncTickTick() async {
        let readKey = tickTickKey
        guard canSync, let listID = settings.tickTickListID,
              let token = await Task.detached(operation: { readKey() }).value else { return }
        var wrote = false
        for op in TickTickSync.operations(items: items, state: state, now: now()) {
            do {
                switch op {
                case .create(let id, let title, let content, let due):
                    let todo = try await tickTickSource.create(title: title, content: content, listID: listID, due: due, token: token)
                    state.tickTick[id] = SyncedTask(taskID: todo.id, listID: todo.projectId, due: due, title: title)
                case .adopt(let id, let task):
                    state.tickTick[id] = task
                case .setDue(let id, var task, let due, let title):
                    try await tickTickSource.setDue(due, title: title, taskID: task.taskID, listID: task.listID, token: token)
                    task.due = due
                    if let title { task.title = title }
                    state.tickTick[id] = task
                case .complete(let id, let task):
                    try await tickTickSource.complete(taskID: task.taskID, listID: task.listID, token: token)
                    state.tickTick[id]?.due = nil
                }
            } catch TickTickError.notFound {
                state.tickTick[op.itemID] = nil
            } catch {
                status[.tickTick] = .error("Sync failed: \(error.localizedDescription)")
                break
            }
            wrote = true
        }
        TickTickSync.prune(&state, items: items)
        saveState()
        // Reads the new tasks back, so they link to their items.
        if wrote { await refreshTickTick() }
    }

    public func tickTickLists() async throws -> [TickTickList] {
        let readKey = tickTickKey
        guard let token = await Task.detached(operation: { readKey() }).value else { return [] }
        return try await tickTickSource.lists(token: token)
    }

    /// Done on a to-do completes it in TickTick.
    public func complete(_ todo: Todo) async {
        await writeTodo { try await $0.complete(taskID: todo.id, listID: todo.projectId, token: $1) }
    }

    /// Snoozing a to-do moves its due date; it shows under Snoozed until then.
    public func reschedule(_ todo: Todo, to day: Date) async {
        await writeTodo { try await $0.setDue(day, title: nil, taskID: todo.id, listID: todo.projectId, token: $1) }
    }

    private func writeTodo(_ write: (TickTickSyncing, String) async throws -> Void) async {
        let readKey = tickTickKey
        guard let token = await Task.detached(operation: { readKey() }).value else { return }
        do {
            try await write(tickTickSource, token)
            actionError = nil
        } catch {
            actionError = "TickTick: \(error.localizedDescription)"
        }
        await refreshTickTick()
    }

    // MARK: Harness actions

    /// Starts the configured agent for the item's kind of work, reusing its workspace when there is one.
    public func startWork(_ item: WorkItem) async {
        guard let kind = item.need.kind,
              let ref = WorkRef(item: item, viewer: github?.viewer, ticketRepo: settings.ticketRepo) else { return }
        let work = settings.work(kind)
        do {
            let existing = kind == .continueTicket ? try await harness.findWorkspace(for: ref) : nil
            if let workspace = item.workspace ?? existing, kind == .continueTicket {
                try await harness.open(workspace)
            } else {
                try await harness.startWork(ref, agent: work.agent, prompt: PromptTemplate.fill(work.prompt, item: item))
            }
            actionError = nil
        } catch {
            actionError = "Start work failed: \(error.localizedDescription)"
        }
        await refreshOrca()
    }

    public func open(_ workspace: Workspace) async {
        do {
            try await harness.open(workspace)
        } catch {
            actionError = "Opening the workspace failed: \(error.localizedDescription)"
        }
    }

    /// Prepare automation: creates worktrees for new items without starting an agent, only inside work hours.
    func prepareNewItems() {
        guard settings.workHours.contains(now()), case .ok = status[.orca] else { return }
        for item in items where item.workspace == nil && item.group != .snoozed && !state.prepared.contains(item.id) {
            guard let kind = item.need.kind, settings.work(kind).automation == .prepare,
                  let ref = WorkRef(item: item, viewer: github?.viewer, ticketRepo: settings.ticketRepo) else { continue }
            state.prepared.insert(item.id)
            saveState()
            Task {
                do {
                    try await harness.startWork(ref, agent: nil, prompt: nil)
                } catch {
                    actionError = "Prepare failed for \(item.title): \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Local actions

    public func mark(_ item: WorkItem, _ mark: LocalState.Mark) {
        // A to-do lives in TickTick: Done completes it there and Snooze moves its due date.
        if item.id.hasPrefix("todo:"), let todo = item.todo {
            switch mark {
            case .done: Task { await complete(todo) }; return
            case .snoozed(let until): Task { await reschedule(todo, to: until) }; return
            case .notMine: break
            }
        }
        state.mark(item, mark)
        saveState()
        recompute()
    }

    public func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let scopeChanged = next.searchScope != settings.searchScope || next.bots != settings.bots
        let orcaChanged = next.orcaPath != settings.orcaPath
        settings = next
        if orcaChanged {
            applyOrcaPath()
            Task { await refreshOrca() }
        }
        try? store.save(settings)
        recompute()
        if scopeChanged { Task { await refreshGitHub() } }
    }

    func saveState() { try? store.save(state) }

    /// Points the Orca harness at the configured CLI, falling back to the bundled one.
    private func applyOrcaPath() {
        guard var orca = harness as? OrcaHarness else { return }
        orca.orcaPath = OrcaHarness.locate(configured: settings.orcaPath) ?? orca.orcaPath
        harness = orca
    }
}
