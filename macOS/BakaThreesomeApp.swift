import BakaUI
import SwiftUI

@main
struct BakaThreesomeApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .defaultSize(width: 1120, height: 760)

        Settings {
            AppSettingsView()
        }
    }
}
