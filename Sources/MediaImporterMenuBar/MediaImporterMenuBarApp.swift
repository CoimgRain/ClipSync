import AppKit
import SwiftUI

@main
struct MediaImporterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var diskMonitor: DiskMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var importer: MediaImporter
    @StateObject private var autoImportCoordinator: AutoImportCoordinator

    init() {
        let diskMonitor = DiskMonitor()
        let settings = AppSettings()
        let importer = MediaImporter()

        _diskMonitor = StateObject(wrappedValue: diskMonitor)
        _settings = StateObject(wrappedValue: settings)
        _importer = StateObject(wrappedValue: importer)
        _autoImportCoordinator = StateObject(
            wrappedValue: AutoImportCoordinator(
                diskMonitor: diskMonitor,
                settings: settings,
                importer: importer
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(diskMonitor)
                .environmentObject(settings)
                .environmentObject(importer)
                .frame(width: 360)
        } label: {
            MenuBarLabelView()
                .environmentObject(diskMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
