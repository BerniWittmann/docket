import Foundation

/// An open TickTick task that is tagged #docket or names a PR or ticket.
public struct Todo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var projectId: String
    public var title: String
    public var content: String?
    public var dueDate: Date?
    public var status: Int
    public var tags: [String]?

    public init(id: String, projectId: String, title: String, content: String? = nil, dueDate: Date? = nil, status: Int = 0, tags: [String]? = ["docket"]) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.content = content
        self.dueDate = dueDate
        self.status = status
        self.tags = tags
    }

    public var isTagged: Bool { tags?.contains { $0.caseInsensitiveCompare(TickTickSource.tag) == .orderedSame } ?? false }

    public var url: String { "https://ticktick.com/webapp/#p/\(projectId)/tasks/\(id)" }

    /// PRs (`repo#123`, lowercased) and tickets (`ABC-123`) named in the title or content, by URL or by shorthand.
    public var references: Set<String> {
        let text = title + "\n" + (content ?? "")
        var refs = Set<String>()
        for m in text.matches(of: /github\.com\/[\w.-]+\/([\w.-]+)\/pull\/(\d+)/) { refs.insert("\(m.1)#\(m.2)".lowercased()) }
        for m in text.matches(of: /(?:^|[\s(\[])(?:[\w.-]+\/)?([\w.-]+)#(\d+)\b/) { refs.insert("\(m.1)#\(m.2)".lowercased()) }
        for m in text.matches(of: /\b([A-Za-z]{2,5})-(\d{1,6})\b/) { refs.insert("\(m.1)-\(m.2)".uppercased()) }
        return refs
    }
}

extension WorkItem {
    /// What a #docket task can name to link to this item.
    public var references: Set<String> {
        var refs = Set(pullRequests.map { "\($0.repoName)#\($0.number)".lowercased() })
        if let linkedTicket { refs.insert(linkedTicket.identifier.uppercased()) }
        return refs
    }
}
