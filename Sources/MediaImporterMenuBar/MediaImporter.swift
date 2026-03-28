import Combine
import Foundation

enum MediaFileKind: Sendable {
    case photo
    case video
}

enum MediaCatalogSupport {
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "bmp", "tif", "tiff", "raw", "dng",
    ]
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mts", "m2ts", "mpg", "mpeg", "wmv", "mkv",
    ]
    static let allowedExtensions = photoExtensions.union(videoExtensions)

    static func kind(forNormalizedExtension fileExtension: String) -> MediaFileKind? {
        if photoExtensions.contains(fileExtension) {
            return .photo
        }

        if videoExtensions.contains(fileExtension) {
            return .video
        }

        return nil
    }
}

struct ExistingMediaNameIndex: Sendable {
    let photoNames: Set<String>
    let videoNames: Set<String>

    static let empty = ExistingMediaNameIndex(photoNames: [], videoNames: [])

    func contains(_ filename: String, kind: MediaFileKind) -> Bool {
        let normalizedName = filename.lowercased()

        switch kind {
        case .photo:
            return photoNames.contains(normalizedName)
        case .video:
            return videoNames.contains(normalizedName)
        }
    }
}

enum MediaFileCatalog {
    static func buildExistingNameIndex(at destinationRoot: URL) -> ExistingMediaNameIndex {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: destinationRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var photoNames: Set<String> = []
        var videoNames: Set<String> = []

        while let fileURL = enumerator?.nextObject() as? URL {
            if Task.isCancelled {
                break
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory != true else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            let normalizedName = fileURL.lastPathComponent.lowercased()

            switch MediaCatalogSupport.kind(forNormalizedExtension: fileExtension) {
            case .photo:
                photoNames.insert(normalizedName)
            case .video:
                videoNames.insert(normalizedName)
            case nil:
                break
            }
        }

        return ExistingMediaNameIndex(photoNames: photoNames, videoNames: videoNames)
    }
}

@MainActor
final class MediaImporter: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var lastResultMessage = "等待导入"
    @Published private(set) var importProgress: Double?
    @Published private(set) var currentImportVolumeID: String?
    @Published private(set) var importedBytes: Int64 = 0
    @Published private(set) var totalImportBytes: Int64 = 0
    @Published private(set) var importedPhotoCount = 0
    @Published private(set) var totalPhotoCount = 0
    @Published private(set) var importedVideoCount = 0
    @Published private(set) var totalVideoCount = 0

    private var currentImportTask: Task<ImportResult, Error>?
    private var progressRefreshTask: Task<Void, Never>?
    private var statusResetTask: Task<Void, Never>?
    private var importStartDate: Date?
    private var lastProgressRevision: UInt64 = 0
    private var lastProgressUpdateDate: Date?
    private var lastSampledImportedBytes: Int64 = 0
    private var smoothedBytesPerSecond: Double?

    init() {}

#if DEBUG
    init(
        previewIsImporting: Bool,
        previewMessage: String,
        previewProgress: Double?,
        previewCurrentImportVolumeID: String?,
        previewImportedBytes: Int64,
        previewTotalImportBytes: Int64,
        previewImportedPhotoCount: Int,
        previewTotalPhotoCount: Int,
        previewImportedVideoCount: Int,
        previewTotalVideoCount: Int
    ) {
        self.isImporting = previewIsImporting
        self.lastResultMessage = previewMessage
        self.importProgress = previewProgress
        self.currentImportVolumeID = previewCurrentImportVolumeID
        self.importedBytes = previewImportedBytes
        self.totalImportBytes = previewTotalImportBytes
        self.importedPhotoCount = previewImportedPhotoCount
        self.totalPhotoCount = previewTotalPhotoCount
        self.importedVideoCount = previewImportedVideoCount
        self.totalVideoCount = previewTotalVideoCount
        if previewIsImporting, previewImportedBytes > 0, previewTotalImportBytes > previewImportedBytes {
            self.importStartDate = Date().addingTimeInterval(-90)
            self.lastProgressUpdateDate = Date()
            self.lastSampledImportedBytes = previewImportedBytes
            self.smoothedBytesPerSecond = Double(previewImportedBytes) / 90
        }
    }
#endif

    func importMedia(from volume: MountedVolume, to destinationFolder: URL, settings: AppSettings) async -> Bool {
        guard !isImporting else { return false }
        startImportSession(for: volume)
        setPersistentStatusMessage("正在导入 \(volume.name)...")

        defer {
            resetImportSession()
        }

        do {
            let classificationConfiguration = settings.folderClassificationConfiguration
            let progressBuffer = ImportProgressBuffer()
            startProgressRefresh(using: progressBuffer, volumeName: volume.name)
            let task = Task.detached(priority: .userInitiated) { [volume, destinationFolder] in
                try ImportWorker.copyMediaFiles(
                    from: volume.url,
                    to: destinationFolder,
                    volumeName: volume.name,
                    classificationConfiguration: classificationConfiguration
                ) { progress in
                    progressBuffer.store(progress)
                }
            }
            currentImportTask = task
            let result = try await task.value
            applyBufferedProgress(from: progressBuffer, volumeName: volume.name, force: true)
            progressRefreshTask?.cancel()
            progressRefreshTask = nil
            settings.appendClassificationLogs(result.classificationLogs)

            if result.copiedCount == 0 {
                if result.skippedExistingCount > 0 {
                    setStatusMessage(
                        "已跳过 \(result.skippedExistingCount) 个已导入文件",
                        autoDismissAfter: 3.6
                    )
                } else {
                    setStatusMessage("\(volume.name) 中没有找到可导入的媒体文件", autoDismissAfter: 3.6)
                }
            } else {
                if result.skippedExistingCount > 0 {
                    setStatusMessage(
                        "已导入 \(result.copiedCount) 个文件，跳过 \(result.skippedExistingCount) 个已导入文件",
                        autoDismissAfter: 3.8
                    )
                } else {
                    setStatusMessage("已导入 \(result.copiedCount) 个文件到 \(result.destinationFolderName)", autoDismissAfter: 3.6)
                }
            }
            return true
        } catch is CancellationError {
            setStatusMessage("已取消导入", autoDismissAfter: 2.8)
            return false
        } catch {
            setStatusMessage("导入失败：\(error.localizedDescription)", autoDismissAfter: 4.2)
            return false
        }
    }

    func cancelImport() {
        currentImportTask?.cancel()
        setPersistentStatusMessage("正在取消导入...")
    }

    func setStatusMessage(_ message: String) {
        setStatusMessage(message, autoDismissAfter: 3.2)
    }

    func setStatusMessage(_ message: String, autoDismissAfter delay: TimeInterval) {
        lastResultMessage = message
        scheduleStatusReset(after: delay, expectedMessage: message)
    }

    var importRemainingTimeText: String? {
        guard totalImportBytes > 0,
              importedBytes > 0,
              let importStartDate else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(importStartDate)
        guard elapsed > 0.2 else { return nil }

        let fallbackBytesPerSecond = Double(importedBytes) / elapsed
        let bytesPerSecond = smoothedBytesPerSecond ?? fallbackBytesPerSecond
        guard bytesPerSecond > 0 else { return nil }

        let remainingBytes = max(0, totalImportBytes - importedBytes)
        let remainingSeconds = Double(remainingBytes) / bytesPerSecond

        return Self.remainingTimeText(remainingSeconds)
    }

    var importProgressDetailText: String? {
        guard totalImportBytes > 0 else { return nil }
        return "\(Self.progressByteText(importedBytes)) / \(Self.progressByteText(totalImportBytes))"
    }

    private func startProgressRefresh(using progressBuffer: ImportProgressBuffer, volumeName: String) {
        progressRefreshTask?.cancel()
        progressRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.applyBufferedProgress(from: progressBuffer, volumeName: volumeName)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func applyBufferedProgress(
        from progressBuffer: ImportProgressBuffer,
        volumeName: String,
        force: Bool = false
    ) {
        let (snapshot, revision) = progressBuffer.snapshot()
        guard let snapshot else { return }
        guard force || revision != lastProgressRevision else { return }

        lastProgressRevision = revision
        apply(snapshot: snapshot, volumeName: volumeName)
    }

    private func apply(snapshot: ImportProgressSnapshot, volumeName: String) {
        let now = Date()

        if let lastProgressUpdateDate,
           snapshot.importedBytes > lastSampledImportedBytes {
            let deltaSeconds = now.timeIntervalSince(lastProgressUpdateDate)
            let deltaBytes = snapshot.importedBytes - lastSampledImportedBytes

            if deltaSeconds > 0.03, deltaBytes > 0 {
                let instantaneousSpeed = Double(deltaBytes) / deltaSeconds

                if instantaneousSpeed.isFinite {
                    if let smoothedBytesPerSecond {
                        self.smoothedBytesPerSecond = (smoothedBytesPerSecond * 0.78) + (instantaneousSpeed * 0.22)
                    } else {
                        self.smoothedBytesPerSecond = instantaneousSpeed
                    }
                }
            }
        }

        lastProgressUpdateDate = now
        lastSampledImportedBytes = snapshot.importedBytes
        importedBytes = snapshot.importedBytes
        totalImportBytes = snapshot.totalBytes
        importedPhotoCount = snapshot.importedPhotoCount
        totalPhotoCount = snapshot.totalPhotoCount
        importedVideoCount = snapshot.importedVideoCount
        totalVideoCount = snapshot.totalVideoCount
        importProgress = snapshot.totalBytes > 0 ? Double(snapshot.importedBytes) / Double(snapshot.totalBytes) : nil
        setPersistentStatusMessage("正在导入 \(volumeName)...")
    }

    private func startImportSession(for volume: MountedVolume) {
        statusResetTask?.cancel()
        statusResetTask = nil
        isImporting = true
        currentImportVolumeID = volume.id
        importProgress = 0
        importedBytes = 0
        totalImportBytes = 0
        importedPhotoCount = 0
        totalPhotoCount = 0
        importedVideoCount = 0
        totalVideoCount = 0
        importStartDate = Date()
        lastProgressRevision = 0
        lastProgressUpdateDate = importStartDate
        lastSampledImportedBytes = 0
        smoothedBytesPerSecond = nil
    }

    private func resetImportSession() {
        progressRefreshTask?.cancel()
        progressRefreshTask = nil
        isImporting = false
        importProgress = nil
        currentImportVolumeID = nil
        importedBytes = 0
        totalImportBytes = 0
        importedPhotoCount = 0
        totalPhotoCount = 0
        importedVideoCount = 0
        totalVideoCount = 0
        importStartDate = nil
        lastProgressRevision = 0
        lastProgressUpdateDate = nil
        lastSampledImportedBytes = 0
        smoothedBytesPerSecond = nil
        currentImportTask = nil
    }

    private func setPersistentStatusMessage(_ message: String) {
        statusResetTask?.cancel()
        statusResetTask = nil
        lastResultMessage = message
    }

    private func scheduleStatusReset(after delay: TimeInterval, expectedMessage: String) {
        statusResetTask?.cancel()
        statusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !self.isImporting, self.lastResultMessage == expectedMessage else { return }
            self.lastResultMessage = "等待导入"
            self.statusResetTask = nil
        }
    }

    struct ImportResult: Sendable {
        let copiedCount: Int
        let skippedExistingCount: Int
        let destinationFolderName: String
        let classificationLogs: [FolderClassificationLogEntry]
    }

    struct ImportProgressSnapshot: Sendable {
        let importedBytes: Int64
        let totalBytes: Int64
        let importedPhotoCount: Int
        let totalPhotoCount: Int
        let importedVideoCount: Int
        let totalVideoCount: Int
    }

    enum ImportError: LocalizedError {
        case destinationInsideSourceVolume

        var errorDescription: String? {
            switch self {
            case .destinationInsideSourceVolume:
                return "导入目标文件夹不能位于正在导入的设备内部，请选择 Mac 本地磁盘上的文件夹。"
            }
        }
    }

    nonisolated static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents

        guard candidateComponents.count >= ancestorComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    private static func progressByteText(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }

        switch unitIndex {
        case 1, 2:
            return String(format: "%.2f %@", value, units[unitIndex])
        default:
            return String(format: "%.3f %@", value, units[unitIndex])
        }
    }

    private static func remainingTimeText(_ seconds: TimeInterval) -> String {
        let clampedSeconds = max(0, Int(seconds.rounded(.up)))
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60
        let remainingSeconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private final class ImportProgressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var latestSnapshot: MediaImporter.ImportProgressSnapshot?
    private var revision: UInt64 = 0

    func store(_ snapshot: MediaImporter.ImportProgressSnapshot) {
        lock.lock()
        latestSnapshot = snapshot
        revision &+= 1
        lock.unlock()
    }

    func snapshot() -> (MediaImporter.ImportProgressSnapshot?, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (latestSnapshot, revision)
    }
}

private enum ImportWorker {
    static func copyMediaFiles(
        from sourceRoot: URL,
        to destinationFolder: URL,
        volumeName: String,
        classificationConfiguration: FolderClassificationConfiguration,
        onProgress: @escaping @Sendable (_ progress: MediaImporter.ImportProgressSnapshot) -> Void
    ) throws -> MediaImporter.ImportResult {
        try RemovableVolumeAccessStore.withAccess(to: sourceRoot) { accessibleSourceRoot in
            let fileManager = FileManager.default
            let standardizedSourceRoot = accessibleSourceRoot.standardizedFileURL
            let standardizedDestinationFolder = destinationFolder.standardizedFileURL

            guard !MediaImporter.isSameOrDescendant(standardizedDestinationFolder, of: standardizedSourceRoot) else {
                throw MediaImporter.ImportError.destinationInsideSourceVolume
            }

            let mediaFiles = try collectMediaFiles(from: accessibleSourceRoot)

            let existingNameIndex = MediaFileCatalog.buildExistingNameIndex(at: standardizedDestinationFolder)

            var pendingMediaFiles: [ImportableFile] = []
            var skippedExistingPhotoCount = 0
            var skippedExistingVideoCount = 0
            var totalPhotoCount = 0
            var totalVideoCount = 0

            for file in mediaFiles {
                if existingNameIndex.contains(file.url.lastPathComponent, kind: file.kind.mediaFileKind) {
                    switch file.kind {
                    case .photo:
                        skippedExistingPhotoCount += 1
                    case .video:
                        skippedExistingVideoCount += 1
                    }
                } else {
                    pendingMediaFiles.append(file)
                    switch file.kind {
                    case .photo:
                        totalPhotoCount += 1
                    case .video:
                        totalVideoCount += 1
                    }
                }
            }

            let skippedExistingCount = skippedExistingPhotoCount + skippedExistingVideoCount
            let timestamp = makeImportFolderName()
            let finalFolder = standardizedDestinationFolder
                .appendingPathComponent(volumeName, isDirectory: true)
                .appendingPathComponent(timestamp, isDirectory: true)

            let totalBytes = pendingMediaFiles.reduce(into: Int64(0)) { partialResult, file in
                partialResult += file.size
            }
            let pendingPhotoCount = totalPhotoCount
            let pendingVideoCount = totalVideoCount
            var importedBytes: Int64 = 0
            var copiedCount = 0
            var importedPhotoCount = 0
            var importedVideoCount = 0
            var classificationLogs: [FolderClassificationLogEntry] = []
            onProgress(
                MediaImporter.ImportProgressSnapshot(
                    importedBytes: importedBytes,
                    totalBytes: totalBytes,
                    importedPhotoCount: importedPhotoCount,
                    totalPhotoCount: pendingPhotoCount,
                    importedVideoCount: importedVideoCount,
                    totalVideoCount: pendingVideoCount
                )
            )

            guard !pendingMediaFiles.isEmpty else {
                return MediaImporter.ImportResult(
                    copiedCount: 0,
                    skippedExistingCount: skippedExistingCount,
                    destinationFolderName: finalFolder.lastPathComponent,
                    classificationLogs: []
                )
            }

            try fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)

            for file in pendingMediaFiles {
                try Task.checkCancellation()
                let matchedRule = file.kind == .video
                    ? classificationConfiguration.matchingRule(for: file.sourceFolderName)
                    : nil
                let targetFolder = matchedRule.map {
                    standardizedDestinationFolder.appendingPathComponent($0.normalizedTargetFolderPath, isDirectory: true)
                } ?? finalFolder
                try fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                let uniqueTarget = try resolvedDestinationURL(
                    for: file.url.lastPathComponent,
                    in: targetFolder,
                    strategy: classificationConfiguration.conflictStrategy,
                    fileManager: fileManager
                )
                let baseImportedBytes = importedBytes
                let currentImportedPhotoCount = importedPhotoCount
                let currentImportedVideoCount = importedVideoCount
                try copyFileInChunks(from: file.url, to: uniqueTarget) { copiedBytesForFile in
                    onProgress(
                        MediaImporter.ImportProgressSnapshot(
                            importedBytes: baseImportedBytes + copiedBytesForFile,
                            totalBytes: totalBytes,
                            importedPhotoCount: currentImportedPhotoCount,
                            totalPhotoCount: pendingPhotoCount,
                            importedVideoCount: currentImportedVideoCount,
                            totalVideoCount: pendingVideoCount
                        )
                    )
                }
                copiedCount += 1
                importedBytes += file.size
                switch file.kind {
                case .photo:
                    importedPhotoCount += 1
                case .video:
                    importedVideoCount += 1
                }
                classificationLogs.append(
                    FolderClassificationLogEntry(
                        fileName: file.url.lastPathComponent,
                        sourceFolderName: file.sourceFolderName,
                        destinationSubpath: relativeDisplayPath(for: uniqueTarget, root: standardizedDestinationFolder),
                        ruleKeyword: matchedRule?.keyword,
                        ruleTargetFolderName: matchedRule?.normalizedTargetFolderPath,
                        didMatchRule: matchedRule != nil,
                        conflictStrategy: classificationConfiguration.conflictStrategy
                    )
                )
                onProgress(
                    MediaImporter.ImportProgressSnapshot(
                        importedBytes: importedBytes,
                        totalBytes: totalBytes,
                        importedPhotoCount: importedPhotoCount,
                        totalPhotoCount: pendingPhotoCount,
                        importedVideoCount: importedVideoCount,
                        totalVideoCount: pendingVideoCount
                    )
                )
            }

            return MediaImporter.ImportResult(
                copiedCount: copiedCount,
                skippedExistingCount: skippedExistingCount,
                destinationFolderName: finalFolder.lastPathComponent,
                classificationLogs: classificationLogs
            )
        }
    }

    private static func collectMediaFiles(
        from sourceRoot: URL
    ) throws -> [ImportableFile] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var mediaFiles: [ImportableFile] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            guard MediaCatalogSupport.allowedExtensions.contains(fileExtension),
                  let mediaKind = MediaCatalogSupport.kind(forNormalizedExtension: fileExtension) else {
                continue
            }

            mediaFiles.append(
                ImportableFile(
                    url: fileURL,
                    size: Int64(values.fileSize ?? 0),
                    kind: .init(mediaFileKind: mediaKind),
                    sourceFolderName: fileURL.deletingLastPathComponent().lastPathComponent
                )
            )
        }

        return mediaFiles
    }

    private static func resolvedDestinationURL(
        for filename: String,
        in folder: URL,
        strategy: FolderConflictStrategy,
        fileManager: FileManager
    ) throws -> URL {
        let original = folder.appendingPathComponent(filename)

        switch strategy {
        case .rename:
            return uniqueDestinationURL(for: filename, in: folder, fileManager: fileManager)
        case .replace:
            if fileManager.fileExists(atPath: original.path) {
                try fileManager.removeItem(at: original)
            }
            return original
        }
    }

    private static func uniqueDestinationURL(for filename: String, in folder: URL, fileManager: FileManager) -> URL {
        let original = folder.appendingPathComponent(filename)

        guard !fileManager.fileExists(atPath: original.path) else {
            let ext = original.pathExtension
            let base = original.deletingPathExtension().lastPathComponent

            for index in 1...10_000 {
                let candidateName: String
                if ext.isEmpty {
                    candidateName = "\(base)-\(index)"
                } else {
                    candidateName = "\(base)-\(index).\(ext)"
                }

                let candidate = folder.appendingPathComponent(candidateName)
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            return folder.appendingPathComponent(UUID().uuidString + "-" + filename)
        }

        return original
    }

    private static func relativeDisplayPath(for fileURL: URL, root: URL) -> String {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        return relativeComponents.joined(separator: "/")
    }

    private static func copyFileInChunks(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (_ copiedBytes: Int64) -> Void
    ) throws {
        let fileManager = FileManager.default
        let parentDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: destinationURL.path, contents: nil)

        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)

        var copiedBytes: Int64 = 0
        let chunkSize = 128 * 1024

        do {
            while true {
                try Task.checkCancellation()
                let data = try inputHandle.read(upToCount: chunkSize) ?? Data()
                if data.isEmpty {
                    break
                }

                try outputHandle.write(contentsOf: data)
                copiedBytes += Int64(data.count)
                progress(copiedBytes)
            }
        } catch {
            try? inputHandle.close()
            try? outputHandle.close()
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        progress(copiedBytes)
        try inputHandle.close()
        try outputHandle.close()
    }

    private static func makeImportFolderName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private struct ImportableFile: Sendable {
        enum Kind: Sendable {
            case photo
            case video

            init(mediaFileKind: MediaFileKind) {
                switch mediaFileKind {
                case .photo:
                    self = .photo
                case .video:
                    self = .video
                }
            }

            var mediaFileKind: MediaFileKind {
                switch self {
                case .photo:
                    return .photo
                case .video:
                    return .video
                }
            }
        }

        let url: URL
        let size: Int64
        let kind: Kind
        let sourceFolderName: String
    }
}
