import Foundation

public struct TickTickList: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
}

public protocol TickTickSyncing: Sendable {
    /// Open tasks that are tagged #docket or name a PR or ticket.
    func todos(token: String) async throws -> [Todo]
    func lists(token: String) async throws -> [TickTickList]
    func create(title: String, content: String, listID: String, due: Date, token: String) async throws -> Todo
    /// Sets an all-day due date, and the title when given, and reopens the task if it was completed.
    func setDue(_ due: Date, title: String?, taskID: String, listID: String, token: String) async throws
    func complete(taskID: String, listID: String, token: String) async throws
}

/// TickTick's Open API with a personal API token. The only place Docket writes to.
public struct TickTickSource: TickTickSyncing {
    public static let base = URL(string: "https://api.ticktick.com/open/v1/")!
    public static let tag = "docket"

    public init() {}

    public func todos(token: String) async throws -> [Todo] {
        let open = try Self.decoder().decode([Todo].self, from: try await call("task/filter", body: ["status": [0]], token: token))
        return open.filter { $0.isTagged || !$0.references.isEmpty }
    }

    public func lists(token: String) async throws -> [TickTickList] {
        try Self.decoder().decode([TickTickList].self, from: try await call("project", token: token))
    }

    public func create(title: String, content: String, listID: String, due: Date, token: String) async throws -> Todo {
        var body: [String: Any] = ["title": title, "content": content, "projectId": listID, "tags": [Self.tag]]
        body.merge(Self.allDay(due)) { $1 }
        return try Self.decoder().decode(Todo.self, from: try await call("task", body: body, token: token))
    }

    public func setDue(_ due: Date, title: String?, taskID: String, listID: String, token: String) async throws {
        // Round-trips the whole task, so fields this update does not name are kept.
        let data = try await call("project/\(listID)/task/\(taskID)", token: token)
        guard var task = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SourceError.message("Unexpected TickTick task") }
        task.merge(Self.allDay(due)) { $1 }
        if let title { task["title"] = title }
        task["status"] = 0
        task["completedTime"] = nil
        _ = try await call("task/\(taskID)", body: task, token: token)
    }

    public func complete(taskID: String, listID: String, token: String) async throws {
        _ = try await call("project/\(listID)/task/\(taskID)/complete", body: [:], token: token)
    }

    // MARK: HTTP

    func call(_ path: String, body: [String: Any]? = nil, token: String) async throws -> Data {
        var request = URLRequest(url: Self.base.appending(path: path), timeoutInterval: 30)
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw SourceError.message("TickTick rejected the API token")
        case 404: throw TickTickError.notFound
        case let code: throw SourceError.message("TickTick answered \(code): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
    }

    /// An all-day date at local midnight, the way the TickTick apps store it.
    static func allDay(_ day: Date, calendar: Calendar = .current) -> [String: Any] {
        let midnight = format(calendar.startOfDay(for: day))
        return ["dueDate": midnight, "startDate": midnight, "isAllDay": true, "timeZone": calendar.timeZone.identifier]
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f.string(from: date)
    }

    /// TickTick dates look like `2026-03-05T00:00:00.000+0000`.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
                f.dateFormat = format
                if let date = f.date(from: string) { return date }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }
}

public enum TickTickError: Error, Equatable {
    /// The task was deleted in TickTick.
    case notFound
}
