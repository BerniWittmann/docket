import Foundation

public struct Person: Codable, Hashable, Sendable {
    public var login: String
    public var isBot: Bool

    public init(login: String, isBot: Bool = false) {
        self.login = login
        self.isBot = isBot || login.hasSuffix("[bot]")
    }
}

public struct PREvent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case comment, review, commit, forcePush, reviewRequested
    }

    public var kind: Kind
    /// Nil for commits, which have no GitHub actor in the timeline.
    public var actor: Person?
    public var at: Date
    /// APPROVED, CHANGES_REQUESTED, COMMENTED or DISMISSED for reviews.
    public var reviewState: String?
    /// The requested reviewer for reviewRequested events.
    public var subject: String?

    public init(kind: Kind, actor: Person?, at: Date, reviewState: String? = nil, subject: String? = nil) {
        self.kind = kind
        self.actor = actor
        self.at = at
        self.reviewState = reviewState
        self.subject = subject
    }
}

public struct ReviewThread: Hashable, Sendable {
    public var isResolved: Bool
    public var lastAuthor: Person?
    public var lastAt: Date?
}

public struct PullRequest: Hashable, Sendable, Identifiable {
    public enum State: String, Sendable { case open = "OPEN", closed = "CLOSED", merged = "MERGED" }

    public var repo: String
    public var repoName: String
    public var number: Int
    public var title: String
    public var url: String
    public var author: Person?
    public var isDraft: Bool
    public var state: State
    public var headRef: String
    public var createdAt: Date
    public var updatedAt: Date
    public var reviewDecision: String?
    public var mergeable: String?
    public var checks: String?
    public var requestedReviewers: [String]
    public var latestReviews: [PREvent]
    public var events: [PREvent]
    public var threads: [ReviewThread]

    public var id: String { "\(repo)#\(number)" }

    /// The Linear ticket this PR belongs to, by the branch convention `node-1234-slug` (else an ID in the title).
    public var ticketID: String? { Self.ticketID(branch: headRef) ?? Self.ticketID(title: title) }

    static func ticketID(branch: String) -> String? {
        let name = branch.split(separator: "/").last.map(String.init) ?? branch
        guard let match = name.firstMatch(of: /^([A-Za-z]{2,5})-(\d{1,6})(?:-|$)/) else { return nil }
        return "\(match.1.uppercased())-\(match.2)"
    }

    /// The worktree branch for reviewing this PR: `review-<n>-<slug of the title>`.
    public var reviewBranch: String {
        let slug = Self.slug(title)
        return slug.isEmpty ? "review-\(number)" : "review-\(number)-\(slug)"
    }

    /// Whether `branch` is a review worktree for PR `number`, with or without a slug.
    public static func isReviewBranch(_ branch: String, number: Int) -> Bool {
        branch == "review-\(number)" || branch.hasPrefix("review-\(number)-")
    }

    /// A short, readable slug: the title without its `type(scope):` prefix, cut at a word within 30 characters.
    static func slug(_ title: String) -> String {
        let text = title.replacing(/^[a-z]+(\([^)]*\))?!?:\s*/, with: "").lowercased()
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var slug = ""
        for word in words {
            let next = slug.isEmpty ? word : "\(slug)-\(word)"
            if next.count > 30 { break }
            slug = next
        }
        return slug.isEmpty ? String(words.first?.prefix(30) ?? "") : slug
    }

    static func ticketID(title: String) -> String? {
        title.firstMatch(of: /\b([A-Z]{2,5}-\d{1,6})\b/).map { String($0.1) }
    }
    public var ciFailed: Bool { checks == "FAILURE" || checks == "ERROR" }
}

// MARK: - GraphQL decoding

private struct GQLActor: Decodable {
    var __typename: String?
    var login: String?
    var slug: String?
    var person: Person? { login.map { Person(login: $0, isBot: __typename == "Bot") } }
}

private struct GQLTimelineItem: Decodable {
    struct Commit: Decodable { var committedDate: Date }
    var __typename: String
    var author: GQLActor?
    var actor: GQLActor?
    var requestedReviewer: GQLActor?
    var createdAt: Date?
    var submittedAt: Date?
    var state: String?
    var commit: Commit?

    var event: PREvent? {
        switch __typename {
        case "IssueComment":
            return createdAt.map { PREvent(kind: .comment, actor: author?.person, at: $0) }
        case "PullRequestReview":
            return submittedAt.map { PREvent(kind: .review, actor: author?.person, at: $0, reviewState: state) }
        case "PullRequestCommit":
            return commit.map { PREvent(kind: .commit, actor: nil, at: $0.committedDate) }
        case "HeadRefForcePushedEvent":
            return createdAt.map { PREvent(kind: .forcePush, actor: actor?.person, at: $0) }
        case "ReviewRequestedEvent":
            return createdAt.map {
                PREvent(kind: .reviewRequested, actor: nil, at: $0,
                        subject: requestedReviewer?.login ?? requestedReviewer?.slug)
            }
        default:
            return nil
        }
    }
}

extension PullRequest: Decodable {
    private enum Keys: String, CodingKey {
        case number, title, url, isDraft, state, createdAt, updatedAt, headRefName, repository, author
        case reviewDecision, mergeable, reviewRequests, latestReviews, reviewThreads, commits, timelineItems
    }

    private struct Repository: Decodable { var name: String; var nameWithOwner: String }
    private struct ReviewRequest: Decodable { var requestedReviewer: GQLActor? }
    private struct LatestReview: Decodable { var author: GQLActor?; var state: String; var submittedAt: Date? }
    private struct ThreadNode: Decodable {
        struct Comment: Decodable { var author: GQLActor?; var createdAt: Date }
        var isResolved: Bool
        var comments: Nodes<Comment>
    }
    private struct CommitNode: Decodable {
        struct Commit: Decodable {
            struct Rollup: Decodable { var state: String }
            var statusCheckRollup: Rollup?
        }
        var commit: Commit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let repository = try c.decode(Repository.self, forKey: .repository)
        repo = repository.nameWithOwner
        repoName = repository.name
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        author = try c.decodeIfPresent(GQLActor.self, forKey: .author)?.person
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        state = State(rawValue: try c.decode(String.self, forKey: .state)) ?? .open
        headRef = try c.decodeIfPresent(String.self, forKey: .headRefName) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        reviewDecision = try c.decodeIfPresent(String.self, forKey: .reviewDecision)
        mergeable = try c.decodeIfPresent(String.self, forKey: .mergeable)
        requestedReviewers = (try c.decodeIfPresent(Nodes<ReviewRequest>.self, forKey: .reviewRequests))?
            .nodes.compactMap { $0.requestedReviewer?.login ?? $0.requestedReviewer?.slug } ?? []
        latestReviews = (try c.decodeIfPresent(Nodes<LatestReview>.self, forKey: .latestReviews))?.nodes.compactMap { r in
            r.submittedAt.map { PREvent(kind: .review, actor: r.author?.person, at: $0, reviewState: r.state) }
        } ?? []
        threads = (try c.decodeIfPresent(Nodes<ThreadNode>.self, forKey: .reviewThreads))?.nodes.map { t in
            let last = t.comments.nodes.last
            return ReviewThread(isResolved: t.isResolved, lastAuthor: last?.author?.person, lastAt: last?.createdAt)
        } ?? []
        checks = (try c.decodeIfPresent(Nodes<CommitNode>.self, forKey: .commits))?.nodes.last?.commit.statusCheckRollup?.state
        events = (try c.decodeIfPresent(Nodes<GQLTimelineItem>.self, forKey: .timelineItems))?.nodes.compactMap(\.event) ?? []
    }
}
