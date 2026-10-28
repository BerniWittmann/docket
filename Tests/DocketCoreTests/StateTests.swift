import Testing
import Foundation
@testable import DocketCore

private var item: WorkItem { Merge.items(Fixtures.input()).first { $0.id == "linear:NODE-6114" }! }
private func withActivity(_ item: WorkItem) -> WorkItem {
    var changed = item
    changed.fingerprint += "|new"
    return changed
}
private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()
private func local(_ s: String) -> Date {
    try! Date.ISO8601FormatStyle(timeZone: berlin.timeZone).parse(s)
}

@Suite("Local state and settings")
struct StateTests {
    @Test("fact 35: settings and marks survive a restart")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalStore(directory: dir)
        #expect(store.isFirstRun)

        var settings = store.loadSettings()
        settings.repos = ["n8n-io/n8n", "acme/*"]
        settings.theme = .n8n
        settings.work[WorkKind.review.rawValue]?.prompt = "/custom {url}"
        settings.workHours.start = 9 * 60
        try store.save(settings)

        var state = LocalState()
        state.mark(item, .snoozed(until: .iso("2030-01-01T08:00:00Z")))
        state.mark(withActivity(item), .notMine)
        state.marks["gh:other"] = .init(mark: .done, fingerprint: "x")
        state.notified.insert("key")
        try store.save(state)

        let reopened = LocalStore(directory: dir)
        #expect(!reopened.isFirstRun)
        #expect(reopened.loadSettings() == settings)
        #expect(reopened.loadState() == state)
    }

    @Test("settings files missing newer keys still load with defaults")
    func partialSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"theme":"n8n"}"#.utf8).write(to: dir.appending(path: "settings.json"))
        let settings = LocalStore(directory: dir).loadSettings()
        #expect(settings.theme == .n8n)
        #expect(settings.repos == ["n8n-io/*"])
    }

    @Test("fact 8: repos default to n8n-io/* and map to search qualifiers")
    func repos() {
        var settings = Settings()
        #expect(settings.repos == ["n8n-io/*"])
        #expect(settings.searchScope == "org:n8n-io")
        settings.repos = ["n8n-io/n8n", "acme/*", " "]
        #expect(settings.searchScope == "repo:n8n-io/n8n org:acme")
    }

    @Test("fact 33: snooze moves the item to Snoozed until it expires")
    func snoozeExpiry() {
        var state = LocalState()
        let now = Date.iso("2026-10-09T10:00:00Z")
        state.mark(item, .snoozed(until: SnoozeOption.oneHour.date(from: now, hours: WorkHours())))
        #expect(state.apply(to: [item], now: now).first?.group == .snoozed)
        #expect(state.isSilenced(item, now: now))

        let later = now.addingTimeInterval(3601)
        #expect(state.apply(to: [item], now: later).first?.group == item.need.group)
        #expect(state.marks.isEmpty)
    }

    @Test("fact 33: new activity wakes a snooze early")
    func snoozeWake() {
        var state = LocalState()
        state.mark(item, .snoozed(until: .distantFuture))
        let woken = state.apply(to: [withActivity(item)])
        #expect(woken.first?.group == item.need.group)
        #expect(state.marks.isEmpty)
        #expect(!state.isSilenced(withActivity(item)))
    }

    @Test("fact 33: snooze options")
    func snoozeOptions() {
        let friday = local("2026-10-09T15:30:00+02:00")
        let hours = WorkHours()
        #expect(SnoozeOption.oneHour.date(from: friday, hours: hours, calendar: berlin) == local("2026-10-09T16:30:00+02:00"))
        #expect(SnoozeOption.tomorrow.date(from: friday, hours: hours, calendar: berlin) == local("2026-10-10T08:00:00+02:00"))
        #expect(SnoozeOption.nextWeek.date(from: friday, hours: hours, calendar: berlin) == local("2026-10-12T08:00:00+02:00"))
        let picked = local("2026-11-01T12:00:00+01:00")
        #expect(SnoozeOption.until(picked).date(from: friday, hours: hours, calendar: berlin) == picked)
    }

    @Test("fact 34: done hides until new activity; not mine hides for good")
    func doneAndNotMine() {
        var state = LocalState()
        state.mark(item, .done)
        #expect(state.apply(to: [item]).isEmpty)
        #expect(state.isSilenced(item))
        #expect(state.apply(to: [withActivity(item)]).count == 1)
        #expect(state.marks.isEmpty)

        state.mark(item, .notMine)
        #expect(state.apply(to: [withActivity(item)]).isEmpty)
        #expect(state.isSilenced(withActivity(item)))
    }

    @Test("fact 37: work hours default to Mon–Fri 8:00–18:00")
    func workHours() {
        let hours = WorkHours()
        #expect(hours.contains(local("2026-10-09T17:59:00+02:00"), calendar: berlin))
        #expect(!hours.contains(local("2026-10-09T18:00:00+02:00"), calendar: berlin), "Friday 18:00 is outside")
        #expect(!hours.contains(local("2026-10-10T12:00:00+02:00"), calendar: berlin), "Saturday")
        #expect(!hours.contains(local("2026-10-12T07:59:00+02:00"), calendar: berlin))
        #expect(hours.contains(local("2026-10-12T08:00:00+02:00"), calendar: berlin), "Monday 8:00 is inside")
        #expect(hours.nextStart(after: local("2026-10-09T18:00:00+02:00"), calendar: berlin) == local("2026-10-12T08:00:00+02:00"))

        var custom = WorkHours()
        custom.days = [1, 7]
        custom.start = 10 * 60
        #expect(custom.contains(local("2026-10-10T10:00:00+02:00"), calendar: berlin))
        #expect(!custom.contains(local("2026-10-09T12:00:00+02:00"), calendar: berlin))
    }

    @Test("fact 38: notification toggle defaults")
    func notificationDefaults() {
        let settings = Settings()
        for on in [EventKind.agentNeedsMe, .agentResultUnread, .newReview, .humanFeedback, .reviewBotFeedback] {
            #expect(settings.notifies(on))
        }
        #expect(!settings.notifies(.ciFailed))
        #expect(!settings.notifies(.readyToMerge))
    }

    @Test("facts 28–31: per-kind agent, prompt and automation defaults, all editable")
    func workDefaults() {
        var settings = Settings()
        #expect(settings.work(.review).prompt == "/pr-review {url}")
        for kind in [WorkKind.feedback, .fixCI, .resolveConflict] {
            #expect(settings.work(kind).prompt == "/pr-review-feedback {url}")
        }
        #expect(settings.work(.startTicket).prompt == "/fix-ticket {ticket}")
        #expect(settings.work(.continueTicket).prompt == "Continue {ticket}: check the branch and the ticket, then propose the next step")
        #expect(WorkKind.allCases.allSatisfy { settings.work($0).agent == "claude" && settings.work($0).automation == .manual })

        settings.work[WorkKind.review.rawValue] = WorkSetting(agent: "codex", prompt: "review {repo}#{number}", automation: .prepare)
        #expect(settings.work(.review).agent == "codex")
        #expect(settings.work(.review).automation == .prepare)
    }

    @Test("fact 30: templates fill {url}, {ticket}, {number} and {repo}")
    func templates() {
        let filled = PromptTemplate.fill("{url} {ticket} {number} {repo}", item: item)
        #expect(filled == "https://github.com/n8n-io/n8n/pull/40339 NODE-6114 40339 n8n-io/n8n")
        let review = Merge.items(Fixtures.input()).first { $0.id == "gh:n8n-io/n8n#39679" }!
        #expect(PromptTemplate.fill("/pr-review {url}", item: review) == "/pr-review https://github.com/n8n-io/n8n/pull/39679")
    }
}
