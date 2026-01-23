import SwiftUI
import SwiftData

/// AI 操作类型
enum AIAction {
    case explain
    case summarize
    case translate

    var title: String {
        switch self {
        case .explain:
            return "解释内容"
        case .summarize:
            return "总结内容"
        case .translate:
            return "翻译内容"
        }
    }

    var placeholder: String {
        switch self {
        case .explain:
            return "请解释这段内容："
        case .summarize:
            return "请总结这段内容："
        case .translate:
            return "请将这段内容翻译成中文："
        }
    }
}

/// 阅读器容器 - 根据书籍类型切换阅读器
struct ReaderContainer: View {
    @Environment(\.modelContext) private var modelContext
    let book: BookItem
    @Binding var isPresented: Bool
    @State private var selectedText: String = ""
    @State private var selectedRect: CGRect = .zero
    @State private var currentPageIndex: Int = 0
    @State private var isLoading: Bool = true
    @State private var showAIInputAlert: Bool = false
    @State private var currentAIAction: AIAction = .explain
    @State private var quickChatPanel: QuickChatPanel?
    @State private var isSidebarVisible: Bool = true

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("正在加载书籍...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // 左侧：阅读器
                    Group {
                            // 传递 AI 对话历史
                            let _ = print("DEBUG: Passing \(book.aiChats.count) chats to reader for book: \(book.title)")
                            
                            if book.fileType == "pdf" {
                                PDFReaderView(
                                    book: book,
                                    selectedText: $selectedText,
                                    selectedRect: $selectedRect,
                                    currentPageIndex: $currentPageIndex,
                                    onSendToAI: { prompt in
                                        sendAIRequest(prompt: prompt)
                                    }
                                )
                            .onChange(of: currentPageIndex) { newValue in
                                // 保存阅读进度
                                book.lastReadPage = newValue
                                book.lastOpenedAt = Date()
                            }
                        } else if book.fileType == "epub" {
                            EPUBReaderView(
                                book: book,
                                selectedText: $selectedText,
                                selectedRect: $selectedRect,
                                onSendToAI: { prompt in
                                    sendAIRequest(prompt: prompt)
                                }
                            )
                        } else {
                            Text("不支持的文件类型")
                                .font(.title)
                        }
                    }
                    .frame(minWidth: 600, idealWidth: 900)

                    // 右侧：AI 面板
                    if isSidebarVisible {
                        AISidePanel(book: book, selectedText: $selectedText)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                            .transition(.move(edge: .trailing))
                    }
                }
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 12) {
                        // 返回按钮 (Icon only)
                        Button(action: { isPresented = false }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("返回书库 (⌘[)")

                        // 目录按钮 (Icon only)
                        Button(action: {
                             NotificationCenter.default.post(name: NSNotification.Name("ToggleTOCNotification"), object: nil)
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("显示目录")
                    }
                    .padding(20)
                }
                .overlay(alignment: .topTrailing) {
                    // 侧边栏切换按钮
                    Button(action: {
                        withAnimation {
                            isSidebarVisible.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 14))
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help(isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
                    .padding(16)
                }
            }
        }
        .onAppear {
            loadBook()
            setupNotificationObservers()
        }
        .onDisappear {
            removeNotificationObservers()
            // 退出时保存
            try? modelContext.save()
        }
        .alert(currentAIAction.title, isPresented: $showAIInputAlert) {
            Button("取消") { }
            Button("发送") {
                sendAIRequest()
            }
        } message: {
            Text("选中的文本：\"\(selectedText.prefix(100))\(selectedText.count > 100 ? "..." : "")\"")
        }
    }

    private func loadBook() {
        if let lastPage = book.lastReadPage {
            currentPageIndex = lastPage
        }
        isLoading = false
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // 监听快捷聊天框显示通知
        NotificationCenter.default.addObserver(
            forName: .init("ShowQuickChatNotification"),
            object: nil,
            queue: .main
        ) { [self] notification in
            handleShowQuickChat(notification: notification)
        }
    }

    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: .init("ShowQuickChatNotification"), object: nil)
    }

    private func handleShowQuickChat(notification: Notification) {
        // 防止重复创建弹窗
        guard QuickChatPanel.current == nil else {
            return
        }

        guard let userInfo = notification.userInfo,
              let text = userInfo["text"] as? String,
              let positionValue = userInfo["position"] as? NSValue,
              let coordinator = userInfo["coordinator"] as? BridgeCoordinator else {
            return
        }

        let position = positionValue.pointValue

        // 显示快捷聊天框
        QuickChatPanel.current = QuickChatPopover.show(
            selectedText: text,
            at: position,
            onSend: { [self] prompt in
                // 发送到 AI 侧边栏
                sendAIRequest(prompt: prompt)
                // 关闭面板
                QuickChatPanel.current?.safeClose()
                // 清除文本选择
                coordinator.clearSelection()
            },
            onCancel: {
                // 关闭面板
                QuickChatPanel.current?.safeClose()
                // 清除文本选择
                coordinator.clearSelection()
            }
        )
    }

    // MARK: - AI Actions

    private func explainSelection() {
        currentAIAction = .explain
        showAIInputAlert = true
    }

    private func summarizeSelection() {
        currentAIAction = .summarize
        showAIInputAlert = true
    }

    private func translateSelection() {
        currentAIAction = .translate
        showAIInputAlert = true
    }

    private func sendAIRequest() {
        // 直接发送通知到 AISidePanel
        let fullPrompt = currentAIAction.placeholder + selectedText
        sendAIRequest(prompt: fullPrompt)

        // 关闭弹窗
        showAIInputAlert = false
    }

    private func sendAIRequest(prompt: String) {
        // 直接发送通知到 AISidePanel
        NotificationCenter.default.post(
            name: .init("AIRequestNotification"),
            object: prompt,
            userInfo: ["selectedText": selectedText]
        )
    }
}

// MARK: - PDF Reader View

struct PDFReaderView: View {
    let book: BookItem
    @Binding var selectedText: String
    @Binding var selectedRect: CGRect
    @Binding var currentPageIndex: Int
    var onSendToAI: ((String) -> Void)?

    var body: some View {
        Group {
            if let url = book.bookmarkURL {
                PDFKitView(
                    url: url,
                    selectedText: $selectedText,
                    selectedRect: $selectedRect,
                    currentPageIndex: $currentPageIndex,
                    aiChats: book.aiChats,
                    onSelectionChanged: { text, rect, pageIndex in
                        // 选中文本变化时的处理（可选）
                    },
                    onAISend: { prompt in
                        // 发送 AI 请求
                        onSendToAI?(prompt)
                    }
                )
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.orange)
                    Text("无法打开文件")
                        .font(.headline)
                    Text("文件可能已被移动或删除")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - EPUB Reader View

struct EPUBReaderView: View {
    @Environment(\.modelContext) private var modelContext
    let book: BookItem
    @StateObject private var coordinator = BridgeCoordinator()
    @State private var contentURL: URL?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @Binding var selectedText: String
    @Binding var selectedRect: CGRect
    var onSendToAI: ((String) -> Void)?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在解压 EPUB...")
            } else if let url = contentURL {
                ZStack {
                    EpubWebView(contentURL: url, coordinator: coordinator)
                }
                .onReceive(coordinator.$currentSelection) { selection in
                    selectedText = selection.text
                    selectedRect = selection.rect
                }
                .onReceive(coordinator.$showHUD) { show in
                    // 可以在这里处理 HUD 显示状态
                }
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.orange)
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            await loadEPUB()
            setupCallbacks()
        }
        .onChange(of: book.aiChats) {
            Task {
                await updateChatHistoryHighlights()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleTOCNotification"))) { _ in
            coordinator.toggleTOC()
        }
    }

    private func loadEPUB() async {
        guard let url = book.bookmarkURL else {
            errorMessage = "无法访问文件"
            isLoading = false
            return
        }

        do {
            // Critical: Copy to temp to ensure subprocess access
            let accessing = url.startAccessingSecurityScopedResource()
            var tempSourceURL: URL?
            
            if accessing {
                // Create a temporary copy that the app definitely owns
                let tempFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                try? FileManager.default.removeItem(at: tempFile)
                try FileManager.default.copyItem(at: url, to: tempFile)
                tempSourceURL = tempFile
                
                url.stopAccessingSecurityScopedResource()
            } else {
                 throw NSError(domain: "com.aireader", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问源文件"])
            }
            
            guard let sourceURL = tempSourceURL else {
                 throw NSError(domain: "com.aireader", code: -1, userInfo: [NSLocalizedDescriptionKey: "文件复制失败"])
            }
            
            defer {
                try? FileManager.default.removeItem(at: sourceURL)
            }

            let htmlURL = try await EPUBLoader.loadEPUB(from: sourceURL)
            contentURL = htmlURL
            isLoading = false
            
            // 加载聊天历史
            Task {
                // 延迟一点等待页面 JS 注入完成
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await updateChatHistoryHighlights()
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func setupCallbacks() {
        // 设置快捷聊天框回调 - 直接显示弹窗
        coordinator.onShowQuickChat = { [weak coordinator] text, position in
            guard let coordinator = coordinator else { return }

            // 防止重复创建弹窗
            guard QuickChatPanel.current == nil else { return }

            print("显示快捷聊天框: \(text.prefix(20))... at \(position)")

            // 直接显示快捷聊天框
            QuickChatPanel.current = QuickChatPopover.show(
                selectedText: text,
                at: position,
                onSend: { prompt in
                    // 发送到 AI 侧边栏
                    NotificationCenter.default.post(
                        name: .init("AIRequestNotification"),
                        object: prompt,
                        userInfo: ["selectedText": text]
                    )
                    // 关闭面板
                    QuickChatPanel.current?.safeClose()
                    // 清除文本选择
                    coordinator.clearSelection()
                },
                onCancel: {
                    // 关闭面板
                    QuickChatPanel.current?.safeClose()
                    // 清除文本选择
                    coordinator.clearSelection()
                }
            )
        }

        // 设置滚动位置回调
        coordinator.onScrollPositionChanged = { [book] href in
            // 保存阅读进度
            // 使用 Task 避免在非 UI 线程更新
            Task { @MainActor in
                book.lastReadLocation = href
                book.lastOpenedAt = Date()
            }
        }
        
        // 设置删除聊天记录回调
        let deleteContext: ModelContext = modelContext  // Explicit type to avoid ViewBuilder inference
        coordinator.onDeleteChat = { [book] chatIdString in
            Task { @MainActor in
                guard let chatId = UUID(uuidString: chatIdString) else {
                    print("ERROR: Invalid chat ID format: \(chatIdString)")
                    return
                }
                
                // Find and delete the chat
                if let chatToDelete = book.aiChats.first(where: { $0.id == chatId }) {
                    deleteContext.delete(chatToDelete)
                    try? deleteContext.save()
                    print("DEBUG: Deleted chat \(chatIdString)")
                    
                    // Refresh timeline by posting notification
                    NotificationCenter.default.post(name: .init("AIChatCompletedNotification"), object: nil)
                } else {
                    print("ERROR: Chat not found: \(chatIdString)")
                }
            }
        }

        // 监听 AI 聊天完成通知，更新 Timeline 高亮
        NotificationCenter.default.addObserver(
            forName: .init("AIChatCompletedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            print("DEBUG: Received AIChatCompletedNotification, updating highlights...")
            Task { @MainActor in
                await updateChatHistoryHighlights()
            }
        }

        // 恢复上次阅读位置
        if let lastLocation = book.lastReadLocation {
            Task {
                // 延迟一点等待页面完全加载
                try? await Task.sleep(nanoseconds: 500 * 1_000_000)
                await coordinator.navigateTo(href: lastLocation)
            }
        }
    }

    private func updateChatHistoryHighlights() async {
        print("DEBUG: updateChatHistoryHighlights called, \(book.aiChats.count) chats")
        let chatData = book.aiChats.map { chat in
            print("DEBUG: Chat - actionType: \(chat.actionType ?? "nil"), paragraphId: \(chat.annotationCfi ?? "nil")")
            return ChatContextData(
                id: chat.id.uuidString,
                text: chat.relatedText,
                prompt: chat.prompt,
                response: chat.response,
                actionType: chat.actionType ?? "chat", // explain, summarize, translate
                createdAt: chat.createdAt,
                paragraphId: chat.annotationCfi  // 传递段落 ID
            )
        }

        if let firstChat = chatData.first {
             DebugLogger.log("DEBUG: First chat text sample: \(firstChat.text.prefix(50))...")
        }
        DebugLogger.log("DEBUG: Calling coordinator.highlightChatHistory with \(chatData.count) chats")
        await coordinator.highlightChatHistory(chats: chatData)
        DebugLogger.log("DEBUG: coordinator.highlightChatHistory completed")
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookItem.self, configurations: config)

    let sampleBook = BookItem(
        title: "示例书籍",
        author: "作者",
        bookmarkData: Data(),
        fileType: "pdf",
        filePath: "/path/to/book.pdf"
    )

    container.mainContext.insert(sampleBook)

    return ReaderContainer(book: sampleBook, isPresented: .constant(true))
        .modelContainer(container)
}
