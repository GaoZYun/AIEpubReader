import SwiftUI

/// 浮动 HUD - 文本选择后显示的操作菜单
struct FloatingHUD: View {
    let isVisible: Bool
    let rect: CGRect
    let onExplain: () -> Void
    let onSummarize: () -> Void
    let onTranslate: () -> Void

    @State private var isVisibleInternal: Bool = false

    var body: some View {
        if isVisible {
            HStack(spacing: 4) {
                HUDButton(icon: "lightbulb", title: "解释", action: onExplain)
                Divider()
                    .frame(height: 20)
                HUDButton(icon: "list.bullet", title: "总结", action: onSummarize)
                Divider()
                    .frame(height: 20)
                HUDButton(icon: "character.book.closed", title: "翻译", action: onTranslate)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .position(getHUDPosition())
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                isVisibleInternal = true
            }
            .onDisappear {
                isVisibleInternal = false
            }
        }
    }

    private func getHUDPosition() -> CGPoint {
        // 将 rect 的顶部中心作为 HUD 位置
        let x = rect.midX
        let y = rect.minY - 30 // 在文本上方 30 点

        // 确保不超出屏幕边界
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1000
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800

        let clampedX = max(100, min(x, screenWidth - 100))
        let clampedY = max(50, min(y, screenHeight - 50))

        return CGPoint(x: clampedX, y: clampedY)
    }
}

// MARK: - HUD Button

struct HUDButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                if isHovered {
                    Text(title)
                        .font(.caption)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, isHovered ? 10 : 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.blue.opacity(0.2) : Color.clear)
            .foregroundColor(isHovered ? .primary : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Alternative: Arrow-style HUD

struct FloatingHUDArrow: View {
    let isVisible: Bool
    let position: CGPoint
    let onExplain: () -> Void
    let onSummarize: () -> Void
    let onTranslate: () -> Void

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // 箭头
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: -8, y: -8))
                    path.addLine(to: CGPoint(x: 8, y: -8))
                    path.closeSubpath()
                }
                .fill(Color.white)
                .frame(width: 16, height: 8)
                .shadow(color: .black.opacity(0.1), radius: 2)

                // 按钮容器
                HStack(spacing: 0) {
                    ArrowButton(icon: "lightbulb", isLeft: true, action: onExplain)
                    Divider()
                    ArrowButton(icon: "list.bullet", isLeft: false, isRight: false, action: onSummarize)
                    Divider()
                    ArrowButton(icon: "character.book.closed", isRight: true, action: onTranslate)
                }
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
            .position(position)
        }
    }
}

struct ArrowButton: View {
    let icon: String
    var isLeft: Bool = false
    var isRight: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(isHovering ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
        )
    }
}

// MARK: - Menu Style HUD

struct FloatingHUDMenu: View {
    let isVisible: Bool
    let rect: CGRect
    let onExplain: () -> Void
    let onSummarize: () -> Void
    let onTranslate: () -> Void

    var body: some View {
        if isVisible {
            Menu {
                Button { onExplain() } label: {
                    Label("解释这段内容", systemImage: "lightbulb")
                }
                Button { onSummarize() } label: {
                    Label("总结要点", systemImage: "list.bullet")
                }
                Button { onTranslate() } label: {
                    Label("翻译", systemImage: "character.book.closed")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
            .position(CGPoint(x: rect.maxX + 20, y: rect.midY))
        }
    }
}

// MARK: - Preview

#Preview("Floating HUD") {
    ZStack {
        VStack {
            Text("这是一段示例文本，你可以选择它来触发 HUD。")
                .font(.title)
                .padding()
            Text("选中这段文字后，HUD 会显示在文本上方。")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        FloatingHUD(
            isVisible: true,
            rect: CGRect(x: 200, y: 200, width: 300, height: 50),
            onExplain: { print("Explain") },
            onSummarize: { print("Summarize") },
            onTranslate: { print("Translate") }
        )
    }
    .frame(width: 800, height: 600)
}

#Preview("HUD Components") {
    VStack(spacing: 40) {
        // 标准样式
        HStack(spacing: 4) {
            HUDButton(icon: "lightbulb", title: "解释", action: {})
            Divider().frame(height: 20)
            HUDButton(icon: "list.bullet", title: "总结", action: {})
            Divider().frame(height: 20)
            HUDButton(icon: "character.book.closed", title: "翻译", action: {})
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)

        // 箭头样式
        FloatingHUDArrow(
            isVisible: true,
            position: CGPoint(x: 100, y: 100),
            onExplain: {},
            onSummarize: {},
            onTranslate: {}
        )
    }
    .frame(width: 400, height: 300)
}
