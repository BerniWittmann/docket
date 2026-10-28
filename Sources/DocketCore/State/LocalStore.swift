import Foundation

/// JSON files in Application Support: settings.json and state.json.
public struct LocalStore: Sendable {
    public var directory: URL

    public init(directory: URL = URL.applicationSupportDirectory.appending(path: "Docket")) {
        self.directory = directory
    }

    public var isFirstRun: Bool { !FileManager.default.fileExists(atPath: url("state").path) }

    public func loadSettings() -> Settings { load("settings", defaults: Settings()) }
    public func loadState() -> LocalState { load("state", defaults: LocalState()) }
    public func save(_ settings: Settings) throws { try save(settings, as: "settings") }
    public func save(_ state: LocalState) throws { try save(state, as: "state") }

    private func url(_ name: String) -> URL { directory.appending(path: "\(name).json") }

    /// Missing keys fall back to the defaults, so older files keep loading after new settings appear.
    private func load<T: Codable>(_ name: String, defaults: T) -> T {
        guard let data = try? Data(contentsOf: url(name)),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: DocketJSON.encoder().encode(defaults)) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(stored) { $1 }),
              let value = try? DocketJSON.decoder().decode(T.self, from: merged)
        else { return defaults }
        return value
    }

    private func save<T: Encodable>(_ value: T, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try DocketJSON.encoder().encode(value).write(to: url(name), options: .atomic)
    }
}
