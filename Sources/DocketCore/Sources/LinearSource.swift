import Foundation

public struct LinearInbox: Sendable {
    public var viewerName: String
    public var tickets: [Ticket]
}

public protocol LinearFetching: Sendable {
    func fetch(key: String) async throws -> LinearInbox
    /// Looks up tickets by identifier, such as tickets named in the branches of other people's PRs.
    func lookup(identifiers: [String], key: String) async throws -> [Ticket]
}

/// Reads my assigned Linear tickets with a personal API key. Never sends mutations.
public struct LinearSource: LinearFetching {
    public static let endpoint = URL(string: "https://api.linear.app/graphql")!
    public static let query = """
    query {
      viewer {
        name
        assignedIssues(first: 100, filter: { state: { type: { in: ["unstarted", "started"] } } }) {
          nodes { identifier title url branchName updatedAt state { name type } attachments { nodes { url } } assignee { name } }
        }
      }
    }
    """
    static let viewerQuery = "query { viewer { name } }"

    public init() {}

    public func fetch(key: String) async throws -> LinearInbox {
        try Self.decodeIssues(try await Self.post(Self.query, key: key))
    }

    public func lookup(identifiers: [String], key: String) async throws -> [Ticket] {
        guard !identifiers.isEmpty else { return [] }
        return try Self.decodeLookup(try await Self.post(Self.lookupQuery(identifiers), key: key))
    }

    /// One aliased `issue(id:)` per identifier. Identifiers come from `PullRequest.ticketID`, so they are `ABC-123`.
    static func lookupQuery(_ identifiers: [String]) -> String {
        let fields = "identifier title url branchName updatedAt state { name type } assignee { name }"
        let lookups = identifiers.enumerated().map { "  t\($0.offset): issue(id: \"\($0.element)\") { \(fields) }" }
        return "query {\n\(lookups.joined(separator: "\n"))\n}"
    }

    /// Unknown identifiers come back as errors next to the found tickets; those are skipped.
    static func decodeLookup(_ data: Data) throws -> [Ticket] {
        struct Lenient: Decodable {
            var value: Ticket?
            init(from decoder: Decoder) throws { value = try? Ticket(from: decoder) }
        }
        struct Response: Decodable { var data: [String: Lenient?]?; var errors: [GraphQLError]? }
        let response = try DocketJSON.decoder().decode(Response.self, from: data)
        guard let found = response.data else {
            throw SourceError.message(response.errors?.first?.message ?? "Empty Linear response")
        }
        return found.keys.sorted().compactMap { found[$0]??.value }
    }

    /// Checks a key and returns the viewer's name for "Connected as …".
    public func validate(key: String) async throws -> String {
        try Self.decodeIssues(try await Self.post(Self.viewerQuery, key: key)).viewerName
    }

    static func request(_ query: String, key: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(key.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        return request
    }

    public static func post(_ query: String, key: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(query, key: key))
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw SourceError.message("Linear rejected the API key") }
        return data
    }

    public static func decodeIssues(_ data: Data) throws -> LinearInbox {
        struct Response: Decodable {
            struct Body: Decodable { var viewer: Viewer }
            struct Viewer: Decodable { var name: String; var assignedIssues: Nodes<Ticket>? }
            var data: Body?
            var errors: [GraphQLError]?
        }
        let response = try DocketJSON.decoder().decode(Response.self, from: data)
        guard let viewer = response.data?.viewer else {
            throw SourceError.message(response.errors?.first?.message ?? "Empty Linear response")
        }
        return LinearInbox(viewerName: viewer.name, tickets: viewer.assignedIssues?.nodes ?? [])
    }
}
