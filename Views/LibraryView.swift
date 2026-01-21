import SwiftUI
import SwiftData

/// 极简书库视图
struct LibraryView: View {
    let books: [BookItem]
    let onOpen: (BookItem) -> Void
    let onDelete: (BookItem) -> Void
    let onImport: (URL) -> Void
    
    @State private var searchText = ""
    @State private var showImportSheet = false
    @State private var showDebugLogs = false
    @State private var editingBook: BookItem?
    @State private var isImporting: Bool = false
    
    // 自适应网格布局
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24)
    ]
    
    var filteredBooks: [BookItem] {
        if searchText.isEmpty {
            return books
        } else {
            return books.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            header
            
            // 内容区域
            if books.isEmpty {
                emptyState
            } else {
                bookGrid
            }
        }
        .background(Color(nsColor: .windowBackgroundColor)) // 使用系统窗口背景色
        .fileImporter(
            isPresented: $showImportSheet,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onImport(url)
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogView()
        }
        .sheet(item: $editingBook) { book in
            EditBookView(book: book)
        }
    }
    
    // MARK: - Components
    
    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text("Library")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(.primary)
            
            Text("\(books.count) books")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
            
            Spacer()
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .frame(width: 200)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // 导入按钮
            Button(action: { showImportSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color.primary)
                    .foregroundColor(Color(nsColor: .windowBackgroundColor))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .help("Import Book")
            .help("Import Book")
            
            // 调试日志按钮
            Button(action: { showDebugLogs = true }) {
                Image(systemName: "ladybug")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(.secondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .help("Show Debug Logs")
            
            // 设置按钮
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(.secondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .help("Settings")
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
    
    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(filteredBooks) { book in
                    BookItemView(
                        book: book,
                        onOpen: { onOpen(book) },
                        onDelete: { onDelete(book) },
                        onExport: { exportBookChats(book) },
                        onEdit: { editingBook = book }
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("Your library is empty")
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundColor(.secondary)
            
            Button(action: { showImportSheet = true }) {
                Text("Import your first book")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.primary)
                    .foregroundColor(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - CSV Export
    
    private func exportBookChats(_ book: BookItem) {
        let chats = book.aiChats.sorted { $0.createdAt < $1.createdAt }
        
        guard !chats.isEmpty else {
            return
        }
        
        var csvContent = "日期,操作类型,段落ID,原文,提问,回答\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for chat in chats {
            let date = dateFormatter.string(from: chat.createdAt)
            let actionType = chat.actionType ?? "chat"
            let paragraphId = chat.annotationCfi ?? ""
            let relatedText = escapeCSV(chat.relatedText)
            let prompt = escapeCSV(chat.prompt)
            let response = escapeCSV(chat.response)
            
            csvContent += "\(date),\(actionType),\(paragraphId),\(relatedText),\(prompt),\(response)\n"
        }
        
        let savePanel = NSSavePanel()
        savePanel.title = "导出聊天记录"
        savePanel.nameFieldStringValue = "\(book.title)_聊天记录.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let bom = "\u{FEFF}"
                    try (bom + csvContent).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("ERROR: Failed to export CSV: \(error)")
                }
            }
        }
    }
    
    private func escapeCSV(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: " ")
        escaped = escaped.replacingOccurrences(of: "\r", with: " ")
        if escaped.contains(",") || escaped.contains("\"") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}

/// 单个书籍项（包含右键菜单）
struct BookItemView: View {
    let book: BookItem
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onEdit: () -> Void
    
    var progress: Double {
        guard let current = book.lastReadPage, let total = book.pageCount, total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            BookCoverView(
                title: book.title,
                author: book.author ?? "Unknown Author",
                fileType: book.fileType,
                coverImage: book.coverImageData.flatMap { NSImage(data: $0) },
                themeColor: book.themeColor.map { Color(hex: $0) }
            )
            
            // 进度显示
            if progress > 0 {
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)
                                .cornerRadius(2)
                            
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                .cornerRadius(2)
                        }
                    }
                    .frame(width: 120, height: 4)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onTapGesture {
            onOpen()
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Edit Metadata") { onEdit() }
            Divider()
            Button("Export Chat History") { onExport() }
            Divider()
            Button("Remove from Library", role: .destructive) { onDelete() }
        }
    }
}
