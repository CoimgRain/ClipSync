import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let diskMonitor: DiskMonitor
    private let settings: AppSettings
    private let importer: MediaImporter

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let mainPopover = NSPopover()
    private var hoverPreviewPanel: HoverPreviewPanel?

    private var cancellables = Set<AnyCancellable>()
    private var hoverMonitorTimer: Timer?
    private var pendingHoverPreviewWorkItem: DispatchWorkItem?
    private var pendingHoverCloseWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(diskMonitor: DiskMonitor, settings: AppSettings, importer: MediaImporter) {
        self.diskMonitor = diskMonitor
        self.settings = settings
        self.importer = importer
        super.init()
    }

    func install() {
        configureStatusItem()
        configurePopovers()
        bindState()
        startHoverMonitor()
        installOutsideClickMonitors()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.lineBreakMode = .byTruncatingMiddle
        button.setAccessibilityRole(.button)

        updateStatusItemAppearance()
    }

    private func configurePopovers() {
        mainPopover.behavior = .transient
        mainPopover.animates = true
        mainPopover.contentSize = NSSize(width: 392, height: 760)
        mainPopover.contentViewController = NSHostingController(
            rootView: MenuContentView()
                .environmentObject(diskMonitor)
                .environmentObject(settings)
                .environmentObject(importer)
                .frame(width: 360)
        )

        configureHoverPreviewPanel()
    }

    private func configureHoverPreviewPanel() {
        let hostingController = NSHostingController(
            rootView: HoverPreviewListView()
                .environmentObject(diskMonitor)
                .environmentObject(settings)
                .environmentObject(importer)
        )

        let panel = HoverPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: HoverPreviewLayout.panelWidth, height: HoverPreviewLayout.minimumPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        panel.ignoresMouseEvents = false
        hoverPreviewPanel = panel
        updateHoverPreviewPanelSize()
    }

    private func bindState() {
        diskMonitor.$removableVolumes
            .receive(on: RunLoop.main)
            .sink { [weak self] volumes in
                guard let self else { return }
                updateStatusItemAppearance()
                updateHoverPreviewPanelSize()

                if volumes.isEmpty {
                    closeHoverPreview()
                }
            }
            .store(in: &cancellables)
    }

    private func startHoverMonitor() {
        hoverMonitorTimer?.invalidate()

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleHoverMonitorTick()
            }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        hoverMonitorTimer = timer
    }

    private func installOutsideClickMonitors() {
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleExternalClick(at: NSEvent.mouseLocation)
                }
            }
        }

        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handleExternalClick(at: self?.screenPoint(for: event) ?? NSEvent.mouseLocation)
                return event
            }
        }
    }

    private func handleHoverMonitorTick() {
        guard let _ = statusItem.button else { return }

        if mainPopover.isShown {
            cancelScheduledHoverPreview()
            closeHoverPreview()
            return
        }

        let pointerLocation = NSEvent.mouseLocation
        let isHoveringStatusItem = statusItemScreenFrame?.contains(pointerLocation) ?? false
        let isHoveringPreview = hoverPreviewPanelScreenFrame?.contains(pointerLocation) ?? false

        if isHoveringStatusItem {
            scheduleHoverPreview()
            cancelScheduledHoverPreviewClose()
            return
        }

        cancelScheduledHoverPreview()

        if isHoveringPreview {
            cancelScheduledHoverPreviewClose()
        } else {
            scheduleHoverPreviewClose()
        }
    }

    private var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonFrameInWindow)
    }

    private var hoverPreviewPanelScreenFrame: NSRect? {
        hoverPreviewPanel?.frame
    }

    private var mainPopoverScreenFrame: NSRect? {
        mainPopover.contentViewController?.view.window?.frame
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func handleExternalClick(at screenPoint: NSPoint) {
        guard mainPopover.isShown else { return }

        if statusItemScreenFrame?.contains(screenPoint) == true {
            return
        }

        if mainPopoverScreenFrame?.contains(screenPoint) == true {
            return
        }

        mainPopover.performClose(nil)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        let hasVolumes = !diskMonitor.removableVolumes.isEmpty
        let mountedCount = diskMonitor.removableVolumes.count
        let title: String

        if let firstVolume = diskMonitor.removableVolumes.first, mountedCount == 1 {
            title = firstVolume.availableText
        } else if mountedCount > 1 {
            title = "\(mountedCount) 个设备"
        } else {
            title = "媒体导入"
        }

        button.title = title
        button.image = NSImage(
            systemSymbolName: hasVolumes ? "externaldrive.fill.badge.checkmark" : "externaldrive",
            accessibilityDescription: title
        )
        button.contentTintColor = hasVolumes ? NSColor.controlAccentColor : NSColor.labelColor
        button.toolTip = nil
    }

    private func updateHoverPreviewPanelSize() {
        let cardCount = max(diskMonitor.removableVolumes.count, 1)
        let computedHeight =
            (CGFloat(cardCount) * HoverPreviewLayout.estimatedCardHeight)
            + (CGFloat(max(cardCount - 1, 0)) * HoverPreviewLayout.cardSpacing)
            + (HoverPreviewLayout.contentPadding * 2)
        hoverPreviewPanel?.setContentSize(
            NSSize(
                width: HoverPreviewLayout.panelWidth,
                height: max(HoverPreviewLayout.minimumPanelHeight, computedHeight)
            )
        )
    }

    private func scheduleHoverPreview() {
        guard !diskMonitor.removableVolumes.isEmpty else { return }
        guard hoverPreviewPanel?.isVisible != true else { return }
        guard pendingHoverPreviewWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.showHoverPreview()
            }
        }

        pendingHoverPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func cancelScheduledHoverPreview() {
        pendingHoverPreviewWorkItem?.cancel()
        pendingHoverPreviewWorkItem = nil
    }

    private func scheduleHoverPreviewClose() {
        guard hoverPreviewPanel?.isVisible == true else { return }
        guard pendingHoverCloseWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.closeHoverPreview()
            }
        }

        pendingHoverCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func cancelScheduledHoverPreviewClose() {
        pendingHoverCloseWorkItem?.cancel()
        pendingHoverCloseWorkItem = nil
    }

    private func showHoverPreview() {
        cancelScheduledHoverPreview()
        cancelScheduledHoverPreviewClose()

        guard hoverPreviewPanel?.isVisible != true else { return }
        guard !mainPopover.isShown else { return }
        guard let button = statusItem.button else { return }
        guard let panel = hoverPreviewPanel else { return }
        guard !diskMonitor.removableVolumes.isEmpty else { return }

        updateHoverPreviewPanelSize()
        positionHoverPreviewPanel(relativeTo: button, panel: panel)
        panel.orderFrontRegardless()
    }

    private func closeHoverPreview() {
        cancelScheduledHoverPreview()
        cancelScheduledHoverPreviewClose()
        hoverPreviewPanel?.orderOut(nil)
    }

    private func positionHoverPreviewPanel(relativeTo button: NSStatusBarButton, panel: NSPanel) {
        guard let buttonFrame = statusItemScreenFrame else { return }

        let panelSize = panel.frame.size
        let screenVisibleFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var originX = buttonFrame.midX - (panelSize.width / 2)
        originX = max(screenVisibleFrame.minX + 8, min(originX, screenVisibleFrame.maxX - panelSize.width - 8))

        let originY = max(screenVisibleFrame.minY + 8, buttonFrame.minY - panelSize.height - 8)
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize), display: true)
    }

    @objc
    private func handleStatusItemClick() {
        cancelScheduledHoverPreview()
        closeHoverPreview()

        guard let button = statusItem.button else { return }

        if mainPopover.isShown {
            mainPopover.performClose(nil)
        } else {
            mainPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct HoverPreviewListView: View {
    @EnvironmentObject private var diskMonitor: DiskMonitor

    var body: some View {
        VStack(spacing: HoverPreviewLayout.cardSpacing) {
            ForEach(diskMonitor.removableVolumes) { volume in
                HoverPreviewCard(
                    volume: volume,
                    mediaSummary: diskMonitor.mediaSummaries[volume.id]
                )
            }
        }
        .padding(HoverPreviewLayout.contentPadding)
        .frame(width: HoverPreviewLayout.listWidth, alignment: .top)
        .background(Color.clear)
    }
}

private final class HoverPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum HoverPreviewLayout {
    static let panelWidth: CGFloat = 388
    static let listWidth: CGFloat = 364
    static let minimumPanelHeight: CGFloat = 160
    static let contentPadding: CGFloat = 12
    static let cardSpacing: CGFloat = 12
    static let estimatedCardHeight: CGFloat = 170
}

private struct HoverPreviewCard: View {
    let volume: MountedVolume
    let mediaSummary: VolumeMediaSummary?

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
                Color(red: 0.22, green: 0.63, blue: 0.40),
                Color(red: 0.16, green: 0.50, blue: 0.31),
                Color(red: 0.13, green: 0.42, blue: 0.26),
            ]
        case ..<0.75:
            return [
                Color(red: 0.91, green: 0.77, blue: 0.40),
                Color(red: 0.82, green: 0.60, blue: 0.24),
                Color(red: 0.72, green: 0.48, blue: 0.18),
            ]
        case ..<0.9:
            return [
                Color(red: 0.94, green: 0.66, blue: 0.34),
                Color(red: 0.86, green: 0.50, blue: 0.20),
                Color(red: 0.73, green: 0.38, blue: 0.15),
            ]
        default:
            return [
                Color(red: 0.88, green: 0.44, blue: 0.42),
                Color(red: 0.76, green: 0.30, blue: 0.28),
                Color(red: 0.62, green: 0.22, blue: 0.22),
            ]
        }
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: Array(cardPalette.reversed()),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var statusText: String {
        guard let mediaSummary else {
            return "正在扫描照片和视频..."
        }

        if mediaSummary.pendingPhotoCount == 0 && mediaSummary.pendingVideoCount == 0 {
            return "已全部导入"
        }

        return "待导入 \(mediaSummary.pendingPhotoCount) 张照片 · \(mediaSummary.pendingVideoCount) 个视频"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(volume.formatDescription) 格式 · 已用 \(usagePercent)%")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(volume.roundedTotalText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.16), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
            }

            HStack(spacing: 10) {
                HoverPreviewMetricPill(title: "已用空间", value: volume.usedText)
                HoverPreviewMetricPill(title: "剩余空间", value: volume.availableText)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(usageTint.opacity(0.95))
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
    }
}

private struct HoverPreviewMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }
}
