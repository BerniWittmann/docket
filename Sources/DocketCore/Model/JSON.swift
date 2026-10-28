import Foundation

public enum DocketJSON {
    /// Decodes ISO 8601 dates with or without fractional seconds, and epoch milliseconds.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let millis = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: millis / 1000)
            }
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) { return date }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// GraphQL connection wrapper: `{ "nodes": [...] }`.
struct Nodes<T: Decodable>: Decodable {
    var nodes: [T]
}
