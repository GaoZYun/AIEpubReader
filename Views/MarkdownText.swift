import SwiftUI

struct MarkdownText: View {
    let content: String

    var body: some View {
        Text(attributedString)
            .textSelection(.enabled)
    }

    private var attributedString: AttributedString {
        do {
            // 使用 SwiftUI 的 AttributedString Markdown 解析
            var attributedString = try AttributedString(markdown: content, options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))

            // 设置基础样式
            attributedString.font = .body
            attributedString.foregroundColor = .primary

            return attributedString
        } catch {
            // 如果解析失败，返回原始文本
            return AttributedString(content)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MarkdownText(content: """
# Markdown 渲染示例

这是 **粗体文本** 和 *斜体文本*。

这是 `行内代码`。

```swift
let greeting = "Hello, World!"
print(greeting)
```

- 列表项 1
- 列表项 2
- 列表项 3

1. 编号项 1
2. 编号项 2
3. 编号项 3

这是一个[链接](https://example.com)。

支持换行符
和多行文本。
""")

        Divider()

        MarkdownText(content: "**简单示例**：使用 `AttributedString` 实现 Markdown 渲染")
    }
    .padding()
}
