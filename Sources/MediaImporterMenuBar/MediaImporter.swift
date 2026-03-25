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

    private var currentImportTask: Task<ImportResult, Error>?

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
        previewTotalImportBytes: Int64
    ) {
        self.isImporting = previewIsImporting
        self.lastResultMessage = previewMessage
        self.importProgress = previewProgress
        self.currentImportVolumeID = previewCurrentImportVolumeID
        self.importedBytes = previewImportedBytes
        self.totalImportBytes = previewTotalImportBytes
    }
#endif

    func importMedia(from volume: MountedVolume, to destinationFolder: URL) async -> Bool {
        guard !isImporting else { return false }
        isImporting = true
        currentImportVolumeID = volume.id
        importProgress = 0
        importedBytes = 0
        totalImportBytes = 0
        lastResultMessage = "正在导入 \(volume.name)..."

        defer {
            isImporting = false
            importProgress = nil
            currentImportVolumeID = nil
            importedBytes = 0
            totalImportBytes = 0
            currentImportTask = nil
        }

        do {
            let allowedExtensions = self.allowedExtensions
            let task = Task.detached(priority: .userInitiated) { [volume, destinationFolder] in
                try ImportWorker.copyMediaFiles(
                    from: volume.url,
                    to: destinationFolder,
                    volumeName: volume.name,
                    allowedExtensions: allowedExtensions
                ) { importedBytes, totalBytes in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.importedBytes = importedBytes
                        self.totalImportBytes = totalBytes
                        self.importProgress = totalBytes > 0 ? Double(importedBytes) / Double(totalBytes) : nil
                        self.lastResultMessage = "正在导入 \(volume.name)... \(Self.byteText(importedBytes)) / \(Self.byteText(totalBytes))"
                    }
                }
            }
            currentImportTask = task
            let result = try await task.value

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

    var importProgressDetailText: String? {
        guard totalImportBytes > 0 else { return nil }
        return "\(Self.progressByteText(importedBytes)) / \(Self.progressByteText(totalImportBytes))"
    }

    struct ImportResult: Sendable {
        let copiedCount: Int
        let destinationFolderName: String
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

        return String(format: "%.2f %@", value, units[unitIndex])
    }
}

private enum ImportWorker {
    static func copyMediaFiles(
        from sourceRoot: URL,
        to destinationFolder: URL,
        volumeName: String,
        allowedExtensions: Set<String>,
        onProgress: @escaping @Sendable (_ importedBytes: Int64, _ totalBytes: Int64) -> Void
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
            allowedExtensions: allowedExtensions
        )

        let totalBytes = mediaFiles.reduce(into: Int64(0)) { partialResult, file in
            partialResult += file.size
        }
        var importedBytes: Int64 = 0
        var copiedCount = 0
        onProgress(importedBytes, totalBytes)

        for file in mediaFiles {
            try Task.checkCancellation()
            let uniqueTarget = uniqueDestinationURL(for: file.url.lastPathComponent, in: finalFolder)
            let baseImportedBytes = importedBytes
            try copyFileInChunks(from: file.url, to: uniqueTarget) { copiedBytesForFile in
                onProgress(baseImportedBytes + copiedBytesForFile, totalBytes)
            }
            copiedCount += 1
            importedBytes += file.size
            onProgress(importedBytes, totalBytes)
        }

        return MediaImporter.ImportResult(
            copiedCount: copiedCount,
            destinationFolderName: finalFolder.lastPathComponent
        )
    }

    private static func collectMediaFiles(from sourceRoot: URL, allowedExtensions: Set<String>) throws -> [ImportableFile] {
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
                mediaFiles.append(
                    ImportableFile(
                        url: fileURL,
                        size: Int64(values.fileSize ?? 0)
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
        let chunkSize = 4 * 1024 * 1024

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
        let url: URL
        let size: Int64
    }
}
