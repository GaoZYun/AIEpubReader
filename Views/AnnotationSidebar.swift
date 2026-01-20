import SwiftUI
import SwiftData

struct AnnotationSidebar: View {
    @Query(sort: \Annotation.createdAt, order: .reverse)
    private var annotations: [Annotation]

    @State private var exporting = false
    @State private var showExportAlert = false
    @State private var exportText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            header

            // 笔注列表
            if annotations.isEmpty {
                emptyState
            } else {
                annotationList
            }
        }
        .alert("导出笔注", isPresented: $showExportAlert) {
            Button("复制") {
                copyToClipboard(exportText)
            }
            Button("保存") {
                saveToFile(exportText)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("笔注已准备好导出，选择你的操作")
        }
    }

    // MARK: - 顶部工具栏
    private var header: some View {
        HStack {
            Text("笔注")
                .font(.headline)
                .padding(.leading)

            Spacer()

            if !annotations.isEmpty {
                Button(action: exportAnnotations) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
                .padding(.trailing)
                .help("导出笔注")
            }
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - 空状态
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "highlighter")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("暂无笔注")
                .font(.title3)
                .foregroundColor(.gray)

            Text("选中文字后可以创建笔注")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 笔注列表
    private var annotationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(annotations) { annotation in
                    AnnotationRow(annotation: annotation)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    Divider()
                        .padding(.leading, 16)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - 导出笔注
    private func exportAnnotations() {
        var markdown = "# 笔注导出\n\n"
        markdown += "导出时间: \(Date().formatted())\n\n"
        markdown += "---\n\n"

        for (index, annotation) in annotations.enumerated() {
            markdown += "## 笔注 \(annotations.count - index)\n\n"

            // 高亮内容
            markdown += "### 高亮内容\n\n"
            markdown += "> \(annotation.content)\n\n"

            // 笔记
            if let note = annotation.note, !note.isEmpty {
                markdown += "### 笔记\n\n"
                markdown += "\(note)\n\n"
            }

            // 元数据
            markdown += "### 信息\n\n"
            if let pageIndex = annotation.pageIndex {
                markdown += "- 页码: \(pageIndex)\n"
            }
            markdown += "- 创建时间: \(annotation.createdAt.formatted())\n"

            if let cfi = annotation.cfi {
                markdown += "- 章节: \(cfi)\n"
            }

            markdown += "\n---\n\n"
        }

        exportText = markdown
        showExportAlert = true
    }

    // MARK: - 复制到剪贴板
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - 保存到文件
    private func saveToFile(_ text: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "笔注导出_\(Date().formatted(.iso8601.day().month().year())).md"

        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - 笔注行视图
struct AnnotationRow: View {
    @Environment(\.modelContext) private var modelContext
    let annotation: Annotation

    @State private var isEditing = false
    @State private var editedNotes: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 高亮内容预览
            contentSection

            // 笔记区域
            noteSection

            // 底部工具栏
            toolbar
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 高亮内容区域
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "highlighter")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text("高亮内容")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let pageIndex = annotation.pageIndex {
                    Text("第 \(pageIndex) 页")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(previewText)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 笔记区域
    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundColor(.blue)

                Text("笔记")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isEditing {
                TextEditor(text: $editedNotes)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 150)
                    .focused($isFocused)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                    )
            } else {
                if let note = annotation.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("点击编辑按钮添加笔记...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    // MARK: - 底部工具栏
    private var toolbar: some View {
        HStack(spacing: 8) {
            // 时间标签
            Text(annotation.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // 编辑/保存按钮
            if isEditing {
                HStack(spacing: 4) {
                    Button(action: cancelEdit) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消")

                    Button(action: saveNotes) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("保存")
                }
            } else {
                Button(action: startEdit) {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("编辑笔记")
            }

            // 删除按钮
            Button(action: deleteAnnotation) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("删除笔注")
        }
    }

    // MARK: - 预览文本
    private var previewText: String {
        let text = annotation.content
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    // MARK: - 开始编辑
    private func startEdit() {
        editedNotes = annotation.note ?? ""
        isEditing = true
        isFocused = true
    }

    // MARK: - 取消编辑
    private func cancelEdit() {
        isEditing = false
        editedNotes = ""
    }

    // MARK: - 保存笔记
    private func saveNotes() {
        annotation.note = editedNotes
        isEditing = false
        editedNotes = ""

        try? modelContext.save()
    }

    // MARK: - 删除笔注
    private func deleteAnnotation() {
        modelContext.delete(annotation)
        try? modelContext.save()
    }
}

// MARK: - 预览
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Annotation.self, configurations: config)

    // 添加示例数据
    let context = container.mainContext

    let annotation1 = Annotation(
        content: "这是一段很长的示例高亮文本，它会被截断显示。这段文字用来演示当高亮内容超过100个字符时，界面会如何处理。我们会看到前100个字符，然后是一个省略号，表示还有更多内容。",
        pageIndex: 42,
        note: "这是一个重要的概念，需要仔细理解。"
    )
    context.insert(annotation1)

    let annotation2 = Annotation(
        content: "短一点的文本",
        pageIndex: 45,
        note: ""
    )
    context.insert(annotation2)

    return AnnotationSidebar()
        .modelContainer(container)
        .frame(width: 350, height: 600)
}
