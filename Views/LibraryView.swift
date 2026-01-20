import SwiftUI
import SwiftData

/// 极简书库视图
struct LibraryView: View {
    let books: [BookItem]
    let onOpen: (BookItem) -> Void
    let onDelete: (BookItem) -> Void
    let onImport: (URL) -> Void
    
    @State private var searchText: String = ""
    @State private var hoverBookId: UUID?
    @State private var showImportSheet: Bool = false
    
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
                        onDelete: { onDelete(book) }
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
}

/// 单个书籍项（包含右键菜单）
struct BookItemView: View {
    let book: BookItem
    let onOpen: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            BookCoverView(
                title: book.title,
                author: book.author ?? "Unknown Author",
                fileType: book.fileType,
                coverImage: book.coverImageData.flatMap { NSImage(data: $0) }
            )
        }
        .onTapGesture {
            onOpen()
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Remove from Library", role: .destructive) { onDelete() }
        }
    }
}
