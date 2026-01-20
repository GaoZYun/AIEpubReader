import SwiftUI

struct AIInputPopover: View {
    // 弹窗类型
    enum PopoverType: String, CaseIterable {
        case explain = "解释"
        case summarize = "总结"
        case translate = "翻译"

        var title: String {
            switch self {
            case .explain: return "解释选中文本"
            case .summarize: return "总结选中文本"
            case .translate: return "翻译选中文本"
            }
        }

        var promptTemplate: String {
            switch self {
            case .explain: return "请详细解释以下内容："
            case .summarize: return "请为以下内容写一个简洁的总结："
            case .translate: return "请将以下内容翻译成中文："
            }
        }
    }

    // 弹窗配置
    struct Configuration {
        let type: PopoverType
        let selectedText: String
        let position: CGPoint
    }

    // 状态变量
    @Binding var isPresented: Bool
    @State private var inputText: String = ""
    @State private var showSelectedText: Bool = true
    @State private var selectedText: String
    @State private var popoverType: PopoverType
    @State private var onSend: (String) -> Void

    // 弹窗位置
    @State private var popoverPosition: CGPoint

    init(
        isPresented: Binding<Bool>,
        config: Configuration,
        onSend: @escaping (String) -> Void
    ) {
        self._isPresented = isPresented
        self._selectedText = State(initialValue: config.selectedText)
        self._popoverType = State(initialValue: config.type)
        self._onSend = State(initialValue: onSend)
        self._popoverPosition = State(initialValue: config.position)
        self.inputText = config.type.promptTemplate
    }

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Text(popoverType.title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
            }

            // 选中文本预览（可折叠）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("选中文本")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSelectedText.toggle()
                        }
                    }) {
                        Image(systemName: showSelectedText ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if showSelectedText {
                    Text(selectedText)
                        .font(.body)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }

            // 输入框
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 提示词")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $inputText)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            // 按钮
            HStack(spacing: 12) {
                Button(action: {
                    isPresented = false
                }) {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(nsColor: .controlAccentColor).opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }

                Button(action: {
                    onSend(inputText)
                    isPresented = false
                }) {
                    Text("发送")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320, height: showSelectedText ? 420 : 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .onAppear {
            // 自动聚焦到输入框
            DispatchQueue.main.async {
                // 这里可以添加获取第一响应者的逻辑
            }
        }
    }
}

// 预览
struct AIInputPopover_Previews: PreviewProvider {
    static var previews: some View {
        AIInputPopover(
            isPresented: .constant(true),
            config: .init(
                type: .explain,
                selectedText: "这是一段选中的文本，需要被解释。",
                position: CGPoint(x: 100, y: 100)
            ),
            onSend: { text in
                print("发送: \(text)")
            }
        )
    }
}