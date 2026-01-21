import Foundation
import WebKit

/// 文本选择信息
struct TextSelection {
    let text: String
    let cfi: String? // EPUB Canonical Fragment Identifier
    let rect: CGRect // 屏幕坐标
    let pageIndex: Int? // PDF 页码

    let isEmpty: Bool

    init(text: String, cfi: String? = nil, rect: CGRect = .zero, pageIndex: Int? = nil) {
        self.text = text
        self.cfi = cfi
        self.rect = rect
        self.pageIndex = pageIndex
        self.isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 发送给 JS 的聊天数据
struct ChatContextData: Codable {
    let id: String
    let text: String // Related text (paragraph or selection)
    let prompt: String // User's prompt
    let response: String? // AI's response
    let actionType: String // explain, summarize, translate
    let createdAt: Date
    let paragraphId: String? // 段落 ID，用于精准匹配
}

/// BridgeCoordinator - 处理 WKWebView 和原生代码之间的通信
@MainActor
final class BridgeCoordinator: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var currentSelection: TextSelection = .init(text: "")
    @Published var showHUD: Bool = false

    // MARK: - Callbacks

    var onSelectionChanged: ((TextSelection) -> Void)?
    var onScrollPositionChanged: ((String) -> Void)?
    var onShowQuickChat: ((String, CGPoint) -> Void)?
    var onDeleteChat: ((String) -> Void)?  // Callback for deleting a chat by ID
    
    // Cache for chat history to re-apply on navigation
    private var cachedChats: [ChatContextData] = []
    
    // Debounce for reinitialize calls
    private var reinitializeDebounceTask: Task<Void, Never>?
    
    // MARK: - WKNavigationDelegated: ((String) -> Void)?

    // MARK: - Private Properties

    private var debounceTimer: Timer?
    private var lastProcessedText: String = ""
    private weak var webView: WKWebView?  // 保持 WebView 引用用于坐标转换

    // MARK: - WKScriptMessageHandler

    func makeScriptMessageHandler() -> WKScriptMessageHandler {
        return ScriptMessageHandler(coordinator: self)
    }

    // MARK: - JavaScript Injection

    /// 注入文本选择监听脚本
    func injectSelectionHandler(into webView: WKWebView) {
        self.webView = webView  // 保存 WebView 引用

        let script = """
        // DEBUG: Script injection started
        console.log('[AIReader] Script injection started');

        // 监听文本选择
        document.addEventListener('selectionchange', function() {
            const selection = window.getSelection();
            const selectedText = selection.toString();

            if (selectedText.length > 0) {
                // 获取选中文本的边界矩形
                const range = selection.getRangeAt(0);
                const rect = range.getBoundingClientRect();

                // 生成简单的 CFI（对于完整实现需要使用 EPUB.js）
                const cfi = generateSimpleCFI(range);

                // 发送到 Swift（传递 WebView 内部坐标）
                window.webkit.messageHandlers.selectionHandler.postMessage({
                    text: selectedText,
                    cfi: cfi,
                    x: rect.left + window.scrollX,
                    y: rect.top + window.scrollY,
                    width: rect.width,
                    height: rect.height
                });
            }
        });
        
        // 监听滚动位置（防抖）
        let scrollTimeout;
        window.addEventListener('scroll', function() {
            clearTimeout(scrollTimeout);
            scrollTimeout = setTimeout(function() {
                reportScrollPosition();
            }, 500);
        });
        
        function reportScrollPosition() {
            const chapters = document.querySelectorAll('.chapter');
            for (const chapter of chapters) {
                const rect = chapter.getBoundingClientRect();
                // 如果章节顶部在视口上半部分，或者章节占据了整个视口
                if ((rect.top >= 0 && rect.top < window.innerHeight / 2) || (rect.top < 0 && rect.bottom > window.innerHeight / 2)) {
                    const href = chapter.dataset.originalHref;
                    if (href) {
                        window.webkit.messageHandlers.scrollHandler.postMessage({ href: href });
                    }
                    break;
                }
            }
        }

        // 简单的 CFI 生成函数
        function generateSimpleCFI(range) {
            try {
                const startContainer = range.startContainer;
                const startOffset = range.startOffset;
                const endOffset = range.endOffset;

                // 构建路径
                let path = [];
                let node = startContainer;

                while (node && node.nodeType !== Node.DOCUMENT_NODE) {
                    if (node.parentNode) {
                        const siblings = Array.from(node.parentNode.childNodes);
                        const index = siblings.indexOf(node);
                        path.unshift(index);
                    }
                    node = node.parentNode;
                }

                return '/epub-cfi:' + path.join('/') + '[' + startOffset + '-' + endOffset + ']';
            } catch (e) {
                return null;
            }
        }

        // 高亮选中的文本
        function highlightText(cfi, color) {
            try {
                const selection = window.getSelection();
                if (selection.rangeCount > 0) {
                    const range = selection.getRangeAt(0);
                    const span = document.createElement('span');
                    span.className = 'ai-reader-highlight';
                    span.style.backgroundColor = color || '#ffff00';
                    span.style.padding = '2px 0';

                    try {
                        range.surroundContents(span);
                    } catch (e) {
                        // 对于跨多个元素的选择，使用不同的方法
                        document.execCommand('hiliteColor', false, color || '#ffff00');
                    }
                }
                return true;
            } catch (e) {
                console.error('Highlight error:', e);
                return false;
            }
        }

        // 移除高亮
        function removeHighlight(cfi) {
            const highlights = document.querySelectorAll('.ai-reader-highlight');
            highlights.forEach(hl => {
                const parent = hl.parentNode;
                while (hl.firstChild) {
                    parent.insertBefore(hl.firstChild, hl);
                }
                parent.removeChild(hl);
            });
            return true;
        }

        // Render Inline Layout for Chat History
        function parseMarkdown(text) {
            if (!text) return '';
            // 1. Escape HTML
            let html = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            // 2. Bold (**text**)
            html = html.replace(/\\*\\*(.*?)\\*\\*/g, '<strong>$1</strong>');
            // 3. Italic (*text*)
            html = html.replace(/\\*(.*?)\\*/g, '<em>$1</em>');
            // 4. Code (`text`)
            html = html.replace(/`(.*?)`/g, '<code>$1</code>');
            // 5. Lists (- item) -> • item
            html = html.replace(/(?:^|\\n)-\\s+(.*)/g, '<br>• $1');
            // 6. Numbered Lists (1. item) -> 1. item
            html = html.replace(/(?:^|\\n)(\\d+\\.)\\s+(.*)/g, '<br>$1 $2');
            // 7. Headers
            html = html.replace(/(?:^|\\n)###\\s+(.*)/g, '<br><strong>$1</strong>');
            html = html.replace(/(?:^|\\n)##\\s+(.*)/g, '<br><strong style="font-size:1.1em">$1</strong>');
            // 8. Newlines
            html = html.replace(/\\n/g, '<br>');
            // Cleanup leading BRs
            if (html.startsWith('<br>')) html = html.substring(4);
            return html;
        }

        window.highlightChatHistory = function(chats) {
            console.log('Rendering Timeline for ' + (chats ? chats.length : 0) + ' chats...');
            if (!chats || chats.length === 0) return;

            // 1. Clear existing timelines
            document.querySelectorAll('.ai-timeline-container').forEach(el => el.remove());
            document.querySelectorAll('.ai-timeline-active').forEach(el => el.classList.remove('ai-timeline-active'));
            
            // Debug: Print all active paragraph IDs
            const paragraphs = Array.from(document.querySelectorAll('p'));
            const pIds = paragraphs.map(p => p.id).filter(id => id.startsWith('ai-p-'));
            console.log("DEBUG: Active Paragraph IDs (" + pIds.length + "): " + pIds.slice(0, 5).join(", ") + (pIds.length > 5 ? "..." : ""));

            chats.forEach(chat => {
                console.log("DEBUG: Processing chat for ID: " + chat.paragraphId);
                // Allow proceeding if we have an ID, even if text is missing (legacy data support)
                if ((!chat.text || chat.text.length < 2) && !chat.paragraphId) {
                    console.log("DEBUG: Skipping invalid chat (no text and no ID)");
                    return;
                }

                let targetP = null;

                // === PRIORITY 1: Use paragraphId for exact matching ===
                if (chat.paragraphId) {
                    targetP = document.getElementById(chat.paragraphId);
                    if (targetP) {
                        console.log("✓ ID Match: " + chat.paragraphId);
                    } else {
                        // === PRIORITY 1.5: Bridge Matching for Legacy IDs ===
                        // Old format: ai-p-{fullMD5}-{globalIdx}  e.g. ai-p-79e323a007d0bf6d18abaf067bb5063d-64
                        // New format: ai-p-{chapterHash8}-{idx}-{contentHash8}  e.g. ai-p-85cff1c8-0-c8e22982
                        // Bridge: Extract first 8 chars of old MD5 and match against contentHash8 suffix
                        const oldFormatMatch = chat.paragraphId.match(/^ai-p-([0-9a-f]{32})-\\d+$/);
                        if (oldFormatMatch) {
                            const oldContentHashPrefix = oldFormatMatch[1].substring(0, 8);
                            console.log("DEBUG: Attempting bridge match with contentHash prefix: " + oldContentHashPrefix);
                            
                            // Search for paragraph ending with this contentHash
                            for (const p of paragraphs) {
                                if (p.id && p.id.endsWith('-' + oldContentHashPrefix)) {
                                    targetP = p;
                                    console.log("✓ Bridge Match: " + chat.paragraphId + " -> " + p.id);
                                    break;
                                }
                            }
                            
                            if (!targetP) {
                                console.log("DEBUG: Bridge match failed for " + chat.paragraphId + ". Chapter may have changed.");
                                return; // Skip text fallback for structured IDs
                            }
                        } else {
                            // New format ID not found - skip silently
                            const newFormatMatch = chat.paragraphId.match(/^ai-p-[0-9a-f]{8}-\\d+-[0-9a-f]{8}$/);
                            if (newFormatMatch) {
                                console.log("DEBUG: New format ID " + chat.paragraphId + " not found. Skipping.");
                                return;
                            }
                            // Unknown format - try text fallback
                            console.log("⚠ Unknown ID format: " + chat.paragraphId + ", falling back to text match");
                        }
                    }
                }

                // === PRIORITY 2: Fallback to text matching (ONLY for legacy/missing IDs) ===
                if (!targetP) {
                    // DATA CLEANUP: Remove potential button text from legacy data
                    let rawChatText = chat.text;
                    ["解释", "总结", "翻译", "分析", "explain", "summarize", "translate", "analyze"].forEach(token => {
                         if (rawChatText.endsWith(token)) {
                             rawChatText = rawChatText.substring(0, rawChatText.length - token.length).trim();
                         }
                    });

                    const chatTextNorm = rawChatText.replace(/\\s+/g, '').toLowerCase();

                    if (chatTextNorm.length < 2) {
                        console.log("DEBUG: Skipping text match - text too short");
                    } else {
                        for (const p of paragraphs) {
                            // Extract clean text from P (ignore buttons)
                            let pText = "";
                            for (const node of p.childNodes) {
                                if (node.nodeType === Node.TEXT_NODE) {
                                    pText += node.textContent;
                                } else if (node.nodeType === Node.ELEMENT_NODE && !node.classList.contains('ai-paragraph-actions')) {
                                    pText += node.textContent;
                                }
                            }

                            const pTextNorm = pText.replace(/\\s+/g, '').toLowerCase();

                            if (pTextNorm.length < 5) continue; // Skip too short paragraphs

                            // 1. Exact or P contains Chat (Chat is a selection)
                            if (pTextNorm.includes(chatTextNorm)) {
                                targetP = p;
                                console.log("✓ Text Match: " + p.id);
                                break;
                            }

                            // 2. Chat contains P (Chat is full paragraph + extra/dirty)
                            if (pTextNorm.length > 10 && chatTextNorm.includes(pTextNorm)) {
                                targetP = p;
                                console.log("✓ Fuzzy Text Match: " + p.id);
                                break;
                            }
                        }
                    }

                    if (!targetP) {
                        console.log("✗ Match failed for: " + chatTextNorm.substring(0, 30));
                    }
                }

                if (targetP) {
                    // Add timeline marker if not already present
                    if (!targetP.querySelector('.ai-timeline-marker')) {
                        const marker = document.createElement('div');
                        marker.className = 'ai-timeline-marker';
                        marker.title = '此段落有 AI 对话记录';
                        marker.onclick = (e) => {
                            e.stopPropagation();
                            toggleTimeline(targetP);
                        };
                        targetP.appendChild(marker);
                    }
                    targetP.classList.add('has-timeline');

                    // Find or create timeline container SPECIFIC to this paragraph
                    // CRITICAL: Must check data-paragraph-id to avoid mixing content from different paragraphs
                    let timeline = null;
                    let sibling = targetP.nextElementSibling;
                    
                    // Only look at IMMEDIATE next sibling - don't traverse beyond
                    if (sibling && sibling.classList.contains('ai-timeline-container') && sibling.dataset.paragraphId === targetP.id) {
                        timeline = sibling;
                    }
                    
                    // If no matching container found, create a new one
                    if (!timeline) {
                        timeline = document.createElement('div');
                        timeline.className = 'ai-timeline-container';
                        timeline.dataset.paragraphId = targetP.id;
                        targetP.parentNode.insertBefore(timeline, targetP.nextSibling);
                    }
                    
                    // Create chat item
                    const item = document.createElement('div');
                    item.className = 'ai-chat-item';
                    item.dataset.chatId = chat.id; // Store chat ID for deletion
                    
                    // Delete button (hidden by default, shown on hover)
                    const deleteBtn = document.createElement('button');
                    deleteBtn.className = 'ai-chat-delete-btn';
                    deleteBtn.innerHTML = '×';
                    deleteBtn.title = '删除此记录';
                    deleteBtn.onclick = function(e) {
                        e.stopPropagation();
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.deleteChatMessage) {
                            window.webkit.messageHandlers.deleteChatMessage.postMessage(chat.id);
                        }
                    };
                    
                    // Action Label
                    const meta = document.createElement('div');
                    meta.className = 'ai-chat-action';
                    meta.textContent = chat.actionType || 'Chat';
                    
                    // AI Response Bubble
                    const bubble = document.createElement('div');
                    bubble.className = 'ai-chat-bubble';
                    
                    const responseText = chat.response || "(No response saved)";
                    
                    if (responseText.includes('<think>')) {
                        const parts = responseText.split('</think>');
                        if (parts.length > 1) {
                           const thinking = parts[0].replace('<think>', '');
                           const content = parts[1];
                           const contentHtml = parseMarkdown(content);
                           bubble.innerHTML = `<div style="color:#888;font-size:0.9em;margin-bottom:8px;padding-bottom:4px;border-bottom:1px solid #eee">Thinking...</div><div>${contentHtml}</div>`;
                        } else {
                           bubble.innerHTML = parseMarkdown(responseText);
                        }
                    } else {
                        bubble.innerHTML = parseMarkdown(responseText);
                    }
                    
                    item.appendChild(deleteBtn);
                    item.appendChild(meta);
                    item.appendChild(bubble);
                    timeline.appendChild(item);
                    
                    targetP.classList.add('ai-timeline-active');
                    timeline.style.display = 'block';
                }
            });
        };
        
        // 注入 CSS 样式用于段落交互和时间轴
        const historyStyle = document.createElement('style');
        historyStyle.innerHTML = `
            /* 段落交互样式 */
            p.ai-paragraph-hover {
                transform: scale(1.005);
                box-shadow: 0 2px 12px rgba(0,0,0,0.05);
                background-color: var(--hover-bg, rgba(250, 250, 250, 0.95));
                border-radius: 4px;
                transition: all 0.2s ease-out;
                position: relative;
                z-index: 10;
                cursor: pointer;
            }
            
            p {
                transition: transform 0.2s, box-shadow 0.2s, background-color 0.2s;
                position: relative;
            }

            /* 快捷操作按钮容器 */
            .ai-paragraph-actions {
                position: absolute;
                right: 0;
                top: -36px;
                display: flex;
                gap: 6px;
                padding: 4px 0 8px 0;
                opacity: 0;
                transform: translateY(5px);
                transition: all 0.2s;
                pointer-events: none;
                z-index: 20;
            }

            p.ai-paragraph-hover .ai-paragraph-actions {
                opacity: 1;
                transform: translateY(0);
                pointer-events: auto;
            }

            .ai-action-btn {
                background: #333;
                color: white;
                border: none;
                border-radius: 4px;
                padding: 4px 10px;
                font-size: 12px;
                font-family: -apple-system, system-ui;
                cursor: pointer;
                box-shadow: 0 2px 6px rgba(0,0,0,0.1);
                white-space: nowrap;
            }
            
            .ai-action-btn:hover {
                background: #000;
                transform: translateY(-1px);
            }

            /* 聊天记录时间轴区域 */
            .ai-timeline-container {
                margin: 10px 0 30px 10px;
                border-left: 2px solid #eee;
                padding-left: 15px;
                display: none;
                animation: slideDown 0.3s ease-out forwards;
            }
            
            @keyframes slideDown {
                from { opacity: 0; transform: translateY(-5px); }
                to { opacity: 1; transform: translateY(0); }
            }

            .ai-chat-item {
                margin-bottom: 12px;
                position: relative;
            }
            
            .ai-chat-item::before {
                content: '';
                position: absolute;
                left: -22px; 
                top: 6px;
                width: 8px;
                height: 8px;
                background: #8b6b61;
                border-radius: 50%;
                border: 2px solid white;
                box-shadow: 0 0 0 1px #eee;
            }
            
            /* Delete Button - hidden by default, shown on hover */
            .ai-chat-delete-btn {
                position: absolute;
                top: 4px;
                right: 4px;
                width: 20px;
                height: 20px;
                border: none;
                background: rgba(220, 53, 69, 0.8);
                color: white;
                border-radius: 50%;
                font-size: 14px;
                font-weight: bold;
                cursor: pointer;
                opacity: 0;
                transition: opacity 0.2s ease, transform 0.2s ease;
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 10;
            }
            
            .ai-chat-item:hover .ai-chat-delete-btn {
                opacity: 1;
            }
            
            .ai-chat-delete-btn:hover {
                background: rgba(220, 53, 69, 1);
                transform: scale(1.1);
            }

            .ai-chat-action {
                font-size: 11px;
                color: #999;
                margin-bottom: 2px;
            }
            
            .ai-chat-bubble {
                background: var(--timeline-bg, #f9f9f9);
                padding: 8px 12px;
                border-radius: 8px;
                border-top-left-radius: 2px;
                font-size: 14px;
                color: var(--timeline-text, #444);
                line-height: 1.5;
            }

            /* Timeline 标记 - 显示在有聊天记录的段落左侧 */
            .ai-timeline-marker {
                position: absolute;
                left: -28px;
                top: 4px;
                width: 20px;
                height: 20px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                border-radius: 50%;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-size: 12px;
                font-weight: bold;
                cursor: pointer;
                box-shadow: 0 2px 6px rgba(102, 126, 234, 0.3);
                transition: all 0.2s ease;
                z-index: 5;
            }

            .ai-timeline-marker:hover {
                transform: scale(1.15);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.5);
            }

            .ai-timeline-marker::after {
                content: '💬';
                font-size: 11px;
            }

            /* 有 timeline 的段落添加左边距，为标记留出空间 */
            p.has-timeline {
                margin-left: 32px !important;
                position: relative;
            }

            /* Timeline 展开时的标记样式 */
            p.ai-timeline-active .ai-timeline-marker {
                background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            }
        `;
        document.head.appendChild(historyStyle);

        // MD5 哈希函数 - 必须在 initParagraphs 之前定义！
        function md5(string) {
            function rotateLeft(value, shift) {
                return (value << shift) | (value >>> (32 - shift));
            }
            function addUnsigned(x, y) {
                const lsw = (x & 0xFFFF) + (y & 0xFFFF);
                const msw = (x >> 16) + (y >> 16) + (lsw >> 16);
                return (msw << 16) | (lsw & 0xFFFF);
            }
            function f(x, y, z) { return (x & y) | (~x & z); }
            function g(x, y, z) { return (x & z) | (y & ~z); }
            function h(x, y, z) { return x ^ y ^ z; }
            function i(x, y, z) { return y ^ (x | ~z); }
            function ff(a, b, c, d, x, s, ac) {
                a = addUnsigned(a, addUnsigned(addUnsigned(f(b, c, d), x), ac));
                return addUnsigned(rotateLeft(a, s), b);
            }
            function gg(a, b, c, d, x, s, ac) {
                a = addUnsigned(a, addUnsigned(addUnsigned(g(b, c, d), x), ac));
                return addUnsigned(rotateLeft(a, s), b);
            }
            function hh(a, b, c, d, x, s, ac) {
                a = addUnsigned(a, addUnsigned(addUnsigned(h(b, c, d), x), ac));
                return addUnsigned(rotateLeft(a, s), b);
            }
            function ii(a, b, c, d, x, s, ac) {
                a = addUnsigned(a, addUnsigned(addUnsigned(i(b, c, d), x), ac));
                return addUnsigned(rotateLeft(a, s), b);
            }
            function convertToWordArray(str) {
                let lWordCount;
                const lMessageLength = str.length;
                const lNumberOfWordsTemp1 = lMessageLength + 8;
                const lNumberOfWordsTemp2 = (lNumberOfWordsTemp1 - (lNumberOfWordsTemp1 % 64)) / 64;
                const lNumberOfWords = (lNumberOfWordsTemp2 + 1) * 16;
                const lWordArray = Array(lNumberOfWords - 1);
                let lBytePosition = 0;
                let lByteCount = 0;
                while (lByteCount < lMessageLength) {
                    lWordCount = (lByteCount - (lByteCount % 4)) / 4;
                    lBytePosition = (lByteCount % 4) * 8;
                    lWordArray[lWordCount] = (lWordArray[lWordCount] | (str.charCodeAt(lByteCount) << lBytePosition));
                    lByteCount++;
                }
                lWordCount = (lByteCount - (lByteCount % 4)) / 4;
                lBytePosition = (lByteCount % 4) * 8;
                lWordArray[lWordCount] = (lWordArray[lWordCount] | (0x80 << lBytePosition));
                lWordArray[lNumberOfWords - 2] = lMessageLength << 3;
                lWordArray[lNumberOfWords - 1] = lMessageLength >>> 29;
                return lWordArray;
            }
            function wordToHex(lValue) {
                let wordToHexValue = '', wordToHexValueTemp = '', lByte, lCount;
                for (lCount = 0; lCount <= 3; lCount++) {
                    lByte = (lValue >>> (lCount * 8)) & 255;
                    wordToHexValueTemp = '0' + lByte.toString(16);
                    wordToHexValue = wordToHexValue + wordToHexValueTemp.substr(wordToHexValueTemp.length - 2, 2);
                }
                return wordToHexValue;
            }
            let x = Array();
            let k, AA, BB, CC, DD, a, b, c, d;
            const S11 = 7, S12 = 12, S13 = 17, S14 = 22;
            const S21 = 5, S22 = 9, S23 = 14, S24 = 20;
            const S31 = 4, S32 = 11, S33 = 16, S34 = 23;
            const S41 = 6, S42 = 10, S43 = 15, S44 = 21;
            const utf8Str = unescape(encodeURIComponent(string));
            x = convertToWordArray(utf8Str);
            a = 0x67452301; b = 0xEFCDAB89; c = 0x98BADCFE; d = 0x10325476;
            for (k = 0; k < x.length; k += 16) {
                AA = a; BB = b; CC = c; DD = d;
                a = ff(a, b, c, d, x[k + 0], S11, 0xD76AA478);
                d = ff(d, a, b, c, x[k + 1], S12, 0xE8C7B756);
                c = ff(c, d, a, b, x[k + 2], S13, 0x242070DB);
                b = ff(b, c, d, a, x[k + 3], S14, 0xC1BDCEEE);
                a = ff(a, b, c, d, x[k + 4], S11, 0xF57C0FAF);
                d = ff(d, a, b, c, x[k + 5], S12, 0x4787C62A);
                c = ff(c, d, a, b, x[k + 6], S13, 0xA8304613);
                b = ff(b, c, d, a, x[k + 7], S14, 0xFD469501);
                a = ff(a, b, c, d, x[k + 8], S11, 0x698098D8);
                d = ff(d, a, b, c, x[k + 9], S12, 0x8B44F7AF);
                c = ff(c, d, a, b, x[k + 10], S13, 0xFFFF5BB1);
                b = ff(b, c, d, a, x[k + 11], S14, 0x895CD7BE);
                a = ff(a, b, c, d, x[k + 12], S11, 0x6B901122);
                d = ff(d, a, b, c, x[k + 13], S12, 0xFD987193);
                c = ff(c, d, a, b, x[k + 14], S13, 0xA679438E);
                b = ff(b, c, d, a, x[k + 15], S14, 0x49B40821);
                a = gg(a, b, c, d, x[k + 1], S21, 0xF61E2562);
                d = gg(d, a, b, c, x[k + 6], S22, 0xC040B340);
                c = gg(c, d, a, b, x[k + 11], S23, 0x265E5A51);
                b = gg(b, c, d, a, x[k + 0], S24, 0xE9B6C7AA);
                a = gg(a, b, c, d, x[k + 5], S21, 0xD62F105D);
                d = gg(d, a, b, c, x[k + 10], S22, 0x2441453);
                c = gg(c, d, a, b, x[k + 15], S23, 0xD8A1E681);
                b = gg(b, c, d, a, x[k + 4], S24, 0xE7D3FBC8);
                a = gg(a, b, c, d, x[k + 9], S21, 0x21E1CDE6);
                d = gg(d, a, b, c, x[k + 14], S22, 0xC33707D6);
                c = gg(c, d, a, b, x[k + 3], S23, 0xF4D50D87);
                b = gg(b, c, d, a, x[k + 8], S24, 0x455A14ED);
                a = gg(a, b, c, d, x[k + 13], S21, 0xA9E3E905);
                d = gg(d, a, b, c, x[k + 7], S22, 0xFCEFA3F8);
                c = gg(c, d, a, b, x[k + 12], S23, 0x676F02D9);
                b = gg(b, c, d, a, x[k + 1], S24, 0x8D2A4C8A);
                a = hh(a, b, c, d, x[k + 5], S31, 0xFFFA3942);
                d = hh(d, a, b, c, x[k + 8], S32, 0x8771F681);
                c = hh(c, d, a, b, x[k + 11], S33, 0x6D9D6122);
                b = hh(b, c, d, a, x[k + 14], S34, 0xFDE5380C);
                a = hh(a, b, c, d, x[k + 1], S31, 0xA4BEEA44);
                d = hh(d, a, b, c, x[k + 4], S32, 0x4BDECFA9);
                c = hh(c, d, a, b, x[k + 7], S33, 0xF6BB4B60);
                b = hh(b, c, d, a, x[k + 10], S34, 0xBEBFBC70);
                a = hh(a, b, c, d, x[k + 13], S31, 0x289B7EC6);
                d = hh(d, a, b, c, x[k + 0], S32, 0xEAA127FA);
                c = hh(c, d, a, b, x[k + 3], S33, 0xD4EF3085);
                b = hh(b, c, d, a, x[k + 6], S34, 0x4881D05);
                a = hh(a, b, c, d, x[k + 9], S31, 0xD9D4D039);
                d = hh(d, a, b, c, x[k + 12], S32, 0xE6DB99E5);
                c = hh(c, d, a, b, x[k + 15], S33, 0x1FA27CF8);
                b = hh(b, c, d, a, x[k + 2], S34, 0xC4AC5665);
                a = ii(a, b, c, d, x[k + 0], S41, 0xF4292244);
                d = ii(d, a, b, c, x[k + 7], S42, 0x432AFF97);
                c = ii(c, d, a, b, x[k + 14], S43, 0xAB9423A7);
                b = ii(b, c, d, a, x[k + 5], S44, 0xFC93A039);
                a = ii(a, b, c, d, x[k + 12], S41, 0x655B59C3);
                d = ii(d, a, b, c, x[k + 3], S42, 0x8F0CCC92);
                c = ii(c, d, a, b, x[k + 10], S43, 0xFFEFF47D);
                b = ii(b, c, d, a, x[k + 1], S44, 0x85845DD1);
                a = ii(a, b, c, d, x[k + 8], S41, 0x6FA87E4F);
                d = ii(d, a, b, c, x[k + 15], S42, 0xFE2CE6E0);
                c = ii(c, d, a, b, x[k + 6], S43, 0xA3014314);
                b = ii(b, c, d, a, x[k + 13], S44, 0x4E0811A1);
                a = ii(a, b, c, d, x[k + 4], S41, 0xF7537E82);
                d = ii(d, a, b, c, x[k + 11], S42, 0xBD3AF235);
                c = ii(c, d, a, b, x[k + 2], S43, 0x2AD7D2BB);
                b = ii(b, c, d, a, x[k + 9], S44, 0xEB86D391);
                a = addUnsigned(a, AA);
                b = addUnsigned(b, BB);
                c = addUnsigned(c, CC);
                d = addUnsigned(d, DD);
            }
            return (wordToHex(a) + wordToHex(b) + wordToHex(c) + wordToHex(d)).toLowerCase();
        }

        // 1. 初始化段落交互
        function initParagraphs() {
            // Filter for uninitialized paragraphs only
            const uninitializedParagraphs = Array.from(document.querySelectorAll('p:not([data-ai-initialized])'));
            
            console.log('[AIReader] Found ' + uninitializedParagraphs.length + ' paragraphs to initialize');

            if (uninitializedParagraphs.length === 0) {
                return;
            }

            uninitializedParagraphs.forEach(p => {
                // === STABLE ID STRATEGY ===
                // Format: ai-p-{chapterHash8}-{indexInChapter}-{contentHash8}
                // This is stable because:
                // 1. chapterHash depends on EPUB structure (data-original-href), not load order
                // 2. indexInChapter is relative to chapter, not entire document
                // 3. contentHash provides uniqueness for identical positions
                
                if (!p.id || p.id.startsWith('ai-p-')) {
                    // 1. Find parent chapter
                    const chapter = p.closest('.chapter');
                    const chapterHref = chapter ? (chapter.dataset.originalHref || 'root') : 'root';
                    const chapterHash = md5(chapterHref).substring(0, 8);
                    
                    // 2. Get index within this chapter (stable relative position)
                    const chapterParagraphs = chapter 
                        ? Array.from(chapter.querySelectorAll('p'))
                        : Array.from(document.querySelectorAll('p'));
                    const indexInChapter = chapterParagraphs.indexOf(p);
                    
                    // 3. Extract clean text for content hash
                    let pText = "";
                    for (const node of p.childNodes) {
                        if (node.nodeType === Node.TEXT_NODE) {
                            pText += node.textContent;
                        } else if (node.nodeType === Node.ELEMENT_NODE && !node.classList.contains('ai-paragraph-actions')) {
                            pText += node.textContent;
                        }
                    }
                    const normalizedText = pText.replace(/\\s+/g, ' ').trim();
                    const contentHash = md5(normalizedText).substring(0, 8);
                    
                    // 4. Generate stable ID
                    try {
                        p.id = 'ai-p-' + chapterHash + '-' + indexInChapter + '-' + contentHash;
                    } catch (e) {
                         console.error("MD5 gen failed", e);
                         p.id = 'ai-p-' + chapterHash + '-' + indexInChapter;
                    }
                }

                // Create button container
                const actionContainer = document.createElement('div');
                actionContainer.className = 'ai-paragraph-actions';

                // Create buttons
                const buttonData = [
                    { label: '解释', code: 'explain' },
                    { label: '总结', code: 'summarize' },
                    { label: '翻译', code: 'translate' },
                    { label: '分析', code: 'analyze' }
                ];

                buttonData.forEach(action => {
                    const btn = document.createElement('button');
                    btn.className = 'ai-action-btn';
                    btn.textContent = action.label;
                    btn.onclick = (e) => {
                        e.stopPropagation();

                        // Extract clean text (exclude buttons)
                        let pText = "";
                        for (const node of p.childNodes) {
                            if (node.nodeType === Node.TEXT_NODE) {
                                pText += node.textContent;
                            } else if (node.nodeType === Node.ELEMENT_NODE && !node.classList.contains('ai-paragraph-actions')) {
                                pText += node.textContent;
                            }
                        }

                        window.webkit.messageHandlers.directAIAction.postMessage({
                            text: pText.trim(),
                            action: action.code,
                            paragraphId: p.id
                        });
                    };
                    actionContainer.appendChild(btn);
                });

                p.appendChild(actionContainer);

                // Hover events
                p.addEventListener('mouseenter', () => {
                    p.classList.add('ai-paragraph-hover');
                });
                p.addEventListener('mouseleave', () => {
                    p.classList.remove('ai-paragraph-hover');
                });

                // Click to toggle timeline
                p.addEventListener('click', (e) => {
                    const selection = window.getSelection();
                    if (selection.toString().length > 0) return;
                    toggleTimeline(p);
                });

                // Mark as initialized
                p.setAttribute('data-ai-initialized', 'true');
            });

            console.log('[AIReader] Paragraph UI initialized');
        }

        // 2. 切换时间轴显示
        function toggleTimeline(paragraph) {
            console.log('[Timeline] Toggle for: ' + paragraph.id);

            // Find timeline container (search siblings after the paragraph)
            let timeline = paragraph.nextElementSibling;
            while (timeline && !timeline.classList.contains('ai-timeline-container') && timeline !== paragraph.parentNode.lastChild) {
                timeline = timeline.nextElementSibling;
            }

            // Also try to find by dataset as fallback
            if (!timeline || !timeline.classList.contains('ai-timeline-container')) {
                const allTimelines = document.querySelectorAll('.ai-timeline-container');
                for (const tl of allTimelines) {
                    if (tl.dataset.paragraphId === paragraph.id) {
                        timeline = tl;
                        break;
                    }
                }
            }

            if (timeline && timeline.classList.contains('ai-timeline-container')) {
                const isHidden = timeline.style.display === 'none' || !timeline.style.display;
                timeline.style.display = isHidden ? 'block' : 'none';
                paragraph.classList.toggle('ai-timeline-active', !isHidden);
                console.log('[Timeline] ' + (isHidden ? 'SHOW' : 'HIDE') + ' timeline for: ' + paragraph.id);
            } else {
                console.log('[Timeline] No timeline found for: ' + paragraph.id);
            }
        }

        // 延迟初始化，等待 DOM 稳定
        setTimeout(initParagraphs, 500);

        // 再次尝试初始化，以防 DOM 加载延迟
        setTimeout(initParagraphs, 1500);

        // 监听 DOM 变化，如果有新段落添加则初始化
        const observer = new MutationObserver((mutations) => {
            const newParagraphs = document.querySelectorAll('p:not([data-ai-initialized])');
            if (newParagraphs.length > 0) {
                console.log('[AIReader] Found ' + newParagraphs.length + ' uninitialized paragraphs');
                initParagraphs();
            }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        // 全局变量保存聊天数据
        window.paragraphChats = {}; // p-id -> [chat]

        console.log('AIReader bridge injected successfully (Paragraph Mode v4 - Robust Init)');
        """

        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    /// 注册消息处理器
    func registerMessageHandlers(for webView: WKWebView) {
        let handler = makeScriptMessageHandler()
        webView.configuration.userContentController.add(handler, name: "selectionHandler")
        webView.configuration.userContentController.add(handler, name: "scrollHandler")
        webView.configuration.userContentController.add(handler, name: "consoleLog")
        webView.configuration.userContentController.add(handler, name: "directAIAction")
        webView.configuration.userContentController.add(handler, name: "deleteChatMessage")
    }

    // MARK: - JS Console Bridge
    func injectConsoleBridge(into webView: WKWebView) {
        let script = """
        // Override console logging to forward to Swift
        (function() {
            var oldLog = console.log;
            var oldWarn = console.warn;
            var oldError = console.error;
            
            console.log = function(message) {
                window.webkit.messageHandlers.consoleLog.postMessage({ type: 'log', message: String(message) });
                oldLog.apply(console, arguments);
            };
            
            console.warn = function(message) {
                window.webkit.messageHandlers.consoleLog.postMessage({ type: 'warn', message: String(message) });
                oldWarn.apply(console, arguments);
            };
            
            console.error = function(message) {
                window.webkit.messageHandlers.consoleLog.postMessage({ type: 'error', message: String(message) });
                oldError.apply(console, arguments);
            };
        })();
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    // MARK: - Selection Handling

    func handleSelectionMessage(_ body: [String: Any]) {
        guard let text = body["text"] as? String else {
            // 清空选择
            currentSelection = .init(text: "")
            showHUD = false
            lastProcessedText = ""
            return
        }

        // 空文本处理
        if text.isEmpty {
            currentSelection = .init(text: "")
            showHUD = false
            lastProcessedText = ""
            return
        }

        let cfi = body["cfi"] as? String

        let x = (body["x"] as? CGFloat) ?? 0
        let y = (body["y"] as? CGFloat) ?? 0
        let width = (body["width"] as? CGFloat) ?? 0
        let height = (body["height"] as? CGFloat) ?? 0

        // WebView 内部坐标
        let webViewRect = CGRect(x: x, y: y, width: width, height: height)
        var selection = TextSelection(text: text, cfi: cfi, rect: webViewRect)

        // 只有文本真正改变时才继续处理
        if text == lastProcessedText {
            return
        }

        // 取消之前的防抖定时器
        debounceTimer?.invalidate()

        // 使用防抖延迟处理
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            // 必须在主线程执行
            DispatchQueue.main.async {
                guard let self = self else { return }

                // 再次检查文本是否还是最新的
                if text != self.lastProcessedText {
                    self.lastProcessedText = text
                    self.currentSelection = selection
                    self.showHUD = true

                    self.onSelectionChanged?(selection)

                    // 触发快捷聊天框
                    // 将 WebView 内部坐标转换为屏幕坐标
                    let screenPosition = self.convertToScreenPosition(webViewX: x, webViewY: y, width: width, height: height)
                    self.onShowQuickChat?(text, screenPosition)
                }
            }
        }
    }

    /// 将 WebView 内部坐标转换为屏幕坐标
    private func convertToScreenPosition(webViewX: CGFloat, webViewY: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        // 直接使用鼠标位置，这是最可靠的方式
        // 因为用户选择文本时鼠标一定在选中区域附近
        return NSEvent.mouseLocation
    }

    /// 清除当前选择
    func clearSelection() {
        currentSelection = .init(text: "")
        showHUD = false
    }

    // MARK: - Highlight Operations

    /// 在 WebView 中执行高亮
    func highlightText(in webView: WKWebView, color: String = "#ffff00") async -> Bool {
        let script = "highlightText('\(currentSelection.cfi ?? "")', '\(color)')"
        do {
            return try await webView.evaluateJavaScript(script) as? Bool ?? false
        } catch {
            return false
        }
    }

    /// 移除高亮
    func removeHighlight(in webView: WKWebView) async -> Bool {
        let script = "removeHighlight('\(currentSelection.cfi ?? "")')"
        do {
            return try await webView.evaluateJavaScript(script) as? Bool ?? false
        } catch {
            return false
        }
    }

    // MARK: - PDF Selection Handling

    /// 处理 PDF 选择（从 PDFKit）
    func handlePDFSelection(_ text: String, rect: CGRect, pageIndex: Int) {
        guard !text.isEmpty else {
            currentSelection = .init(text: "")
            showHUD = false
            return
        }

        let selection = TextSelection(text: text, rect: rect, pageIndex: pageIndex)
        currentSelection = selection
        showHUD = true

        onSelectionChanged?(selection)
    }

    // MARK: - Navigation

    /// 导航到指定位置
    func navigateTo(href: String) async {
        let script = "navigateToChapter('\(href)')"
        _ = try? await webView?.evaluateJavaScript(script)
    }
    
    func highlightChatHistory(chats: [ChatContextData]) async {
        // Update cache
        self.cachedChats = chats
        
        guard let jsonData = try? JSONEncoder().encode(chats),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let script = "window.highlightChatHistory(\(jsonString));"
        _ = try? await webView?.evaluateJavaScript(script)
    }

    /// 重新初始化段落按钮（每次导航完成后）- 带防抖
    func reinitializeParagraphsAndChats() {
        guard let webView = self.webView else { return }
        
        // Cancel any pending reinitialize task (debounce)
        reinitializeDebounceTask?.cancel()
        
        // Schedule new task with delay
        reinitializeDebounceTask = Task { @MainActor in
            // Wait for DOM to stabilize and debounce repeated calls
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            
            // Check if cancelled
            if Task.isCancelled { return }
            
            print("DEBUG: reinitializeParagraphsAndChats executing (debounced)")
            _ = try? await webView.evaluateJavaScript("if (typeof initParagraphs === 'function') initParagraphs();")
            
            // Re-apply cached chat history if available
            if !self.cachedChats.isEmpty {
                print("DEBUG: Re-applying \(self.cachedChats.count) cached chats after navigation")
                await self.highlightChatHistory(chats: self.cachedChats)
            }
        }
    }
    
    // MARK: - Direct AI Action
    
    func handleDirectAIAction(_ body: [String: Any]) {
        guard let text = body["text"] as? String,
              let actionCode = body["action"] as? String else { return }

        let paragraphId = body["paragraphId"] as? String  // 接收段落 ID

        // Post notification for AISidePanel to handle
        var userInfo: [String: Any] = [
            "text": text,
            "action": actionCode
        ]
        if let pid = paragraphId {
            userInfo["paragraphId"] = pid  // 传递段落 ID
        }

        NotificationCenter.default.post(
            name: .init("DirectAIActionNotification"),
            object: nil,
            userInfo: userInfo
        )
    }

    // MARK: - Theme Management
    
    public func updateTheme(_ theme: String, for webView: WKWebView) {
        let js: String
        
        switch theme {
        case "dark":
            js = """
            document.documentElement.style.setProperty('--bg-color', '#1a1a1a');
            document.documentElement.style.setProperty('--text-color', '#e0e0e0');
            document.documentElement.style.setProperty('--accent-color', '#A88B81');
            document.documentElement.style.setProperty('--hover-bg', '#2a2a2a');
            document.documentElement.style.setProperty('--selection-bg', '#264f78');
            document.documentElement.style.setProperty('--timeline-bg', '#333333');
            document.documentElement.style.setProperty('--timeline-text', '#e0e0e0');
            """
        case "light":
            js = """
            document.documentElement.style.setProperty('--bg-color', '#fdfbf7');
            document.documentElement.style.setProperty('--text-color', '#333333');
            document.documentElement.style.setProperty('--accent-color', '#8b6b61');
            document.documentElement.style.setProperty('--hover-bg', '#ffffff');
            document.documentElement.style.setProperty('--selection-bg', '#b3d9ff');
            document.documentElement.style.setProperty('--timeline-bg', '#f9f9f9');
            document.documentElement.style.setProperty('--timeline-text', '#444444');
            """
        default: // system
            js = """
            if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.style.setProperty('--bg-color', '#1a1a1a');
                document.documentElement.style.setProperty('--text-color', '#e0e0e0');
                document.documentElement.style.setProperty('--accent-color', '#A88B81');
                document.documentElement.style.setProperty('--hover-bg', '#2a2a2a');
                document.documentElement.style.setProperty('--selection-bg', '#264f78');
                document.documentElement.style.setProperty('--timeline-bg', '#333333');
                document.documentElement.style.setProperty('--timeline-text', '#e0e0e0');
            } else {
                document.documentElement.style.setProperty('--bg-color', '#fdfbf7');
                document.documentElement.style.setProperty('--text-color', '#333333');
                document.documentElement.style.setProperty('--accent-color', '#8b6b61');
                document.documentElement.style.setProperty('--hover-bg', '#ffffff');
                document.documentElement.style.setProperty('--selection-bg', '#b3d9ff');
                document.documentElement.style.setProperty('--timeline-bg', '#f9f9f9');
                document.documentElement.style.setProperty('--timeline-text', '#444444');
            }
            """
        }
        
        webView.evaluateJavaScript(js)
    }
}

// MARK: - ScriptMessageHandler

private class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var coordinator: BridgeCoordinator?

    init(coordinator: BridgeCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "selectionHandler", let body = message.body as? [String: Any] {
            coordinator?.handleSelectionMessage(body)
        } else if message.name == "scrollHandler", let body = message.body as? [String: Any] {
            if let href = body["href"] as? String {
                coordinator?.onScrollPositionChanged?(href)
            }
        } else if message.name == "consoleLog", let body = message.body as? [String: Any] {
            let type = body["type"] as? String ?? "log"
            let msg = body["message"] as? String ?? ""
            NSLog("JS [\(type.uppercased())]: \(msg)")
        } else if message.name == "directAIAction", let body = message.body as? [String: Any] {
            coordinator?.handleDirectAIAction(body)
        } else if message.name == "deleteChatMessage", let chatId = message.body as? String {
            coordinator?.onDeleteChat?(chatId)
        }
    }
}
