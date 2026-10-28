import Testing
import Foundation
@testable import DocketCore

@Suite("Linear source, live")
struct LiveLinearTests {
    @Test("an invalid key is rejected", .enabled(if: ProcessInfo.processInfo.environment["DOCKET_LIVE"] == "1"))
    func invalidKey() async {
        await #expect(throws: SourceError.message("Linear rejected the API key")) {
            _ = try await LinearSource().validate(key: "lin_api_invalid")
        }
    }

    @Test("records my assigned tickets", .enabled(if: ProcessInfo.processInfo.environment["DOCKET_LIVE"] == "1"
        && (ProcessInfo.processInfo.environment["LINEAR_API_KEY"] ?? Keychain.read()) != nil))
    func live() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["LINEAR_API_KEY"] ?? Keychain.read())
        let data = try await LinearSource.post(LinearSource.query, key: key)
        let inbox = try LinearSource.decodeIssues(data)
        #expect(!inbox.viewerName.isEmpty)
        #expect(inbox.tickets.allSatisfy { $0.isOpen })
        if let out = ProcessInfo.processInfo.environment["DOCKET_RECORD_LINEAR"] { try data.write(to: URL(fileURLWithPath: out)) }
        print("LIVE linear viewer=\(inbox.viewerName) tickets=\(inbox.tickets.map(\.identifier))")
    }
}
