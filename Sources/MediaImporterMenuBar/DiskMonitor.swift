import AppKit
import Combine
import Foundation

struct MountedVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
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

    var subtitle: String {
        "剩余 \(availableText) / 共 \(totalText)"
    }
}

@MainActor
final class DiskMonitor: ObservableObject {
    @Published private(set) var removableVolumes: [MountedVolume] = []

    private var observers: [NSObjectProtocol] = []
    private let notificationCenter = NSWorkspace.shared.notificationCenter

    init() {
        refreshVolumes()
        startObserving()
    }

#if DEBUG
    init(previewVolumes: [MountedVolume]) {
        removableVolumes = previewVolumes
    }
#endif

    func refreshVolumes() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
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

        removableVolumes = urls.compactMap(Self.makeMountedVolume(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

        let isExternal = (values.volumeIsRemovable == true || values.volumeIsEjectable == true)
            && values.volumeIsInternal != true

        guard isExternal else { return nil }

        let capacities = capacityInfo(for: url, values: values)

        return MountedVolume(
            id: url.path,
            name: values.volumeName ?? url.lastPathComponent,
            url: url,
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
}
