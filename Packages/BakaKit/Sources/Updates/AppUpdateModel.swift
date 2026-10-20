import Observation

@MainActor
@Observable
public final class AppUpdateModel {
    public private(set) var availableVersion: String?
    public private(set) var canCheckForUpdates = false
    public private(set) var isConfigured = false
    @ObservationIgnored private let driver: any UpdateDriver

    public convenience init() { self.init(driver: SparkleUpdateDriver()) }

    init(driver: any UpdateDriver) {
        self.driver = driver
        driver.onChange = { [weak self] event in
            switch event {
            case .canCheck(let enabled): self?.canCheckForUpdates = enabled
            case .available(let version): self?.availableVersion = version
            case .dismissed: self?.availableVersion = nil
            }
        }
        isConfigured = driver.start()
    }

    public func checkForUpdates() {
        guard isConfigured, canCheckForUpdates || availableVersion != nil else { return }
        driver.checkForUpdates()
    }
}

// The port keeps UI state testable without downloading or installing real updates.
@MainActor
protocol UpdateDriver: AnyObject {
    var onChange: (@MainActor (UpdateEvent) -> Void)? { get set }
    func start() -> Bool
    func checkForUpdates()
}

enum UpdateEvent: Sendable {
    case canCheck(Bool)
    case available(String)
    case dismissed
}
