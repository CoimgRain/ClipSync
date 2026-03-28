import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum FolderConflictStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case rename
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename:
            return "重命名"
        case .replace:
            return "覆盖"
        }
    }

    var detail: String {
        switch self {
        case .rename:
            return "遇到同名文件时自动保留两份"
        case .replace:
            return "遇到同名文件时用新文件替换旧文件"
        }
    }
}

struct FolderClassificationRule: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var keyword: String
    var targetFolderName: String
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        keyword: String = "",
        targetFolderName: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.targetFolderName = targetFolderName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    var normalizedKeyword: String {
        keyword
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var normalizedTargetFolderPath: String {
        targetFolderName
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    var isConfigured: Bool {
        !normalizedKeyword.isEmpty && !normalizedTargetFolderPath.isEmpty
    }
}

struct FolderClassificationConfiguration: Sendable {
    let isEnabled: Bool
    let rules: [FolderClassificationRule]
    let conflictStrategy: FolderConflictStrategy

    func matchingRule(for folderName: String) -> FolderClassificationRule? {
        guard isEnabled else { return nil }
        let normalizedFolderName = folderName.lowercased()
        return rules.first(where: {
            $0.isEnabled
                && $0.isConfigured
                && normalizedFolderName.contains($0.normalizedKeyword)
        })
    }
}

struct FolderClassificationLogEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let fileName: String
    let sourceFolderName: String
    let destinationSubpath: String
    let ruleKeyword: String?
    let ruleTargetFolderName: String?
    let didMatchRule: Bool
    let conflictStrategy: FolderConflictStrategy

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        fileName: String,
        sourceFolderName: String,
        destinationSubpath: String,
        ruleKeyword: String?,
        ruleTargetFolderName: String?,
        didMatchRule: Bool,
        conflictStrategy: FolderConflictStrategy
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fileName = fileName
        self.sourceFolderName = sourceFolderName
        self.destinationSubpath = destinationSubpath
        self.ruleKeyword = ruleKeyword
        self.ruleTargetFolderName = ruleTargetFolderName
        self.didMatchRule = didMatchRule
        self.conflictStrategy = conflictStrategy
    }
}

private struct FolderClassificationExportPayload: Codable {
    let isEnabled: Bool
    let conflictStrategy: FolderConflictStrategy
    let rules: [FolderClassificationRule]
}

enum RemovableVolumeAccessStore {
    nonisolated(unsafe) private static let defaults = UserDefaults.standard
    private static let bookmarkStoreKey = "removableVolumeBookmarks"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var activeSessions: [String: ActiveRemovableVolumeSession] = [:]

    static func withAccess<T>(
        to url: URL,
        _ body: (URL) throws -> T
    ) rethrows -> T {
        let access = beginAccess(to: url)
        defer {
            access.stop()
        }

        return try body(access.url)
    }

    static func withAccess<T>(
        to url: URL,
        _ body: (URL) async throws -> T
    ) async rethrows -> T {
        let access = beginAccess(to: url)
        defer {
            access.stop()
        }

        return try await body(access.url)
    }

    private static func beginAccess(to originalURL: URL) -> RemovableVolumeAccess {
        let standardizedURL = originalURL.standardizedFileURL
        let key = standardizedURL.path

        lock.lock()
        if let session = activeSessions[key] {
            session.referenceCount += 1
            let url = session.url
            lock.unlock()
            return RemovableVolumeAccess(url: url) {
                endAccess(forKey: key)
            }
        }
        lock.unlock()

        let resolvedURL = resolvedBookmarkedURL(for: standardizedURL) ?? standardizedURL
        let didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()
        persistBookmarkIfPossible(for: resolvedURL)

        let newSession = ActiveRemovableVolumeSession(
            url: resolvedURL,
            shouldStopAccessing: didStartAccessing
        )

        lock.lock()
        if let existingSession = activeSessions[key] {
            existingSession.referenceCount += 1
            let url = existingSession.url
            lock.unlock()

            if didStartAccessing {
                resolvedURL.stopAccessingSecurityScopedResource()
            }

            return RemovableVolumeAccess(url: url) {
                endAccess(forKey: key)
            }
        }

        activeSessions[key] = newSession
        lock.unlock()

        return RemovableVolumeAccess(url: resolvedURL) {
            endAccess(forKey: key)
        }
    }

    private static func endAccess(forKey key: String) {
        let sessionToClose: ActiveRemovableVolumeSession?

        lock.lock()
        if let session = activeSessions[key] {
            session.referenceCount -= 1
            if session.referenceCount <= 0 {
                activeSessions.removeValue(forKey: key)
                sessionToClose = session
            } else {
                sessionToClose = nil
            }
        } else {
            sessionToClose = nil
        }
        lock.unlock()

        guard let sessionToClose, sessionToClose.shouldStopAccessing else { return }
        sessionToClose.url.stopAccessingSecurityScopedResource()
    }

    private static func resolvedBookmarkedURL(for fallbackURL: URL) -> URL? {
        guard let bookmarkData = storedBookmarks[fallbackURL.path] else {
            return nil
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                persistBookmarkIfPossible(for: resolvedURL)
            }

            return resolvedURL
        } catch {
            removeBookmark(forKey: fallbackURL.path)
            return nil
        }
    }

    private static func persistBookmarkIfPossible(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveBookmark(bookmark, forKey: url.standardizedFileURL.path)
        } catch {
            // 外接卷 bookmark 持久化失败时，至少保留本次 access session，避免同一轮任务继续连弹。
        }
    }

    private static var storedBookmarks: [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        return defaults.dictionary(forKey: bookmarkStoreKey) as? [String: Data] ?? [:]
    }

    private static func saveBookmark(_ bookmark: Data, forKey key: String) {
        lock.lock()
        var bookmarks = defaults.dictionary(forKey: bookmarkStoreKey) as? [String: Data] ?? [:]
        bookmarks[key] = bookmark
        defaults.set(bookmarks, forKey: bookmarkStoreKey)
        lock.unlock()
    }

    private static func removeBookmark(forKey key: String) {
        lock.lock()
        var bookmarks = defaults.dictionary(forKey: bookmarkStoreKey) as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: key)
        defaults.set(bookmarks, forKey: bookmarkStoreKey)
        lock.unlock()
    }

    private final class ActiveRemovableVolumeSession {
        let url: URL
        let shouldStopAccessing: Bool
        var referenceCount: Int

        init(url: URL, shouldStopAccessing: Bool, referenceCount: Int = 1) {
            self.url = url
            self.shouldStopAccessing = shouldStopAccessing
            self.referenceCount = referenceCount
        }
    }

    private struct RemovableVolumeAccess {
        let url: URL
        let stopHandler: () -> Void

        func stop() {
            stopHandler()
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // 这里保留一个可读的 path，主要用于 UI 显示和兼容旧配置。
    @Published var destinationFolderPath: String {
        didSet {
            Self.defaults.set(destinationFolderPath, forKey: Self.destinationFolderKey)
        }
    }

    @Published var autoImportEnabled: Bool {
        didSet {
            Self.defaults.set(autoImportEnabled, forKey: Self.autoImportKey)
        }
    }

    @Published var autoImportEnabledVolumeIDs: Set<String> {
        didSet {
            Self.defaults.set(Array(autoImportEnabledVolumeIDs).sorted(), forKey: Self.autoImportEnabledVolumeIDsKey)
        }
    }

    @Published var folderClassificationEnabled: Bool {
        didSet {
            Self.defaults.set(folderClassificationEnabled, forKey: Self.folderClassificationEnabledKey)
        }
    }

    @Published var folderConflictStrategy: FolderConflictStrategy {
        didSet {
            Self.defaults.set(folderConflictStrategy.rawValue, forKey: Self.folderConflictStrategyKey)
        }
    }

    @Published var folderClassificationRules: [FolderClassificationRule] {
        didSet {
            persistFolderClassificationRules()
        }
    }

    @Published private(set) var classificationLogs: [FolderClassificationLogEntry] {
        didSet {
            persistClassificationLogs()
        }
    }

    private static let destinationFolderKey = "destinationFolderPath"
    private static let destinationFolderBookmarkKey = "destinationFolderBookmark"
    private static let autoImportKey = "autoImportEnabled"
    private static let autoImportEnabledVolumeIDsKey = "autoImportEnabledVolumeIDs"
    private static let folderClassificationEnabledKey = "folderClassificationEnabled"
    private static let folderConflictStrategyKey = "folderConflictStrategy"
    private static let folderClassificationRulesKey = "folderClassificationRules"
    private static let classificationLogsKey = "classificationLogs"
    private static let maxClassificationLogs = 300
    private static let defaults = UserDefaults.standard

    init() {
        self.destinationFolderPath = ""
        self.autoImportEnabled = Self.defaults.bool(forKey: Self.autoImportKey)
        self.autoImportEnabledVolumeIDs = Set(Self.defaults.stringArray(forKey: Self.autoImportEnabledVolumeIDsKey) ?? [])
        self.folderClassificationEnabled = Self.defaults.object(forKey: Self.folderClassificationEnabledKey) as? Bool ?? false
        self.folderConflictStrategy = FolderConflictStrategy(rawValue: Self.defaults.string(forKey: Self.folderConflictStrategyKey) ?? "") ?? .rename
        self.folderClassificationRules = Self.decode([FolderClassificationRule].self, from: Self.folderClassificationRulesKey) ?? []
        self.classificationLogs = Self.decode([FolderClassificationLogEntry].self, from: Self.classificationLogsKey) ?? []
        restoreDestinationFolder()
    }

#if DEBUG
    init(
        previewDestinationFolderPath: String,
        autoImportEnabled: Bool,
        previewAutoImportEnabledVolumeIDs: Set<String> = [],
        previewFolderClassificationEnabled: Bool = false,
        previewFolderConflictStrategy: FolderConflictStrategy = .rename,
        previewFolderClassificationRules: [FolderClassificationRule] = [],
        previewClassificationLogs: [FolderClassificationLogEntry] = []
    ) {
        self.destinationFolderPath = previewDestinationFolderPath
        self.autoImportEnabled = autoImportEnabled
        self.autoImportEnabledVolumeIDs = previewAutoImportEnabledVolumeIDs
        self.folderClassificationEnabled = previewFolderClassificationEnabled
        self.folderConflictStrategy = previewFolderConflictStrategy
        self.folderClassificationRules = previewFolderClassificationRules
        self.classificationLogs = previewClassificationLogs
    }
#endif

    var destinationFolderURL: URL? {
        resolvedDestinationFolderURL()
    }

    var folderClassificationConfiguration: FolderClassificationConfiguration {
        FolderClassificationConfiguration(
            isEnabled: folderClassificationEnabled,
            rules: folderClassificationRules,
            conflictStrategy: folderConflictStrategy
        )
    }

    var enabledRuleCount: Int {
        folderClassificationRules.filter { $0.isEnabled && $0.isConfigured }.count
    }

    func isAutoImportEnabled(forVolumeID volumeID: String) -> Bool {
        autoImportEnabledVolumeIDs.contains(volumeID)
    }

    func setAutoImport(_ isEnabled: Bool, forVolumeID volumeID: String) {
        let normalizedVolumeID = volumeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVolumeID.isEmpty else { return }

        if isEnabled {
            autoImportEnabledVolumeIDs.insert(normalizedVolumeID)
        } else {
            autoImportEnabledVolumeIDs.remove(normalizedVolumeID)
        }
    }

    func toggleAutoImport(forVolumeID volumeID: String) {
        setAutoImport(!isAutoImportEnabled(forVolumeID: volumeID), forVolumeID: volumeID)
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

    func chooseDestinationFolderForClassification() {
        chooseDestinationFolder()
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

    func addFolderClassificationRule() {
        folderClassificationRules.append(FolderClassificationRule())
    }

    func removeFolderClassificationRule(id: UUID) {
        folderClassificationRules.removeAll { $0.id == id }
    }

    func moveFolderClassificationRule(id: UUID, offset: Int) {
        guard let currentIndex = folderClassificationRules.firstIndex(where: { $0.id == id }) else {
            return
        }

        let nextIndex = currentIndex + offset
        guard folderClassificationRules.indices.contains(nextIndex) else {
            return
        }

        let rule = folderClassificationRules.remove(at: currentIndex)
        folderClassificationRules.insert(rule, at: nextIndex)
    }

    func testRuleMatch(for folderName: String) -> FolderClassificationRule? {
        folderClassificationConfiguration.matchingRule(for: folderName)
    }

    @discardableResult
    func exportFolderClassificationRules() throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "folder-classification-rules.json"
        panel.title = "导出文件夹分类规则"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let payload = FolderClassificationExportPayload(
            isEnabled: folderClassificationEnabled,
            conflictStrategy: folderConflictStrategy,
            rules: folderClassificationRules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func importFolderClassificationRules() throws -> Int? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = "导入文件夹分类规则"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let payload = try decoder.decode(FolderClassificationExportPayload.self, from: data)
        folderClassificationEnabled = payload.isEnabled
        folderConflictStrategy = payload.conflictStrategy
        folderClassificationRules = payload.rules
        return payload.rules.count
    }

    func createClassificationFolders() async throws -> Int {
        let configuredTargetFolders = Array(
            Set(
                folderClassificationRules
                    .filter { $0.isEnabled && $0.isConfigured }
                    .map(\.normalizedTargetFolderPath)
            )
        )
        .sorted()

        guard !configuredTargetFolders.isEmpty else {
            return 0
        }

        return try await withDestinationFolderAccess { destinationRoot in
            let fileManager = FileManager.default
            for relativePath in configuredTargetFolders {
                let targetURL = destinationRoot.appendingPathComponent(relativePath, isDirectory: true)
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            }
            return configuredTargetFolders.count
        }
    }

    func appendClassificationLogs(_ entries: [FolderClassificationLogEntry]) {
        guard !entries.isEmpty else { return }
        classificationLogs = Array((entries + classificationLogs).prefix(Self.maxClassificationLogs))
    }

    func clearClassificationLogs() {
        classificationLogs = []
    }

    private func restoreDestinationFolder() {
        // 优先恢复 bookmark；如果是老版本只存了 path，就顺手迁移一次。
        if let url = resolvedDestinationFolderURL(refreshBookmarkIfNeeded: true) {
            destinationFolderPath = url.path
            return
        }

        destinationFolderPath = Self.defaults.string(forKey: Self.destinationFolderKey) ?? ""
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
            Self.defaults.set(bookmark, forKey: Self.destinationFolderBookmarkKey)
            destinationFolderPath = url.path
        } catch {
            Self.defaults.removeObject(forKey: Self.destinationFolderBookmarkKey)
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
        if let bookmarkData = Self.defaults.data(forKey: Self.destinationFolderBookmarkKey) {
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
                Self.defaults.removeObject(forKey: Self.destinationFolderBookmarkKey)
            }
        }

        guard !destinationFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: destinationFolderPath, isDirectory: true)
    }

    private func persistFolderClassificationRules() {
        persistEncoded(folderClassificationRules, forKey: Self.folderClassificationRulesKey)
    }

    private func persistClassificationLogs() {
        persistEncoded(classificationLogs, forKey: Self.classificationLogsKey)
    }

    private func persistEncoded<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            Self.defaults.set(data, forKey: key)
        } catch {
            Self.defaults.removeObject(forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from key: String) -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
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
