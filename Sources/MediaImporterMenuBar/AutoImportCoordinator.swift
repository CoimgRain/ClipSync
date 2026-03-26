import Combine
import Foundation

@MainActor
final class AutoImportCoordinator: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []
    private var handledVolumeIDs: Set<String> = []
    private var queuedVolumeIDs: Set<String> = []

    init(diskMonitor: DiskMonitor, settings: AppSettings, importer: MediaImporter) {
        Publishers.CombineLatest3(
            diskMonitor.$removableVolumes,
            settings.$destinationFolderPath,
            settings.$autoImportEnabled
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak importer] volumes, folderPath, autoImportEnabled in
            guard let self, let importer else { return }

            let activeVolumeIDs = Set(volumes.map(\.id))
            self.handledVolumeIDs.formIntersection(activeVolumeIDs)
            self.queuedVolumeIDs.formIntersection(activeVolumeIDs)

            guard autoImportEnabled else { return }
            guard !importer.isImporting else { return }
            guard let nextVolume = volumes.first(where: {
                !self.handledVolumeIDs.contains($0.id) && !self.queuedVolumeIDs.contains($0.id)
            }) else {
                return
            }
            guard !folderPath.isEmpty else {
                importer.setStatusMessage("请先选择导入文件夹")
                return
            }

            self.queuedVolumeIDs.insert(nextVolume.id)

            Task { @MainActor [weak self, weak importer] in
                guard let self, let importer else { return }

                defer {
                    self.queuedVolumeIDs.remove(nextVolume.id)
                }

                do {
                    let didSucceed = try await settings.withDestinationFolderAccess { destinationFolderURL in
                        await importer.importMedia(from: nextVolume, to: destinationFolderURL, settings: settings)
                    }

                    if didSucceed {
                        self.handledVolumeIDs.insert(nextVolume.id)
                    }
                } catch {
                    importer.setStatusMessage(error.localizedDescription)
                }
            }
        }
        .store(in: &cancellables)
    }
}
