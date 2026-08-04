import Foundation
import XCTest

final class DoubaoV3SpeechProviderSourceTests: XCTestCase {
    func testProviderUsesHTTPDataTaskAndResponseDecoder() throws {
        let source = try providerSource()

        XCTAssertTrue(source.contains("URLSessionDataTask?"))
        XCTAssertTrue(source.contains("session.dataTask(with: request)"))
        XCTAssertTrue(source.contains("response as? HTTPURLResponse"))
        XCTAssertTrue(
            source.contains("DoubaoV3HTTPResponseDecoder.decode(data)")
        )
        XCTAssertFalse(source.contains("URLSessionWebSocketTask"))
        XCTAssertFalse(source.contains("webSocketTask("))
        XCTAssertFalse(source.contains("receiveNext()"))
    }

    func testProviderClassifiesHTTPAndTransportFailures() throws {
        let source = try providerSource()

        XCTAssertTrue(source.contains("error.code == .timedOut"))
        XCTAssertTrue(
            source.contains(
                "CloudSpeechErrorMapper.mapDoubaoV3HTTPStatus("
            )
        )
        XCTAssertTrue(source.contains("statusCode:"))
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
