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
    @StateObject private var folderClassificationWindowController = FolderClassificationWindowController()

    private var visibleStatusMessage: String? {
        guard importer.isImporting || importer.lastResultMessage != "等待导入" else {
            return nil
        }

        return importer.lastResultMessage
    }

    private var destinationPanelFill: Color {
        Color(red: 0.40, green: 0.40, blue: 0.42).opacity(0.26)
    }

    private var bottomBackdrop: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.00),
                        Color.black.opacity(0.01),
                        Color.black.opacity(0.03),
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.15),
                        Color.black.opacity(0.24),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: visibleStatusMessage == nil ? 245 : 280)
            .blur(radius: 32)
            .mask(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.04),
                        .white.opacity(0.14),
                        .white.opacity(0.34),
                        .white.opacity(0.68),
                        .white,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .offset(y: visibleStatusMessage == nil ? 38 : 48)
            .allowsHitTesting(false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            destinationSection
            deviceSection
            bottomSection
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.2), value: visibleStatusMessage)
    }

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let visibleStatusMessage {
                StatusBanner(message: visibleStatusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            footerSection
        }
        .background(alignment: .bottom) {
            bottomBackdrop
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
                            Text("未选择目标文件夹")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))

                            Text("可在右下角设置中指定本地目录")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.72))
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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        settings.autoImportEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: settings.autoImportEnabled ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(settings.autoImportEnabled ? .blue : .white.opacity(0.72))

                        Text(settings.autoImportEnabled ? "自动导入已开启" : "目前未自动导入")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(destinationPanelFill, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(destinationPanelFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
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
                        .foregroundStyle(settings.autoImportEnabled ? .blue : .secondary)
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
    @State private var feedbackMessage: String?
    @State private var isCreatingFolders = false

    let onDone: () -> Void

    private var matchedRuleForTest: FolderClassificationRule? {
        guard !testFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return settings.testRuleMatch(for: testFolderName)
    }

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
                    Text("文件夹分类规则")
                        .font(.title3.bold())
                    Text("按列表顺序匹配原始文件夹名称；命中规则后，对应文件夹中的视频会自动进入指定目标文件夹。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configurationSection
                    ruleListSection
                    testSection
                    logsSection
                }
                .padding(.bottom, 4)
            }
        }
        .padding(20)
        .frame(width: 760, height: 720, alignment: .topLeading)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基础设置")
                .font(.headline)

            Toggle("启用文件夹分类规则", isOn: $settings.folderClassificationEnabled)

            Picker("同名文件处理", selection: $settings.folderConflictStrategy) {
                ForEach(FolderConflictStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.folderConflictStrategy.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前导入目标")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(settings.destinationFolderPath.isEmpty ? "还没有选择导入文件夹" : settings.destinationFolderPath)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                Button("选择目标文件夹") {
                    settings.chooseDestinationFolderForClassification()
                }
                .buttonStyle(.bordered)

                Button("预创建分类文件夹") {
                    createClassificationFolders()
                }
                .buttonStyle(.bordered)
                .disabled(isCreatingFolders || settings.destinationFolderPath.isEmpty)

                Spacer()

                Button("导入规则") {
                    importRules()
                }
                .buttonStyle(.bordered)

                Button("导出规则") {
                    exportRules()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ruleListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("规则列表")
                        .font(.headline)
                    Text("优先级从上到下；当多个规则同时命中时，系统只采用最前面的那一条。")
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
            }

            if settings.folderClassificationRules.isEmpty {
                Text("还没有规则。新增后即可按原始文件夹名称自动把视频归到指定子文件夹。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("规则测试")
                .font(.headline)

            TextField("输入原始文件夹名称，例如 POK_001", text: $testFolderName)
                .textFieldStyle(.roundedBorder)

            Group {
                if testFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入一个文件夹名称，系统会按当前规则顺序模拟匹配结果。")
                        .foregroundStyle(.secondary)
                } else if let matchedRuleForTest {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("命中规则：\(matchedRuleForTest.keyword)")
                        Text("目标文件夹：\(matchedRuleForTest.normalizedTargetFolderPath)")
                    }
                } else {
                    Text("没有命中任何规则，将按默认导入逻辑进入设备名/时间戳目录。")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作日志")
                        .font(.headline)
                    Text("记录自动分类匹配到的文件以及默认导入结果，最新记录会显示在最上面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("清空日志") {
                    settings.clearClassificationLogs()
                }
                .buttonStyle(.bordered)
                .disabled(settings.classificationLogs.isEmpty)
            }

            if settings.classificationLogs.isEmpty {
                Text("还没有自动分类日志。下一次导入命中规则后，这里会显示详细记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(settings.classificationLogs.prefix(14)) { entry in
                        FolderClassificationLogRow(entry: entry, formatter: Self.logDateFormatter)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func createClassificationFolders() {
        isCreatingFolders = true
        Task {
            defer { isCreatingFolders = false }

            do {
                let createdCount = try await settings.createClassificationFolders()
                feedbackMessage = createdCount == 0 ? "当前没有可创建的启用规则文件夹。" : "已创建 \(createdCount) 个分类文件夹。"
            } catch {
                feedbackMessage = error.localizedDescription
            }
        }
    }

    private func importRules() {
        do {
            if let importedCount = try settings.importFolderClassificationRules() {
                feedbackMessage = "已导入 \(importedCount) 条规则。"
            }
        } catch {
            feedbackMessage = "导入规则失败：\(error.localizedDescription)"
        }
    }

    private func exportRules() {
        do {
            if let exportURL = try settings.exportFolderClassificationRules() {
                feedbackMessage = "规则已导出到 \(exportURL.lastPathComponent)。"
            }
        } catch {
            feedbackMessage = "导出规则失败：\(error.localizedDescription)"
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("启用", isOn: $rule.isEnabled)
                    .toggleStyle(.switch)

                Text("优先级 \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveUp)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveDown)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("关键词")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如 pok", text: $rule.keyword)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("目标文件夹")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如 pocket/final", text: $rule.targetFolderName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(rule.isConfigured ? "将匹配包含“\(rule.keyword)”的原始文件夹名，命中后目标目录为 \(rule.normalizedTargetFolderPath)" : "关键词和目标文件夹都填好后，这条规则才会参与匹配。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.40, green: 0.40, blue: 0.42).opacity(0.26))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    private var animationStyle: CardAnimationStyle {
        switch volume.usageFraction {
        case ..<0.5:
            return .aurora
        case ..<0.75:
            return .ribbon
        case ..<0.9:
            return .bloom
        default:
            return .ember
        }
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

    private var mediaSummary: VolumeMediaSummary? {
        diskMonitor.mediaSummaries[volume.id]
    }

    private var hasImportableMedia: Bool {
        guard let mediaSummary else { return true }
        return mediaSummary.photoCount > 0 || mediaSummary.videoCount > 0
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

    private var mediaSummaryText: String {
        guard let mediaSummary else {
            return "正在扫描照片和视频..."
        }

        return "共扫描到 \(mediaSummary.photoCount) 张照片，\(mediaSummary.videoCount) 个视频"
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
                        Image(systemName: "folder")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 22)

                    Button {
                        ejectVolume()
                    } label: {
                        Image(systemName: "eject")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
            withAnimation(capacityChipAnimation) {
                isHoveringCapacityChip = hovering
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
        .frame(minHeight: 84)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(volume.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    (
                        Text(verbatim: volume.formatDescription)
                        + Text(" 格式")
                        + Text(" · 已用 ")
                        + Text("\(usagePercent)%")
                    )
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .padding(.leading, 4)

                Spacer(minLength: 0)

                capacityChip
                    .padding(.top, 2)
            }

            capacityTilesRow

            if isCurrentVolumeImporting {
                importProgressSection
            } else {
                idleSection
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
    }

    private var idleSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("扫描结果")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))

                Text(mediaSummaryText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 30)

            Button(actionButtonTitle) {
                handlePrimaryAction()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isPrimaryActionDisabled ? .white.opacity(0.62) : .white.opacity(0.96))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPrimaryActionDisabled ? Color.gray.opacity(0.34) : Color.black.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isPrimaryActionDisabled ? Color.white.opacity(0.06) : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
        .padding(.top, -33)
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

                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        Text(importer.importRemainingTimeText ?? "--:--")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                    }
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
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
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
        .padding(.top, -24)
    }

    private func handlePrimaryAction() {
        guard !settings.destinationFolderPath.isEmpty else {
            settings.chooseDestinationFolder()
            return
        }

        Task {
            do {
                _ = try await settings.withDestinationFolderAccess { destinationFolderURL in
                    await importer.importMedia(from: volume, to: destinationFolderURL, settings: settings)
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

private enum CardAnimationStyle {
    case aurora
    case ribbon
    case bloom
    case ember
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
