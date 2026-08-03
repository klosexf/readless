import Foundation
import XCTest

final class DoubaoV3SpeechProviderSourceTests: XCTestCase {
    func testWebSocketUpgradeDoesNotIncludeSynthesisPacket() throws {
        let source = try providerSource()

        XCTAssertTrue(source.contains("var handshakeRequest = request"))
        XCTAssertTrue(source.contains("handshakeRequest.httpBody = nil"))
        XCTAssertTrue(source.contains("session.webSocketTask(with: handshakeRequest)"))
    }

    private func providerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/System/DoubaoV3SpeechProvider.swift"
            ),
            encoding: .utf8
        )
    }
}
