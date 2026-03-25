import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var diskMonitor: DiskMonitor

    var body: some View {
        if let firstVolume = diskMonitor.removableVolumes.first {
            Label(firstVolume.availableText, systemImage: "externaldrive.fill.badge.checkmark")
        } else {
            Label("媒体导入", systemImage: "externaldrive")
        }
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var diskMonitor: DiskMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importer: MediaImporter
    @State private var isShowingSettingsPopover = false

    private var visibleStatusMessage: String? {
        guard importer.isImporting || importer.lastResultMessage != "等待导入" else {
            return nil
        }

        return importer.lastResultMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            destinationSection
            deviceSection

            if let visibleStatusMessage {
                StatusBanner(message: visibleStatusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            footerSection
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.2), value: visibleStatusMessage)
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("导入目标")
                    .font(.headline)

                Spacer()

                if settings.autoImportEnabled {
                    Label("自动导入已开启", systemImage: "bolt.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if settings.destinationFolderPath.isEmpty {
                Text("还没有选择导入文件夹。先在右上角设置里指定一个本地目录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(settings.destinationFolderPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var deviceSection: some View {
        if diskMonitor.removableVolumes.isEmpty {
            EmptyDeviceState()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(diskMonitor.removableVolumes) { volume in
                        VolumeCard(volume: volume)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 420)
        }
    }

    private var footerSection: some View {
        HStack(alignment: .center) {
            Button("刷新设备") {
                diskMonitor.refreshVolumes()
            }
            .controlSize(.regular)

            Spacer()

            settingsMenu
        }
    }

    private var settingsMenu: some View { //设置按钮选项
        Button {
            isShowingSettingsPopover.toggle()
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .padding(.leading, -3)
                    Text("设置")
                }

                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: 12)
                    .padding(.leading, 7)   // 左边间距 = 2
                    .padding(.trailing, 9)  // 右边间距 = 6

                Image(systemName: isShowingSettingsPopover ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 2)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .popover(isPresented: $isShowingSettingsPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            settingsPopoverContent
        }
    }

    private var settingsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入设置")
                .font(.headline)

            Button {
                isShowingSettingsPopover = false
                settings.chooseDestinationFolder()
            } label: {
                Label("选择导入目标文件夹", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Toggle("插入后自动导入", isOn: $settings.autoImportEnabled)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("当前目标文件夹")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(settings.destinationFolderPath.isEmpty ? "还没有选择文件夹" : settings.destinationFolderPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 280, alignment: .leading)
        .padding(14)
    }
}

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct EmptyDeviceState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("未检测到 U 盘或 SD 卡")
                .font(.headline)

            Text("插入设备后会自动刷新列表")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VolumeCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importer: MediaImporter

    let volume: MountedVolume

    private var isCurrentVolumeImporting: Bool {
        importer.currentImportVolumeID == volume.id && importer.importProgress != nil
    }

    private var usagePercent: Int {
        Int((volume.usageFraction * 100).rounded())
    }

    private var usageTint: Color {
        switch volume.usageFraction {
        case ..<0.5:
            return Color(red: 0.17, green: 0.62, blue: 0.39)
        case ..<0.75:
            return Color(red: 0.83, green: 0.62, blue: 0.18)
        case ..<0.9:
            return Color(red: 0.84, green: 0.45, blue: 0.18)
        default:
            return Color(red: 0.78, green: 0.24, blue: 0.25)
        }
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                usageTint.opacity(0.28),
                usageTint.opacity(0.1),
                Color.black.opacity(0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var actionButtonTitle: String {
        settings.destinationFolderPath.isEmpty ? "选择导入目标文件夹" : "导入照片和视频"
    }

    private var helperText: String {
        if settings.destinationFolderPath.isEmpty {
            return "请先选择一个导入目标文件夹。"
        }

        if importer.isImporting {
            return "当前已有导入任务在进行中，完成后可以继续处理其他设备。"
        }

        if settings.autoImportEnabled {
            return "已开启自动导入，新插入的设备会自动开始导入。"
        }

        return "导入时会按“设备名/时间戳”创建新文件夹，不会删除设备里的原始文件。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name)
                        .font(.headline)
                    Text(volume.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(usagePercent)% 已用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.08), in: Capsule())
            }

            ProgressView(value: volume.usageFraction)
                .progressViewStyle(.linear)
                .tint(usageTint)

            HStack(spacing: 10) {
                InfoTile(title: "可用空间", value: volume.availableText)
                InfoTile(title: "总容量", value: volume.totalText)
            }

            if isCurrentVolumeImporting {
                importProgressSection
            } else {
                idleSection
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var idleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(helperText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(actionButtonTitle) {
                handlePrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!settings.destinationFolderPath.isEmpty && importer.isImporting)
        }
    }

    private var importProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("正在导入...")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                if let detailText = importer.importProgressDetailText {
                    Text(detailText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            ProgressView(value: importer.importProgress ?? 0)
                .progressViewStyle(.linear)
                .tint(usageTint)

            Text(importer.lastResultMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("取消导入") {
                    importer.cancelImport()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handlePrimaryAction() {
        guard !settings.destinationFolderPath.isEmpty else {
            settings.chooseDestinationFolder()
            return
        }

        Task {
            do {
                _ = try await settings.withDestinationFolderAccess { destinationFolderURL in
                    await importer.importMedia(from: volume, to: destinationFolderURL)
                }
            } catch {
                importer.setStatusMessage(error.localizedDescription)
            }
        }
    }
}

private struct InfoTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#if DEBUG
private struct MenuContentPreviewHost: View {
    @StateObject private var diskMonitor: DiskMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var importer: MediaImporter

    private let previewWidth: CGFloat = 360
    private let previewHeight: CGFloat = 700

    init(
        diskMonitor: DiskMonitor,
        settings: AppSettings,
        importer: MediaImporter
    ) {
        _diskMonitor = StateObject(wrappedValue: diskMonitor)
        _settings = StateObject(wrappedValue: settings)
        _importer = StateObject(wrappedValue: importer)
    }

    var body: some View {
        MenuContentView()
            .environmentObject(diskMonitor)
            .environmentObject(settings)
            .environmentObject(importer)
            .frame(width: previewWidth, height: previewHeight, alignment: .top)
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .previewLayout(.fixed(width: previewWidth + 32, height: previewHeight + 32))
    }
}

struct MenuContentView_Previews: PreviewProvider {
    private static let previewVolume = MountedVolume(
        id: "preview-volume",
        name: "SONY_CARD",
        url: URL(fileURLWithPath: "/Volumes/SONY_CARD", isDirectory: true),
        totalCapacity: 256_000_000_000,
        availableCapacity: 143_500_000_000
    )

    static var previews: some View {
        Group {
            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(previewVolumes: []),
                settings: AppSettings(previewDestinationFolderPath: "", autoImportEnabled: false),
                importer: MediaImporter()
            )
            .previewDisplayName("Empty State")

            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(previewVolumes: [previewVolume]),
                settings: AppSettings(
                    previewDestinationFolderPath: "/Users/kang/Pictures/Media Imports",
                    autoImportEnabled: true
                ),
                importer: MediaImporter()
            )
            .previewDisplayName("Ready To Import")

            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(previewVolumes: [previewVolume]),
                settings: AppSettings(
                    previewDestinationFolderPath: "/Users/kang/Pictures/Media Imports",
                    autoImportEnabled: false
                ),
                importer: MediaImporter(
                    previewIsImporting: true,
                    previewMessage: "正在导入 SONY_CARD... 18.50 GB / 40.20 GB",
                    previewProgress: 0.46,
                    previewCurrentImportVolumeID: previewVolume.id,
                    previewImportedBytes: 18_500_000_000,
                    previewTotalImportBytes: 40_200_000_000
                )
            )
            .previewDisplayName("Importing")
        }
    }
}
#endif
