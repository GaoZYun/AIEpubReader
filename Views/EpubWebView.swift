import SwiftUI
import WebKit

/// EPUB Web 视图包装器
struct EpubWebView: NSViewRepresentable {
    let contentURL: URL
    @ObservedObject var coordinator: BridgeCoordinator
    @AppStorage("appTheme") private var appTheme: String = "system"

    func makeNSView(context: Context) -> WKWebView {
        print("DEBUG: EpubWebView.makeNSView")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()
        
        // Critical for local file access
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        // 注入桥接脚本
        coordinator.injectSelectionHandler(into: webView)
        coordinator.injectConsoleBridge(into: webView)
        coordinator.registerMessageHandlers(for: webView)

        // 加载内容
        let resolvedURL = contentURL.resolvingSymlinksInPath()
        let readAccessURL = resolvedURL.deletingLastPathComponent()
        print("DEBUG: Initial loadFileURL: \(resolvedURL.path)")
        print("DEBUG: Read Access: \(readAccessURL.path)")
        
        webView.loadFileURL(resolvedURL, allowingReadAccessTo: readAccessURL)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        print("DEBUG: EpubWebView.updateNSView")
        // 如果 URL 改变，重新加载
        if nsView.url?.path != contentURL.path {
            let resolvedURL = contentURL.resolvingSymlinksInPath()
            let readAccessURL = resolvedURL.deletingLastPathComponent()
            
            print("DEBUG: Reloading because path changed. Current: \(String(describing: nsView.url?.path)), New: \(resolvedURL.path)")
            nsView.loadFileURL(resolvedURL, allowingReadAccessTo: readAccessURL)
        } else {
             print("DEBUG: Skipping reload, path matches.")
        }
        
        // Update theme
        coordinator.updateTheme(appTheme, for: nsView)
    }

    func makeCoordinator() -> BridgeCoordinator {
        coordinator
    }
}

// MARK: - WKNavigationDelegate

extension BridgeCoordinator: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 允许 iframe 加载
        if navigationAction.targetFrame != nil && !navigationAction.targetFrame!.isMainFrame {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // 允许特殊协议
        if url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        // 允许初始加载 (index.html) 或其锚点
        // 注意：contentURL 可能是 file:///.../index.html
        // 请求的 URL 可能是 file:///.../index.html#chapter-1
        
        let isSamePath = url.path == webView.url?.path || (webView.url == nil)
        
        // 检查是否是仅仅改变了 fragment (锚点)
        if let currentURL = webView.url, url.path == currentURL.path {
            print("DEBUG: Allowing anchor navigation: \(url)")
            decisionHandler(.allow)
            return
        }
        
        // 检查是否是初始加载 index.html
        if url.lastPathComponent == "index.html" {
            print("DEBUG: Allowing main page load: \(url)")
            decisionHandler(.allow)
            return
        }
        
        // 拦截所有其他跳转 (防止跳到 part0001.html)
        print("DEBUG: Blocking navigation to: \(url)")
        decisionHandler(.cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 注入基础样式
        injectBaseStyles(into: webView)
        
        // 应用当前主题
        // 注意：这里需要从 UserDefaults 获取主题，因为 coordinator 本身不存储 appTheme
        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        updateTheme(theme, for: webView)

        // 重新初始化段落按钮和聊天记录（每次导航完成后）
        reinitializeParagraphsAndChats()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("DEBUG: EPUB navigation failed: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("DEBUG: EPUB provisional navigation failed: \(error.localizedDescription)")
    }

    // MARK: - Style Injection

    private func injectBaseStyles(into webView: WKWebView) {
        let css = """
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }

        img {
            max-width: 100%;
            height: auto;
        }

        p {
            margin-bottom: 1em;
        }

        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            font-weight: 600;
        }

        .ai-reader-highlight {
            border-radius: 2px;
        }

        /* 选中文本样式 */
        ::selection {
            background: var(--selection-bg, #b3d9ff);
        }

        /* 隐藏滚动条但保持功能 */
        ::-webkit-scrollbar {
            width: 8px;
        }

        ::-webkit-scrollbar-track {
            background: #f1f1f1;
        }

        ::-webkit-scrollbar-thumb {
            background: #888;
            border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: #555;
        }
        """

        let script = """
        var style = document.createElement('style');
        style.innerHTML = '\(css.replacingOccurrences(of: "\n", with: ""))';
        document.head.appendChild(style);
        """

        webView.evaluateJavaScript(script)
    }
}

// MARK: - EPUB Loader

struct EPUBLoader {
    /// 加载 EPUB 文件并返回可显示的 HTML URL
    static func loadEPUB(from url: URL) async throws -> URL {
        let cachesDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let tempDir = cachesDir.appendingPathComponent("AIReaderBooks").appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 解压 EPUB
        guard unzipEPUB(at: url, to: tempDir) else {
            throw EPUBError.unzipFailed
        }

        // 查找并处理 OPF 文件
        print("DEBUG: Looking for OPF in \(tempDir.path)")
        let opfURL = try findOPFFile(in: tempDir)
        print("DEBUG: Found OPF at \(opfURL.path)")

        // 生成增强版的 HTML 文件用于显示
        let htmlURL = try generateHTMLContent(opfURL: opfURL, outputDir: tempDir)
        print("DEBUG: Generated HTML at \(htmlURL.path)")
        
        // Verify HTML content
        let htmlSize = (try? FileManager.default.attributesOfItem(atPath: htmlURL.path)[.size] as? Int64) ?? 0
        print("DEBUG: HTML file size: \(htmlSize) bytes")

        return htmlURL
    }

    private static func unzipEPUB(at sourceURL: URL, to destinationURL: URL) -> Bool {
        print("DEBUG: Unzipping \(sourceURL.path) to \(destinationURL.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", sourceURL.path, "-d", destinationURL.path] // Added -o for overwrite

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("DEBUG: Unzip output: \(output)")
            }
            
            print("DEBUG: Unzip termination status: \(process.terminationStatus)")
            
            // Log directory contents
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationURL.path) {
                print("DEBUG: Destination content count: \(contents.count)")
                if contents.count < 10 {
                    print("DEBUG: Contents: \(contents)")
                }
            } else {
                print("DEBUG: Failed to list destination directory details")
            }
            
            return process.terminationStatus == 0
        } catch {
            print("DEBUG: EPUB 解压失败: \(error.localizedDescription)")
            return false
        }
    }

    private static func findOPFFile(in tempDir: URL) throws -> URL {
        // 首先检查 container.xml
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        if let containerContent = try? String(contentsOf: containerPath, encoding: .utf8) {
            if let range = containerContent.range(of: "full-path=\"([^\"]+)\"", options: .regularExpression) {
                let match = String(containerContent[range])
                let relativePath = match
                    .replacingOccurrences(of: "full-path=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                let opfURL = tempDir.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: opfURL.path) {
                    return opfURL
                }
            }
        }

        // 尝试常见路径
        let possiblePaths = [
            tempDir.appendingPathComponent("OEBPS/content.opf"),
            tempDir.appendingPathComponent("OPS/content.opf"),
            tempDir.appendingPathComponent("content.opf"),
            tempDir.appendingPathComponent("OEBPS/package.opf"),
            tempDir.appendingPathComponent("OPS/package.opf"),
            tempDir.appendingPathComponent("package.opf")
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path.path) {
            return path
        }

        throw EPUBError.opfNotFound
    }

    private static func generateHTMLContent(opfURL: URL, outputDir: URL) throws -> URL {
        let opfContent = try String(contentsOf: opfURL, encoding: .utf8)
        let baseURL = opfURL.deletingLastPathComponent()

        // 提取元数据
        let title = extractMetadata(from: opfContent, tag: "dc:title") ?? "EPUB Book"
        let author = extractMetadata(from: opfContent, tag: "dc:creator") ?? "Unknown Author"

        // 提取 manifest 和 spine
        let manifest = extractManifest(from: opfContent, baseURL: baseURL)
        let spineOrder = extractSpineOrder(from: opfContent)

        // 按照 spine 顺序排列章节
        var spineItems: [(url: URL, title: String?, id: String)] = []
        for itemId in spineOrder {
            if let item = manifest[itemId] {
                spineItems.append(item)
            }
        }

        // 添加 manifest 中剩余的项目
        for (id, item) in manifest {
            if !spineOrder.contains(id) {
                spineItems.append(item)
            }
        }

        // 解析目录（NCX 或 Nav）
        let tableOfContents = extractTableOfContents(from: opfContent, baseURL: baseURL, manifest: manifest, spineOrder: spineOrder)

        // 收集所有 CSS 文件
        let cssFiles = extractCSSFiles(from: opfContent, baseURL: baseURL, manifest: manifest)

        // 生成 HTML
        var html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
        """

        // 添加原始 CSS 链接
        for cssFile in cssFiles {
            let relativePath = cssFile.relativePath(from: baseURL)
            html += """
            <link rel="stylesheet" href="\(relativePath)">
            """
        }

        // 添加内联样式
        html += """
        <style>
            :root {
                --bg-color: #fdfbf7;
                --text-color: #333333;
                --text-color: #333333;
                --accent-color: #8b6b61;
                --hover-bg: #ffffff;
                --selection-bg: #b3d9ff;
                --timeline-bg: #f9f9f9;
                --timeline-text: #444444;
                --sidebar-width: 300px;
            }

            * { box-sizing: border-box; }
            
            body {
                font-family: 'Charter', 'Iowan Old Style', 'Palatino Linotype', 'Times New Roman', Serif;
                line-height: 1.8;
                font-size: 18px;
                margin: 0;
                padding: 0;
                color: var(--text-color);
                background-color: var(--bg-color);
                -webkit-font-smoothing: antialiased;
            }

            /* 沉浸式阅读布局 */
            /* 沉浸式阅读布局 */
            .epub-container {
                max-width: 42rem; /* 约 672px，最佳阅读宽度 */
                margin: 0 auto;
                padding: 40px 20px 100px 20px;
                background-color: var(--bg-color);
            }

            /* 顶部标题栏（滚动时隐藏） */
            .epub-header {
                text-align: center;
                margin-bottom: 60px;
                padding-bottom: 20px;
                border-bottom: 1px solid rgba(0,0,0,0.05);
            }

            .epub-header h1 {
                margin: 0 0 10px 0;
                font-size: 2.2em;
                font-weight: 700;
                letter-spacing: -0.02em;
                color: #222;
            }

            .epub-header .author {
                font-style: italic;
                color: #666;
                font-family: -apple-system, system-ui, sans-serif;
                font-size: 14px;
            }
            
            /* 章节样式 */
            .chapter {
                margin-bottom: 80px;
            }

            .chapter h1, .chapter h2, .chapter h3 {
                margin-top: 2em;
                margin-bottom: 1em;
                line-height: 1.3;
                font-weight: 600;
                color: #222;
            }

            .chapter p {
                margin-bottom: 1.5em;
                text-align: justify;
                hyphens: auto;
            }
            
            /* 图片样式 */
            .chapter img {
                max-width: 100%;
                height: auto;
                display: block;
                margin: 30px auto;
                border-radius: 4px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            }
            
            /* UI 控件容器 */
            .ui-controls {
                position: fixed;
                top: 20px;
                right: 20px;
                display: flex;
                gap: 12px;
                z-index: 1000;
            }

            /* 按钮通用样式 */
            .icon-btn {
                background: white;
                color: #555;
                border: 1px solid rgba(0,0,0,0.1);
                border-radius: 50%;
                width: 40px;
                height: 40px;
                font-size: 18px;
                cursor: pointer;
                box-shadow: 0 2px 8px rgba(0,0,0,0.05);
                transition: all 0.2s ease;
                display: flex;
                align-items: center;
                justify-content: center;
            }
            
            .icon-btn:hover {
                transform: translateY(-2px);
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
                color: black;
            }

            /* 目录侧边栏 */
            .toc-sidebar {
                position: fixed;
                top: 0;
                right: -320px; /* 隐藏 */
                width: var(--sidebar-width);
                height: 100vh;
                background: rgba(255, 255, 255, 0.95);
                backdrop-filter: blur(20px);
                -webkit-backdrop-filter: blur(20px);
                box-shadow: -10px 0 30px rgba(0,0,0,0.05);
                transition: transform 0.3s cubic-bezier(0.4, 0.0, 0.2, 1);
                z-index: 1001;
                display: flex;
                flex-direction: column;
            }

            .toc-sidebar.open {
                transform: translateX(-320px);
            }
            
            .toc-header {
                padding: 20px;
                border-bottom: 1px solid rgba(0,0,0,0.05);
                display: flex;
                align-items: center;
                justify-content: space-between;
            }
            
            .toc-header h2 {
                margin: 0;
                font-size: 18px;
                font-weight: 600;
                font-family: -apple-system, system-ui, sans-serif;
            }
            
            .toc-close {
                background: none;
                border: none;
                font-size: 20px;
                cursor: pointer;
                color: #999;
                padding: 0;
            }
            
            .toc-close:hover {
                color: #333;
            }

            .toc-content {
                flex: 1;
                overflow-y: auto;
                padding: 10px 0;
            }
            
            .toc-list {
                list-style: none;
                padding: 0;
                margin: 0;
            }

            .toc-list li {
                margin: 0;
            }

            .toc-list a {
                display: block;
                padding: 10px 24px;
                color: #444;
                text-decoration: none;
                font-size: 15px;
                font-family: -apple-system, system-ui, sans-serif;
                border-left: 3px solid transparent;
                transition: all 0.2s;
            }

            .toc-list a:hover {
                background: rgba(0,0,0,0.03);
                color: #000;
            }
            
            /* 各级目录缩进 */
            .toc-level-1 a { font-weight: 500; }
            .toc-level-2 a { padding-left: 36px; font-size: 14px; color: #666; }
            .toc-level-3 a { padding-left: 48px; font-size: 13px; color: #888; }
            
            /* AI Reader 高亮样式 */
            .ai-reader-highlight {
                background-color: rgba(255, 230, 0, 0.3);
                border-bottom: 2px solid rgba(255, 200, 0, 0.6);
                cursor: pointer;
            }
            
            /* 响应式调整 */
            @media (max-width: 768px) {
                body { font-size: 16px; }
                .epub-container { padding: 20px 20px 80px 20px; }
            }
        </style>
        </head>
        <body>
            <div class="ui-controls">
                <button class="icon-btn" onclick="toggleTOC()" title="目录">☰</button>
                <button class="icon-btn" onclick="scrollToTop()" title="返回顶部">↑</button>
            </div>

            <aside class="toc-sidebar" id="tocSidebar">
                <div class="toc-header">
                    <h2>目录</h2>
                    <button class="toc-close" onclick="toggleTOC()">×</button>
                </div>
                <div class="toc-content">
                    <ul class="toc-list">
        """

        // 添加目录项
        for tocItem in tableOfContents {
            html += generateTOCItem(tocItem, baseURL: baseURL)
        }

        html += """
                    </ul>
                </div>
            </aside>

            <main class="epub-container">
                <div class="epub-header">
                    <h1>\(title)</h1>
                    <div class="author">\(author)</div>
                </div>
        """

        // 添加章节内容
        for (index, item) in spineItems.enumerated() {
            // 使用 spine id 作为锚点，确保唯一性
            let anchorId = "chapter-\(index)"
            html += """
            <div class="chapter" id="\(anchorId)" data-original-href="\(item.url.relativePath(from: baseURL))">
            """

            // 读取并处理章节内容
            if let itemContent = try? String(contentsOf: item.url, encoding: .utf8) {
                let bodyContent = extractBodyContent(from: itemContent, baseURL: baseURL)
                html += bodyContent
            } else {
                html += "<p>内容加载失败</p>"
            }

            html += """
            </div>
            """
        }

        html += """
            </main>

            <script>
                function toggleTOC() {
                    document.getElementById('tocSidebar').classList.toggle('open');
                }

                function scrollToTop() {
                    window.scrollTo({ top: 0, behavior: 'smooth' });
                }
                
                // 导航到章节
                function navigateToChapter(href) {
                    console.log("Navigating to: " + href);
                    
                    // 1. 尝试直接通过 ID 查找（如果是 ID 链接）
                    if (href.startsWith('#')) {
                        const element = document.querySelector(href);
                        if (element) {
                            element.scrollIntoView({ behavior: 'smooth', block: 'start' });
                            return;
                        }
                    } else {
                        // Prevent navigation if it looks like a file path but we are in index.html
                        // Only scroll to the chapter
                        
                        const parts = href.split('#');
                        const filePath = parts[0];
                        const anchor = parts.length > 1 ? parts[1] : null;
                        
                        // 查找匹配文件路径的章节容器
                        const chapters = document.querySelectorAll('.chapter');
                        for (const chapter of chapters) {
                            // Check exact match or if chapter href ends with the file path
                            // This handles differences like "text/part001.html" vs "part001.html"
                            if (chapter.dataset.originalHref === filePath || 
                                chapter.dataset.originalHref.endsWith(filePath) ||
                                filePath.endsWith(chapter.dataset.originalHref)) {
                                
                                if (anchor) {
                                    // 如果有锚点，在章节内部查找 ID
                                    // Use CSS.escape just in case
                                    const target = chapter.querySelector('#' + anchor);
                                    if (target) {
                                        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                        return;
                                    }
                                }
                                // 否则滚动到章节顶部
                                chapter.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                return;
                            }
                        }
                    }
                    
                    console.log("Navigation target not found for: " + href);
                    // Do NOT fallback to window.location = href, as that breaks the view
                    
                    // 2. 尝试通过 data-original-href 匹配章节 (处理跨文件链接)
                    // href 可能是 "part001.html" 或 "part001.html#section1"
                    
                    const parts = href.split('#');
                    const filePath = parts[0];
                    const anchor = parts.length > 1 ? parts[1] : null;
                    
                    // 查找匹配文件路径的章节容器
                    const chapters = document.querySelectorAll('.chapter');
                    for (const chapter of chapters) {
                        if (chapter.dataset.originalHref === filePath) {
                            if (anchor) {
                                // 如果有锚点，在章节内部查找 ID
                                const target = chapter.querySelector('#' + anchor);
                                if (target) {
                                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                    return;
                                }
                            }
                            // 否则滚动到章节顶部
                            chapter.scrollIntoView({ behavior: 'smooth', block: 'start' });
                            return;
                        }
                    }
                    
                    console.log("Navigation target not found");
                }

                // 点击目录外部关闭侧边栏
                document.addEventListener('click', function(event) {
                    const sidebar = document.getElementById('tocSidebar');
                    const toggle = document.querySelector('.icon-btn[onclick="toggleTOC()"]');
                    if (!sidebar.contains(event.target) && !toggle.contains(event.target)) {
                        sidebar.classList.remove('open');
                    }
                });
            </script>
        </body>
        </html>
        """

        let htmlURL = outputDir.appendingPathComponent("index.html")
        try html.write(to: htmlURL, atomically: true, encoding: String.Encoding.utf8)
        
        print("DEBUG: Generated HTML header: \(html.prefix(200).replacingOccurrences(of: "\n", with: " "))")
        print("DEBUG: HTML Length: \(html.count)")

        return htmlURL
    }

    private static func generateTOCItem(_ item: TOCItem, baseURL: URL) -> String {
        var html = ""
        let levelClass = "toc-level-\(min(item.level, 3))"

        if let href = item.href {
            // 处理相对路径
            let fullURL = baseURL.appendingPathComponent(href)
            let relativePath = fullURL.relativePath(from: baseURL)

            // 提取锚点（如果有）
            let anchor: String
            if let anchorIndex = href.firstIndex(of: "#") {
                anchor = String(href[anchorIndex...])
            } else {
                anchor = ""
            }
            
            // 构造传递给 navigateToChapter 的路径
            // 注意：这里我们传递原始相对路径，让 JS 去匹配 data-original-href
            let navPath = relativePath.isEmpty ? anchor : relativePath + anchor

            // 使用 onclick 调用 navigateToChapter
            html += """
            <li class="\(levelClass)">
                <a href="javascript:void(0)" onclick="navigateToChapter('\(navPath)'); toggleTOC(); return false;">
                    \(item.title)
                </a>
            </li>
            """
        } else {
             // 没有链接的目录项（可能是分组标题）
             html += """
             <li class="\(levelClass)">
                 <span style="display:block; padding:10px 24px; color:#999; font-size:14px;">\(item.title)</span>
             </li>
             """
        }

        // 递归生成子目录
        if !item.children.isEmpty {
            for child in item.children {
                html += generateTOCItem(child, baseURL: baseURL)
            }
        }

        return html
    }
    
    // MARK: - Helper Methods

    private static func extractMetadata(from opf: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let range = opf.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let match = String(opf[range])
        return match.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractManifest(from opf: String, baseURL: URL) -> [String: (url: URL, title: String?, id: String)] {
        var manifest: [String: (url: URL, title: String?, id: String)] = [:]

        let manifestPattern = "<item[^>]*>"
        let matches = opf.epubMatches(for: manifestPattern)

        for match in matches {
            var id: String?
            var href: String?

            // 提取 id
            if let idRange = match.range(of: "id=\"([^\"]+)\"", options: .regularExpression) {
                id = String(match[idRange])
                    .replacingOccurrences(of: "id=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }

            // 提取 href
            if let hrefRange = match.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                href = String(match[hrefRange])
                    .replacingOccurrences(of: "href=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .removingPercentEncoding
            }

            if let itemId = id, let itemHref = href {
                let itemURL = baseURL.appendingPathComponent(itemHref)
                let title = extractTitleFromHref(itemHref)
                manifest[itemId] = (itemURL, title, itemId)
            }
        }

        return manifest
    }

    private static func extractSpineOrder(from opf: String) -> [String] {
        var order: [String] = []

        let spinePattern = "<itemref[^>]*>"
        let matches = opf.epubMatches(for: spinePattern)

        for match in matches {
            if let idrefRange = match.range(of: "idref=\"([^\"]+)\"", options: .regularExpression) {
                let idref = String(match[idrefRange])
                    .replacingOccurrences(of: "idref=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                order.append(idref)
            }
        }

        return order
    }

    private static func extractCSSFiles(from opf: String, baseURL: URL, manifest: [String: (url: URL, title: String?, id: String)]) -> [URL] {
        var cssFiles: [URL] = []

        let manifestPattern = "<item[^>]*>"
        let matches = opf.epubMatches(for: manifestPattern)

        for match in matches {
            // 检查是否是 CSS 文件
            if match.contains("media-type=\"text/css\"") ||
               match.lowercased().contains(".css") {
                if let hrefRange = match.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                    let href = String(match[hrefRange])
                        .replacingOccurrences(of: "href=\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .removingPercentEncoding ?? ""

                    let cssURL = baseURL.appendingPathComponent(href)
                    if FileManager.default.fileExists(atPath: cssURL.path) {
                        cssFiles.append(cssURL)
                    }
                }
            }
        }

        return cssFiles
    }

    private static func extractTableOfContents(from opf: String, baseURL: URL, manifest: [String: (url: URL, title: String?, id: String)], spineOrder: [String]) -> [TOCItem] {
        print("DEBUG: OPF Content (first 1000 chars): \(opf.prefix(1000))")
        var tocItems: [TOCItem] = []

        // 1. 尝试通过 spine toc 属性找到 NCX ID (标准 EPUB 2)
        var ncxHref: String?
        if let spineMatch = opf.range(of: "<spine[^>]*toc=\"([^\"]+)\"", options: .regularExpression) {
            let spineTag = String(opf[spineMatch])
            if let idRange = spineTag.range(of: "toc=\"([^\"]+)\"", options: .regularExpression) {
                let id = String(spineTag[idRange])
                    .replacingOccurrences(of: "toc=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                
                // Find item with this ID in manifest
                let itemPattern = "<item[^>]*id=\"\(id)\"[^>]*href=\"([^\"]+)\"[^>]*>"
                if let itemMatch = opf.range(of: itemPattern, options: .regularExpression) {
                    let itemTag = String(opf[itemMatch])
                    if let hrefRange = itemTag.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                        ncxHref = String(itemTag[hrefRange])
                            .replacingOccurrences(of: "href=\"", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                            .removingPercentEncoding
                    }
                }
            }
        }

        // 2. 如果方法 1 失败，尝试旧的 MIME 类型搜索
        if ncxHref == nil {
            let ncxPattern = "<item[^>]*media-type=\"application/x-dtbncx\\+xml\"[^>]*>"
            if let ncxMatch = opf.range(of: ncxPattern, options: [.regularExpression, .caseInsensitive]) {
                let ncxItem = String(opf[ncxMatch])
                if let hrefRange = ncxItem.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                    ncxHref = String(ncxItem[hrefRange])
                        .replacingOccurrences(of: "href=\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .removingPercentEncoding
                }
            }
        }
        
        if let href = ncxHref {
             let ncxURL = baseURL.appendingPathComponent(href)
             print("DEBUG: Found NCX at \(ncxURL)")
             if let ncxContent = try? String(contentsOf: ncxURL, encoding: .utf8) {
                 tocItems = parseNCX(ncxContent, baseURL: baseURL)
                 print("DEBUG: Parsed NCX, found \(tocItems.count) items")
                 if !tocItems.isEmpty {
                     return tocItems
                 }
             } else {
                 print("DEBUG: Failed to read NCX content")
             }
        } else {
             print("DEBUG: No NCX file found in OPF (using multiple methods)")
        }

        // 如果 NCX 失败，尝试解析 Nav 文件
        let navPattern = "<item[^>]*properties=\"[^\"]*nav[^\"]*\"[^>]*>"
        if let navMatch = opf.range(of: navPattern, options: .regularExpression) {
            print("DEBUG: Found Nav item match")
            let navItem = String(opf[navMatch])
            if let hrefRange = navItem.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
                let href = String(navItem[hrefRange])
                    .replacingOccurrences(of: "href=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .removingPercentEncoding ?? ""

                let navURL = baseURL.appendingPathComponent(href)
                if let navContent = try? String(contentsOf: navURL, encoding: .utf8) {
                    tocItems = parseNav(navContent, baseURL: baseURL)
                    if !tocItems.isEmpty {
                        return tocItems
                    }
                }
            }
        }

        // 如果都失败了，从 spine 和 manifest 生成简单目录
        // 使用 spineOrder 保证顺序
        for id in spineOrder {
            if let item = manifest[id],
               (item.url.pathExtension.lowercased() == "html" || item.url.pathExtension.lowercased() == "xhtml") {
                
                // 尝试从文件内容中提取标题
                var title = item.title ?? "Chapter"
                
                // Check for generic or generated titles
                let isGenericTitle = title == "Chapter" || 
                                   title.hasSuffix(".html") || 
                                   title.hasSuffix(".xhtml") || 
                                   title.lowercased().hasPrefix("part") || 
                                   title.lowercased().hasPrefix("section") ||
                                   (Int(title) != nil) ||
                                   title.count < 3
                                   
                if isGenericTitle {
                    if let content = try? String(contentsOf: item.url, encoding: .utf8) {
                        if let extracted = extractTitleFromHTMLContent(content) {
                            title = extracted
                        }
                    }
                }
                tocItems.append(TOCItem(title: title, href: item.url.relativePath(from: baseURL), level: 1, children: []))
            }
        }
        
        // 如果仍然为空，使用 Manifest 填充
        if tocItems.isEmpty {
             let sortedManifest = manifest.values.sorted { $0.id < $1.id }
             for item in sortedManifest {
                 if item.url.pathExtension.lowercased() == "html" || item.url.pathExtension.lowercased() == "xhtml" {
                     var title = item.id
                     // Aggressively try to extract title for manifest fallbacks
                     if let content = try? String(contentsOf: item.url, encoding: .utf8) {
                         if let extracted = extractTitleFromHTMLContent(content) {
                             title = extracted
                         }
                     }
                     tocItems.append(TOCItem(title: title, href: item.url.relativePath(from: baseURL), level: 1, children: []))
                 }
             }
        }

        return tocItems
    }
    
    /// 从 HTML 内容中提取标题
    private static func extractTitleFromHTMLContent(_ html: String) -> String? {
        // 只检查文件前 5000 个字符，提高性能
        let prefix = String(html.prefix(5000))
        
        // 1. Try h1 with any attributes
        if let range = prefix.range(of: "<h1[^>]*>([^<]+)</h1>", options: [.regularExpression, .caseInsensitive]) {
            let match = String(prefix[range])
            // Extract text content inside tags
            if let textRange = match.range(of: ">([^<]+)<", options: .regularExpression) {
                let text = String(match[textRange]).dropFirst().dropLast()
                return String(text).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 2. Try title tag
        if let range = prefix.range(of: "<title[^>]*>([^<]+)</title>", options: [.regularExpression, .caseInsensitive]) {
            let match = String(prefix[range])
             if let textRange = match.range(of: ">([^<]+)<", options: .regularExpression) {
                let text = String(match[textRange]).dropFirst().dropLast()
                return String(text).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 3. Try h2 with any attributes
        if let range = prefix.range(of: "<h2[^>]*>([^<]+)</h2>", options: [.regularExpression, .caseInsensitive]) {
            let match = String(prefix[range])
             if let textRange = match.range(of: ">([^<]+)<", options: .regularExpression) {
                let text = String(match[textRange]).dropFirst().dropLast()
                return String(text).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }

    // MARK: - XML Parser for NCX/Nav
    
    private static func parseNCX(_ ncxContent: String, baseURL: URL) -> [TOCItem] {
        let parser = ImprovedNCXParser(baseURL: baseURL)
        return parser.parse(xml: ncxContent)
    }

    private static func parseNav(_ navContent: String, baseURL: URL) -> [TOCItem] {
        // Simple regex fallback for Nav documents (HTML5) is usually okay, but let's improve it slightly
        // to handle attributes better.
        // For now, regex is acceptable for Nav as it's standard HTML structure.
        return parseNavRegex(navContent, baseURL: baseURL)
    }
    
    // MARK: - Legacy Regex Nav Parser (Renamed)
    private static func parseNavRegex(_ navContent: String, baseURL: URL) -> [TOCItem] {
        var tocItems: [TOCItem] = []

        let olPattern = "<ol[^>]*>.*?</ol>"
        // NSRegularExpression.Options.dotMatchesLineSeparators is only for NSRegularExpression init, not String.range(of:options:)
        // But for String.range we can use standard regex. To match dot across lines we use [\s\S] or (?s)
        
        if let olRange = navContent.range(of: olPattern, options: [.regularExpression]) { // Simplified options
            let olContent = String(navContent[olRange])

            let liPattern = "<li[^>]*>.*?</li>"
            let matches = olContent.epubMatches(for: liPattern, options: .dotMatchesLineSeparators)

            for match in matches {
                var title = extractNavTitle(from: match)
                if Int(title) != nil || title.count < 3 {
                    // Try to get title from href file if missing
                    if let href = extractNavHref(from: match) {
                         // Logic to fallback to file content would go here
                    }
                }
                
                let href = extractNavHref(from: match)
                let level = extractNavLevel(from: match)

                let item = TOCItem(
                    title: title.isEmpty ? "Chapter" : title,
                    href: href?.removingPercentEncoding,
                    level: level,
                    children: []
                )
                tocItems.append(item)
            }
        }
        return tocItems
    }
}

// MARK: - Improved NCX XML Parser

class ImprovedNCXParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private var rootItems: [TOCItem] = []
    private var itemStack: [TOCMutableItem] = []
    
    private var currentElement: String = ""
    private var currentLabel: String = ""
    
    private class TOCMutableItem {
        var title: String = ""
        var href: String?
        var children: [TOCItem] = []
        var level: Int
        
        init(level: Int) { self.level = level }
        
        func toItem() -> TOCItem {
            return TOCItem(title: title, href: href, level: level, children: children)
        }
    }
    
    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }
    
    func parse(xml: String) -> [TOCItem] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return rootItems
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        
        if currentElement == "navpoint" {
            let level = itemStack.count + 1
            let newItem = TOCMutableItem(level: level)
            itemStack.append(newItem)
            currentLabel = ""
        } else if currentElement == "content" {
            if let src = attributeDict["src"] {
                itemStack.last?.href = src
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "text" {
            // Only capture text if we are inside a navLabel/text
             currentLabel += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        
        if element == "text" {
             itemStack.last?.title = currentLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if element == "navpoint" {
            if let completedItem = itemStack.popLast() {
                if itemStack.isEmpty {
                    rootItems.append(completedItem.toItem())
                } else {
                    itemStack.last?.children.append(completedItem.toItem())
                }
            }
        }
    }
}

// MARK: - EPUBLoader Helpers Extension

extension EPUBLoader {
    
    // MARK: - Nav Regex Helpers
    
    static func extractNavTitle(from li: String) -> String {
        let pattern = "<a[^>]*>([^<]+)</a>"
        if let range = li.range(of: pattern, options: .regularExpression) {
            let match = String(li[range])
            return match.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未命名"
    }

    static func extractNavHref(from li: String) -> String? {
        let pattern = "<a[^>]+href=\"([^\"]+)\"[^>]*>"
        if let range = li.range(of: pattern, options: .regularExpression) {
            let match = String(li[range])
            return match.replacingOccurrences(of: "[^>]+href=\"", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\".*", with: "", options: .regularExpression)
        }
        return nil
    }

    static func extractNavLevel(from li: String) -> Int {
        // 通过计算嵌套的 ol 标签来确定层级
        let depth = li.components(separatedBy: "<ol").count - 1
        return min(max(depth, 1), 3)
    }
    
    static func extractTitleFromHref(_ href: String) -> String? {
        let filename = URL(fileURLWithPath: href).deletingPathExtension().lastPathComponent
        return filename.capitalized
    }

    // MARK: - Content Extraction Helpers

    static func extractBodyContent(from html: String, baseURL: URL) -> String {
        var content = html

        // 提取 body 内容
        if let bodyRange = content.range(of: "<body[^>]*>([\\s\\S]+)</body>", options: .regularExpression) {
            content = String(content[bodyRange])
                .replacingOccurrences(of: "<body[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</body>", with: "")
        }

        // 修正相对路径
        content = fixRelativePaths(content, baseURL: baseURL)

        return content
    }

    static func fixRelativePaths(_ html: String, baseURL: URL) -> String {
        var content = html

        // 使用 NSRegularExpression 修正图片路径
        if let imgRegex = try? NSRegularExpression(pattern: "<img[^>]+src=\"([^\"]+)\"[^>]*>", options: []) {
            let imgRange = NSRange(content.startIndex..., in: content)
            let imgMatches = imgRegex.matches(in: content, options: [], range: imgRange)

            for match in imgMatches.reversed() {
                if let range = Range(match.range, in: content) {
                    let imgTag = String(content[range])
                    if let srcRegex = try? NSRegularExpression(pattern: "src=\"([^\"]+)\"", options: []),
                       let srcMatch = srcRegex.firstMatch(in: imgTag, options: [], range: NSRange(imgTag.startIndex..., in: imgTag)),
                       let srcRange = Range(srcMatch.range(at: 1), in: imgTag) {
                        let src = String(imgTag[srcRange])
                        if !src.hasPrefix("http://") && !src.hasPrefix("https://") && !src.hasPrefix("data:") {
                            let absolutePath = baseURL.appendingPathComponent(src)
                            let relativePath = absolutePath.relativePath(from: baseURL)
                            let newImgTag = imgTag.replacingOccurrences(of: "src=\"[^\"]+\"", with: "src=\"\(relativePath)\"", options: .regularExpression)
                            content.replaceSubrange(range, with: newImgTag)
                        }
                    }
                }
            }
        }

        // 使用 NSRegularExpression 修正链接路径
        if let linkRegex = try? NSRegularExpression(pattern: "<link[^>]+href=\"([^\"]+)\"[^>]*>", options: []) {
            let linkRange = NSRange(content.startIndex..., in: content)
            let linkMatches = linkRegex.matches(in: content, options: [], range: linkRange)

            for match in linkMatches.reversed() {
                if let range = Range(match.range, in: content) {
                    let linkTag = String(content[range])
                    if let hrefRegex = try? NSRegularExpression(pattern: "href=\"([^\"]+)\"", options: []),
                       let hrefMatch = hrefRegex.firstMatch(in: linkTag, options: [], range: NSRange(linkTag.startIndex..., in: linkTag)),
                       let hrefRange = Range(hrefMatch.range(at: 1), in: linkTag) {
                        let href = String(linkTag[hrefRange])
                        if !href.hasPrefix("http://") && !href.hasPrefix("https://") {
                            let absolutePath = baseURL.appendingPathComponent(href)
                            let relativePath = absolutePath.relativePath(from: baseURL)
                            let newLinkTag = linkTag.replacingOccurrences(of: "href=\"[^\"]+\"", with: "href=\"\(relativePath)\"", options: .regularExpression)
                            content.replaceSubrange(range, with: newLinkTag)
                        }
                    }
                }
            }
        }

        return content
    }
}

// MARK: - TOC Models

struct TOCItem {
    let title: String
    let href: String?
    let level: Int
    var children: [TOCItem]
}

enum EPUBError: Error {
    case unzipFailed
    case opfNotFound
}

// MARK: - String Extension

extension String {
    func epubMatches(for regex: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: options) else { return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        let matches = regex.matches(in: self, options: [], range: range)
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: self) else { return nil }
            return String(self[range])
        }
    }
}

// MARK: - URL Extension

extension URL {
    func relativePath(from base: URL) -> String {
        let pathComponents = self.pathComponents
        let baseComponents = base.pathComponents

        // 找出共同的路径前缀
        var commonIndex = 0
        while commonIndex < min(pathComponents.count, baseComponents.count) &&
              pathComponents[commonIndex] == baseComponents[commonIndex] {
            commonIndex += 1
        }

        // 构建相对路径
        let upLevelCount = max(0, baseComponents.count - commonIndex - 1)
        var relativeComponents = Array(repeating: "..", count: upLevelCount)
        relativeComponents.append(contentsOf: pathComponents[commonIndex...])

        return relativeComponents.joined(separator: "/")
    }

    // 将 String 的 epubMatches 作为静态方法
    static func makeRelativePath(from: URL, to: URL) -> String {
        return to.relativePath(from: from)
    }
}
