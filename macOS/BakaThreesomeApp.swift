import AppKit
import BakaUI
import SwiftUI

@main
struct BakaThreesomeApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var services = ApplicationServices()

    var body: some Scene {
        WindowGroup {
            LibraryView(services: services)
                .onAppear {
                    applicationDelegate.services = services
                }
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(model: services.updates)
            }
        }

        Settings {
            AppSettingsView(services: services)
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var services: ApplicationServices?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let services else { return .terminateNow }
        Task {
            await services.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
