import Foundation
import XCTest

final class VoiceServiceSettingsLayoutTests: XCTestCase {
    func testProviderCredentialsFollowTheirIdentifierField() throws {
        let source = try mainWindowSource()

        try assertOrder(
            in: source,
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

    func testVoiceServiceControlsDoNotUseFixedWidth() throws {
        let source = try mainWindowSource()

        XCTAssertFalse(source.contains(".frame(width: 230)"))
        XCTAssertTrue(source.contains(".frame(width: 92, alignment: .leading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)"))
    }

    private func mainWindowSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "readless/MainWindowView.swift"
            ),
            encoding: .utf8
        )
    }

    private func assertOrder(
        in source: String,
        snippets: [String]
    ) throws {
        let locations = try snippets.map { snippet in
            source.distance(
                from: source.startIndex,
                to: try XCTUnwrap(source.range(of: snippet)).lowerBound
            )
        }
        XCTAssertEqual(locations, locations.sorted())
    }
}
