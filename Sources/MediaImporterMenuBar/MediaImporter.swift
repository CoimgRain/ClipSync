import Combine
import Foundation

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
    private var importStartDate: Date?
    private var lastProgressRevision: UInt64 = 0
    private var lastProgressUpdateDate: Date?
    private var lastSampledImportedBytes: Int64 = 0
    private var smoothedBytesPerSecond: Double?

    private let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "bmp", "tif", "tiff", "raw", "dng",
    ]
    private let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mts", "m2ts", "mpg", "mpeg", "wmv", "mkv",
    ]
    private let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "bmp", "tif", "tiff", "raw", "dng",
        "mp4", "mov", "m4v", "avi", "mts", "m2ts", "mpg", "mpeg", "wmv", "mkv",
    ]

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

    func importMedia(from volume: MountedVolume, to destinationFolder: URL) async -> Bool {
        guard !isImporting else { return false }
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
        lastResultMessage = "正在导入 \(volume.name)..."

        defer {
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

        do {
            let allowedExtensions = self.allowedExtensions
            let photoExtensions = self.photoExtensions
            let videoExtensions = self.videoExtensions
            let progressBuffer = ImportProgressBuffer()
            startProgressRefresh(using: progressBuffer, volumeName: volume.name)
            let task = Task.detached(priority: .userInitiated) { [volume, destinationFolder] in
                try ImportWorker.copyMediaFiles(
                    from: volume.url,
                    to: destinationFolder,
                    volumeName: volume.name,
                    allowedExtensions: allowedExtensions,
                    photoExtensions: photoExtensions,
                    videoExtensions: videoExtensions
                ) { progress in
                    progressBuffer.store(progress)
                }
            }
            currentImportTask = task
            let result = try await task.value
            applyBufferedProgress(from: progressBuffer, volumeName: volume.name, force: true)
            progressRefreshTask?.cancel()
            progressRefreshTask = nil

            if result.copiedCount == 0 {
                lastResultMessage = "\(volume.name) 中没有找到可导入的媒体文件"
            } else {
                lastResultMessage = "已导入 \(result.copiedCount) 个文件到 \(result.destinationFolderName)"
            }
            return true
        } catch is CancellationError {
            lastResultMessage = "已取消导入"
            return false
        } catch {
            lastResultMessage = "导入失败：\(error.localizedDescription)"
            return false
        }
    }

    func cancelImport() {
        currentImportTask?.cancel()
        lastResultMessage = "正在取消导入..."
    }

    func setStatusMessage(_ message: String) {
        lastResultMessage = message
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
        let referenceDate = lastProgressUpdateDate ?? importStartDate
        let adjustmentWindow = min(Date().timeIntervalSince(referenceDate), 1)
        let adjustedRemainingBytes = max(0, Double(remainingBytes) - bytesPerSecond * adjustmentWindow)
        let remainingSeconds = adjustedRemainingBytes / bytesPerSecond

        return Self.remainingTimeText(remainingSeconds)
    }

    var importProgressDetailText: String? {
        guard totalImportBytes > 0 else { return nil }
        return "\(Self.progressByteText(importedBytes)) / \(Self.progressByteText(totalImportBytes))"
    }

    var importProgressCountText: String? {
        guard totalPhotoCount > 0 || totalVideoCount > 0 else { return nil }

        return "\(importedPhotoCount) / \(totalPhotoCount) 张照片, \(importedVideoCount) / \(totalVideoCount) 个视频"
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
        lastResultMessage = "正在导入 \(volumeName)..."
    }

    struct ImportResult: Sendable {
        let copiedCount: Int
        let destinationFolderName: String
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

    static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents

        guard candidateComponents.count >= ancestorComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    private static func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
        allowedExtensions: Set<String>,
        photoExtensions: Set<String>,
        videoExtensions: Set<String>,
        onProgress: @escaping @Sendable (_ progress: MediaImporter.ImportProgressSnapshot) -> Void
    ) throws -> MediaImporter.ImportResult {
        let fileManager = FileManager.default
        let standardizedSourceRoot = sourceRoot.standardizedFileURL
        let standardizedDestinationFolder = destinationFolder.standardizedFileURL

        guard !isSameOrDescendant(standardizedDestinationFolder, of: standardizedSourceRoot) else {
            throw MediaImporter.ImportError.destinationInsideSourceVolume
        }

        let timestamp = makeImportFolderName()
        let finalFolder = standardizedDestinationFolder
            .appendingPathComponent(volumeName, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        try fileManager.createDirectory(at: finalFolder, withIntermediateDirectories: true)

        let mediaFiles = try collectMediaFiles(
            from: sourceRoot,
            allowedExtensions: allowedExtensions,
            photoExtensions: photoExtensions,
            videoExtensions: videoExtensions
        )

        let totalBytes = mediaFiles.reduce(into: Int64(0)) { partialResult, file in
            partialResult += file.size
        }
        let totalPhotoCount = mediaFiles.filter { $0.kind == .photo }.count
        let totalVideoCount = mediaFiles.filter { $0.kind == .video }.count
        var importedBytes: Int64 = 0
        var copiedCount = 0
        var importedPhotoCount = 0
        var importedVideoCount = 0
        onProgress(
            MediaImporter.ImportProgressSnapshot(
                importedBytes: importedBytes,
                totalBytes: totalBytes,
                importedPhotoCount: importedPhotoCount,
                totalPhotoCount: totalPhotoCount,
                importedVideoCount: importedVideoCount,
                totalVideoCount: totalVideoCount
            )
        )

        for file in mediaFiles {
            try Task.checkCancellation()
            let uniqueTarget = uniqueDestinationURL(for: file.url.lastPathComponent, in: finalFolder)
            let baseImportedBytes = importedBytes
            let currentImportedPhotoCount = importedPhotoCount
            let currentImportedVideoCount = importedVideoCount
            try copyFileInChunks(from: file.url, to: uniqueTarget) { copiedBytesForFile in
                onProgress(
                    MediaImporter.ImportProgressSnapshot(
                        importedBytes: baseImportedBytes + copiedBytesForFile,
                        totalBytes: totalBytes,
                        importedPhotoCount: currentImportedPhotoCount,
                        totalPhotoCount: totalPhotoCount,
                        importedVideoCount: currentImportedVideoCount,
                        totalVideoCount: totalVideoCount
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
            onProgress(
                MediaImporter.ImportProgressSnapshot(
                    importedBytes: importedBytes,
                    totalBytes: totalBytes,
                    importedPhotoCount: importedPhotoCount,
                    totalPhotoCount: totalPhotoCount,
                    importedVideoCount: importedVideoCount,
                    totalVideoCount: totalVideoCount
                )
            )
        }

        return MediaImporter.ImportResult(
            copiedCount: copiedCount,
            destinationFolderName: finalFolder.lastPathComponent
        )
    }

    private static func collectMediaFiles(
        from sourceRoot: URL,
        allowedExtensions: Set<String>,
        photoExtensions: Set<String>,
        videoExtensions: Set<String>
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
            if allowedExtensions.contains(fileExtension) {
                let kind: ImportableFile.Kind
                if photoExtensions.contains(fileExtension) {
                    kind = .photo
                } else if videoExtensions.contains(fileExtension) {
                    kind = .video
                } else {
                    continue
                }

                mediaFiles.append(
                    ImportableFile(
                        url: fileURL,
                        size: Int64(values.fileSize ?? 0),
                        kind: kind
                    )
                )
            }
        }

        return mediaFiles
    }

    private static func uniqueDestinationURL(for filename: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
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

    private static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents

        guard candidateComponents.count >= ancestorComponents.count else {
            return false
        }

        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
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
        }

        let url: URL
        let size: Int64
        let kind: Kind
    }
}
