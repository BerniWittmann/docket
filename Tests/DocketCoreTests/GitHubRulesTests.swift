import Testing
import Foundation
@testable import DocketCore

private let viewer = Fixtures.viewer
private func need(_ pr: PullRequest, bots: BotLists = .defaults) -> Need? {
    GitHubRules.need(for: pr, viewer: viewer, bots: bots)
}
private func comment(_ login: String, bot: Bool = false, at: String = "2026-10-09T10:00:00Z") -> PREvent {
    PREvent(kind: .comment, actor: Person(login: login, isBot: bot), at: .iso(at))
}

/// 40339: my PR, CI green, no feedback, one reviewer requested.
private var waitingPR: PullRequest { Fixtures.pr(40339) }

@Suite("GitHub rules")
struct GitHubRulesTests {
    @Test("fact 10: requested and not reviewed → Review #N")
    func review() {
        let n = need(Fixtures.pr(39679))
        #expect(n?.group == .reviews)
        #expect(n?.headline == "Review #39679")
        #expect(n?.kind == .review)
        #expect(n?.event == .newReview)
    }

    @Test("fact 11: pushes and replies after my review wait until the author re-requests me")
    func noReReviewWithoutRequest() {
        #expect(need(Fixtures.pr(36487)) == nil, "pushed after my review, never re-requested")

        var pr = Fixtures.pr(39679)
        pr.requestedReviewers.removeAll { $0 == viewer }
        pr.events.append(PREvent(kind: .review, actor: Person(login: viewer), at: .iso("2026-10-09T08:00:00Z"), reviewState: "CHANGES_REQUESTED"))
        pr.events.append(PREvent(kind: .commit, actor: nil, at: .iso("2026-10-09T09:00:00Z")))
        pr.events.append(comment(pr.author!.login, at: "2026-10-09T09:30:00Z"))
        #expect(need(pr) == nil)
    }

    @Test("fact 11: re-requested after my review → Re-review #N, waiting since the request")
    func reReview() {
        var pr = Fixtures.pr(39679)
        pr.events.append(PREvent(kind: .review, actor: Person(login: viewer), at: .iso("2026-10-09T08:00:00Z"), reviewState: "APPROVED"))
        pr.events.append(PREvent(kind: .commit, actor: nil, at: .iso("2026-10-09T09:00:00Z")))
        pr.events.append(PREvent(kind: .reviewRequested, actor: nil, at: .iso("2026-10-09T09:30:00Z"), subject: viewer))
        #expect(need(pr)?.headline == "Re-review #39679")
        #expect(need(pr)?.since == .iso("2026-10-09T09:30:00Z"))
        #expect(need(pr)?.event == .newReview)
    }

    @Test("fact 12 + 39: review-bot unresolved threads → Address feedback, review-bot event")
    func reviewBotFeedback() {
        let n = need(Fixtures.botFeedbackPR)
        #expect(n?.group == .myPRs)
        #expect(n?.headline == "Address feedback")
        #expect(n?.kind == .feedback)
        #expect(n?.event == .reviewBotFeedback)
    }

    @Test("fact 12: a human comment after my last activity → Address feedback, human event")
    func humanComment() {
        var pr = waitingPR
        pr.events.append(comment("user-9"))
        #expect(need(pr)?.headline == "Address feedback")
        #expect(need(pr)?.event == .humanFeedback)
    }

    @Test("fact 12: a human change request → Address feedback")
    func humanChangesRequested() {
        var pr = waitingPR
        pr.reviewDecision = "CHANGES_REQUESTED"
        pr.requestedReviewers = []
        pr.events.append(PREvent(kind: .review, actor: Person(login: "user-9"), at: .iso("2026-10-09T10:00:00Z"), reviewState: "CHANGES_REQUESTED"))
        pr.events.append(PREvent(kind: .commit, actor: nil, at: .iso("2026-10-09T11:00:00Z")))
        #expect(need(pr)?.headline == "Address feedback", "a change request stands until re-requested")
    }

    @Test("fact 12: a review-bot change request → Address feedback")
    func botChangesRequested() {
        var pr = waitingPR
        pr.events.append(PREvent(kind: .review, actor: Person(login: "aikido-pr-checks", isBot: true), at: .iso("2026-10-09T10:00:00Z"), reviewState: "CHANGES_REQUESTED"))
        #expect(need(pr)?.headline == "Address feedback")
        #expect(need(pr)?.event == .reviewBotFeedback)
    }

    @Test("fact 12: an unresolved thread I answered last is not feedback")
    func answeredThread() {
        var pr = waitingPR
        pr.threads = [ReviewThread(isResolved: false, lastAuthor: Person(login: viewer), lastAt: .iso("2026-10-09T10:00:00Z"))]
        #expect(need(pr)?.group == .waiting)
        pr.threads = [ReviewThread(isResolved: false, lastAuthor: Person(login: "user-9"), lastAt: .iso("2026-10-09T10:00:00Z"))]
        #expect(need(pr)?.headline == "Address feedback")
    }

    @Test("fact 12: an unresolved thread I pushed after waits for the reviewer (41010)")
    func pushedAfterThread() {
        var pr = waitingPR
        let at = Date.iso("2026-10-09T10:00:00Z")
        pr.threads = [ReviewThread(isResolved: false, lastAuthor: Person(login: "cubic-dev-ai", isBot: true), lastAt: at)]
        #expect(need(pr)?.headline == "Address feedback")
        pr.events.append(PREvent(kind: .commit, actor: nil, at: at.addingTimeInterval(60)))
        #expect(need(pr)?.group == .waiting)
    }

    @Test("fact 13: every change-requester re-requested → Waiting")
    func reRequested() {
        let n = need(Fixtures.pr(40322))
        #expect(n?.group == .waiting)
        #expect(n?.headline == "Re-review requested from @user-2")

        var pr = Fixtures.pr(40322)
        pr.requestedReviewers = []
        #expect(need(pr)?.headline == "Address feedback", "not re-requested any more")
    }

    @Test("fact 12–13: a re-requested reviewer commenting after my last activity is feedback again")
    func reRequestedReviewerAsks() {
        var pr = Fixtures.pr(40322)
        pr.events.append(comment("user-2", at: "2026-10-09T11:48:56Z"))
        #expect(need(pr)?.headline == "Address feedback")
        #expect(need(pr)?.event == .humanFeedback)
        #expect(need(pr)?.since == .iso("2026-10-09T11:48:56Z"))
    }

    @Test("fact 14: noise bots never affect status")
    func noiseBots() {
        for bot in ["codecov", "github-actions", "cla-bot", "dependabot[bot]", "n8n-assistant"] {
            var pr = waitingPR
            pr.events.append(comment(bot, bot: true))
            pr.threads.append(ReviewThread(isResolved: false, lastAuthor: Person(login: bot, isBot: true), lastAt: .iso("2026-10-09T10:00:00Z")))
            #expect(need(pr)?.group == .waiting, "\(bot) should be ignored")
        }
    }

    @Test("fact 14: review bots affect status, and both lists are editable")
    func editableBotLists() {
        var pr = waitingPR
        pr.events.append(comment("cubic-dev-ai", bot: true))
        #expect(need(pr)?.headline == "Address feedback")

        var codecov = waitingPR
        codecov.events.append(comment("codecov", bot: true))
        let bots = BotLists(reviewBots: ["codecov"], noiseBots: ["cubic-dev-ai"])
        #expect(need(codecov, bots: bots)?.headline == "Address feedback")
        #expect(need(pr, bots: bots)?.group == .waiting)
    }

    @Test("fact 14: a review bot's plain review summary on a push is not feedback")
    func botReviewSummary() {
        var pr = waitingPR
        pr.events.append(PREvent(kind: .review, actor: Person(login: "cubic-dev-ai", isBot: true), at: .iso("2026-10-09T10:00:00Z"), reviewState: "COMMENTED"))
        #expect(need(pr)?.group == .waiting)
    }

    @Test("fact 15: failing CI or a conflict → Fix CI / Resolve conflict")
    func ciAndConflict() {
        var ci = waitingPR
        ci.checks = "FAILURE"
        #expect(need(ci)?.headline == "Fix CI")
        #expect(need(ci)?.group == .myPRs)
        #expect(need(ci)?.kind == .fixCI)
        #expect(need(ci)?.event == .ciFailed)

        var conflict = waitingPR
        conflict.mergeable = "CONFLICTING"
        #expect(need(conflict)?.headline == "Resolve conflict")
        #expect(need(conflict)?.kind == .resolveConflict)
    }

    @Test("fact 16: approved and mergeable → Ready to merge")
    func readyToMerge() {
        var pr = waitingPR
        pr.reviewDecision = "APPROVED"
        #expect(need(pr)?.headline == "Ready to merge")
        #expect(need(pr)?.group == .myPRs)
        #expect(need(pr)?.event == .readyToMerge)
        pr.mergeable = "UNKNOWN"
        #expect(need(pr)?.group == .waiting)
    }

    @Test("fact 17: waiting for review with nothing to do → Waiting")
    func waiting() {
        #expect(need(waitingPR)?.group == .waiting)
        #expect(need(waitingPR)?.headline == "Waiting for review")
        #expect(need(Fixtures.pr(5482))?.group == .waiting)
    }

    @Test("PRs I am only involved in, with nothing new, are hidden")
    func hidden() {
        #expect(need(Fixtures.pr(39878)) == nil)
        var merged = waitingPR
        merged.state = .merged
        #expect(need(merged) == nil)
    }

    @Test("decodes every searched PR once, with the viewer")
    func decoding() {
        let inbox = Fixtures.github
        #expect(inbox.viewer == viewer)
        #expect(inbox.pullRequests.count == 14)
        #expect(Set(inbox.pullRequests.map(\.id)).count == inbox.pullRequests.count)
        let pr = Fixtures.pr(40322)
        #expect(pr.repo == "n8n-io/n8n")
        #expect(pr.headRef == "node-5998-ms-teams-use-icon-from-agent-in-manifest")
        #expect(pr.requestedReviewers == ["user-2"])
    }
}
