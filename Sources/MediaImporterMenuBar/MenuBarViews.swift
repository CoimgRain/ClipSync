import AppKit
import SwiftUI

private enum PreviewExecutionContext {
    static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }()
}

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
    let onContentHeightChange: ((CGFloat) -> Void)?
    @State private var isShowingSettingsPopover = false
    @State private var destinationAnimationSeed = UUID().uuidString
    @State private var isHoveringAutoImportChip = false
    @State private var lastReportedContentHeight: CGFloat = 0
    @StateObject private var folderClassificationWindowController = FolderClassificationWindowController()

    init(onContentHeightChange: ((CGFloat) -> Void)? = nil) {
        self.onContentHeightChange = onContentHeightChange
    }

    private var visibleStatusMessage: String? {
        guard importer.isImporting || importer.lastResultMessage != "等待导入" else {
            return nil
        }

        return importer.lastResultMessage
    }

    private var destinationPanelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var destinationPanelPalette: [Color] {
        [
            Color(red: 0.66, green: 0.84, blue: 1.00),
            Color(red: 0.48, green: 0.73, blue: 0.97),
            Color(red: 0.34, green: 0.61, blue: 0.90),
            Color(red: 0.24, green: 0.48, blue: 0.75),
        ]
    }

    private var destinationPanelTint: Color {
        Color(red: 0.44, green: 0.72, blue: 0.98)
    }

    private var destinationPanelGradient: LinearGradient {
        LinearGradient(
            colors: Array(destinationPanelPalette.reversed()),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var destinationChipFill: Color {
        Color(red: 0.24, green: 0.40, blue: 0.58).opacity(0.30)
    }

    private var autoImportChipAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.82)
    }

    private var autoImportChipIconColor: Color {
        settings.autoImportEnabled ? Color(red: 1.00, green: 0.84, blue: 0.24) : .white.opacity(0.72)
    }

    private var destinationPanelBackground: some View {
        ZStack {
            destinationPanelShape
                .fill(destinationPanelGradient)

            AnimatedColorFlow(
                seed: destinationAnimationSeed,
                style: .aurora,
                palette: destinationPanelPalette,
                primaryTint: destinationPanelTint
            )

            AnimatedOrbField(
                seed: destinationAnimationSeed,
                style: .aurora,
                primaryTint: destinationPanelTint,
                palette: destinationPanelPalette
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
            .clipShape(destinationPanelShape)
        }
        .clipShape(destinationPanelShape)
    }

    private var mediaSummaryRefreshTaskID: String {
        let volumeIDs = diskMonitor.removableVolumes.map(\.id).joined(separator: "|")
        return "\(diskMonitor.mediaSummaryRefreshToken.uuidString)|\(settings.destinationFolderPath)|\(volumeIDs)"
    }

    private let cardStackSpacing: CGFloat = 12

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: cardStackSpacing) {
            destinationSection
            deviceSection
            bottomSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: MenuContentHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
    }

    var body: some View {
        contentBody
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onPreferenceChange(MenuContentHeightPreferenceKey.self) { newHeight in
            let measuredHeight = ceil(newHeight)
            guard abs(measuredHeight - lastReportedContentHeight) > 0.5 else { return }
            lastReportedContentHeight = measuredHeight
            onContentHeightChange?(measuredHeight)
        }
        .animation(.easeInOut(duration: 0.2), value: visibleStatusMessage)
        .task(id: mediaSummaryRefreshTaskID) {
            guard !PreviewExecutionContext.isActive else { return }
            await refreshMediaSummaries()
        }
    }

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let visibleStatusMessage {
                StatusBanner(message: visibleStatusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            footerSection
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("目标文件夹")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.96))

                    if settings.destinationFolderPath.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            
                            Text("可在右下角设置中指定本地目录")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    } else {
                        Text(settings.destinationFolderPath)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.90))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button {
                    withAnimation(autoImportChipAnimation) {
                        settings.autoImportEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: -15) {
                        ZStack {
                            Image(systemName: "bolt.slash.fill")
                                .opacity(settings.autoImportEnabled ? 0 : 1)
                                .scaleEffect(settings.autoImportEnabled ? 0.82 : 1)
                                .offset(y: settings.autoImportEnabled ? -1 : 0)

                            Image(systemName: "bolt.fill")
                                .opacity(settings.autoImportEnabled ? 1 : 0)
                                .scaleEffect(settings.autoImportEnabled ? 1 : 0.82)
                                .offset(y: settings.autoImportEnabled ? 0 : 1)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(autoImportChipIconColor)
                        .frame(width: 30, height: 30)
                        .shadow(
                            color: settings.autoImportEnabled
                                ? Color(red: 1.00, green: 0.84, blue: 0.24).opacity(isHoveringAutoImportChip ? 0.28 : 0.18)
                                : .clear,
                            radius: settings.autoImportEnabled ? (isHoveringAutoImportChip ? 8 : 5) : 0,
                            x: 0,
                            y: 0
                        )

                        Text(settings.autoImportEnabled ? "自动导入已开启" : "目前未自动导入")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 11)
                    }
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 3)
                .frame(minHeight: 30)
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(AutoImportStatusChipButtonStyle(
                    isHovered: isHoveringAutoImportChip,
                    fillColor: destinationChipFill
                ))
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isHoveringAutoImportChip = hovering
                    }
                }
                .animation(autoImportChipAnimation, value: settings.autoImportEnabled)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(destinationPanelBackground)
        .overlay {
            destinationPanelShape
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        VStack(spacing: cardStackSpacing) {
            if diskMonitor.removableVolumes.isEmpty {
                EmptyDeviceState()
            } else {
                ForEach(diskMonitor.removableVolumes) { volume in
                    VolumeCard(volume: volume)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func refreshMediaSummaries() async {
        guard !diskMonitor.removableVolumes.isEmpty else {
            await diskMonitor.rescanMediaSummaries(comparingAgainst: nil)
            return
        }

        guard !settings.destinationFolderPath.isEmpty else {
            await diskMonitor.rescanMediaSummaries(comparingAgainst: nil)
            return
        }

        do {
            try await settings.withDestinationFolderAccess { destinationFolderURL in
                await diskMonitor.rescanMediaSummaries(comparingAgainst: destinationFolderURL)
            }
        } catch {
            await diskMonitor.rescanMediaSummaries(comparingAgainst: nil)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.headline)

                    Text("导入目标、自动导入和分类规则都在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("选择目标文件夹")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(settings.destinationFolderPath.isEmpty ? "点按选择导入文件夹" : settings.destinationFolderPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    isShowingSettingsPopover = false
                    settings.chooseDestinationFolder()
                }

                HStack(spacing: 12) {
                    Image(systemName: settings.autoImportEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(settings.autoImportEnabled ? Color(red: 1.00, green: 0.84, blue: 0.24) : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动导入")
                            .font(.body.weight(.semibold))
                        Text("插入设备后自动开始导入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.autoImportEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }

                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("文件夹分类规则")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("按文件夹名称自动归类视频")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(settings.enabledRuleCount) 条")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(settings.enabledRuleCount > 0 ? .blue : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    isShowingSettingsPopover = false
                    folderClassificationWindowController.present(settings: settings)
                }
            }

        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
    }
}

@MainActor
private final class FolderClassificationWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(settings: AppSettings) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = FolderClassificationRulesView { [weak self] in
            self?.close()
        }
        .environmentObject(settings)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "文件夹分类规则"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 760, height: 720))
        window.minSize = NSSize(width: 720, height: 640)

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct FolderClassificationRulesView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var testFolderName = ""
    @State private var isShowingLogsSheet = false

    let onDone: () -> Void

    private var matchedRuleForTest: FolderClassificationRule? {
        guard !testFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return settings.testRuleMatch(for: testFolderName)
    }

    private var logsSummaryText: String {
        if settings.classificationLogs.isEmpty {
            return "还没有日志。以后导入时命中规则，这里会自动记录。"
        }

        return "目前已有 \(settings.classificationLogs.count) 条日志，需要时再点开查看就行。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("文件夹分类规则")
                        .font(.title3.bold())
                    Text("想要的效果很简单：当原始文件夹名里包含某个词时，对应视频就自动放进你指定的目标子文件夹。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topOverviewSection
                    ruleListSection
                    supplementarySection
                    secondaryToolsSection
                }
                .padding(.bottom, 4)
            }
        }
        .padding(20)
        .frame(width: 760, height: 720, alignment: .topLeading)
        .sheet(isPresented: $isShowingLogsSheet) {
            FolderClassificationLogsSheetView()
                .environmentObject(settings)
        }
    }

    private var topOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基础设置")
                .font(.headline)

            HStack(alignment: .top, spacing: 14) {
                stepOneSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: 138, alignment: .topLeading)

                stepTwoSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: 138, alignment: .topLeading)
            }
        }
    }

    private var secondaryToolsSection: some View {
        HStack(alignment: .top, spacing: 14) {
            testSection
                .frame(maxWidth: .infinity, alignment: .topLeading)

            logsSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stepOneSection: some View {
        FolderClassificationSettingCard(
            badgeText: "步骤 1",
            title: "导入目标文件夹",
            detail: settings.destinationFolderPath.isEmpty
                ? "还没有选择导入目标文件夹。"
                : "已经选择好导入目标文件夹了。"
        ) {
            HStack(alignment: .top, spacing: 10) {
                Text(settings.destinationFolderPath.isEmpty ? "还没有选择导入文件夹" : settings.destinationFolderPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("选择目标文件夹") {
                    settings.chooseDestinationFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var stepTwoSection: some View {
        FolderClassificationSettingCard(
            badgeText: "步骤 2",
            title: "开启自动分类",
            detail: "开启后，下面的规则才会参与匹配。"
        ) {
            HStack(alignment: .center, spacing: 10) {
                Text("开启文件夹自动分类")
                    .font(.callout.weight(.semibold))

                Spacer()

                Toggle("", isOn: $settings.folderClassificationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var supplementarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("补充设置")
                .font(.headline)

            FolderClassificationSettingCard(
                badgeText: "补充设置",
                title: "同名文件处理",
                detail: settings.folderConflictStrategy.detail
            ) {
                Picker("", selection: $settings.folderConflictStrategy) {
                    ForEach(FolderConflictStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ruleListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    FolderClassificationSectionTitle(
                        badgeText: "步骤 3",
                        title: "规则列表"
                    )
                    Text("新增规则后，填写“包含什么词”和“放到哪个子文件夹”，就可以开始自动分类。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    settings.addFolderClassificationRule()
                } label: {
                    Label("新增规则", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("匹配顺序从上到下依次执行，命中第一条就停止。可以把更常用的规则放在更上面。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if settings.folderClassificationRules.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有规则。")
                        .font(.subheadline.weight(.semibold))
                    Text("新增一条后，填上“包含什么词”和“放到哪个文件夹”，就可以开始自动分类。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(zip(settings.folderClassificationRules.indices, $settings.folderClassificationRules)), id: \.1.id) { index, ruleBinding in
                        FolderClassificationRuleRow(
                            rule: ruleBinding,
                            index: index,
                            canMoveUp: index > 0,
                            canMoveDown: index < settings.folderClassificationRules.count - 1,
                            onMoveUp: { settings.moveFolderClassificationRule(id: ruleBinding.wrappedValue.id, offset: -1) },
                            onMoveDown: { settings.moveFolderClassificationRule(id: ruleBinding.wrappedValue.id, offset: 1) },
                            onDelete: { settings.removeFolderClassificationRule(id: ruleBinding.wrappedValue.id) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("试一下规则")
                .font(.headline)

            TextField("输入一个原始文件夹名称，例如 POK_001", text: $testFolderName)
                .textFieldStyle(.roundedBorder)

            Group {
                if testFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入后，系统会按当前规则顺序帮你模拟一次结果。")
                        .foregroundStyle(.secondary)
                } else if let matchedRuleForTest {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("会命中关键词：\(matchedRuleForTest.keyword)")
                        Text("视频会进入：\(matchedRuleForTest.normalizedTargetFolderPath)")
                    }
                } else {
                    Text("没有命中任何规则，系统会按默认导入方式放进“设备名/时间戳”目录。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作日志")
                        .font(.headline)
                    Text("日志单独打开看，这里不再整页铺开，界面会更清爽。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("打开日志") {
                    isShowingLogsSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(logsSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FolderClassificationRuleRow: View {
    @Binding var rule: FolderClassificationRule

    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FolderClassificationBadge(text: "规则 \(index + 1)")

                Toggle("启用这条规则", isOn: $rule.isEnabled)
                    .toggleStyle(.switch)

                Spacer()

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canMoveUp)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canMoveDown)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当原始文件夹名里包含")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如 pok", text: $rule.keyword)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("就把视频放到这个子文件夹")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如 Pocket 或 Pocket/Final", text: $rule.targetFolderName)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                if rule.isConfigured {
                    Text("效果预览")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("如果文件夹名里包含“\(rule.keyword)”，视频会自动进入“\(rule.normalizedTargetFolderPath)”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("把上面两项都填好后，这条规则才会生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct FolderClassificationLogRow: View {
    let entry: FolderClassificationLogEntry
    let formatter: DateFormatter

    private var ruleDescription: String {
        if entry.didMatchRule,
           let ruleKeyword = entry.ruleKeyword,
           let targetFolder = entry.ruleTargetFolderName {
            return "规则：\(ruleKeyword) -> \(targetFolder)"
        }

        return "未命中规则，按默认目录导入"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.fileName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(formatter.string(from: entry.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("源文件夹：\(entry.sourceFolderName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("目标路径：\(entry.destinationSubpath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(ruleDescription)
                .font(.caption)
                .foregroundStyle(entry.didMatchRule ? .primary : .secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FolderClassificationLogsSheetView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作日志")
                        .font(.title3.bold())
                    Text("这里会记录每次自动分类命中了哪条规则，以及最终放到了哪里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("清空日志") {
                    settings.clearClassificationLogs()
                }
                .buttonStyle(.bordered)
                .disabled(settings.classificationLogs.isEmpty)

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            if settings.classificationLogs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有日志。")
                        .font(.headline)
                    Text("等下一次导入命中规则后，这里就会出现记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(settings.classificationLogs) { entry in
                            FolderClassificationLogRow(entry: entry, formatter: Self.logDateFormatter)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 560, alignment: .topLeading)
    }
}

private struct FolderClassificationSettingCard<Content: View>: View {
    let badgeText: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolderClassificationSectionTitle(
                badgeText: badgeText,
                title: title
            )

            content

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct FolderClassificationSectionTitle: View {
    let badgeText: String
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FolderClassificationBadge(text: badgeText)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct FolderClassificationBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.blue.opacity(0.16), in: Capsule())
    }
}

private struct MenuContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    @State private var animationSeed = UUID().uuidString

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var cardPalette: [Color] {
        [
            Color(red: 0.80, green: 0.67, blue: 0.53),
            Color(red: 0.70, green: 0.56, blue: 0.41),
            Color(red: 0.53, green: 0.38, blue: 0.25),
            Color(red: 0.40, green: 0.27, blue: 0.17),
        ]
    }

    private var cardTint: Color {
        Color(red: 0.69, green: 0.53, blue: 0.37)
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
                seed: animationSeed,
                style: .aurora,
                palette: cardPalette,
                primaryTint: cardTint
            )

            AnimatedOrbField(
                seed: animationSeed,
                style: .aurora,
                primaryTint: cardTint,
                palette: cardPalette
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.20),
                    Color.white.opacity(0.07),
                    .clear,
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .clipShape(cardShape)
        }
        .clipShape(cardShape)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.72))

            Text("未检测到 U 盘或 SD 卡")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.94))

            Text("插入设备后会自动刷新列表")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(cardBackground)
        .overlay {
            cardShape
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct VolumeCard: View {
    @EnvironmentObject private var diskMonitor: DiskMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var importer: MediaImporter
    @State private var animationSeed = UUID().uuidString
    @State private var isHoveringCapacityChip = false
    @State private var isHoveringOpenVolumeAction = false
    @State private var isHoveringEjectVolumeAction = false
    @State private var isHoveringCard = false
    @State private var isPrimaryActionHovered = false
    @State private var isCancelImportHovered = false
    @State private var headerRowWidth: CGFloat = 0

    let volume: MountedVolume

    private var isCurrentVolumeImporting: Bool {
        importer.currentImportVolumeID == volume.id && importer.importProgress != nil
    }

    private var visualStyle: VolumeVisualStyle {
        volume.visualStyle
    }

    private var usagePercent: Int {
        volume.usagePercent
    }

    private var usageTint: Color {
        visualStyle.usageTint
    }

    private var cardPalette: [Color] {
        visualStyle.cardPalette
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

    private var animationStyle: CardAnimationStyle {
        visualStyle.animationStyle
    }

    private var expandableSectionAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    private var shouldShowFooterSection: Bool {
        isCurrentVolumeImporting || isHoveringCard
    }

    private var footerSectionTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var cardBackground: some View {
        ZStack {
            cardShape
                .fill(cardGradient)

            AnimatedColorFlow(
                seed: animationSeed,
                style: animationStyle,
                palette: cardPalette,
                primaryTint: usageTint
            )

            AnimatedOrbField(
                seed: animationSeed,
                style: animationStyle,
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
        if isFullyImported {
            return "已全部导入"
        }

        if !hasImportableMedia {
            return "无可导入影音"
        }

        return settings.destinationFolderPath.isEmpty ? "选择导入目标文件夹" : "导入照片和视频"
    }

    private var shouldHighlightPrimaryAction: Bool {
        !isPrimaryActionDisabled && !isFullyImported
    }

    private var actionButtonForegroundColor: Color {
        if isFullyImported {
            return .white
        }

        return isPrimaryActionDisabled ? .white.opacity(0.62) : .white.opacity(0.96)
    }

    private var actionButtonFillColor: Color {
        if isFullyImported {
            return Color(red: 0.22, green: 0.74, blue: 0.40).opacity(0.96)
        }

        return isPrimaryActionDisabled ? Color.gray.opacity(0.34) : Color.black.opacity(0.18)
    }

    private var actionButtonHoverOverlayColor: Color {
        shouldHighlightPrimaryAction && isPrimaryActionHovered ? .white.opacity(0.08) : .clear
    }

    private var actionButtonBorderColor: Color {
        if isFullyImported {
            return .white.opacity(0.8)
        }

        if isPrimaryActionDisabled {
            return .white.opacity(0.06)
        }

        return isPrimaryActionHovered ? .white.opacity(0.18) : .white.opacity(0.10)
    }

    private var cancelImportHoverOverlayColor: Color {
        isCancelImportHovered ? .white.opacity(0.08) : .clear
    }

    private var cancelImportBorderColor: Color {
        isCancelImportHovered ? .white.opacity(0.18) : .white.opacity(0.10)
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

    private var mediaSummary: VolumeMediaSummary? {
        diskMonitor.mediaSummaries[volume.id]
    }

    private var hasImportableMedia: Bool {
        guard let mediaSummary else { return true }
        return mediaSummary.hasImportableMedia
    }

    private var isFullyImported: Bool {
        guard let mediaSummary, !settings.destinationFolderPath.isEmpty else { return false }
        let hasImportedMedia = mediaSummary.importedPhotoCount > 0 || mediaSummary.importedVideoCount > 0
        return hasImportedMedia && mediaSummary.pendingPhotoCount == 0 && mediaSummary.pendingVideoCount == 0
    }

    private var isPrimaryActionDisabled: Bool {
        (!settings.destinationFolderPath.isEmpty && importer.isImporting) || !hasImportableMedia
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

    @ViewBuilder
    private var mediaSummaryDetailView: some View {
        if let mediaSummary {
            VStack(alignment: .leading, spacing: 3) {
                mediaSummaryLine(
                    symbol: "photo.on.rectangle.angled",
                    importedCount: mediaSummary.importedPhotoCount,
                    pendingCount: mediaSummary.pendingPhotoCount
                )

                mediaSummaryLine(
                    symbol: "video.fill",
                    importedCount: mediaSummary.importedVideoCount,
                    pendingCount: mediaSummary.pendingVideoCount
                )
            }
            .layoutPriority(1)
        } else {
            Text(
                settings.destinationFolderPath.isEmpty
                    ? "正在扫描照片和视频..."
                    : "正在扫描照片和视频\n并核对已导入文件..."
            )
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
    }

    private func mediaSummaryLine(
        symbol: String,
        importedCount: Int,
        pendingCount: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 10)

            HStack(spacing: 0) {
                summaryMetricColumn(
                    symbol: "checkmark.circle.fill",
                    value: importedCount
                )
                .frame(maxWidth: .infinity, alignment: .trailing)

                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 7)

                summaryMetricColumn(
                    symbol: "arrow.down.circle.fill",
                    value: pendingCount
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryMetricColumn(symbol: String, value: Int) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 10, weight: .semibold))
                .offset(y: -1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .allowsTightening(true)
    }

    private var compactCapacityChipWidth: CGFloat {
        max(84, CGFloat(volume.roundedTotalText.count) * 10.2 + 34)
    }

    private var expandedCapacityChipWidth: CGFloat {
        max(compactCapacityChipWidth + 34, 128)
    }

    private var capacityChipAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.18)
    }

    private var formatSummaryAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    private static let formatSummaryUIFont = NSFont.systemFont(ofSize: 14, weight: .semibold)

    private var formatSummaryFormatNameText: String {
        volume.formatDescription
    }

    private var formatSummaryFormatSuffixText: String {
        " 格式"
    }

    private var expandedFormatSummaryMiddleText: String {
        " · 已用 "
    }

    private var compactFormatSummaryMiddleText: String {
        " · "
    }

    private func formatSummaryTextWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Self.formatSummaryUIFont]).width)
    }

    private var expandedFormatSummaryMiddleWidth: CGFloat {
        formatSummaryTextWidth(expandedFormatSummaryMiddleText)
    }

    private var compactFormatSummaryMiddleWidth: CGFloat {
        formatSummaryTextWidth(compactFormatSummaryMiddleText)
    }

    private var formatSummaryTrailingText: String {
        "\(usagePercent)%"
    }

    private var capacityChipBackground: some View {
        Capsule()
            .fill(Color.black.opacity(0.2))
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func openVolumeInFinder() {
        guard NSWorkspace.shared.open(volume.url) else {
            importer.setStatusMessage("无法打开 \(volume.name)")
            return
        }
    }

    private func ejectVolume() {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            importer.setStatusMessage("正在弹出 \(volume.name)...")
            diskMonitor.refreshVolumes()
        } catch {
            importer.setStatusMessage("无法弹出 \(volume.name)")
        }
    }

    private var capacityChip: some View {
        ZStack {
            if isHoveringCapacityChip {
                HStack(spacing: 0) {
                    Button {
                        openVolumeInFinder()
                    } label: {
                        Image(systemName: isHoveringOpenVolumeAction ? "folder.fill" : "folder")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(CapacityChipActionButtonStyle(isHovered: isHoveringOpenVolumeAction))
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.14)) {
                            isHoveringOpenVolumeAction = hovering
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 22)

                    Button {
                        ejectVolume()
                    } label: {
                        Image(systemName: isHoveringEjectVolumeAction ? "eject.fill" : "eject")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(CapacityChipActionButtonStyle(isHovered: isHoveringEjectVolumeAction))
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.14)) {
                            isHoveringEjectVolumeAction = hovering
                        }
                    }
                }
                .foregroundStyle(.white.opacity(0.95))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(volume.roundedTotalText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.95))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: isHoveringCapacityChip ? expandedCapacityChipWidth : compactCapacityChipWidth, height: 42)
        .background {
            capacityChipBackground
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .animation(capacityChipAnimation, value: isHoveringCapacityChip)
        .onHover { hovering in
            isHoveringCapacityChip = hovering
            if !hovering {
                isHoveringOpenVolumeAction = false
                isHoveringEjectVolumeAction = false
            }
        }
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

    private var capacityTilesRowHeight: CGFloat {
        let usedFraction = max(0, min(1, volume.usageFraction))
        let remainingFraction = max(0, 1 - usedFraction)
        let showsUsedTile = usedFraction > 0.0001
        let showsRemainingTile = remainingFraction > 0.0001
        let separatorWidth: CGFloat = (showsUsedTile && showsRemainingTile) ? 12 : 0
        let availableWidth = max(headerRowWidth, 0)
        let usedMinimumWidth = showsUsedTile ? InfoTile.minimumWidth(title: "已用空间", value: volume.usedText) : 0
        let remainingMinimumWidth = showsRemainingTile ? InfoTile.minimumWidth(title: "剩余空间", value: volume.availableText) : 0
        let requiresStackedLayout = availableWidth > 0 && showsUsedTile && showsRemainingTile
            && (usedMinimumWidth + remainingMinimumWidth + separatorWidth > availableWidth)

        return requiresStackedLayout ? 136 : 54
    }

    private var capacityTilesRow: some View {
        GeometryReader { proxy in
            let usedFraction = max(0, min(1, volume.usageFraction))
            let remainingFraction = max(0, 1 - usedFraction)
            let showsUsedTile = usedFraction > 0.0001
            let showsRemainingTile = remainingFraction > 0.0001
            let separatorWidth: CGFloat = (showsUsedTile && showsRemainingTile) ? 12 : 0
            let contentWidth = max(0, proxy.size.width - separatorWidth)
            let usedMinimumWidth = showsUsedTile ? InfoTile.minimumWidth(title: "已用空间", value: volume.usedText) : 0
            let remainingMinimumWidth = showsRemainingTile ? InfoTile.minimumWidth(title: "剩余空间", value: volume.availableText) : 0
            let widths = capacityTileWidths(
                totalWidth: contentWidth,
                usedMinimumWidth: usedMinimumWidth,
                remainingMinimumWidth: remainingMinimumWidth
            )
            let requiresStackedLayout = showsUsedTile && showsRemainingTile
                && (usedMinimumWidth + remainingMinimumWidth + separatorWidth > proxy.size.width)

            Group {
                if requiresStackedLayout {
                    VStack(spacing: 8) {
                        if showsUsedTile {
                            InfoTile(
                                title: "已用空间",
                                value: volume.usedText,
                                backgroundColors: neutralInfoTileBackgroundColors,
                                borderColor: infoTileBorderColor
                            )
                        }

                        if showsRemainingTile {
                            InfoTile(
                                title: "剩余空间",
                                value: volume.availableText,
                                backgroundColors: neutralInfoTileBackgroundColors,
                                borderColor: infoTileBorderColor
                            )
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        if showsUsedTile {
                            InfoTile(
                                title: "已用空间",
                                value: volume.usedText,
                                backgroundColors: neutralInfoTileBackgroundColors,
                                borderColor: infoTileBorderColor
                            )
                            .frame(width: widths.used, alignment: .leading)
                        }

                        if showsUsedTile && showsRemainingTile {
                            Circle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .frame(width: separatorWidth)
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: capacityTilesRowHeight)
    }

    private var formatSummaryView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(formatSummaryFormatNameText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(formatSummaryFormatSuffixText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            ZStack {
                Text(expandedFormatSummaryMiddleText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isHoveringCapacityChip ? 0 : 1)
                    .offset(x: isHoveringCapacityChip ? -4 : 0)

                Text(compactFormatSummaryMiddleText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isHoveringCapacityChip ? 1 : 0)
                    .offset(x: isHoveringCapacityChip ? 0 : 4)
            }
            .frame(
                width: isHoveringCapacityChip
                    ? compactFormatSummaryMiddleWidth
                    : expandedFormatSummaryMiddleWidth,
                alignment: .center
            )
            .clipped()

            Text(formatSummaryTrailingText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.70))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(formatSummaryAnimation, value: isHoveringCapacityChip)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(volume.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    formatSummaryView
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                capacityChip
                    .padding(.top, 2)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: HeaderRowWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(HeaderRowWidthPreferenceKey.self) { newValue in
                headerRowWidth = newValue
            }

            capacityTilesRow

            if shouldShowFooterSection {
                Group {
                    if isCurrentVolumeImporting {
                        importProgressSection
                    } else {
                        idleSection
                    }
                }
                .transition(footerSectionTransition)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .contentShape(cardShape)
        .onHover { hovering in
            withAnimation(expandableSectionAnimation) {
                isHoveringCard = hovering
            }

            if !hovering {
                isPrimaryActionHovered = false
                isCancelImportHovered = false
            }
        }
    }

    private var idleSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                mediaSummaryDetailView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 30)

            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 5) {
                    if isFullyImported {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white)
                    }

                    Text(actionButtonTitle)
                        .foregroundStyle(isFullyImported ? .white : .white.opacity(0.96))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(actionButtonForegroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(actionButtonFillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(actionButtonHoverOverlayColor)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(actionButtonBorderColor, lineWidth: 1)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .scaleEffect(shouldHighlightPrimaryAction && isPrimaryActionHovered ? 1.015 : 1)
            .shadow(
                color: shouldHighlightPrimaryAction && isPrimaryActionHovered
                    ? Color.white.opacity(0.10)
                    : .clear,
                radius: 10,
                x: 0,
                y: 0
            )
            .opacity(isFullyImported ? 1 : (isPrimaryActionDisabled ? 0.55 : 1))
            .allowsHitTesting(!isPrimaryActionDisabled)
            .animation(.easeOut(duration: 0.22), value: isPrimaryActionHovered)
            .onHover { hovering in
                isPrimaryActionHovered = hovering
            }
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
    }

    private var importProgressSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(importer.importProgressDetailText ?? "-- / --")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Group {
                        if PreviewExecutionContext.isActive {
                            Text(importer.importRemainingTimeText ?? "--:--")
                        } else {
                            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                                Text(importer.importRemainingTimeText ?? "--:--")
                            }
                        }
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                }

                GeometryReader { proxy in
                    let progress = max(0, min(1, importer.importProgress ?? 0))

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.20))

                        Capsule()
                            .fill(Color.white.opacity(0.96))
                            .frame(width: max(18, proxy.size.width * progress))
                            .animation(.linear(duration: 0.18), value: progress)
                    }
                }
                .frame(height: 8)

                if importer.totalPhotoCount > 0 || importer.totalVideoCount > 0 {
                    HStack(spacing: 12) {
                        Text("\(importer.importedPhotoCount)/\(importer.totalPhotoCount) 张照片")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(importer.importedVideoCount)/\(importer.totalVideoCount) 个视频")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                } else {
                    Text(importer.lastResultMessage)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 46)

            Button("取消导入") {
                importer.cancelImport()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(cancelImportHoverOverlayColor)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(cancelImportBorderColor, lineWidth: 1)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .scaleEffect(isCancelImportHovered ? 1.015 : 1)
            .shadow(
                color: isCancelImportHovered ? Color.white.opacity(0.10) : .clear,
                radius: 10,
                x: 0,
                y: 0
            )
            .animation(.easeOut(duration: 0.22), value: isCancelImportHovered)
            .onHover { hovering in
                isCancelImportHovered = hovering
            }
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
    }

    private func handlePrimaryAction() {
        guard !settings.destinationFolderPath.isEmpty else {
            settings.chooseDestinationFolder()
            return
        }

        Task {
            do {
                _ = try await settings.withDestinationFolderAccess { destinationFolderURL in
                    let didFinish = await importer.importMedia(from: volume, to: destinationFolderURL, settings: settings)
                    await diskMonitor.rescanMediaSummaries(comparingAgainst: destinationFolderURL)
                    return didFinish
                }
            } catch {
                importer.setStatusMessage(error.localizedDescription)
            }
        }
    }
}

private struct CapacityChipActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.08 : 0)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(configuration.isPressed ? 0.20 : (isHovered ? 0.14 : 0)), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovered ? 1.02 : 1))
            .shadow(
                color: isHovered ? .white.opacity(configuration.isPressed ? 0.04 : 0.10) : .clear,
                radius: 8,
                x: 0,
                y: 0
            )
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: isHovered)
    }
}

private struct AutoImportStatusChipButtonStyle: ButtonStyle {
    let isHovered: Bool
    let fillColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(fillColor)
                    .overlay {
                        Capsule()
                            .fill(.white.opacity(configuration.isPressed ? 0.13 : (isHovered ? 0.07 : 0)))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                .white.opacity(configuration.isPressed ? 0.22 : (isHovered ? 0.16 : 0.10)),
                                lineWidth: 1
                            )
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.015 : 1))
            .shadow(
                color: isHovered ? .white.opacity(configuration.isPressed ? 0.04 : 0.10) : .clear,
                radius: isHovered ? 10 : 0,
                x: 0,
                y: 0
            )
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: isHovered)
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
    private static let widthBuffer: CGFloat = 16

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

private struct HeaderRowWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum CardAnimationStyle {
    case aurora
    case ribbon
    case bloom
    case ember
}

struct VolumeVisualStyle {
    let usageTint: Color
    let cardPalette: [Color]
    let animationStyle: CardAnimationStyle
}

extension MountedVolume {
    var usagePercent: Int {
        Int((usageFraction * 100).rounded())
    }

    var visualStyle: VolumeVisualStyle {
        switch usageFraction {
        case ..<0.5:
            return VolumeVisualStyle(
                usageTint: Color(red: 0.17, green: 0.62, blue: 0.39),
                cardPalette: [
                    Color(red: 0.35, green: 0.78, blue: 0.54),
                    Color(red: 0.22, green: 0.63, blue: 0.40),
                    Color(red: 0.16, green: 0.50, blue: 0.31),
                    Color(red: 0.13, green: 0.42, blue: 0.26),
                ],
                animationStyle: .aurora
            )
        case ..<0.75:
            return VolumeVisualStyle(
                usageTint: Color(red: 0.83, green: 0.62, blue: 0.18),
                cardPalette: [
                    Color(red: 0.91, green: 0.77, blue: 0.40),
                    Color(red: 0.82, green: 0.60, blue: 0.24),
                    Color(red: 0.72, green: 0.48, blue: 0.18),
                    Color(red: 0.58, green: 0.37, blue: 0.14),
                ],
                animationStyle: .ribbon
            )
        case ..<0.9:
            return VolumeVisualStyle(
                usageTint: Color(red: 0.84, green: 0.45, blue: 0.18),
                cardPalette: [
                    Color(red: 0.94, green: 0.66, blue: 0.34),
                    Color(red: 0.86, green: 0.50, blue: 0.20),
                    Color(red: 0.73, green: 0.38, blue: 0.15),
                    Color(red: 0.60, green: 0.28, blue: 0.12),
                ],
                animationStyle: .bloom
            )
        default:
            return VolumeVisualStyle(
                usageTint: Color(red: 0.78, green: 0.24, blue: 0.25),
                cardPalette: [
                    Color(red: 0.88, green: 0.44, blue: 0.42),
                    Color(red: 0.76, green: 0.30, blue: 0.28),
                    Color(red: 0.62, green: 0.22, blue: 0.22),
                    Color(red: 0.50, green: 0.16, blue: 0.18),
                ],
                animationStyle: .ember
            )
        }
    }
}

private struct AnimatedOrbField: View {
    let seed: String
    let style: CardAnimationStyle
    let primaryTint: Color
    let palette: [Color]

    @State private var animate = false

    private var specs: [OrbSpec] {
        OrbSpec.make(seed: seed, style: style, palette: palette, fallbackTint: primaryTint)
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
            guard !PreviewExecutionContext.isActive else { return }
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

        static func make(seed: String, style: CardAnimationStyle, palette: [Color], fallbackTint: Color) -> [OrbSpec] {
            var generator = SeededGenerator(seed: seed)
            let colors = palette.isEmpty ? [fallbackTint] : palette
            let profile = profile(for: style)
            let count = profile.count

            return (0..<count).map { index in
                let color = colors[index % colors.count]
                return OrbSpec(
                    id: index,
                    color: color,
                    opacity: generator.next(in: profile.opacity),
                    sizeScale: generator.next(in: profile.sizeScale),
                    blurScale: generator.next(in: profile.blurScale),
                    anchorX: generator.next(in: profile.anchorX),
                    anchorY: generator.next(in: profile.anchorY),
                    travelX: generator.next(in: profile.travelX),
                    travelY: generator.next(in: profile.travelY),
                    duration: generator.next(in: profile.duration),
                    delay: generator.next(in: profile.delay)
                )
            }
        }

        private static func profile(for style: CardAnimationStyle) -> (
            count: Int,
            opacity: ClosedRange<Double>,
            sizeScale: ClosedRange<CGFloat>,
            blurScale: ClosedRange<CGFloat>,
            anchorX: ClosedRange<CGFloat>,
            anchorY: ClosedRange<CGFloat>,
            travelX: ClosedRange<CGFloat>,
            travelY: ClosedRange<CGFloat>,
            duration: ClosedRange<Double>,
            delay: ClosedRange<Double>
        ) {
            switch style {
            case .aurora:
                return (
                    count: 6,
                    opacity: 0.14...0.28,
                    sizeScale: 0.24...0.56,
                    blurScale: 0.08...0.14,
                    anchorX: -0.10...1.10,
                    anchorY: -0.05...1.10,
                    travelX: -0.12...0.12,
                    travelY: -0.10...0.10,
                    duration: 7.0...10.5,
                    delay: 0.0...2.0
                )
            case .ribbon:
                return (
                    count: 8,
                    opacity: 0.10...0.22,
                    sizeScale: 0.18...0.38,
                    blurScale: 0.05...0.10,
                    anchorX: -0.04...1.04,
                    anchorY: -0.10...1.12,
                    travelX: -0.06...0.06,
                    travelY: -0.22...0.22,
                    duration: 5.6...8.8,
                    delay: 0.0...1.6
                )
            case .bloom:
                return (
                    count: 4,
                    opacity: 0.18...0.32,
                    sizeScale: 0.42...0.82,
                    blurScale: 0.10...0.18,
                    anchorX: -0.22...1.18,
                    anchorY: -0.18...1.18,
                    travelX: -0.18...0.18,
                    travelY: -0.14...0.14,
                    duration: 8.2...12.2,
                    delay: 0.0...2.8
                )
            case .ember:
                return (
                    count: 7,
                    opacity: 0.16...0.30,
                    sizeScale: 0.20...0.46,
                    blurScale: 0.06...0.12,
                    anchorX: -0.08...1.08,
                    anchorY: 0.42...1.16,
                    travelX: -0.10...0.10,
                    travelY: -0.28...(-0.06),
                    duration: 4.8...7.6,
                    delay: 0.0...1.5
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
    let seed: String
    let style: CardAnimationStyle
    let palette: [Color]
    let primaryTint: Color

    @State private var animate = false

    private var flowSpec: FlowSpec {
        FlowSpec.make(seed: seed)
    }

    private var brightColor: Color {
        palette.first ?? primaryTint
    }

    private var deepColor: Color {
        palette.last ?? primaryTint
    }

    var body: some View {
        GeometryReader { proxy in
            flowBody(in: proxy)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !PreviewExecutionContext.isActive else { return }
            guard !animate else { return }
            animate = true
        }
    }

    @ViewBuilder
    private func flowBody(in proxy: GeometryProxy) -> some View {
        switch style {
        case .aurora:
            ZStack {
                flowEllipse(
                    colors: [brightColor.opacity(1.0), brightColor.opacity(0.72), .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                    width: proxy.size.width * flowSpec.firstWidthScale,
                    height: proxy.size.height * flowSpec.firstHeightScale,
                    blur: flowSpec.firstBlur,
                    startRotation: flowSpec.firstStartRotation,
                    endRotation: flowSpec.firstEndRotation,
                    startX: proxy.size.width * flowSpec.firstStartX,
                    endX: proxy.size.width * flowSpec.firstEndX,
                    startY: proxy.size.height * flowSpec.firstStartY,
                    endY: proxy.size.height * flowSpec.firstEndY,
                    duration: flowSpec.firstDuration,
                    delay: flowSpec.firstDelay
                )

                flowEllipse(
                    colors: [deepColor.opacity(0.24), brightColor.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom,
                    width: proxy.size.width * flowSpec.secondWidthScale,
                    height: proxy.size.height * flowSpec.secondHeightScale,
                    blur: flowSpec.secondBlur,
                    startRotation: flowSpec.secondStartRotation,
                    endRotation: flowSpec.secondEndRotation,
                    startX: proxy.size.width * flowSpec.secondStartX,
                    endX: proxy.size.width * flowSpec.secondEndX,
                    startY: proxy.size.height * flowSpec.secondStartY,
                    endY: proxy.size.height * flowSpec.secondEndY,
                    duration: flowSpec.secondDuration,
                    delay: flowSpec.secondDelay
                )
            }

        case .ribbon:
            ZStack {
                flowEllipse(
                    colors: [brightColor.opacity(0.92), brightColor.opacity(0.52), .clear],
                    startPoint: .top,
                    endPoint: .bottom,
                    width: proxy.size.width * 0.42,
                    height: proxy.size.height * 1.26,
                    blur: 18,
                    startRotation: -8,
                    endRotation: 14,
                    startX: proxy.size.width * 0.18,
                    endX: proxy.size.width * 0.36,
                    startY: -proxy.size.height * 0.08,
                    endY: proxy.size.height * 0.10,
                    duration: flowSpec.firstDuration * 0.92,
                    delay: flowSpec.firstDelay * 0.5
                )

                flowEllipse(
                    colors: [deepColor.opacity(0.22), brightColor.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                    width: proxy.size.width * 1.10,
                    height: proxy.size.height * 0.34,
                    blur: 20,
                    startRotation: -22,
                    endRotation: 18,
                    startX: -proxy.size.width * 0.14,
                    endX: proxy.size.width * 0.18,
                    startY: proxy.size.height * 0.18,
                    endY: -proxy.size.height * 0.06,
                    duration: flowSpec.secondDuration * 0.84,
                    delay: flowSpec.secondDelay * 0.45
                )
            }

        case .bloom:
            ZStack {
                flowEllipse(
                    colors: [brightColor.opacity(0.98), brightColor.opacity(0.52), .clear],
                    startPoint: .center,
                    endPoint: .trailing,
                    width: proxy.size.width * 0.86,
                    height: proxy.size.width * 0.86,
                    blur: 24,
                    startRotation: -10,
                    endRotation: 12,
                    startX: -proxy.size.width * 0.12,
                    endX: proxy.size.width * 0.08,
                    startY: -proxy.size.height * 0.04,
                    endY: proxy.size.height * 0.10,
                    duration: flowSpec.firstDuration * 1.06,
                    delay: flowSpec.firstDelay
                )

                flowEllipse(
                    colors: [deepColor.opacity(0.34), brightColor.opacity(0.20), .clear],
                    startPoint: .center,
                    endPoint: .bottomTrailing,
                    width: proxy.size.width * 0.72,
                    height: proxy.size.width * 0.72,
                    blur: 28,
                    startRotation: 14,
                    endRotation: -16,
                    startX: proxy.size.width * 0.16,
                    endX: -proxy.size.width * 0.06,
                    startY: proxy.size.height * 0.10,
                    endY: -proxy.size.height * 0.08,
                    duration: flowSpec.secondDuration * 1.08,
                    delay: flowSpec.secondDelay
                )
            }

        case .ember:
            ZStack {
                flowEllipse(
                    colors: [brightColor.opacity(0.78), brightColor.opacity(0.30), .clear],
                    startPoint: .bottom,
                    endPoint: .top,
                    width: proxy.size.width * 0.62,
                    height: proxy.size.height * 1.20,
                    blur: 20,
                    startRotation: 6,
                    endRotation: -8,
                    startX: proxy.size.width * 0.04,
                    endX: -proxy.size.width * 0.02,
                    startY: proxy.size.height * 0.28,
                    endY: -proxy.size.height * 0.02,
                    duration: flowSpec.firstDuration * 0.74,
                    delay: flowSpec.firstDelay * 0.35
                )

                flowEllipse(
                    colors: [deepColor.opacity(0.26), brightColor.opacity(0.14), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                    width: proxy.size.width * 0.36,
                    height: proxy.size.height * 1.04,
                    blur: 18,
                    startRotation: -18,
                    endRotation: 22,
                    startX: proxy.size.width * 0.30,
                    endX: -proxy.size.width * 0.18,
                    startY: proxy.size.height * 0.18,
                    endY: -proxy.size.height * 0.18,
                    duration: flowSpec.secondDuration * 0.72,
                    delay: flowSpec.secondDelay * 0.4
                )
            }
        }
    }

    private func flowEllipse(
        colors: [Color],
        startPoint: UnitPoint,
        endPoint: UnitPoint,
        width: CGFloat,
        height: CGFloat,
        blur: CGFloat,
        startRotation: Double,
        endRotation: Double,
        startX: CGFloat,
        endX: CGFloat,
        startY: CGFloat,
        endY: CGFloat,
        duration: Double,
        delay: Double
    ) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur)
            .rotationEffect(.degrees(animate ? endRotation : startRotation))
            .offset(
                x: animate ? endX : startX,
                y: animate ? endY : startY
            )
            .animation(
                .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animate
            )
    }

    private struct FlowSpec {
        let firstDuration: Double
        let secondDuration: Double
        let firstDelay: Double
        let secondDelay: Double
        let firstWidthScale: CGFloat
        let firstHeightScale: CGFloat
        let firstBlur: CGFloat
        let firstStartRotation: Double
        let firstEndRotation: Double
        let firstStartX: CGFloat
        let firstEndX: CGFloat
        let firstStartY: CGFloat
        let firstEndY: CGFloat
        let secondWidthScale: CGFloat
        let secondHeightScale: CGFloat
        let secondBlur: CGFloat
        let secondStartRotation: Double
        let secondEndRotation: Double
        let secondStartX: CGFloat
        let secondEndX: CGFloat
        let secondStartY: CGFloat
        let secondEndY: CGFloat

        static func make(seed: String) -> FlowSpec {
            var generator = SeededGenerator(seed: seed)
            return FlowSpec(
                firstDuration: generator.next(in: 7.6...9.4),
                secondDuration: generator.next(in: 9.2...11.8),
                firstDelay: generator.next(in: 0.0...1.8),
                secondDelay: generator.next(in: 0.3...2.4),
                firstWidthScale: generator.next(in: 0.80...1.06),
                firstHeightScale: generator.next(in: 0.54...0.78),
                firstBlur: generator.next(in: 14...24),
                firstStartRotation: generator.next(in: -26...(-8)),
                firstEndRotation: generator.next(in: 10...24),
                firstStartX: generator.next(in: -0.32...(-0.12)),
                firstEndX: generator.next(in: 0.14...0.34),
                firstStartY: generator.next(in: -0.16...0.16),
                firstEndY: generator.next(in: -0.16...0.16),
                secondWidthScale: generator.next(in: 0.72...0.98),
                secondHeightScale: generator.next(in: 0.68...0.94),
                secondBlur: generator.next(in: 18...30),
                secondStartRotation: generator.next(in: -22...(-6)),
                secondEndRotation: generator.next(in: 6...20),
                secondStartX: generator.next(in: -0.28...0.20),
                secondEndX: generator.next(in: -0.20...0.28),
                secondStartY: generator.next(in: -0.18...0.16),
                secondEndY: generator.next(in: -0.16...0.18)
            )
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

private struct VolumeCardsPreviewHost: View {
    @StateObject private var diskMonitor: DiskMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var importer: MediaImporter

    private let previewWidth: CGFloat = 360
    private let previewHeight: CGFloat = 1080

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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                ForEach(diskMonitor.removableVolumes) { volume in
                    VolumeCard(volume: volume)
                }
            }
            .padding(.vertical, 8)
        }
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
    private static let previewVolumes = [
        MountedVolume(
            id: "preview-volume-green",
            name: "SONY_CARD",
            url: URL(fileURLWithPath: "/Volumes/SONY_CARD", isDirectory: true),
            formatDescription: "exFAT",
            totalCapacity: 256_000_000_000,
            availableCapacity: 143_500_000_000
        ),
        MountedVolume(
            id: "preview-volume-orange",
            name: "Trae CN",
            url: URL(fileURLWithPath: "/Volumes/Trae CN", isDirectory: true),
            formatDescription: "Mac OS Extended",
            totalCapacity: 1_050_000_000,
            availableCapacity: 251_300_000
        ),
        MountedVolume(
            id: "preview-volume-red",
            name: "BACKUP_X",
            url: URL(fileURLWithPath: "/Volumes/BACKUP_X", isDirectory: true),
            formatDescription: "exFAT",
            totalCapacity: 64_000_000_000,
            availableCapacity: 4_700_000_000
        ),
    ]

    private static let previewMediaSummaries: [String: VolumeMediaSummary] = [
        "preview-volume-green": VolumeMediaSummary(photoCount: 250, videoCount: 18),
        "preview-volume-orange": VolumeMediaSummary(photoCount: 0, videoCount: 0),
        "preview-volume-red": VolumeMediaSummary(photoCount: 42, videoCount: 6),
    ]

    static var previews: some View {
        Group {
            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(previewVolumes: []),
                settings: AppSettings(previewDestinationFolderPath: "", autoImportEnabled: false),
                importer: MediaImporter()
            )
            .previewDisplayName("Empty State")

            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(
                    previewVolumes: [previewVolumes[0]],
                    previewMediaSummaries: previewMediaSummaries
                ),
                settings: AppSettings(
                    previewDestinationFolderPath: "/Users/kang/Pictures/Media Imports",
                    autoImportEnabled: true
                ),
                importer: MediaImporter()
            )
            .previewDisplayName("Ready To Import")

            MenuContentPreviewHost(
                diskMonitor: DiskMonitor(
                    previewVolumes: previewVolumes,
                    previewMediaSummaries: previewMediaSummaries
                ),
                settings: AppSettings(
                    previewDestinationFolderPath: "/Users/kang/Pictures/Media Imports",
                    autoImportEnabled: false
                ),
                importer: MediaImporter(
                    previewIsImporting: true,
                    previewMessage: "正在导入 SONY_CARD...",
                    previewProgress: 0.46,
                    previewCurrentImportVolumeID: previewVolumes[0].id,
                    previewImportedBytes: 18_500_000_000,
                    previewTotalImportBytes: 40_200_000_000,
                    previewImportedPhotoCount: 23,
                    previewTotalPhotoCount: 250,
                    previewImportedVideoCount: 5,
                    previewTotalVideoCount: 18
                )
            )
            .previewDisplayName("Importing")

            VolumeCardsPreviewHost(
                diskMonitor: DiskMonitor(
                    previewVolumes: previewVolumes,
                    previewMediaSummaries: previewMediaSummaries
                ),
                settings: AppSettings(
                    previewDestinationFolderPath: "/Users/kang/Pictures/Media Imports",
                    autoImportEnabled: true
                ),
                importer: MediaImporter()
            )
            .previewDisplayName("Volume Variants")
        }
    }
}
#endif
