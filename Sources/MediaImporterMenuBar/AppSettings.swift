import AppKit
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    // 这里保留一个可读的 path，主要用于 UI 显示和兼容旧配置。
    @Published var destinationFolderPath: String {
        didSet {
            UserDefaults.standard.set(destinationFolderPath, forKey: Self.destinationFolderKey)
        }
    }

    @Published var autoImportEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoImportEnabled, forKey: Self.autoImportKey)
        }
    }

    private static let destinationFolderKey = "destinationFolderPath"
    private static let destinationFolderBookmarkKey = "destinationFolderBookmark"
    private static let autoImportKey = "autoImportEnabled"

    init() {
        self.destinationFolderPath = ""
        self.autoImportEnabled = UserDefaults.standard.bool(forKey: Self.autoImportKey)
        restoreDestinationFolder()
    }

#if DEBUG
    init(previewDestinationFolderPath: String, autoImportEnabled: Bool) {
        self.destinationFolderPath = previewDestinationFolderPath
        self.autoImportEnabled = autoImportEnabled
    }
#endif

    var destinationFolderURL: URL? {
        resolvedDestinationFolderURL()
    }

    func chooseDestinationFolder() {
        // 让用户在系统面板里选一个导入目标目录。
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择导入文件夹"
        panel.directoryURL = destinationFolderURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        saveDestinationFolder(selectedURL)
    }

    func withDestinationFolderAccess<T>(
        _ body: (URL) async throws -> T
    ) async throws -> T {
        // 统一从这里开启/关闭 security-scoped 访问，避免外面忘记收尾。
        guard let access = destinationFolderAccess() else {
            throw DestinationFolderError.notConfigured
        }

        defer {
            access.stop()
        }

        return try await body(access.url)
    }

    private func restoreDestinationFolder() {
        // 优先恢复 bookmark；如果是老版本只存了 path，就顺手迁移一次。
        if let url = resolvedDestinationFolderURL(refreshBookmarkIfNeeded: true) {
            destinationFolderPath = url.path
            return
        }

        destinationFolderPath = UserDefaults.standard.string(forKey: Self.destinationFolderKey) ?? ""
        guard !destinationFolderPath.isEmpty else { return }
        saveDestinationFolder(URL(fileURLWithPath: destinationFolderPath, isDirectory: true))
    }

    private func saveDestinationFolder(_ url: URL) {
        do {
            // bookmark 才是正式产品里比较稳定的目录授权持久化方式。
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.destinationFolderBookmarkKey)
            destinationFolderPath = url.path
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.destinationFolderBookmarkKey)
            destinationFolderPath = url.path
        }
    }

    private func destinationFolderAccess() -> DestinationFolderAccess? {
        guard let url = resolvedDestinationFolderURL(refreshBookmarkIfNeeded: true) else {
            return nil
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        return DestinationFolderAccess(url: url, shouldStopAccessing: didStartAccessing)
    }

    private func resolvedDestinationFolderURL(
        refreshBookmarkIfNeeded: Bool = false
    ) -> URL? {
        // 如果 bookmark 失效或过期，尽量在这里自动刷新。
        if let bookmarkData = UserDefaults.standard.data(forKey: Self.destinationFolderBookmarkKey) {
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale, refreshBookmarkIfNeeded {
                    saveDestinationFolder(resolvedURL)
                }

                return resolvedURL
            } catch {
                UserDefaults.standard.removeObject(forKey: Self.destinationFolderBookmarkKey)
            }
        }

        guard !destinationFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: destinationFolderPath, isDirectory: true)
    }

    private struct DestinationFolderAccess {
        let url: URL
        let shouldStopAccessing: Bool

        func stop() {
            guard shouldStopAccessing else { return }
            url.stopAccessingSecurityScopedResource()
        }
    }

    enum DestinationFolderError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "请先选择导入文件夹"
            }
        }
    }
}
