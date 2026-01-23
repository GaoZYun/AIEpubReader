# AIReader 技术参考文档

**版本:** 1.0.0
**日期:** 2026-01-21
**作者:** AIReader 开发团队

## 1. 系统概览

AIReader 是一款基于 **SwiftUI** 和 **SwiftData** 构建的原生 macOS 应用程序。其核心设计理念是“AI 优先 (AI-First)”，致力于将大语言模型（LLM）的能力深度集成到 EPUB 和 PDF 文档的阅读体验中。

### 核心技术栈

- **UI 框架**: SwiftUI (macOS 14.0+)
- **数据持久化**: SwiftData
- **Web 渲染引擎**: WebKit (WKWebView) - 用于 EPUB 渲染
- **PDF 渲染引擎**: PDFKit - 用于 PDF 渲染
- **AI 集成**: OpenAI API 兼容接口

---

## 2. 架构模式

本项目采用 **改进型 MVVM (Model-View-ViewModel)** 架构，并引入 **Coordinator (协调器)** 模式来专门处理原生 Swift 代码与 WebEnvironment (WebKit) 之间复杂的双向通信。

### 高层组件

1. **状态管理**: 使用 `@StateObject`, `@ObservedObject` 管理视图状态，使用 SwiftData 的 `@Query` 实现数据库驱动的 UI 更新。
2. **导航结构**: 基于侧边栏的导航设计 (`LibraryView` 书库视图 vs `ReaderContainer` 阅读器视图)。
3. **桥接层 (Bridge Layer)**: 原生代码与 JavaScript 互相调用的关键通道，实现了文本选择、AI 上下文匹配、时间线渲染等核心交互。

---

## 3. 目录结构与模块详解

### 3.1 数据模型 (`/Models`)

所有持久化数据均通过 SwiftData 管理。

- **`BookItem.swift`**
  - **角色**: 核心实体，代表一本书。
  - **关键属性**:
    - `filePath`: 本地文件的绝对路径（需配合 Sandbox 权限）。
    - `themeColor`: 用于自定义封面的主题色（Hex 字符串）。
    - `lastReadPage` / `progress`: 阅读进度追踪。
    - `aiChats`: 一对多关系，关联该书的所有 AI 对话记录。
  - **用途**: 作为核心上下文对象传递给几乎所有视图。

- **`AIChat.swift`**
  - **角色**: 存储单次 AI 交互（提问 + 回答）。
  - **关键属性**:
    - `relatedText`: 触发对话的书籍原文片段。
    - `paragraphId`: **关键字段**。DOM 节点的唯一标识符（或哈希），用于在 UI 上将对话气泡精确锚定到对应的段落旁。
    - `actionType`: 操作类型枚举 (如 "explain", "summarize", "translate")。

### 3.2 核心服务 (`/Services`)

- **`BridgeCoordinator.swift` (最核心的类)**
  - **类型**: `NSObject`, `WKScriptMessageHandler`, `WKNavigationDelegate`.
  - **角色**: 连接 `EpubWebView` (UI) 和应用逻辑 (Logic) 的胶水层。
  - **核心职责**:
    - **JS 注入**: 负责注入 `selectionHandler.js`, `highlightChatHistory.js` 以及 CSS 变量。
    - **消息处理**: 接收来自 JS 的 `postMessage` 事件（例如用户选中文本）。
    - **UI 控制**: 暴露如 `toggleTOC()` 等方法，供 SwiftUI 层直接控制 Web 页面的侧边栏。
    - **时间线渲染**: 将 `[AIChat]` 数组序列化为 JSON，调用 JS 的 `highlightChatHistory` 方法，在 WebView 内部绘制侧边栏和高亮标记。

- **`LibraryManager.swift`**
  - **角色**: 文件系统操作管家。
  - **核心方法**:
    - `importBook(url)`: 将外部文件复制到应用沙盒容器，生成 `BookItem` 实体。
    - `coverImage(for:)`: 解析 EPUB/PDF 文件提取封面图像。

- **`AIService.swift`**
  - **角色**: LLM API 的网络层。
  - **细节**: 处理流式响应 (`AsyncThrowingStream`)，管理上下文窗口 (Context Window)，以及 Prompt 工程。

### 3.3 视图层 (`/Views`)

#### 根视图与容器

* **`ContentView.swift`**: 应用入口。负责在 `LibraryView` (书库) 和 `ReaderContainer` (阅读器) 之间切换。
- **`ReaderContainer.swift`**:
  - **布局**: 使用 `HSplitView` 实现左右分栏 (左侧阅读器 | 右侧 AI 面板)。
  - **覆盖层 UI**: 管理左上角的“返回”和“目录”按钮 (VStack 布局)。
  - **事件处理**: 监听 `ToggleTOCNotification` 通知，以触发桥接层的操作。

#### 阅读引擎

* **`EpubWebView.swift`** (`NSViewRepresentable`)
  - **渲染机制**: **不直接加载 .epub 文件**。而是解压 EPUB，解析 `OPF` 元数据，将 `spine` 中的所有章节拼接成一个**虚拟的单页 HTML 字符串**。
  - **定制化**: 注入自定义 CSS (字体、隐藏滚动条、侧边栏样式) 和 JS (目录切换、交互监听)。
  - **内部导航**: 利用 HTML 锚点 (`#chapter-ID`) 实现章节跳转。

- **`PDFKitView.swift`** (`NSViewRepresentable`)
  - **机制**: 封装标准的 `PDFView`。
  - **扩展**: 添加自定义的 `UIMenu` 或覆盖层按钮来触发 AI 操作。

#### 交互面板

* **`AISidePanel.swift`**:
  - 右侧边栏，展示对话历史列表。
  - 提供输入框进行追问。
  - 处理 AI "思考中 (Thinking)" 的 UI 状态。

---

## 4. 关键数据流与调用关系图

### 4.1 "时间线 (Timeline)" 渲染流程

**目标**: 在电子书正文对应的段落旁，显示历史 AI 对话标记。

1. **触发**: `ReaderContainer` 加载或数据变更，调用 `updateChatHistoryHighlights()`。
2. **转换**: Swift 将 `book.aiChats` 转换为轻量级 JSON 对象 (包含 ID, 提问, 回答摘要, paragraphId)。
3. **桥接调用**: `BridgeCoordinator` 执行 `webView.evaluateJavaScript("highlightChatHistory(...)")`。
4. **JS 执行** (`BridgeCoordinator.swift` 内嵌的 JS 逻辑):
    - 遍历 DOM 中所有 `<p>` 标签。
    - 匹配 `paragraphId` 或执行模糊文本匹配 (`p.innerText.includes(...)`)。
    - **DOM 操作**: 在匹配的段落旁注入 `<div class="ai-timeline-container">`。
    - **侧边栏填充**: 同时将对话摘要填充到侧边栏的 `#timeline-list` 列表中 (用于快速跳转)。

### 4.2 "返回书库" 流程

1. **用户操作**: 点击 `ReaderContainer` 左上角的“返回”图标。
2. **状态变更**: 将 `isPresented` Binding 设为 `false`。
3. **SwiftUI 响应**: `ContentView` 将根视图从 `ReaderContainer` 切换回 `LibraryView`。
4. **清理**: `EpubWebView` 被销毁。`BridgeCoordinator` 可能会缓存部分状态，但 Webview 实例会被释放。

### 4.3 "切换目录 (Toggle TOC)" 流程

1. **用户操作**: 点击 `ReaderContainer` 左上角的“列表”图标。
2. **通知发送**: `NotificationCenter` 发送 `ToggleTOCNotification` 通知。
3. **监听响应**: `EPUBReaderView` (位于 `ReaderContainer` 内部) 接收通知。
4. **动作触发**: 调用 `coordinator.toggleTOC()`。
5. **桥接执行**: 调用 `webView.evaluateJavaScript("toggleTOC()")`。
6. **JS 执行**: 切换 HTML 中 `#tocSidebar` 元素的 `.open` CSS 类。
7. **动画**: CSS `transform` 属性驱动侧边栏从左侧滑出。

---

## 5. 附录：核心 API 参考 (BridgeCoordinator)

以下是 `BridgeCoordinator` 对外暴露或内部关键的方法列表：
- **`toggleTOC()`**: 公开方法。执行 JS 切换目录侧边栏的显示/隐藏。
- **`injectSelectionHandler(into:)`**: 初始化方法。注入核心 JS 脚本，用于捕获文本选择事件。
- **`updateTheme(_:for:)`**: 当应用主题变更时，更新 Webview 内的 CSS 变量 (如背景色、字体色)。
- **`highlightChatHistory(_:retryCount:)`**: 核心业务方法。将 SwiftData 中的对话记录同步到 Webview DOM 中渲染。
- **`handleSelectionMessage(_:)`**: 内部回调。处理 JS 发回的 `selectionHandler` 消息，解析坐标和文本，弹出原生 HUD。
