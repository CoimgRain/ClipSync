import Combine
import Foundation

@MainActor
final class AutoImportCoordinator: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    private var handledVolumeIDs: Set<String> = []
    private var queuedVolumeIDs: Set<String> = []

    init(diskMonitor: DiskMonitor, settings: AppSettings, importer: MediaImporter) {
        Publishers.CombineLatest4(
            diskMonitor.$removableVolumes,
            settings.$destinationFolderPath,
            settings.$autoImportEnabled,
            settings.$autoImportEnabledVolumeIDs
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak importer] volumes, folderPath, autoImportEnabled, autoImportEnabledVolumeIDs in
            guard let self, let importer else { return }

            let activeVolumeIDs = Set(volumes.map(\.id))
            self.handledVolumeIDs.formIntersection(activeVolumeIDs)
            self.queuedVolumeIDs.formIntersection(activeVolumeIDs)

            guard autoImportEnabled else { return }
            let pendingVolumes = volumes.filter {
                autoImportEnabledVolumeIDs.contains($0.autoImportPreferenceID)
                    && !self.handledVolumeIDs.contains($0.id)
                    && !self.queuedVolumeIDs.contains($0.id)
            }

            guard !pendingVolumes.isEmpty else {
                return
            }

            guard !folderPath.isEmpty else {
                importer.setStatusMessage("请先选择导入文件夹")
                return
            }

            for nextVolume in pendingVolumes {
                self.queuedVolumeIDs.insert(nextVolume.id)

                Task { @MainActor [weak self, weak importer] in
                    guard let self, let importer else { return }

                    defer {
                        self.queuedVolumeIDs.remove(nextVolume.id)
                    }

                    do {
                        let didSucceed = try await settings.withDestinationFolderAccess { destinationFolderURL in
                            let didFinish = await importer.importMedia(from: nextVolume, to: destinationFolderURL, settings: settings)
                            await diskMonitor.rescanMediaSummaries(comparingAgainst: destinationFolderURL)
                            return didFinish
                        }

                        if didSucceed {
                            self.handledVolumeIDs.insert(nextVolume.id)
                        }
                    } catch {
                        importer.setStatusMessage(error.localizedDescription)
                    }
                }
            }
        }
        .store(in: &cancellables)
    }
}
