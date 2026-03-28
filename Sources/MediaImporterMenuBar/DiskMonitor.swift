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
    let autoImportPreferenceID: String
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
    nonisolated private static let volumeResourceKeys: Set<URLResourceKey> = [
        .volumeNameKey,
        .volumeUUIDStringKey,
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

    @Published private(set) var removableVolumes: [MountedVolume] = []
    @Published private(set) var mediaSummaries: [String: VolumeMediaSummary] = [:]
    @Published private(set) var mediaSummaryRefreshToken = UUID()

    private var observers: [NSObjectProtocol] = []
    private let notificationCenter = NSWorkspace.shared.notificationCenter
    private var refreshRevision = 0

    init() {
        startObserving()
        refreshVolumes()
    }

#if DEBUG
    init(previewVolumes: [MountedVolume], previewMediaSummaries: [String: VolumeMediaSummary] = [:]) {
        removableVolumes = previewVolumes
        mediaSummaries = previewMediaSummaries
    }
#endif

    func refreshVolumes() {
        refreshRevision += 1
        let revision = refreshRevision
        let existingSummaries = mediaSummaries

        Task.detached(priority: .userInitiated) { [weak self] in
            let volumes = Self.discoverRemovableVolumes()
            await self?.applyVolumeRefresh(
                volumes,
                existingSummaries: existingSummaries,
                revision: revision
            )
        }
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

    nonisolated private static func makeMountedVolume(from url: URL) -> MountedVolume? {
        guard let values = try? url.resourceValues(forKeys: Self.volumeResourceKeys) else {
            return nil
        }

        let isExternal = values.volumeIsLocal != false
            && values.volumeIsInternal != true
            && url.path.hasPrefix("/Volumes/")

        guard isExternal else { return nil }

        let capacities = capacityInfo(for: url, values: values)
        let volumeUUID = values.volumeUUIDString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preferenceID = volumeUUID.isEmpty
            ? "fallback:\(url.path)|\(capacities.total)|\(values.volumeLocalizedFormatDescription ?? "")"
            : "uuid:\(volumeUUID)"

        return MountedVolume(
            id: url.path,
            autoImportPreferenceID: preferenceID,
            name: values.volumeName ?? url.lastPathComponent,
            url: url,
            formatDescription: values.volumeLocalizedFormatDescription ?? "外部磁盘",
            totalCapacity: capacities.total,
            availableCapacity: capacities.available
        )
    }

    nonisolated private static func discoverRemovableVolumes() -> [MountedVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(Self.volumeResourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap(Self.makeMountedVolume(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func applyVolumeRefresh(
        _ volumes: [MountedVolume],
        existingSummaries: [String: VolumeMediaSummary],
        revision: Int
    ) {
        guard revision == refreshRevision else { return }

        removableVolumes = volumes

        let currentIDs = Set(volumes.map(\.id))
        mediaSummaries = existingSummaries.filter { currentIDs.contains($0.key) }
        mediaSummaryRefreshToken = UUID()
    }

    nonisolated private static func capacityInfo(for url: URL, values: URLResourceValues) -> (total: Int64, available: Int64) {
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
            MediaFileCatalog.buildExistingNameIndex(at: $0)
        } ?? .empty

        var updatedSummaries: [String: VolumeMediaSummary] = [:]

        for volume in volumes {
            guard !Task.isCancelled else { return }
            let summary = Self.scanMediaSummary(at: volume.url, existingNameIndex: existingNameIndex)
            updatedSummaries[volume.id] = summary
        }

        guard !Task.isCancelled else { return }

        let currentIDs = Set(removableVolumes.map(\.id))
        mediaSummaries = updatedSummaries.filter { currentIDs.contains($0.key) }
    }

    nonisolated private static func scanMediaSummary(
        at rootURL: URL,
        existingNameIndex: ExistingMediaNameIndex
    ) -> VolumeMediaSummary {
        RemovableVolumeAccessStore.withAccess(to: rootURL) { accessibleRootURL in
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(
                at: accessibleRootURL,
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
                switch MediaCatalogSupport.kind(forNormalizedExtension: fileExtension) {
                case .photo:
                    photoCount += 1
                    if existingNameIndex.contains(fileURL.lastPathComponent, kind: .photo) {
                        importedPhotoCount += 1
                    }
                case .video:
                    videoCount += 1
                    if existingNameIndex.contains(fileURL.lastPathComponent, kind: .video) {
                        importedVideoCount += 1
                    }
                case nil:
                    break
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
}
