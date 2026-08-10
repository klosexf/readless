import Foundation
import XCTest
@testable import ReadlessCore

@MainActor
final class LocalCredentialStoreTests: XCTestCase {
    nonisolated(unsafe) private var rootURL: URL!
    nonisolated(unsafe) private var fileURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LocalCredentialStoreTests-\(UUID().uuidString)"
            )
        fileURL = rootURL
            .appendingPathComponent("Readless", isDirectory: true)
            .appendingPathComponent("voice-credentials-v1.json")
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testMissingFileHasNoCredential() throws {
        let store = LocalCredentialStore(fileURL: fileURL)

        XCTAssertNil(try store.credential(for: .doubaoV3))
        XCTAssertFalse(store.hasCredential(for: .doubaoV3))
    }

    func testCredentialsRoundTripReplaceAndRemoveBySlot() throws {
        let store = LocalCredentialStore(fileURL: fileURL)

        try store.saveCredential("v3-key", for: .doubaoV3)
        try store.saveCredential(
            "compatible-key",
            for: .openAICompatible
        )
        try store.saveCredential("replacement", for: .doubaoV3)

        XCTAssertEqual(
            try store.credential(for: .doubaoV3),
            "replacement"
        )
        XCTAssertEqual(
            try store.credential(for: .openAICompatible),
            "compatible-key"
        )

        try store.removeCredential(for: .doubaoV3)

        XCTAssertNil(try store.credential(for: .doubaoV3))
        XCTAssertEqual(
            try store.credential(for: .openAICompatible),
            "compatible-key"
        )
    }

    func testStoreCreatesPrivateDirectoryAndFile() throws {
        let store = LocalCredentialStore(fileURL: fileURL)

        try store.saveCredential("secret", for: .doubaoV3)

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.deletingLastPathComponent().path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testCorruptCredentialFileThrows() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let store = LocalCredentialStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.credential(for: .doubaoV3))
    }

    func testRecentReadingRetainsFullTextSourceAndTimestamp() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let record = RecentReading(
            text: "记录正文 A",
            sourceApplication: "Safari",
            startedAt: time
        )

        XCTAssertEqual(record.text, "记录正文 A")
        XCTAssertEqual(record.sourceApplication, "Safari")
        XCTAssertEqual(record.startedAt, time)
    }
}
