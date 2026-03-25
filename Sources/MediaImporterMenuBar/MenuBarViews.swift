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
    @EnvironmentObject private var diskMonitor: DiskMonitor
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

    private var cardPalette: [Color] {
        switch volume.usageFraction {
        case ..<0.5:
            return [
                Color(red: 0.35, green: 0.78, blue: 0.54),
                Color(red: 0.22, green: 0.63, blue: 0.40),
                Color(red: 0.16, green: 0.50, blue: 0.31),
                Color(red: 0.13, green: 0.42, blue: 0.26),
            ]
        case ..<0.75:
            return [
                Color(red: 0.91, green: 0.77, blue: 0.40),
                Color(red: 0.82, green: 0.60, blue: 0.24),
                Color(red: 0.72, green: 0.48, blue: 0.18),
                Color(red: 0.58, green: 0.37, blue: 0.14),
            ]
        case ..<0.9:
            return [
                Color(red: 0.94, green: 0.66, blue: 0.34),
                Color(red: 0.86, green: 0.50, blue: 0.20),
                Color(red: 0.73, green: 0.38, blue: 0.15),
                Color(red: 0.60, green: 0.28, blue: 0.12),
            ]
        default:
            return [
                Color(red: 0.88, green: 0.44, blue: 0.42),
                Color(red: 0.76, green: 0.30, blue: 0.28),
                Color(red: 0.62, green: 0.22, blue: 0.22),
                Color(red: 0.50, green: 0.16, blue: 0.18),
            ]
        }
    }

    private var chipPalette: [Color] {
        switch volume.usageFraction {
        case ..<0.5:
            return [
                Color(red: 0.15, green: 0.42, blue: 0.26).opacity(0.7),
                Color(red: 0.10, green: 0.30, blue: 0.18).opacity(0.7),
            ]
        case ..<0.75:
            return [
                Color(red: 0.46, green: 0.33, blue: 0.12).opacity(0.72),
                Color(red: 0.33, green: 0.23, blue: 0.09).opacity(0.72),
            ]
        case ..<0.9:
            return [
                Color(red: 0.49, green: 0.24, blue: 0.10).opacity(0.72),
                Color(red: 0.35, green: 0.17, blue: 0.08).opacity(0.72),
            ]
        default:
            return [
                Color(red: 0.43, green: 0.15, blue: 0.16).opacity(0.72),
                Color(red: 0.29, green: 0.10, blue: 0.11).opacity(0.72),
            ]
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: Array(cardPalette.reversed()),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBackground: some View {
        ZStack {
            cardShape
                .fill(cardGradient)

            AnimatedColorFlow(
                palette: cardPalette,
                primaryTint: usageTint
            )

            AnimatedOrbField(
                seed: volume.id,
                primaryTint: usageTint,
                palette: cardPalette
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.06),
                    .clear,
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .clipShape(cardShape)
        }
        .clipShape(cardShape)
    }

    private var actionButtonTitle: String {
        settings.destinationFolderPath.isEmpty ? "选择导入目标文件夹" : "导入照片和视频"
    }

    private var neutralInfoTileBackgroundColors: [Color] {
        [
            Color.gray.opacity(0.30),
            Color(red: 0.80, green: 0.84, blue: 0.82).opacity(0.22),
        ]
    }

    private var infoTileBorderColor: Color {
        usageTint.opacity(0.82)
    }

    private var chipBackgroundColors: [Color] {
        neutralInfoTileBackgroundColors
    }

    private var isPrimaryActionDisabled: Bool {
        !settings.destinationFolderPath.isEmpty && importer.isImporting
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

    private var mediaSummaryText: String {
        guard let summary = diskMonitor.mediaSummaries[volume.id] else {
            return "正在扫描照片和视频..."
        }

        return "共扫描到 \(summary.photoCount) 张照片，\(summary.videoCount) 个视频"
    }

    private func capacityTileWidths(totalWidth: CGFloat, usedMinimumWidth: CGFloat, remainingMinimumWidth: CGFloat) -> (used: CGFloat, remaining: CGFloat) {
        let usedFraction = max(0, min(1, volume.usageFraction))
        let remainingFraction = max(0, 1 - usedFraction)

        var usedWidth = max(totalWidth * usedFraction, usedMinimumWidth)
        var remainingWidth = max(totalWidth * remainingFraction, remainingMinimumWidth)
        let overflow = usedWidth + remainingWidth - totalWidth

        guard overflow > 0 else {
            return (usedWidth, remainingWidth)
        }

        let usedFlexibleWidth = max(0, usedWidth - usedMinimumWidth)
        let remainingFlexibleWidth = max(0, remainingWidth - remainingMinimumWidth)
        let flexibleWidth = usedFlexibleWidth + remainingFlexibleWidth

        if flexibleWidth > 0 {
            usedWidth -= overflow * (usedFlexibleWidth / flexibleWidth)
            remainingWidth -= overflow * (remainingFlexibleWidth / flexibleWidth)
            return (usedWidth, remainingWidth)
        }

        return (usedMinimumWidth, remainingMinimumWidth)
    }

    private var capacityTilesRow: some View {
        GeometryReader { proxy in
            let usedFraction = max(0, min(1, volume.usageFraction))
            let remainingFraction = max(0, 1 - usedFraction)
            let showsUsedTile = usedFraction > 0.0001
            let showsRemainingTile = remainingFraction > 0.0001
            let spacing: CGFloat = (showsUsedTile && showsRemainingTile) ? 10 : 0
            let contentWidth = max(0, proxy.size.width - spacing)
            let usedMinimumWidth = showsUsedTile ? InfoTile.minimumWidth(title: "已用空间", value: volume.usedText) : 0
            let remainingMinimumWidth = showsRemainingTile ? InfoTile.minimumWidth(title: "剩余空间", value: volume.availableText) : 0
            let widths = capacityTileWidths(
                totalWidth: contentWidth,
                usedMinimumWidth: usedMinimumWidth,
                remainingMinimumWidth: remainingMinimumWidth
            )

            HStack(spacing: spacing) {
                if showsUsedTile {
                    InfoTile(
                        title: "已用空间",
                        value: volume.usedText,
                        backgroundColors: neutralInfoTileBackgroundColors,
                        borderColor: infoTileBorderColor
                    )
                    .frame(width: widths.used, alignment: .leading)
                }

                if showsRemainingTile {
                    InfoTile(
                        title: "剩余空间",
                        value: volume.availableText,
                        backgroundColors: neutralInfoTileBackgroundColors,
                        borderColor: infoTileBorderColor
                    )
                    .frame(width: widths.remaining, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 82)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name)
                        .font(.system(size: 19, weight: .bold))
                    (
                        Text(verbatim: volume.formatDescription)
                        + Text(" 格式")
                        + Text(" · 已用 ")
                        + Text("\(usagePercent)%")
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(volume.roundedTotalText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(0.2))
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.black.opacity(0), lineWidth: 2.5)
                        }
                }
            }

            capacityTilesRow

            if isCurrentVolumeImporting {
                importProgressSection
            } else {
                idleSection
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var idleSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("扫描结果")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))

                Text(mediaSummaryText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 28)

            Button(actionButtonTitle) {
                handlePrimaryAction()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .opacity(isPrimaryActionDisabled ? 0.55 : 1)
            .disabled(isPrimaryActionDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .padding(.top, -30)
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        )
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
    let backgroundColors: [Color]
    let borderColor: Color
    let borderHighlightOpacity: Double

    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let valueFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let horizontalPadding: CGFloat = 10
    private static let widthBuffer: CGFloat = 0

    init(title: String, value: String, backgroundColors: [Color] = [
        .white.opacity(0.24),
        .white.opacity(0.18),
    ], borderColor: Color = Color.white.opacity(0.48), borderHighlightOpacity: Double = 0.18) {
        self.title = title
        self.value = value
        self.backgroundColors = backgroundColors
        self.borderColor = borderColor
        self.borderHighlightOpacity = borderHighlightOpacity
    }

    static func minimumWidth(title: String, value: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        return ceil(max(titleWidth, valueWidth) + (horizontalPadding * 2) + widthBuffer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // 1. 上层：你原来的淡彩色线（绿/橙变浅）
                        .strokeBorder(borderColor.opacity(0.6), lineWidth: 2)
                    // 2. 底层：白色线（垫在下面）
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.9), lineWidth: 2) // 这里改白色和线宽
                        )
                }
        }
    }
}

private struct AnimatedOrbField: View {
    let seed: String
    let primaryTint: Color
    let palette: [Color]

    @State private var animate = false

    private var specs: [OrbSpec] {
        OrbSpec.make(seed: seed, palette: palette, fallbackTint: primaryTint)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(specs) { spec in
                    Circle()
                        .fill(spec.color.opacity(spec.opacity))
                        .frame(
                            width: proxy.size.width * spec.sizeScale,
                            height: proxy.size.width * spec.sizeScale
                        )
                        .blur(radius: proxy.size.width * spec.blurScale)
                        .position(
                            x: proxy.size.width * (spec.anchorX + (animate ? spec.travelX : -spec.travelX)),
                            y: proxy.size.height * (spec.anchorY + (animate ? spec.travelY : -spec.travelY))
                        )
                        .animation(
                            .easeInOut(duration: spec.duration)
                                .repeatForever(autoreverses: true)
                                .delay(spec.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !animate else { return }
            animate = true
        }
    }

    private struct OrbSpec: Identifiable {
        let id: Int
        let color: Color
        let opacity: Double
        let sizeScale: CGFloat
        let blurScale: CGFloat
        let anchorX: CGFloat
        let anchorY: CGFloat
        let travelX: CGFloat
        let travelY: CGFloat
        let duration: Double
        let delay: Double

        static func make(seed: String, palette: [Color], fallbackTint: Color) -> [OrbSpec] {
            var generator = SeededGenerator(seed: seed)
            let colors = palette.isEmpty ? [fallbackTint] : palette
            let count = 6

            return (0..<count).map { index in
                let color = colors[index % colors.count]
                return OrbSpec(
                    id: index,
                    color: color,
                    opacity: generator.next(in: 0.16...0.30),
                    sizeScale: generator.next(in: 0.26...0.60),
                    blurScale: generator.next(in: 0.08...0.15),
                    anchorX: generator.next(in: -0.10...1.10),
                    anchorY: generator.next(in: -0.05...1.10),
                    travelX: generator.next(in: -0.14...0.14),
                    travelY: generator.next(in: -0.14...0.14),
                    duration: generator.next(in: 13.0...20.0),
                    delay: generator.next(in: 0.0...2.4)
                )
            }
        }
    }

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: String) {
            state = 0xcbf29ce484222325
            for byte in seed.utf8 {
                state ^= UInt64(byte)
                state &*= 0x100000001b3
            }
            if state == 0 {
                state = 0x9e3779b97f4a7c15
            }
        }

        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = (state >> 11) & ((1 << 53) - 1)
            return Double(value) / Double(1 << 53)
        }

        mutating func next(in range: ClosedRange<Double>) -> Double {
            range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
        }

        mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
            CGFloat(next(in: Double(range.lowerBound)...Double(range.upperBound)))
        }
    }
}

private struct AnimatedColorFlow: View {
    let palette: [Color]
    let primaryTint: Color

    @State private var animate = false

    private var brightColor: Color {
        palette.first ?? primaryTint
    }

    private var deepColor: Color {
        palette.last ?? primaryTint
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                brightColor.opacity(1.0),
                                brightColor.opacity(0.72),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.94, height: proxy.size.height * 0.68)
                    .blur(radius: 20)
                    .rotationEffect(.degrees(animate ? 17 : -15))
                    .offset(
                        x: animate ? proxy.size.width * 0.30 : -proxy.size.width * 0.24,
                        y: animate ? -proxy.size.height * 0.10 : proxy.size.height * 0.12
                    )
                    .animation(
                        .easeInOut(duration: 17)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                deepColor.opacity(0.24),
                                brightColor.opacity(0.18),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: proxy.size.width * 0.88, height: proxy.size.height * 0.82)
                    .blur(radius: 24)
                    .rotationEffect(.degrees(animate ? -16 : 11))
                    .offset(
                        x: animate ? -proxy.size.width * 0.22 : proxy.size.width * 0.18,
                        y: animate ? proxy.size.height * 0.10 : -proxy.size.height * 0.12
                    )
                    .animation(
                        .easeInOut(duration: 21)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !animate else { return }
            animate = true
        }
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
        formatDescription: "exFAT",
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
