import Testing
import Foundation
@testable import DocketCore

private let workday = Date.iso("2026-10-09T10:00:00Z")
private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func items() -> [WorkItem] {
    var agentWS = Fixtures.workspace(branch: "eng-slides-update")
    agentWS.agents = [AgentStatus(state: "waiting", stateStartedAt: workday)]
    var resultWS = Fixtures.workspace(branch: "automation-mining")
    resultWS.unread = true
    var ciPR = Fixtures.pr(40339)
    ciPR.checks = "FAILURE"
    var readyPR = Fixtures.pr(5482)
    readyPR.reviewDecision = "APPROVED"
    var humanPR = Fixtures.pr(40322)
    humanPR.events.append(PREvent(kind: .comment, actor: Person(login: "user-9"), at: workday))
    let prs = [Fixtures.pr(39679), Fixtures.botFeedbackPR, ciPR, readyPR, humanPR]
    return Merge.items(InboxInput(viewer: Fixtures.viewer, pullRequests: prs, tickets: [],
                                  workspaces: [agentWS, resultWS], bots: .defaults))
}

private func events(_ items: [WorkItem], settings: Settings = Settings(), state: inout LocalState, at now: Date = workday) -> [EventKind: String] {
    let events = NotificationFilter.events(for: items, settings: settings, state: &state, now: now, calendar: berlin)
    return Dictionary(events.map { ($0.kind, $0.itemID) }, uniquingKeysWith: { a, _ in a })
}

@Suite("Notifications")
struct NotificationTests {
    @Test("fact 38–39: default toggles notify agents, reviews, human and review-bot feedback, not CI or ready to merge")
    func defaults() {
        var state = LocalState()
        let sent = events(items(), state: &state)
        #expect(Set(sent.keys) == [.agentNeedsMe, .agentResultUnread, .newReview, .humanFeedback, .reviewBotFeedback])

        var settings = Settings()
        settings.notifications[EventKind.ciFailed.rawValue] = true
        settings.notifications[EventKind.readyToMerge.rawValue] = true
        settings.notifications[EventKind.newReview.rawValue] = false
        var fresh = LocalState()
        let custom = events(items(), settings: settings, state: &fresh)
        #expect(custom[.ciFailed] == "gh:n8n-io/n8n#40339")
        #expect(custom[.readyToMerge] == "gh:n8n-io/n8n-docs#5482")
        #expect(custom[.newReview] == nil)
    }

    @Test("fact 37: nothing fires outside work hours, and it fires once work hours begin")
    func workHours() {
        var state = LocalState()
        #expect(events(items(), state: &state, at: .iso("2026-10-09T17:00:00Z")).isEmpty, "19:00 in Berlin")
        #expect(events(items(), state: &state, at: .iso("2026-10-10T10:00:00Z")).isEmpty, "Saturday")
        #expect(!events(items(), state: &state, at: .iso("2026-10-12T06:00:00Z")).isEmpty, "Monday 8:00 in Berlin")
    }

    @Test("fact 40: each event notifies at most once, and again only after new activity")
    func once() {
        var state = LocalState()
        #expect(!events(items(), state: &state).isEmpty)
        #expect(events(items(), state: &state).isEmpty)

        var changed = items()
        changed[0].fingerprint += "|new"
        #expect(events(changed, state: &state).count == 1)
    }

    @Test("fact 40: snoozed, done and not-mine items stay silent")
    func silenced() {
        let all = items()
        for mark in [LocalState.Mark.snoozed(until: .distantFuture), .done, .notMine] {
            var state = LocalState()
            for item in all { state.mark(item, mark) }
            #expect(events(all, state: &state).isEmpty, "\(mark)")
        }
    }

    @Test("agent events carry the workspace for Open in Orca")
    func agentWorkspace() {
        var state = LocalState()
        let all = NotificationFilter.events(for: items(), settings: Settings(), state: &state, now: workday, calendar: berlin)
        #expect(all.first { $0.kind == .agentNeedsMe }?.workspaceID != nil)
        #expect(all.first { $0.kind == .newReview }?.workspaceID == nil)
        #expect(all.first { $0.kind == .newReview }?.title == "Review #39679")
    }
}

@MainActor
@Suite("Engine notifications")
struct EngineNotificationTests {
    @Test("the first run records existing events silently; later runs deliver new ones")
    func seeding() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = InboxEngine(store: LocalStore(directory: dir), github: FakeGitHub(), linear: FakeLinear(), linearKey: { nil }, tickTickKey: { nil },
                                harness: FakeHarness(), now: { workday })
        var delivered: [InboxEvent] = []
        first.deliver = { delivered += $0 }
        first.seeding = true
        await first.refreshAll()
        #expect(delivered.isEmpty)
        #expect(!first.state.notified.isEmpty)

        let second = InboxEngine(store: LocalStore(directory: dir), github: FakeGitHub(), linear: FakeLinear(), linearKey: { nil }, tickTickKey: { nil },
                                 harness: FakeHarness(), now: { workday })
        #expect(!second.seeding)
        second.deliver = { delivered += $0 }
        await second.refreshAll()
        #expect(delivered.isEmpty, "already recorded")
    }
}
