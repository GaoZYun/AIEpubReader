import SwiftUI
import PDFKit

/// PDFKit 视图包装器 (Wrapper for Tooltip Overlay support)
struct PDFKitView: View {
    let url: URL
    @Binding var selectedText: String
    @Binding var selectedRect: CGRect
    @Binding var currentPageIndex: Int
    var aiChats: [AIChat] = []
    var onSelectionChanged: ((String, CGRect, Int) -> Void)?
    var onAISend: ((String) -> Void)?
    
    // Tooltip State
    @State private var tooltipText: String?
    @State private var tooltipPosition: CGPoint = .zero

    var body: some View {
        PDFKitViewWithTooltip(
            url: url,
            selectedText: $selectedText,
            selectedRect: $selectedRect,
            currentPageIndex: $currentPageIndex,
            aiChats: aiChats,
            onSelectionChanged: onSelectionChanged,
            onAISend: onAISend,
            tooltipText: $tooltipText,
            tooltipPosition: $tooltipPosition
        )
        .overlay(
            Group {
                if let text = tooltipText, !text.isEmpty {
                    Text(text)
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .font(.caption)
                        .position(x: tooltipPosition.x, y: tooltipPosition.y - 40) // 显示在鼠标上方
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        )
    }
}

// 内部实现：处理 PDFKit 交互和鼠标跟踪
fileprivate struct PDFKitViewWithTooltip: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    @Binding var selectedRect: CGRect
    @Binding var currentPageIndex: Int
    var aiChats: [AIChat]
    var onSelectionChanged: ((String, CGRect, Int) -> Void)?
    var onAISend: ((String) -> Void)?
    
    @Binding var tooltipText: String?
    @Binding var tooltipPosition: CGPoint

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.delegate = context.coordinator

        if let document = PDFDocument(url: url) {
            pdfView.document = document
            if currentPageIndex > 0 && currentPageIndex < document.pageCount {
                if let page = document.page(at: currentPageIndex) {
                    pdfView.go(to: page)
                }
            }
            applyHighlights(to: document)
        }
        
        // 添加鼠标跟踪以支持自定义 Tooltip
        let trackingArea = NSTrackingArea(
            rect: .zero, 
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], 
            owner: context.coordinator, 
            userInfo: nil
        )
        pdfView.addTrackingArea(trackingArea)

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL?.path != url.path {
            if let document = PDFDocument(url: url) {
                nsView.document = document
                applyHighlights(to: document)
            }
        } else if let document = nsView.document {
            // 如果 aiChats 改变，更新高亮
            applyHighlights(to: document)
        }
        
        context.coordinator.onHover = { text, position in
            // 将 View 坐标转换为 SwiftUI 坐标
            self.tooltipText = text
            self.tooltipPosition = position
        }
    }
    
    private func applyHighlights(to document: PDFDocument) {
         for chat in aiChats {
            if chat.relatedText.count < 5 { continue }
            let selections = document.findString(chat.relatedText, withOptions: [.caseInsensitive, .literal])
            for selection in selections {
                guard let page = selection.pages.first else { continue }
                let bounds = selection.bounds(for: page)
                
                // 检查重复
                let oldAnnotations = page.annotations.filter { 
                    $0.type == PDFAnnotationSubtype.highlight.rawValue && 
                    ($0.contents == chat.actionType || $0.contents == chat.actionType?.capitalized)
                }
                if oldAnnotations.contains(where: { $0.bounds.intersects(bounds) }) { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = .yellow.withAlphaComponent(0.3)
                annotation.contents = chat.actionType?.capitalized ?? "Chat"
                page.addAnnotation(annotation)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedText: $selectedText,
            selectedRect: $selectedRect,
            currentPageIndex: $currentPageIndex,
            onSelectionChanged: onSelectionChanged,
            onAISend: onAISend
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSResponder, PDFViewDelegate {
        @Binding var selectedText: String
        @Binding var selectedRect: CGRect
        @Binding var currentPageIndex: Int
        var onSelectionChanged: ((String, CGRect, Int) -> Void)?
        var onAISend: ((String) -> Void)?
        var onHover: ((String?, CGPoint) -> Void)?

        private var debounceTimer: Timer?
        private var lastNotification: Notification?
        private var lastProcessedText: String = ""

        init(selectedText: Binding<String>, selectedRect: Binding<CGRect>, currentPageIndex: Binding<Int>, onSelectionChanged: ((String, CGRect, Int) -> Void)?, onAISend: ((String) -> Void)?) {
            self._selectedText = selectedText
            self._selectedRect = selectedRect
            self._currentPageIndex = currentPageIndex
            self.onSelectionChanged = onSelectionChanged
            self.onSelectionChanged = onSelectionChanged
            self.onAISend = onAISend
            super.init()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // MARK: - Mouse Event
        
        override func mouseMoved(with event: NSEvent) {
            guard let pdfView = event.window?.contentView?.hitTest(event.locationInWindow) as? PDFView else { return }
            
            let locationInView = pdfView.convert(event.locationInWindow, from: nil)
            
            // 获取鼠标下的页面
            if let page = pdfView.page(for: locationInView, nearest: true) {
                let locationInPage = pdfView.convert(locationInView, to: page)
                
                // 查找 mouse 下的 annotation
                // 注意：annotation(at:) 有时候不够精确，可以遍历 page.annotations
                if let annotation = page.annotation(at: locationInPage),
                   annotation.type == PDFAnnotationSubtype.highlight.rawValue,
                   let contents = annotation.contents, !contents.isEmpty {
                    
                    onHover?(contents, locationInView)
                    return
                }
            }
            
            onHover?(nil, .zero)
        }

        // MARK: - PDFViewDelegate

        func PDFViewWillChangePage(_ sender: PDFView, toPage: PDFPage) {
            dismissQuickChat()
            lastProcessedText = ""

            if let document = sender.document {
                let pageIndex = document.index(for: toPage)
                currentPageIndex = pageIndex
            }
        }

        func PDFViewSelectionChanged(_ notification: Notification) {
            lastNotification = notification
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false, block: { [weak self] _ in
                self?.handleSelection()
            })
        }

        private func handleSelection() {
            guard let pdfView = getCurrentPDFView() else { return }

            guard let currentSelection = pdfView.currentSelection,
                  let text = currentSelection.string, !text.isEmpty else {
                selectedText = ""
                selectedRect = .zero
                onSelectionChanged?("", .zero, currentPageIndex)
                dismissQuickChat()
                lastProcessedText = ""
                return
            }

            if text == lastProcessedText { return }
            lastProcessedText = text
            selectedText = text

            let rect = pdfView.convert(currentSelection.bounds(for: pdfView.currentPage!), to: pdfView)
            selectedRect = rect

            onSelectionChanged?(text, rect, currentPageIndex)
            showQuickChat(for: text, at: rect, in: pdfView)
        }

        private func getCurrentPDFView() -> PDFView? {
            if let notification = lastNotification,
               let pdfView = notification.object as? PDFView {
                return pdfView
            }
            if let window = NSApp.keyWindow,
               let contentView = window.contentView {
                return findPDFView(in: contentView)
            }
            return nil
        }

        private func findPDFView(in view: NSView) -> PDFView? {
            if let pdfView = view as? PDFView {
                return pdfView
            }
            for subview in view.subviews {
                if let found = findPDFView(in: subview) {
                    return found
                }
            }
            return nil
        }

        // MARK: - Quick Chat Popover

        private func showQuickChat(for text: String, at rect: CGRect, in pdfView: PDFView) {
            if QuickChatPanel.current != nil { return }
            guard let window = pdfView.window else { return }

            let viewRect = pdfView.convert(rect, to: nil)
            let screenRect = window.convertToScreen(viewRect)

            let position = CGPoint(
                x: screenRect.origin.x + screenRect.width / 2,
                y: screenRect.origin.y + screenRect.height
            )

            QuickChatPanel.current = QuickChatPopover.show(
                selectedText: text,
                at: position,
                onSend: { [weak self] prompt in
                    self?.handleAISend(prompt)
                    self?.dismissQuickChat()
                },
                onCancel: { [weak self] in
                    self?.dismissQuickChat()
                }
            )
        }

        private func dismissQuickChat() {
            QuickChatPanel.current?.safeClose()
        }

        private func handleAISend(_ prompt: String) {
            NotificationCenter.default.post(
                name: .init("AIRequestNotification"),
                object: prompt
            )
            onAISend?(prompt)
        }

        deinit {
            dismissQuickChat()
        }
    }
}

/// PDF 页面导航控制
extension PDFView {
    /// 获取当前页索引
    var currentPageIndex: Int {
        guard let document = self.document, let currentPage = self.currentPage else {
            return 0
        }
        return document.index(for: currentPage)
    }

    /// 跳转到指定页
    func goToPage(_ pageIndex: Int) {
        guard let document = self.document, pageIndex < document.pageCount else {
            return
        }
        if let page = document.page(at: pageIndex) {
            self.go(to: page)
        }
    }
}
