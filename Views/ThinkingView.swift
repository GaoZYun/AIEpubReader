import SwiftUI

/// 思考过程展示视图
struct ThinkingView: View {
    let content: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部：可点击展开/收起
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                    Text("思考过程")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // 思考内容
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thinkingDisplayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var thinkingDisplayText: String {
        // 如果内容太长，截断显示
        let maxLength = 2000
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "\n\n...(内容过长，已截断)"
        }
        return content
    }
}

#Preview {
    @Previewable @State var isExpanded = true

    VStack(alignment: .leading, spacing: 16) {
        ThinkingView(
            content: """
            这是模型的思考过程，展示了 AI 如何分析和处理问题。

            首先，我需要理解用户的问题...
            然后分析上下文...
            最后给出答案。
            """,
            isExpanded: $isExpanded
        )

        ThinkingView(
            content: "简短的思考内容",
            isExpanded: .constant(true)
        )
    }
    .padding()
    .frame(width: 400)
}
