import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [BookItem]
    @State private var selectedBook: BookItem?
    @State private var showReader: Bool = false
    @State private var showImportSheet: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        Group {
            if showReader, let book = selectedBook {
                ReaderContainer(book: book, isPresented: $showReader)
            } else {
                LibraryView(
                    books: books,
                    onOpen: { book in
                        openBook(book)
                    },
                    onDelete: { book in
                        deleteBook(book)
                    },
                    onImport: { url in
                        importBook(from: url)
                    }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // 监听来自 LibraryView 的设置打开请求（如果需要）或是全局快捷键
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettings"))) { _ in
            showSettings = true
        }
    }

    // MARK: - Actions

    private func openBook(_ book: BookItem) {
        selectedBook = book
        book.lastOpenedAt = Date()
        try? modelContext.save()
        // 简单过渡动画
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showReader = true
        }
    }

    private func deleteBook(_ book: BookItem) {
        withAnimation {
            modelContext.delete(book)
            try? modelContext.save()
        }
    }

    private func importBook(from url: URL?) {
        guard let url = url else { return }

        let libraryManager = LibraryManager.shared
        guard let book = libraryManager.importBook(from: url) else {
            print("Failed to import book")
            return
        }

        withAnimation {
            modelContext.insert(book)
            try? modelContext.save()
        }
    }
}

// MARK: - File Importer

struct FileImporter: View {
    @Binding var isPresented: Bool
    let onURLSelected: (URL?) -> Void

    var body: some View {
        VStack {
            Text("选择 EPUB 或 PDF 文件")
                .font(.headline)
                .padding()

            FilePickerWrapper(
                allowedContentTypes: [.pdf, .epub],
                onURLSelected: { url in
                    onURLSelected(url)
                    isPresented = false
                }
            )
        }
        .frame(width: 400, height: 300)
    }
}

struct FilePickerWrapper: NSViewRepresentable {
    let allowedContentTypes: [UTType]
    let onURLSelected: (URL?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            showFilePicker()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes

        // 使用 begin 避免阻塞主线程
        panel.begin { response in
            if response == .OK {
                onURLSelected(panel.url)
            } else {
                onURLSelected(nil)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("aiProvider") private var aiProvider: String = "openai"
    @AppStorage("openaiAPIKey") private var openaiAPIKey: String = ""
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL: String = "http://localhost:11434"
    @AppStorage("selectedModel") private var selectedModel: String = "gpt-4o-mini"
    @AppStorage("appTheme") private var appTheme: String = "system" // system, light, dark
    
    // Custom Prompts
    @AppStorage("promptExplain") private var promptExplain: String = "请解释这段内容："
    @AppStorage("promptSummarize") private var promptSummarize: String = "请总结这段内容的要点："
    @AppStorage("promptTranslate") private var promptTranslate: String = "请将这段内容翻译成中文："
    @AppStorage("promptAnalyze") private var promptAnalyze: String = "请分析这段内容的修辞和深层含义："

    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIConfig")

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("AI 设置")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 设置内容
            Form {
                Section("AI 提供商") {
                    Picker("提供商", selection: $aiProvider) {
                        Text("OpenAI").tag("openai")
                        Text("Ollama").tag("ollama")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("外观 (Display)") {
                    Picker("主题", selection: $appTheme) {
                        Text("跟随系统").tag("system")
                        Text("浅色模式").tag("light")
                        Text("深色模式").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                if aiProvider == "openai" {
                    Section("OpenAI 配置") {
                        SecureField("API Key", text: $openaiAPIKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Text("获取 API Key:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Link("platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                .font(.caption)
                        }

                        TextField("API 端点 (可选)", text: Binding(
                            get: { UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "" },
                            set: { UserDefaults.standard.set($0.isEmpty ? "" : $0, forKey: "openAIBaseURL") }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .help("留空使用官方端点 api.openai.com")

                        Text("提示: 可配置代理或兼容端点")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        // 模型选择 - 改为直接输入
                        HStack {
                            Text("模型")
                                .frame(width: 60, alignment: .leading)
                            TextField("输入模型名称", text: $selectedModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        // 常用模型快捷按钮
                        HStack(spacing: 8) {
                            Text("常用:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo", "claude-3-5-sonnet"], id: \.self) { model in
                                Button(model) {
                                    selectedModel = model
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            Spacer()
                        }

                        Link("OpenAI 官网", destination: URL(string: "https://openai.com")!)
                            .font(.caption)
                    }
                } else {
                    Section("Ollama 配置") {
                        TextField("Base URL", text: $ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)

                        TextField("模型名称", text: $selectedModel)
                            .textFieldStyle(.roundedBorder)

                        Text("提示: 确保本地已运行 Ollama 服务")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Button(action: { Task { await fetchOllamaModels() } }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新模型列表")
                            }
                        }
                        .buttonStyle(.borderless)

                        Link("Ollama 官网", destination: URL(string: "https://ollama.ai")!)
                            .font(.caption)
                    }
                }

                Section("自定义提示词") {
                    VStack(alignment: .leading) {
                        Text("解释 (Explain)")
                            .font(.caption)
                        TextEditor(text: $promptExplain)
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("总结 (Summarize)")
                            .font(.caption)
                        TextEditor(text: $promptSummarize)
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("翻译 (Translate)")
                            .font(.caption)
                        TextEditor(text: $promptTranslate)
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("分析 (Analyze)")
                            .font(.caption)
                        TextEditor(text: $promptAnalyze)
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    }
                    
                    Button("恢复默认提示词") {
                        promptExplain = "请解释这段内容："
                        promptSummarize = "请总结这段内容的要点："
                        promptTranslate = "请将这段内容翻译成中文："
                        promptAnalyze = "请分析这段内容的修辞和深层含义："
                    }
                    .font(.caption)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Spacer()
        }
        .frame(minWidth: 450, minHeight: 400)
        .onChange(of: aiProvider) { _, _ in
            if aiProvider == "ollama" {
                Task { await fetchOllamaModels() }
            }
        }
        .onChange(of: openaiAPIKey) { _, newValue in
            logger.info("SettingsView: OpenAI API Key changed. New length: \(newValue.count)")
        }
        .onAppear {
            logger.info("SettingsView: Appeared. Provider: \(aiProvider), API Key length: \(openaiAPIKey.count)")
            
            // Explicitly set defaults if missing to ensure AISidePanel can read them
            if UserDefaults.standard.string(forKey: "aiProvider") == nil {
                UserDefaults.standard.set("openai", forKey: "aiProvider")
            }
            if UserDefaults.standard.string(forKey: "selectedModel") == nil {
                UserDefaults.standard.set("gpt-4o-mini", forKey: "selectedModel")
            }
        }
    }

    // MARK: - Fetch Ollama Models

    private func fetchOllamaModels() async {
        do {
            let url = URL(string: "\(ollamaBaseURL)/api/tags")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)

            let models = response.models.map { $0.name }
            if !models.isEmpty, selectedModel.isEmpty || !models.contains(selectedModel) {
                selectedModel = models.first ?? "llama2"
            }
        } catch {
            print("Failed to fetch Ollama models: \(error)")
        }
    }
}

// MARK: - Ollama Model Types

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: BookItem.self, configurations: config)

    // 添加示例书籍
    let sampleBook1 = BookItem(
        title: "SwiftUI 编程",
        author: "Apple",
        bookmarkData: Data(),
        fileType: "pdf",
        filePath: "/path/to/book1.pdf"
    )
    let sampleBook2 = BookItem(
        title: "人工智能导论",
        author: "AI 专家",
        bookmarkData: Data(),
        fileType: "epub",
        filePath: "/path/to/book2.epub"
    )

    container.mainContext.insert(sampleBook1)
    container.mainContext.insert(sampleBook2)

    return ContentView()
        .modelContainer(container)
}
