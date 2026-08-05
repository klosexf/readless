import XCTest
@testable import ReadlessCore

@MainActor
final class VoiceServiceSaveCoordinatorTests: XCTestCase {
    private let configuration = VoiceServiceConfiguration.doubaoV3(
        resourceID: "seed-tts-2.0",
        speaker: "saturn-speaker"
    )

    func testNormalSavePersistsConfigurationAndCredential() {
        let settings = SaveSettingsFake()
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
        XCTAssertEqual(settings.configuration, configuration)
        XCTAssertEqual(credentials.values[.doubaoV3], "new-api-key")
    }

    func testSaveRecoversWhenSettingsPersistsBeforeThrowing() {
        let settings = SaveSettingsFake(throwsAfterSave: true)
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
    }

    func testSaveRecoversWhenCredentialPersistsBeforeThrowing() {
        let settings = SaveSettingsFake(configuration: configuration)
        let credentials = SaveCredentialsFake(throwsAfterSave: true)
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            )
        )
    }

    func testSaveFailsWhenOnlyCredentialPersisted() {
        let settings = SaveSettingsFake(
            persistBeforeThrow: false,
            throwsAfterSave: true
        )
        let credentials = SaveCredentialsFake()
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertEqual(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            ),
            .persistenceFailed
        )
    }

    func testSaveFailsWhenOnlyConfigurationPersisted() {
        let settings = SaveSettingsFake(configuration: configuration)
        let credentials = SaveCredentialsFake(
            persistBeforeThrow: false,
            throwsAfterSave: true
        )
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertEqual(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            ),
            .persistenceFailed
        )
    }

    func testSaveDoesNotMistakeOlderCredentialForReplacement() {
        let settings = SaveSettingsFake(configuration: configuration)
        let credentials = SaveCredentialsFake(
            values: [.doubaoV3: "old-api-key"],
            persistBeforeThrow: false,
            throwsAfterSave: true
        )
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertEqual(
            saver.save(
                configuration: configuration,
                credential: "new-api-key"
            ),
            .persistenceFailed
        )
    }

    func testSaveWithoutReplacementAcceptsExistingCredential() {
        let settings = SaveSettingsFake(throwsAfterSave: true)
        let credentials = SaveCredentialsFake(
            values: [.doubaoV3: "existing-api-key"]
        )
        let saver = VoiceServiceSaveCoordinator(
            settings: settings,
            credentials: credentials
        )

        XCTAssertNil(
            saver.save(configuration: configuration, credential: "")
        )
    }
}

private enum SaveFailure: Error {
    case requested
}

@MainActor
private final class SaveSettingsFake: VoiceServiceSettingsSaving {
    var configuration: VoiceServiceConfiguration?

    var profiles: VoiceServiceProfiles {
        guard let configuration else {
            return VoiceServiceProfiles()
        }
        return VoiceServiceProfiles.migrated(from: configuration)
    }

    private let persistBeforeThrow: Bool
    private let throwsAfterSave: Bool

    init(
        configuration: VoiceServiceConfiguration? = nil,
        persistBeforeThrow: Bool = true,
        throwsAfterSave: Bool = false
    ) {
        self.configuration = configuration
        self.persistBeforeThrow = persistBeforeThrow
        self.throwsAfterSave = throwsAfterSave
    }

    func save(configuration: VoiceServiceConfiguration) throws {
        if persistBeforeThrow {
            self.configuration = configuration
        }
        if throwsAfterSave {
            throw SaveFailure.requested
        }
    }

    func selectDoubaoVersion(_ version: DoubaoAPIVersion) {}
}

@MainActor
private final class SaveCredentialsFake: VoiceServiceCredentialStoring {
    var values: [VoiceCredentialSlot: String]
    private let persistBeforeThrow: Bool
    private let throwsAfterSave: Bool

    init(
        values: [VoiceCredentialSlot: String] = [:],
        persistBeforeThrow: Bool = true,
        throwsAfterSave: Bool = false
    ) {
        self.values = values
        self.persistBeforeThrow = persistBeforeThrow
        self.throwsAfterSave = throwsAfterSave
    }

    func hasCredential(for slot: VoiceCredentialSlot) -> Bool {
        values[slot]?.isEmpty == false
    }

    func credential(for slot: VoiceCredentialSlot) throws -> String? {
        values[slot]
    }

    func saveCredential(
        _ credential: String,
        for slot: VoiceCredentialSlot
    ) throws {
        if persistBeforeThrow {
            values[slot] = credential
        }
        if throwsAfterSave {
            throw SaveFailure.requested
        }
    }

    func removeCredential(for slot: VoiceCredentialSlot) throws {
        values.removeValue(forKey: slot)
    }
}
