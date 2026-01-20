import SwiftUI
import SwiftData
import OSLog

/// AI 聊天消息
struct AIMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinkingContent: String?  // 思考过程
    var isThinkingExpanded: Bool  // 是否展开思考
    let timestamp: Date
    var isStreaming: Bool         // 是否正在流式接收

    enum MessageRole: String {
        case user
        case assistant
        case system
    }

    init(role: MessageRole, content: String, thinkingContent: String? = nil, isThinkingExpanded: Bool = false, timestamp: Date = Date(), isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.isThinkingExpanded = isThinkingExpanded
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

/// AI 侧边栏 - 显示 AI 聊天界面
struct AISidePanel: View {
    @Environment(\.modelContext) private var modelContext
    let book: BookItem
    @Binding var selectedText: String

    @State private var messages: [AIMessage] = []
    @State private var userInput: String = ""
    @State private var isGenerating: Bool = false
    @State private var showHistory: Bool = false
    @State private var pendingMessage: String?

    // 存储当前 AI 操作的上下文信息
    @State private var currentParagraphId: String?
    @State private var currentActionType: String?

    @Query private var chatHistory: [AIChat]

    // Custom Prompts
    @AppStorage("promptExplain") private var promptExplain: String = "请解释这段内容："
    @AppStorage("promptSummarize") private var promptSummarize: String = "请总结这段内容的要点："
    @AppStorage("promptTranslate") private var promptTranslate: String = "请将这段内容翻译成中文："
    @AppStorage("promptAnalyze") private var promptAnalyze: String = "请分析这段内容的修辞和深层含义："

    private let aiService = AIService()

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            header

            // 消息列表
            messageList

            // 输入区域
            inputArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIConfig")
            logger.info("[Config] AISidePanel: onAppear")
            loadChatHistory()
            configureAIService()
        }
        .onChange(of: book.id) { _, _ in
            loadChatHistory()
        }
        .onChange(of: pendingMessage) { _, newMessage in
            if let message = newMessage {
                userInput = message
                pendingMessage = nil
            }
        }
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(book: book)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DirectAIActionNotification"))) { notification in
            guard let userInfo = notification.userInfo,
                  let text = userInfo["text"] as? String,
                  let actionCode = userInfo["action"] as? String else { return }

            // 保存段落 ID 和 actionType，用于后续保存到数据库
            currentParagraphId = userInfo["paragraphId"] as? String
            currentActionType = actionCode
            print("DEBUG: DirectAIAction - action: \(actionCode), paragraphId: \(currentParagraphId ?? "nil")")
            
            let promptPrefix: String
            switch actionCode {
            case "explain": promptPrefix = UserDefaults.standard.string(forKey: "promptExplain") ?? "请解释这段内容："
            case "summarize": promptPrefix = UserDefaults.standard.string(forKey: "promptSummarize") ?? "请总结这段内容的要点："
            case "translate": promptPrefix = UserDefaults.standard.string(forKey: "promptTranslate") ?? "请将这段内容翻译成中文："
            case "analyze": promptPrefix = UserDefaults.standard.string(forKey: "promptAnalyze") ?? "请分析这段内容的修辞和深层含义："
            default: promptPrefix = "请分析这段内容："
            }
            
            // 直接触发发送逻辑
            Task {
                await sendMessage(promptPrefix, selectedText: text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AIRequestNotification"))) { notification in
            if let message = notification.object as? String {
                // 检查是否来自快捷聊天框（通过 userInfo 中的 selectedText 判断）
                if let userInfo = notification.userInfo,
                   let selectedText = userInfo["selectedText"] as? String,
                   !selectedText.isEmpty {
                    // 快捷聊天框发送：直接发送消息
                    Task {
                        await sendMessage(message, selectedText: selectedText)
                    }
                } else {
                    // 正常输入：放到输入框
                    pendingMessage = message
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AI 助手")
                .font(.headline)

            Spacer()

            Button(action: { showHistory = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .help("聊天历史")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages.indices, id: \.self) { index in
                            MessageBubble(message: $messages[index])
                                .id(messages[index].id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.secondary)

            Text("AI 阅读助手")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                SuggestionButton(icon: "lightbulb", title: "解释内容", prompt: promptExplain) { prompt in
                    userInput = prompt + (selectedText.isEmpty ? "" : "\n\n选中的文本：\(selectedText)")
                }
                SuggestionButton(icon: "list.bullet", title: "总结要点", prompt: promptSummarize) { prompt in
                    userInput = prompt + (selectedText.isEmpty ? "" : "\n\n选中的文本：\(selectedText)")
                }
                SuggestionButton(icon: "character.book.closed", title: "翻译", prompt: promptTranslate) { prompt in
                    userInput = prompt + (selectedText.isEmpty ? "" : "\n\n选中的文本：\(selectedText)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(.secondary)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            // 选中文本预览
            if !selectedText.isEmpty {
                SelectedTextPreview(text: selectedText)
                Divider()
            }

            HStack(alignment: .bottom, spacing: 8) {
                CustomTextField(
                    placeholder: "输入问题...",
                    text: $userInput,
                    isGenerating: isGenerating,
                    onCommit: {
                        Task { await sendMessage() }
                    }
                )
                .frame(maxWidth: .infinity)

                Button(action: { Task { await sendMessage() } }) {
                    Image(systemName: isGenerating ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions



    private func loadChatHistory() {
        // 从 SwiftData 加载历史聊天
        let bookId = book.id
        let descriptor = FetchDescriptor<AIChat>(
            predicate: #Predicate<AIChat> { chat in
                chat.book?.id == bookId
            }
        )

        if let history = try? modelContext.fetch(descriptor), !history.isEmpty {
            messages = history.map { chat in
                AIMessage(role: .user, content: chat.prompt, timestamp: chat.createdAt)
            } + history.map { chat in
                AIMessage(role: .assistant, content: chat.response, timestamp: chat.createdAt)
            }
        } else {
            messages = []
        }
    }

    private func configureAIService() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIConfig")
        logger.info("[Config] AISidePanel: configureAIService called")
        
        // 从 UserDefaults 加载配置
        // 注意：这里用 Task 异步配置，因为 configureAIService 是同步方法
        // 真正的配置会在 sendMessageInternal 中的 ensureAIConfigured 里完成
        Task {
            let activeProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
            logger.info("[Config] AISidePanel: Active provider: \(activeProvider)")
            
            switch activeProvider {
            case "openai":
                if let apiKey = UserDefaults.standard.string(forKey: "openaiAPIKey"), !apiKey.isEmpty {
                    let baseURL = UserDefaults.standard.string(forKey: "openAIBaseURL")
                    let modelName = UserDefaults.standard.string(forKey: "selectedModel") ?? "gpt-4o-mini"
                    logger.info("[Config] AISidePanel: Configuring OpenAI with API Key length: \(apiKey.count)")
                    await aiService.configure(provider: .openAI(apiKey: apiKey, baseURL: baseURL))
                    await aiService.setModel(modelName)
                } else {
                    logger.error("[Config] AISidePanel: OpenAI selected but API Key is missing or empty")
                }
            case "ollama":
                let baseURLString = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
                let modelName = UserDefaults.standard.string(forKey: "selectedModel") ?? "llama2"
                if let baseURL = URL(string: baseURLString) {
                    logger.info("[Config] AISidePanel: Configuring Ollama with BaseURL: \(baseURL)")
                    await aiService.configure(provider: .ollama(baseURL: baseURL))
                    await aiService.setModel(modelName)
                } else {
                    logger.error("[Config] AISidePanel: Ollama selected but BaseURL is invalid")
                }
            default:
                logger.error("[Config] AISidePanel: Unknown provider: \(activeProvider)")
            }
        }
    }

    /// 确保 AI 服务已配置（在发送消息前调用）
    private func ensureAIConfigured() async {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIConfig")
        
        // 直接同步配置
        // Direct configuration with fallback
        let activeProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai"
        logger.warning("[Config] ensureAIConfigured - activeProvider: \(activeProvider)")

        switch activeProvider {
        case "openai":
            let apiKey = UserDefaults.standard.string(forKey: "openaiAPIKey")
            logger.warning("[Config] ensureAIConfigured - OpenAI APIKey length: \(apiKey?.count ?? 0)")
            
            if let apiKey = apiKey, !apiKey.isEmpty {
                let baseURL = UserDefaults.standard.string(forKey: "openAIBaseURL")
                let modelName = UserDefaults.standard.string(forKey: "selectedModel") ?? "gpt-4o-mini"
                 await aiService.configure(provider: .openAI(apiKey: apiKey, baseURL: baseURL))
                 await aiService.setModel(modelName)
                 logger.info("[Config] AISidePanel: OpenAI configured")
            } else {
                 logger.error("[Config] OpenAI API Key is not configured.")
                 return
            }
        case "ollama":
             let baseURLString = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
             let modelName = UserDefaults.standard.string(forKey: "selectedModel") ?? "llama2"
             if let baseURL = URL(string: baseURLString) {
                 await aiService.configure(provider: .ollama(baseURL: baseURL))
                 await aiService.setModel(modelName)
             }
        default:
             logger.error("[Config] Unknown AI Provider.")
             return
        }
    }

    private func sendMessage() async {
        let prompt = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let context = selectedText.isEmpty ? prompt : "\(prompt)\n\n选中的文本：\(selectedText)"
        await sendMessageInternal(prompt: context, displayContent: prompt)
    }

    /// 快捷聊天框发送消息
    private func sendMessage(_ prompt: String, selectedText: String) async {
        let context = "\(prompt)\n\n选中的文本：\(selectedText)"
        await sendMessageInternal(prompt: context, displayContent: prompt)
    }

    private func sendMessageInternal(prompt: String, displayContent: String) async {
        // Capture context state AT START to prevent race conditions during async streaming
        let capturedParagraphId = self.currentParagraphId
        let capturedActionType = self.currentActionType

        // 确保服务已配置（快捷聊天框发送时可能还未配置）
        await ensureAIConfigured()

        // 添加用户消息
        let userMessage = AIMessage(role: .user, content: displayContent)
        messages.append(userMessage)
        isGenerating = true

        // 添加一个空的 AI 消息，用于流式更新
        let assistantMessage = AIMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        )
        messages.append(assistantMessage)
        let lastIndex = messages.count - 1

        do {
            // 使用流式 API
            let stream = await aiService.streamCompletion(prompt: prompt)

            for try await part in stream {
                switch part {
                case .thinking(let text):
                    // 更新思考内容
                    messages[lastIndex].thinkingContent = (messages[lastIndex].thinkingContent ?? "") + text
                    // 如果有思考内容，默认展开
                    if messages[lastIndex].isThinkingExpanded == false {
                        messages[lastIndex].isThinkingExpanded = true
                    }
                case .content(let text):
                    // 更新内容
                    messages[lastIndex].content += text
                case .done:
                    messages[lastIndex].isStreaming = false
                }
            }

            // 流式传输完成，保存到数据库
            let finalContent = messages[lastIndex].content
            let finalThinking = messages[lastIndex].thinkingContent
            // 将思考内容合并到响应中保存
            let savedResponse: String
            if let thinking = finalThinking, !thinking.isEmpty {
                savedResponse = "<think>\(thinking)</think>\n\n\(finalContent)"
            } else {
                savedResponse = finalContent
            }
            // Use CAPTURED state, not current state
            saveChatToHistory(prompt: prompt, response: savedResponse, context: selectedText, paragraphId: capturedParagraphId, actionType: capturedActionType)

        } catch {
            messages[lastIndex].content = "抱歉，发生了错误：\(error.localizedDescription)"
            messages[lastIndex].isStreaming = false
        }

        isGenerating = false
    }

    private func saveChatToHistory(prompt: String, response: String, context: String, paragraphId: String?, actionType: String?) {
        let chat = AIChat(
            prompt: prompt,
            response: response,
            relatedText: context,
            modelName: "gpt-4o-mini",
            annotationCfi: paragraphId,  // Use passed captured ID
            actionType: actionType       // Use passed captured action type
        )
        chat.book = book
        modelContext.insert(chat)

        try? modelContext.save()

        // 发送通知，让阅读器更新 Timeline 高亮
        print("DEBUG: Posting AIChatCompletedNotification")
        NotificationCenter.default.post(name: .init("AIChatCompletedNotification"), object: nil)
        
        // Remove dependency on global mutable state clearing
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @Binding var message: AIMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                // AI 消息：左对齐
                messageContent
                Spacer()
            } else {
                // 用户消息：右对齐
                Spacer()
                messageContent
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var messageContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // AI 消息：显示思考过程（如果有）
            if message.role == .assistant, let thinkingContent = message.thinkingContent, !thinkingContent.isEmpty {
                ThinkingView(
                    content: thinkingContent,
                    isExpanded: $message.isThinkingExpanded
                )
            }

            // 消息内容
            if message.role == .assistant {
                // AI 消息使用 MarkdownText
                MarkdownText(content: message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    // 流式传输中的光标效果
                    .overlay(alignment: .bottomTrailing) {
                        if message.isStreaming {
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(Color.secondary)
                                        .frame(width: 4, height: 4)
                                        .opacity(animationPhase(for: index))
                                }
                            }
                            .padding(6)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: message.isStreaming)
                        }
                    }
            } else {
                // 用户消息使用普通 Text
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "0xD9F7D3"))
                    .foregroundColor(.primary)
                    .cornerRadius(6)
            }

            Text(timestampText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var timestampText: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(message.timestamp) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(message.timestamp) {
            return "昨天"
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
        }
        return formatter.string(from: message.timestamp)
    }

    // 用于流式光标动画
    @State private var animationTick: Bool = false

    private func animationPhase(for index: Int) -> Double {
        let basePhase = animationTick ? 0.3 : 1.0
        let offset = Double(index) * 0.2
        return max(0.2, basePhase - offset)
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Suggestion Button

struct SuggestionButton: View {
    let icon: String
    let title: String
    let prompt: String
    let onAction: (String) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button(action: {
            onAction(prompt)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selected Text Preview

struct SelectedTextPreview: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("选中的文本")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(String(text.prefix(200)))
                    .font(.body)
                    .lineLimit(3)
                    .foregroundColor(.primary)

                if text.count > 200 {
                    Text("...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
    }
}



// MARK: - Chat History View

struct ChatHistoryView: View {
    let book: BookItem
    @Environment(\.dismiss) private var dismiss
    @Query private var chatHistory: [AIChat]

    var body: some View {
        NavigationStack {
            List(chatHistory) { chat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(chat.prompt)
                        .font(.headline)
                    Text(chat.response)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("聊天历史")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookItem.self, configurations: config)

    let sampleBook = BookItem(
        title: "示例书籍",
        bookmarkData: Data(),
        fileType: "pdf",
        filePath: "/path/to/book.pdf"
    )

    container.mainContext.insert(sampleBook)

    return AISidePanel(book: sampleBook, selectedText: .constant(""))
        .modelContainer(container)
        .frame(width: 400)
}
