import AppKit
import SwiftUI

@main
struct MediaImporterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let diskMonitor = DiskMonitor()
    private let settings = AppSettings()
    private let importer = MediaImporter()
    private lazy var autoImportCoordinator = AutoImportCoordinator(
        diskMonitor: diskMonitor,
        settings: settings,
        importer: importer
    )
    private lazy var statusBarController = StatusBarController(
        diskMonitor: diskMonitor,
        settings: settings,
        importer: importer
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = autoImportCoordinator
        statusBarController.install()
    }
}
