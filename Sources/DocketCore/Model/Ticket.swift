import Foundation

public struct Ticket: Hashable, Sendable, Identifiable, Decodable {
    public struct State: Hashable, Sendable, Decodable {
        public var name: String
        /// Linear workflow type: triage, backlog, unstarted, started, completed, canceled.
        public var type: String
    }

    public var identifier: String
    public var title: String
    public var url: String
    public var branchName: String
    public var updatedAt: Date
    public var state: State
    public var attachmentURLs: [String]
    public var assignee: String?

    public var id: String { identifier }
    public var isOpen: Bool { state.type == "unstarted" || state.type == "started" }

    private enum Keys: String, CodingKey { case identifier, title, url, branchName, updatedAt, state, attachments, assignee }
    private struct Attachment: Decodable { var url: String }
    private struct Assignee: Decodable { var name: String }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        branchName = try c.decodeIfPresent(String.self, forKey: .branchName) ?? ""
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        state = try c.decode(State.self, forKey: .state)
        attachmentURLs = (try c.decodeIfPresent(Nodes<Attachment>.self, forKey: .attachments))?.nodes.map(\.url) ?? []
        assignee = (try? c.decodeIfPresent(Assignee.self, forKey: .assignee))?.name
    }
}
