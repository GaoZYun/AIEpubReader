<div align="center">

# 📚 AIReader

**Read Deeper, Not Faster.**

*A native macOS e-book reader that uses AI to help you truly understand what you read.*

[English](#english) | [中文](#中文)

</div>

---

## English

### Philosophy

> **While everyone else is using AI to read less, we believe in reading more.**

The internet is flooded with tools promising to summarize books in 5 minutes, extract "key insights," or let AI read for you. We think that misses the point entirely.

**AIReader takes a different approach**: instead of replacing your reading, AI becomes your reading companion. When you encounter a difficult passage, an unfamiliar concept, or a thought-provoking paragraph, you can engage in a dialogue with AI to explore it deeply—right there in your book.

This is about **reading books thickly**, not thinly. It's about stopping to think, asking questions, and building genuine understanding.

### Features

- 📖 **Native macOS App** — Built with SwiftUI for a fast, beautiful reading experience
- 📚 **EPUB & PDF Support** — Read your entire library in one place
- 🤖 **Contextual AI Chat** — Select any text and ask AI to explain, analyze, or discuss it
- 💬 **Paragraph Timeline** — Every AI conversation is anchored to the paragraph you were reading, creating a visual "thinking trail" through your book
- 🎨 **Dark Mode** — Full dark mode support with automatic theme switching
- ✍️ **Customizable Prompts** — Define your own prompts for different types of analysis
- 🔌 **Flexible AI Backend** — Works with OpenAI, OpenAI-compatible APIs (OneAPI, Azure, etc.), or local Ollama

### Screenshots

*Coming soon*

### Installation

#### Build from Source

```bash
git clone https://github.com/user/AIReader.git
cd AIReader
swift build -c release
```

The built app will be in `.build/release/AIReader`.

### Configuration

1. Open the app and go to **Settings** (⚙️)
2. Choose your AI provider:
   - **OpenAI**: Enter your API key. Optionally set a custom endpoint for proxies.
   - **Ollama**: Set your local Ollama server URL (default: `http://localhost:11434`)
3. Select your preferred model
4. Customize prompts for Explain/Summarize/Translate/Analyze actions

### Usage

1. Import books via drag-and-drop or the import button
2. Open a book and start reading
3. Select any text to see the AI action menu
4. Choose an action (Explain, Summarize, Translate, Analyze) or type a custom question
5. The AI response appears in the side panel and is saved to the paragraph timeline

### Project Structure

```
AIReader/
├── AIReaderApp.swift           # App entry point
├── ContentView.swift           # Main UI & Settings
├── Models/                     # SwiftData models
│   ├── BookItem.swift          # Book metadata
│   ├── AIChat.swift            # Chat history
│   └── Annotation.swift        # Highlights & notes
├── Views/                      # SwiftUI views
│   ├── LibraryView.swift       # Book library grid
│   ├── ReaderContainer.swift   # Reader wrapper
│   ├── EpubWebView.swift       # EPUB renderer (WebKit)
│   ├── PDFKitView.swift        # PDF renderer
│   ├── AISidePanel.swift       # AI chat panel
│   └── ...
└── Services/                   # Business logic
    ├── AIService.swift         # AI API integration
    ├── LibraryManager.swift    # Book import/storage
    └── BridgeCoordinator.swift # JS-Swift bridge
```

### Tech Stack

- **UI**: SwiftUI + AppKit
- **Data**: SwiftData
- **EPUB Rendering**: WebKit (WKWebView)
- **PDF Rendering**: PDFKit
- **AI**: OpenAI API / Ollama

### License

MIT License

---

## 中文

### 理念

> **当所有人都在用 AI 减少阅读时，我们选择让阅读更深入。**

互联网上充斥着各种工具，承诺能在 5 分钟内总结一本书、提取"核心观点"，或者让 AI 替你读书。我们认为这完全搞错了方向。

**AIReader 采取了不同的方式**：AI 不是来取代你的阅读，而是成为你的阅读伙伴。当你遇到难懂的段落、陌生的概念，或者发人深省的文字时，你可以就地与 AI 展开对话，深入探讨——就在你正在阅读的书中。

这是关于**把书读厚**，而不是读薄。是关于停下来思考、提出问题、构建真正的理解。

### 功能特性

- 📖 **原生 macOS 应用** — 使用 SwiftUI 构建，快速流畅的阅读体验
- 📚 **支持 EPUB 和 PDF** — 在一个应用中阅读你的所有书籍
- 🤖 **上下文 AI 对话** — 选中任意文字，让 AI 解释、分析或讨论
- 💬 **段落时间线** — 每次 AI 对话都锚定在你阅读的段落上，在书中形成一条可视化的"思考轨迹"
- 🎨 **深色模式** — 完整的深色模式支持，自动跟随系统主题
- ✍️ **自定义提示词** — 为不同类型的分析定义你自己的提示词
- 🔌 **灵活的 AI 后端** — 支持 OpenAI、OpenAI 兼容接口（OneAPI、Azure 等）或本地 Ollama

### 截图

*即将添加*

### 安装

#### 从源码构建

```bash
git clone https://github.com/user/AIReader.git
cd AIReader
swift build -c release
```

构建好的应用位于 `.build/release/AIReader`。

### 配置

1. 打开应用，进入 **设置** (⚙️)
2. 选择你的 AI 提供商：
   - **OpenAI**：输入你的 API Key。如果使用代理，可以设置自定义端点。
   - **Ollama**：设置本地 Ollama 服务器地址（默认：`http://localhost:11434`）
3. 选择你偏好的模型
4. 自定义"解释/总结/翻译/分析"的提示词

### 使用方法

1. 通过拖拽或导入按钮添加书籍
2. 打开一本书开始阅读
3. 选中任意文字，会出现 AI 操作菜单
4. 选择一个操作（解释、总结、翻译、分析）或输入自定义问题
5. AI 回复会出现在侧边栏，并保存到段落时间线

### 技术栈

- **界面**: SwiftUI + AppKit
- **数据**: SwiftData
- **EPUB 渲染**: WebKit (WKWebView)
- **PDF 渲染**: PDFKit
- **AI**: OpenAI API / Ollama

### 开源协议

MIT License

---

<div align="center">

**Read with intention. Think with depth.**

Made with ❤️ for readers who refuse to skim.

</div>
