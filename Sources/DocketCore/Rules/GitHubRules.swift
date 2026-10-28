import Foundation

public struct BotLists: Codable, Hashable, Sendable {
    public var reviewBots: [String]
    public var noiseBots: [String]

    public static let defaults = BotLists(
        reviewBots: ["cubic-dev-ai", "aikido-pr-checks"],
        noiseBots: ["cla-bot", "codecov", "github-actions", "dependabot"]
    )

    public enum Role { case human, reviewBot, noise }

    /// Bots that are in neither list count as noise.
    public func role(of person: Person) -> Role {
        let login = Self.normalize(person.login)
        if reviewBots.contains(where: { Self.normalize($0) == login }) { return .reviewBot }
        if noiseBots.contains(where: { Self.normalize($0) == login }) || person.isBot { return .noise }
        return .human
    }

    static func normalize(_ login: String) -> String {
        login.lowercased().replacingOccurrences(of: "[bot]", with: "")
    }
}

public enum GitHubRules {
    public static func need(for pr: PullRequest, viewer: String, bots: BotLists) -> Need? {
        guard pr.state == .open else { return nil }
        return pr.author?.login == viewer
            ? myPRNeed(pr, viewer: viewer, bots: bots)
            : reviewNeed(pr, viewer: viewer)
    }

    // MARK: Someone else's PR

    static func reviewNeed(_ pr: PullRequest, viewer: String) -> Need? {
        let requested = pr.requestedReviewers.contains(viewer)
        let myReviews = (pr.events + pr.latestReviews).filter { $0.kind == .review && $0.actor?.login == viewer }
        guard let lastReview = myReviews.map(\.at).max() else {
            guard requested else { return nil }
            let requestedAt = pr.events.filter { $0.kind == .reviewRequested && $0.subject == viewer }.map(\.at).max()
            return Need(group: .reviews, urgency: .review, headline: "Review #\(pr.number)",
                        since: requestedAt ?? pr.createdAt, kind: .review, event: .newReview, url: pr.url)
        }
        // After my review it is my turn again only when the author asks me again; pushes and replies alone wait.
        // GitHub drops me from the requested reviewers when I review, so being requested now means re-requested.
        guard requested else { return nil }
        let reRequestedAt = pr.events.filter { $0.kind == .reviewRequested && $0.subject == viewer && $0.at > lastReview }.map(\.at).max()
        let since = reRequestedAt ?? lastReview
        return Need(group: .reviews, urgency: .reReview, headline: "Re-review #\(pr.number)",
                    since: since, kind: .review, event: .newReview, url: pr.url)
    }

    // MARK: My PR

    static func myPRNeed(_ pr: PullRequest, viewer: String, bots: BotLists) -> Need? {
        let lastCommitAt = pr.events.filter { $0.kind == .commit }.map(\.at).max()
        let feedback = feedback(on: pr, viewer: viewer, bots: bots)

        if let first = feedback.items.min(by: { $0.at < $1.at }) {
            let human = feedback.items.contains { $0.actor.map { bots.role(of: $0) == .human } ?? true }
            return Need(group: .myPRs, urgency: .feedback, headline: "Address feedback", since: first.at,
                        kind: .feedback, event: human ? .humanFeedback : .reviewBotFeedback, url: pr.url)
        }
        if pr.mergeable == "CONFLICTING" {
            return Need(group: .myPRs, urgency: .conflict, headline: "Resolve conflict",
                        since: lastCommitAt ?? pr.updatedAt, kind: .resolveConflict, url: pr.url)
        }
        if pr.ciFailed {
            return Need(group: .myPRs, urgency: .ciFailed, headline: "Fix CI",
                        since: lastCommitAt ?? pr.updatedAt, kind: .fixCI, event: .ciFailed, url: pr.url)
        }
        if pr.reviewDecision == "APPROVED" && pr.mergeable == "MERGEABLE" && !pr.isDraft {
            let approvedAt = (pr.events + pr.latestReviews).filter { $0.reviewState == "APPROVED" }.map(\.at).max()
            return Need(group: .myPRs, urgency: .readyToMerge, headline: "Ready to merge",
                        since: approvedAt ?? pr.updatedAt, event: .readyToMerge, url: pr.url)
        }
        let since = myLastActivity(pr, viewer: viewer) ?? pr.createdAt
        if !feedback.reRequested.isEmpty {
            let names = feedback.reRequested.sorted().map { "@\($0)" }.joined(separator: ", ")
            return Need(group: .waiting, urgency: .waiting, headline: "Re-review requested from \(names)", since: since, url: pr.url)
        }
        return Need(group: .waiting, urgency: .waiting, headline: pr.isDraft ? "Draft" : "Waiting for review", since: since, url: pr.url)
    }

    struct Feedback {
        /// Feedback I have not addressed. A nil actor stands for a review decision without a known reviewer.
        var items: [(actor: Person?, at: Date)]
        /// Change-requesters who were all asked to re-review.
        var reRequested: Set<String>
    }

    static func feedback(on pr: PullRequest, viewer: String, bots: BotLists) -> Feedback {
        let myLast = myLastActivity(pr, viewer: viewer) ?? pr.createdAt
        let counts: (Person) -> Bool = { $0.login != viewer && bots.role(of: $0) != .noise }

        // The latest deciding review per reviewer.
        var decisions: [String: PREvent] = [:]
        for review in pr.latestReviews + pr.events where review.kind == .review {
            guard let actor = review.actor, counts(actor), review.reviewState != "COMMENTED" else { continue }
            if decisions[actor.login].map({ $0.at < review.at }) ?? true { decisions[actor.login] = review }
        }
        let requesters = decisions.values.filter { $0.reviewState == "CHANGES_REQUESTED" }
        let reRequested = Set(requesters.compactMap(\.actor?.login).filter(pr.requestedReviewers.contains))
        let allReRequested = !requesters.isEmpty && reRequested.count == requesters.count

        var items: [(actor: Person?, at: Date)] = []
        if !allReRequested {
            items += requesters.filter { !reRequested.contains($0.actor?.login ?? "") }.map { ($0.actor, $0.at) }
            if requesters.isEmpty && pr.reviewDecision == "CHANGES_REQUESTED" { items.append((nil, pr.updatedAt)) }
        }
        // Re-requested reviewers' older signals wait for their re-review; anything newer than my last activity counts.
        let fromOthers: (Person, Date) -> Bool = { person, at in
            counts(person) && !(allReRequested && reRequested.contains(person.login) && at <= myLast)
        }
        // An unresolved thread counts until I push or reply after it; then it waits for the reviewer.
        for thread in pr.threads where !thread.isResolved {
            if let author = thread.lastAuthor, let at = thread.lastAt, at > myLast, fromOthers(author, at) { items.append((author, at)) }
        }
        // Humans count with any comment or review; review bots only with plain comments, since they review every push.
        for event in pr.events where event.at > myLast && (event.kind == .comment || event.kind == .review) {
            guard let actor = event.actor, fromOthers(actor, event.at) else { continue }
            if bots.role(of: actor) == .human || event.kind == .comment { items.append((actor, event.at)) }
        }
        return Feedback(items: items, reRequested: allReRequested ? reRequested : [])
    }

    static func myLastActivity(_ pr: PullRequest, viewer: String) -> Date? {
        let mine = pr.events.filter { $0.kind == .commit || $0.actor?.login == viewer }.map(\.at)
        let threadReplies = pr.threads.compactMap { $0.lastAuthor?.login == viewer ? $0.lastAt : nil }
        return (mine + threadReplies).max()
    }

    /// The latest activity that is not from a noise bot, for the detail pane and fingerprints.
    public static func latestActivity(_ pr: PullRequest, bots: BotLists) -> Activity? {
        let event = pr.events
            .filter { $0.kind != .reviewRequested && ($0.actor.map { bots.role(of: $0) != .noise } ?? true) }
            .max { $0.at < $1.at }
        return event.map { e in
            let summary = switch e.kind {
            case .comment: "commented"
            case .review: e.reviewState.map { "reviewed (\($0.lowercased().replacingOccurrences(of: "_", with: " ")))" } ?? "reviewed"
            case .commit: "pushed a commit"
            case .forcePush: "force-pushed"
            case .reviewRequested: "requested a review"
            }
            return Activity(author: e.actor?.login ?? pr.author?.login ?? "someone", at: e.at, summary: summary)
        }
    }
}
