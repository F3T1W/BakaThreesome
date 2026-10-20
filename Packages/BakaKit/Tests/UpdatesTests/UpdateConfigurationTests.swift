@testable import Updates
import Foundation
import Testing

@Test func updateConfigurationRequiresAnEd25519PublicKey() throws {
    for value in ["", "placeholder", Data(repeating: 1, count: 31).base64EncodedString(),
                  Data(repeating: 1, count: 64).base64EncodedString()] {
        #expect(throws: UpdateConfiguration.ConfigurationError.self) { try UpdateConfiguration(publicKey: value) }
    }
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    #expect(try UpdateConfiguration(publicKey: key).publicKey == key)
    #expect(UpdateConfiguration.feedURL.scheme == "https")
    #expect(UpdateConfiguration.feedURL.path == "/F3T1W/ShikiThreesome/releases/latest/download/appcast.xml")
}

@MainActor
@Test func packageTestsNeverStartAnApplicationUpdater() {
    let model = AppUpdateModel()
    #expect(!model.isConfigured)
    #expect(!model.canCheckForUpdates)
    #expect(model.availableVersion == nil)
    model.checkForUpdates()
}

@MainActor
@Test func scheduledUpdateOnlyShowsAReminderUntilTheUserClicks() {
    let driver = FakeUpdateDriver()
    let model = AppUpdateModel(driver: driver)
    #expect(model.isConfigured)
    driver.onChange?(.available("0.2.0"))
    #expect(model.availableVersion == "0.2.0")
    #expect(driver.userChecks == 0)
    // A pending reminder can be brought forward even while a scheduled session is active.
    model.checkForUpdates()
    #expect(driver.userChecks == 1)
    driver.onChange?(.dismissed)
    #expect(model.availableVersion == nil)
    model.checkForUpdates()
    #expect(driver.userChecks == 1)
}

@MainActor
@Test func manualChecksRespectReadinessAndCannotBypassMissingConfiguration() {
    let driver = FakeUpdateDriver()
    let model = AppUpdateModel(driver: driver)
    model.checkForUpdates()
    #expect(driver.userChecks == 0)
    driver.onChange?(.canCheck(true))
    model.checkForUpdates()
    #expect(driver.userChecks == 1)
    driver.onChange?(.canCheck(false))
    model.checkForUpdates()
    #expect(driver.userChecks == 1)

    let disabled = FakeUpdateDriver(configured: false)
    let unconfigured = AppUpdateModel(driver: disabled)
    disabled.onChange?(.canCheck(true))
    unconfigured.checkForUpdates()
    #expect(disabled.userChecks == 0)
}

@MainActor
private final class FakeUpdateDriver: UpdateDriver {
    var onChange: (@MainActor (UpdateEvent) -> Void)?
    private let configured: Bool
    private(set) var userChecks = 0
    init(configured: Bool = true) { self.configured = configured }
    func start() -> Bool { configured }
    func checkForUpdates() { userChecks += 1 }
}
