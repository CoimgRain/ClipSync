import AppKit
import Combine
import Foundation

struct VolumeMediaSummary: Equatable, Sendable {
    let photoCount: Int
    let videoCount: Int
    let importedPhotoCount: Int
    let importedVideoCount: Int

    init(photoCount: Int, videoCount: Int, importedPhotoCount: Int = 0, importedVideoCount: Int = 0) {
        self.photoCount = photoCount
        self.videoCount = videoCount
        self.importedPhotoCount = importedPhotoCount
        self.importedVideoCount = importedVideoCount
    }

    var pendingPhotoCount: Int {
        max(0, photoCount - importedPhotoCount)
    }

    var pendingVideoCount: Int {
        max(0, videoCount - importedVideoCount)
    }

    var hasImportableMedia: Bool {
        pendingPhotoCount > 0 || pendingVideoCount > 0
    }
}

struct MountedVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let formatDescription: String
    let totalCapacity: Int64
    let availableCapacity: Int64

    var usedCapacity: Int64 {
        max(0, totalCapacity - availableCapacity)
    }

    var usageFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    var availableText: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var usedText: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var totalText: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var roundedTotalText: String {
        let units: [(label: String, scale: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
        ]

        let capacity = Double(max(totalCapacity, 0))

        for unit in units where capacity >= unit.scale {
            let roundedValue = Int((capacity / unit.scale).rounded())
            return "\(roundedValue) \(unit.label)"
        }

        return "\(Int(capacity.rounded())) B"
    }

}

@MainActor
final class DiskMonitor: ObservableObject {
    @Published private(set) var removableVolumes: [MountedVolume] = []
    @Published private(set) var mediaSummaries: [String: VolumeMediaSummary] = [:]
    @Published private(set) var mediaSummaryRefreshToken = UUID()

    private var observers: [NSObjectProtocol] = []
    private let notificationCenter = NSWorkspace.shared.notificationCenter
    nonisolated private static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "gif", "bmp", "tif", "tiff", "raw", "dng",
    ]
    nonisolated private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mts", "m2ts", "mpg", "mpeg", "wmv", "mkv",
    ]

    init() {
        refreshVolumes()
        startObserving()
    }

#if DEBUG
    init(previewVolumes: [MountedVolume], previewMediaSummaries: [String: VolumeMediaSummary] = [:]) {
        removableVolumes = previewVolumes
        mediaSummaries = previewMediaSummaries
    }
#endif

    func refreshVolumes() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsLocalKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        let volumes = urls.compactMap(Self.makeMountedVolume(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        removableVolumes = volumes

        let currentIDs = Set(volumes.map(\.id))
        mediaSummaries = mediaSummaries.filter { currentIDs.contains($0.key) }
        mediaSummaryRefreshToken = UUID()
    }

    private func startObserving() {
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]

        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVolumes()
                }
            }
        }
    }

    private static func makeMountedVolume(from url: URL) -> MountedVolume? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsLocalKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ]) else {
            return nil
        }

        let isExternal = values.volumeIsLocal != false
            && values.volumeIsInternal != true
            && url.path.hasPrefix("/Volumes/")

        guard isExternal else { return nil }

        let capacities = capacityInfo(for: url, values: values)

        return MountedVolume(
            id: url.path,
            name: values.volumeName ?? url.lastPathComponent,
            url: url,
            formatDescription: values.volumeLocalizedFormatDescription ?? "外部磁盘",
            totalCapacity: capacities.total,
            availableCapacity: capacities.available
        )
    }

    private static func capacityInfo(for url: URL, values: URLResourceValues) -> (total: Int64, available: Int64) {
        let totalCapacity = Int64(values.volumeTotalCapacity ?? 0)

        let availableCandidates: [Int64?] = [
            values.volumeAvailableCapacityForImportantUsage.map { Int64($0) },
            values.volumeAvailableCapacityForOpportunisticUsage.map { Int64($0) },
            values.volumeAvailableCapacity.map { Int64($0) },
        ]

        if let availableCapacity = availableCandidates.compactMap({ $0 }).first(where: { $0 > 0 }) {
            return (total: totalCapacity, available: availableCapacity)
        }

        if let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path) {
            let fallbackTotal = (fileSystemAttributes[.systemSize] as? NSNumber)?.int64Value ?? totalCapacity
            let fallbackAvailable = (fileSystemAttributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return (total: max(totalCapacity, fallbackTotal), available: fallbackAvailable)
        }

        return (total: totalCapacity, available: 0)
    }

    func rescanMediaSummaries(comparingAgainst destinationRoot: URL?) async {
        let volumes = removableVolumes
        guard !volumes.isEmpty else {
            mediaSummaries = [:]
            return
        }

        let existingNameIndex = destinationRoot.map {
            MediaFileCatalog.buildExistingNameIndex(
                at: $0,
                photoExtensions: Self.photoExtensions,
                videoExtensions: Self.videoExtensions
            )
        } ?? .empty

        var updatedSummaries: [String: VolumeMediaSummary] = [:]

        await withTaskGroup(of: (String, VolumeMediaSummary)?.self) { group in
            for volume in volumes {
                group.addTask {
                    if Task.isCancelled {
                        return nil
                    }

                    let summary = Self.scanMediaSummary(at: volume.url, existingNameIndex: existingNameIndex)
                    return (volume.id, summary)
                }
            }

            for await result in group {
                guard let (volumeID, summary) = result else { continue }
                updatedSummaries[volumeID] = summary
            }
        }

        guard !Task.isCancelled else { return }

        let currentIDs = Set(removableVolumes.map(\.id))
        mediaSummaries = updatedSummaries.filter { currentIDs.contains($0.key) }
    }

    nonisolated private static func scanMediaSummary(
        at rootURL: URL,
        existingNameIndex: ExistingMediaNameIndex
    ) -> VolumeMediaSummary {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var photoCount = 0
        var videoCount = 0
        var importedPhotoCount = 0
        var importedVideoCount = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            if Task.isCancelled {
                break
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory != true else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            if photoExtensions.contains(fileExtension) {
                photoCount += 1
                if existingNameIndex.contains(fileURL.lastPathComponent, kind: .photo) {
                    importedPhotoCount += 1
                }
            } else if videoExtensions.contains(fileExtension) {
                videoCount += 1
                if existingNameIndex.contains(fileURL.lastPathComponent, kind: .video) {
                    importedVideoCount += 1
                }
            }
        }

        return VolumeMediaSummary(
            photoCount: photoCount,
            videoCount: videoCount,
            importedPhotoCount: importedPhotoCount,
            importedVideoCount: importedVideoCount
        )
    }
}
