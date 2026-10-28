import Foundation

public enum SourceStatus: Equatable, Sendable {
    case notConnected
    case loading
    case ok(Date)
    case error(String)

    public var errorMessage: String? { if case .error(let m) = self { m } else { nil } }
}
