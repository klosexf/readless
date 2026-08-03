import Foundation
import XCTest

final class VoiceServiceSettingsLayoutTests: XCTestCase {
    func testProviderCredentialsFollowTheirIdentifierField() throws {
        let source = try mainWindowSource()

        let v1Section = try XCTUnwrap(
            source.components(separatedBy: "case .v1:")
                .dropFirst()
                .first
        )
        try assertOrder(
            in: v1Section,
            snippets: [
                "labeledField(\"App ID\"",
                "credentialField",
                "labeledField(\"Cluster\""
            ]
        )

        let compatibleSection = try XCTUnwrap(
            source.components(separatedBy: "case .openAICompatible:")
                .dropFirst()
                .first
        )
        try assertOrder(
            in: compatibleSection,
            snippets: [
                "labeledField(\"Base URL\"",
                "credentialField",
                "labeledField(\"模型\""
            ]
        )
    }

    func testDoubaoProvidesManualV3AndV1Selection() throws {
        let source = try mainWindowSource()

        XCTAssertTrue(source.contains("Picker(\"接口版本\""))

        let doubaoSection = try XCTUnwrap(
            source.components(separatedBy: "case .doubao:")
                .dropFirst()
                .first
        )
        try assertOrder(
            in: doubaoSection,
            snippets: [
                "Picker(\"接口版本\"",
                "case .v3:",
                "credentialField",
                "\"资源 ID\"",
                "\"音色 ID\"",
                "case .v1:",
                "labeledField(\"App ID\"",
                "credentialField",
                "labeledField(\"Cluster\""
            ]
        )
    }

    func testVoiceServiceControlsDoNotUseFixedWidth() throws {
        let source = try mainWindowSource()

        XCTAssertFalse(source.contains(".frame(width: 230)"))
        XCTAssertTrue(source.contains(".frame(width: 92, alignment: .leading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)"))
    }

    func testReplacingCredentialDoesNotRequireReadingOldKeychainItem() throws {
        let source = try appDelegateSource()
        let saveMethod = try XCTUnwrap(
            source.components(separatedBy: "private func saveVoiceService(")
                .dropFirst()
                .first
        )

        XCTAssertTrue(
            saveMethod.contains("if newCredential.isEmpty {")
        )
    }

    private func mainWindowSource() throws -> String {
        try source(named: "readless/MainWindowView.swift")
    }

    private func appDelegateSource() throws -> String {
        try source(named: "readless/AppDelegate.swift")
    }

    private func source(named path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func assertOrder(
        in source: String,
        snippets: [String]
    ) throws {
        var searchStart = source.startIndex
        let locations = try snippets.map { snippet in
            let range = try XCTUnwrap(
                source.range(of: snippet, range: searchStart..<source.endIndex)
            )
            searchStart = range.upperBound
            return source.distance(
                from: source.startIndex,
                to: range.lowerBound
            )
        }
        XCTAssertEqual(locations, locations.sorted())
    }
}
