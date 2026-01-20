import SwiftUI

/// 快速聊天弹出框 - 显示在选中文本附近的简洁聊天界面
struct QuickChatPopover: View {

    // MARK: - 预设提示词配置

    /// 预设提示词项
    struct PresetPrompt: Identifiable, Equatable {
        let id = UUID()
        let title: String       // 按钮显示文本
        let template: String    // 提示词模板

        /// 构建完整提示词（附加选中文本）
        func buildPrompt(with selectedText: String) -> String {
            return template + "\n\n" + selectedText
        }
    }

    // MARK: - 属性

    /// 选中的文本
    let selectedText: String

    /// 屏幕坐标位置（弹出框显示位置）
    let position: CGPoint

    /// 发送回调 - 传入完整提示词
    let onSend: (String) -> Void

    /// 取消回调
    let onCancel: () -> Void

    /// 自定义预设提示词（可选）
    var customPresets: [PresetPrompt] = []

    // MARK: - 状态

    @State private var customPrompt: String = ""
    @State private var selectedPreset: PresetPrompt?
    @State private var isExpanded: Bool = false
    @FocusState private var isInputFocused: Bool

    // MARK: - 默认预设

    /// 默认预设提示词
    private var defaultPresets: [PresetPrompt] {
        [
            PresetPrompt(title: "解释", template: "请详细解释这段内容："),
            PresetPrompt(title: "总结", template: "请为这段内容写一个简洁的总结："),
            PresetPrompt(title: "翻译", template: "请将这段内容翻译成中文："),
            PresetPrompt(title: "分析", template: "请分析这段内容的要点："),
            PresetPrompt(title: "续写", template: "请根据这段内容进行续写："),
            PresetPrompt(title: "提问", template: "请根据这段内容提出3个深入的问题："),
        ]
    }

    /// 当前使用的预设列表
    private var presets: [PresetPrompt] {
        customPresets.isEmpty ? defaultPresets : customPresets
    }

    // MARK: - 初始化

    init(
        selectedText: String,
        position: CGPoint,
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        customPresets: [PresetPrompt] = []
    ) {
        self.selectedText = selectedText
        self.position = position
        self.onSend = onSend
        self.onCancel = onCancel
        self.customPresets = customPresets
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            headerView

            Divider()

            // 内容区域
            contentView

            Divider()

            // 底部按钮
            actionButtonsView
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - 头部视图

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 14))
                .foregroundColor(.blue)

            Text("快速对话")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 内容视图

    private var contentView: some View {
        VStack(spacing: 12) {
            // 选中文本预览
            selectedTextPreview

            // 预设提示词按钮
            presetButtonsView

            // 自定义输入区域
            if isExpanded {
                customInputView
            }
        }
        .padding(12)
    }

    // MARK: - 选中文本预览

    private var selectedTextPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("选中内容")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(selectedText.count) 字符")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(selectedText)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
        }
    }

    // MARK: - 预设按钮视图

    private var presetButtonsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷操作")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(presets.prefix(isExpanded ? 6 : 4)) { preset in
                    presetButton(for: preset)
                }
            }
        }
    }

    // MARK: - 预设按钮

    private func presetButton(for preset: PresetPrompt) -> some View {
        Button(action: {
            selectedPreset = preset
            handleSend(preset.buildPrompt(with: selectedText))
        }) {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: preset.title))
                    .font(.system(size: 10))

                Text(preset.title)
                    .font(.system(size: 12))

                Spacer(minLength: 0)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                selectedPreset?.id == preset.id
                    ? Color.blue.opacity(0.15)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        selectedPreset?.id == preset.id
                            ? Color.blue.opacity(0.5)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 自定义输入视图

    private var customInputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("自定义提示")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            CustomTextField(
                placeholder: "输入提示 (Enter发送, Shift+Enter换行)...",
                text: $customPrompt,
                isGenerating: false,
                onCommit: {
                    handleSend(customPrompt.isEmpty ? selectedText : customPrompt + "\n\n" + selectedText)
                }
            )
            .frame(minHeight: 60, maxHeight: 100)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 底部操作按钮

    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            // 取消按钮
            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // 展开/收起按钮
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if isExpanded {
                        isInputFocused = true
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                    Text(isExpanded ? "收起" : "更多")
                        .font(.system(size: 12))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // 发送按钮
            Button(action: {
                handleSend(customPrompt.isEmpty ? selectedText : customPrompt + "\n\n" + selectedText)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                    Text("发送")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    (customPrompt.isEmpty && selectedPreset == nil)
                        ? Color.gray
                        : Color.blue
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(customPrompt.isEmpty && selectedPreset == nil && !isExpanded)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - 辅助方法

    /// 处理发送
    private func handleSend(_ prompt: String) {
        onSend(prompt)
    }

    /// 根据预设类型返回图标
    private func iconName(for title: String) -> String {
        switch title {
        case "解释": return "lightbulb"
        case "总结": return "list.bullet"
        case "翻译": return "globe"
        case "分析": return "magnifyingglass"
        case "续写": return "pencil"
        case "提问": return "questionmark.circle"
        default: return "star"
        }
    }
}

// MARK: - NSPanel 包装器

/// NSPanel 包装器，用于在指定位置显示弹出框
class QuickChatPanel: NSPanel {
    static var current: QuickChatPanel?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignKeyObserver: NSObjectProtocol?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }

    init(contentView: NSView, position: CGPoint) {
        super.init(
            contentRect: .zero,
            styleMask: [.hudWindow, .nonactivatingPanel], // 使用 nonactivatingPanel 避免强制抢占主窗口状态，但在需要时可激活
            backing: .buffered,
            defer: false
        )

        self.contentViewController = NSViewController()
        self.contentViewController?.view = contentView

        // 面板配置
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = true // 当应用失去活跃状态时自动隐藏（这是标准行为）

        // 关键：允许面板成为 Key Window 接收键盘输入
        self.becomesKeyOnlyIfNeeded = false

        // 设置面板大小
        let panelSize = NSSize(width: 280, height: 300)

        // 获取屏幕信息
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        // 计算弹窗位置
        var x = position.x - panelSize.width / 2  // 水平居中
        var y = position.y - panelSize.height - 10  // 在 position 上方 10 像素

        // 确保在屏幕边界内
        if x < screenFrame.minX + 10 { x = screenFrame.minX + 10 }
        if x + panelSize.width > screenFrame.maxX - 10 { x = screenFrame.maxX - panelSize.width - 10 }
        if y < screenFrame.minY + 10 {
            // 如果上方空间不够，显示在下方
            y = position.y + 10
        }
        if y + panelSize.height > screenFrame.maxY - 10 { y = screenFrame.maxY - panelSize.height - 10 }

        self.setFrame(
            NSRect(origin: NSPoint(x: x, y: y), size: panelSize),
            display: true
        )

        setupAutoClose()
    }

    private func setupAutoClose() {
        print("QuickChatPanel: 启动自动关闭监听")

        // 1. 监听本地点击（应用内点击）
        // 关键改进：如果点击发生在面板外部，我们应该关闭面板，但必须返回事件
        // 这样用户点击其他地方（如选择文本）的操作才能生效
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            // 简单直接的判断：如果点击事件的窗口不是面板本身，那就是外部点击
            if event.window != self {
                print("QuickChatPanel: 检测到应用内外部点击，准备关闭")
                // 使用异步关闭以避免干扰当前的事件处理循环
                DispatchQueue.main.async {
                    self.safeClose()
                }
            }
            return event
        }

        // 2. 监听全局点击（应用外点击，如桌面或其他应用）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            print("QuickChatPanel: 检测到应用外点击")
            DispatchQueue.main.async {
                self?.safeClose()
            }
        }

        // 3. 监听失去焦点
        // 注意：hidesOnDeactivate = true 已经处理了切换到其他 App 的情况
        // 这里主要处理应用内焦点切换
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            // 只有当应用仍然活跃时才处理（避免与 hidesOnDeactivate 冲突）
            if NSApp.isActive {
                print("QuickChatPanel: 失去焦点")
                self?.safeClose()
            }
        }
    }

    override func close() {
        cleanUp()
        super.close()
        QuickChatPanel.current = nil
    }

    /// 安全关闭方法，可以从外部调用
    func safeClose() {
        cleanUp()
        QuickChatPanel.current = nil
        super.close()
    }

    private func cleanUp() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
    }
}

// MARK: - SwiftUI View 扩展

extension QuickChatPopover {
    /// 将弹出框转换为 NSView 并显示
    func showAsPanel() -> QuickChatPanel {
        let hostingView = NSHostingView(rootView: self)
        hostingView.frame.size = hostingView.fittingSize

        let panel = QuickChatPanel(contentView: hostingView, position: position)
        panel.makeKeyAndOrderFront(nil)

        // 激活面板以确保能接收键盘输入
        DispatchQueue.main.async {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return panel
    }
}

// MARK: - 快捷创建方法

extension QuickChatPopover {
    /// 快速创建并显示弹出框
    static func show(
        selectedText: String,
        at position: CGPoint,
        onSend: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {},
        customPresets: [PresetPrompt] = []
    ) -> QuickChatPanel {
        let popover = QuickChatPopover(
            selectedText: selectedText,
            position: position,
            onSend: onSend,
            onCancel: onCancel,
            customPresets: customPresets
        )
        return popover.showAsPanel()
    }
}

// MARK: - 预览

#Preview("Quick Chat Popover") {
    VStack(spacing: 20) {
        QuickChatPopover(
            selectedText: "Swift 是一种强大的编程语言，用于构建 iOS、macOS、watchOS 和 tvOS 应用。它由 Apple 开发，旨在安全、快速且富有表现力。",
            position: .zero,
            onSend: { prompt in
                print("发送提示词: \(prompt)")
            },
            onCancel: {
                print("取消")
            }
        )

        QuickChatPopover(
            selectedText: "人工智能是计算机科学的一个分支，致力于创造能够执行通常需要人类智能的任务的系统。",
            position: .zero,
            onSend: { _ in },
            onCancel: {}
        )
    }
    .padding()
    .frame(width: 400, height: 400)
}
