import Foundation

public protocol GitHubFetching: Sendable {
    /// Fetches the PRs that might need me in `scope`, plus the PRs at `extraURLs` (for example
    /// PRs attached to my tickets that are merged or not mine).
    func fetch(scope: String, extraURLs: [String]) async throws -> GitHubInbox
}

/// Reads GitHub through the local `gh` login. Docket never sees or stores the token.
public struct GitHubSource: GitHubFetching {
    public var runner: ProcessRunning
    public var ghPath: String?

    public init(runner: ProcessRunning = ProcessRunner(), ghPath: String? = ProcessRunner.locate("gh")) {
        self.runner = runner
        self.ghPath = ghPath
    }

    public func fetch(scope: String, extraURLs: [String]) async throws -> GitHubInbox {
        guard let gh = ghPath else { throw SourceError.message("gh is not installed") }
        let data = try await runner.run(gh, Self.arguments(scope: scope, extraURLs: extraURLs), timeout: 60)
        return try GitHubInbox.decode(data)
    }

    /// `gh auth status` output, or the error explaining why gh is not logged in.
    public func authStatus() async -> Result<String, SourceError> {
        guard let gh = ghPath else { return .failure(.message("gh is not installed")) }
        do {
            let out = try await runner.run(gh, ["auth", "status", "--hostname", "github.com"], timeout: 20)
            return .success(String(decoding: out, as: UTF8.self))
        } catch let error as SourceError {
            return .failure(error)
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    static func arguments(scope: String, extraURLs: [String]) -> [String] {
        let base = "is:pr is:open archived:false \(scope)"
        var variables = ["authored": "\(base) author:@me",
                         "requested": "\(base) user-review-requested:@me",
                         "reviewed": "\(base) reviewed-by:@me -author:@me"]
        var declarations = "$authored: String!, $requested: String!, $reviewed: String!"
        var lookups = ""
        for (i, url) in extraURLs.enumerated() {
            variables["u\(i)"] = url
            declarations += ", $u\(i): URI!"
            lookups += "  pr\(i): resource(url: $u\(i)) { ...PR }\n"
        }
        let query = """
        query(\(declarations)) {
          viewer { login }
          authored: search(query: $authored, type: ISSUE, first: 50) { nodes { ...PR } }
          requested: search(query: $requested, type: ISSUE, first: 50) { nodes { ...PR } }
          reviewed: search(query: $reviewed, type: ISSUE, first: 50) { nodes { ...PR } }
        \(lookups)}
        \(prFragment)
        """
        return ["api", "graphql", "-f", "query=\(query)"] + variables.sorted { $0.key < $1.key }.flatMap { ["-f", "\($0.key)=\($0.value)"] }
    }

    static let prFragment = """
    fragment PR on PullRequest {
      number title url isDraft state createdAt updatedAt headRefName
      repository { name nameWithOwner }
      author { __typename login }
      reviewDecision mergeable
      reviewRequests(first: 20) { nodes { requestedReviewer { __typename ... on User { login } ... on Bot { login } ... on Team { slug } } } }
      latestReviews(first: 20) { nodes { author { __typename login } state submittedAt } }
      reviewThreads(last: 50) { nodes { isResolved comments(last: 1) { nodes { author { __typename login } createdAt } } } }
      commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
      timelineItems(last: 40, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, HEAD_REF_FORCE_PUSHED_EVENT, REVIEW_REQUESTED_EVENT]) {
        nodes {
          __typename
          ... on IssueComment { author { __typename login } createdAt }
          ... on PullRequestReview { author { __typename login } submittedAt state }
          ... on PullRequestCommit { commit { committedDate } }
          ... on HeadRefForcePushedEvent { actor { __typename login } createdAt }
          ... on ReviewRequestedEvent { createdAt requestedReviewer { __typename ... on User { login } } }
        }
      }
    }
    """
}

/// One GitHub poll: who I am and every PR that might need me.
public struct GitHubInbox: Sendable {
    public var viewer: String
    public var pullRequests: [PullRequest]

    /// Decodes a `gh api graphql` response. Every top-level field besides `viewer` is a search
    /// (`{ nodes: [PR] }`) or a single PR looked up by URL; duplicates are dropped.
    public static func decode(_ data: Data) throws -> GitHubInbox {
        struct Response: Decodable { var data: [String: Field]?; var errors: [GraphQLError]? }
        struct Viewer: Decodable { var login: String }
        enum Field: Decodable {
            case viewer(Viewer), search([PullRequest?]), pr(PullRequest?)

            init(from decoder: Decoder) throws {
                if let search = try? Nodes<PullRequest?>(from: decoder) { self = .search(search.nodes) }
                else if let pr = try? PullRequest(from: decoder) { self = .pr(pr) }
                else if let viewer = try? Viewer(from: decoder) { self = .viewer(viewer) }
                else { self = .pr(nil) }
            }
        }

        let response = try DocketJSON.decoder().decode(Response.self, from: data)
        guard let fields = response.data else {
            throw SourceError.message(response.errors?.first?.message ?? "Empty GitHub response")
        }
        var viewer = ""
        var prs: [PullRequest] = []
        var seen = Set<String>()
        for key in fields.keys.sorted() {
            switch fields[key] {
            case .viewer(let v): viewer = v.login
            case .search(let nodes): prs += nodes.compactMap { $0 }
            case .pr(let pr): if let pr { prs.append(pr) }
            case nil: break
            }
        }
        prs = prs.filter { seen.insert($0.id).inserted }
        return GitHubInbox(viewer: viewer, pullRequests: prs)
    }
}

struct GraphQLError: Decodable { var message: String }

public enum SourceError: Error, LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let m) = self { m } else { nil } }
}
