import SwiftUI
import AppKit

// MARK: - Custom Text Field with Keyboard Handling

class CustomNSTextField: NSTextField {
    var onCommit: (() -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
    }
}

struct CustomTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isGenerating: Bool
    var onFocusChanged: ((Bool) -> Void)?
    var onCommit: (() -> Void)?

    func makeNSView(context: Context) -> CustomNSTextField {
        let textField = CustomNSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .none
        textField.lineBreakMode = .byCharWrapping
        textField.cell?.usesSingleLineMode = false
        textField.cell?.wraps = true
        textField.maximumNumberOfLines = 6

        // 确保可以成为第一响应者
        textField.isEnabled = true
        textField.isEditable = true
        textField.isSelectable = true

        // 添加点击手势来获取焦点
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick))
        textField.addGestureRecognizer(clickGesture)

        return textField
    }

    func updateNSView(_ nsView: CustomNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEnabled = !isGenerating
        nsView.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: CustomTextField

        init(_ parent: CustomTextField) {
            self.parent = parent
        }

        @objc func handleClick() {
            // 只有当应用程序处于活动状态时才尝试激活
            if NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        // 处理回车键
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // 检查是否按下了 Shift 键
                let event = NSApp.currentEvent
                if event?.modifierFlags.contains(.shift) == true {
                    // Shift + 回车：插入换行符（默认行为）
                    return false
                } else {
                    // 单独回车：触发发送
                    parent.onCommit?()
                    return true  // 阻止默认行为（插入换行）
                }
            }
            return false
        }
    }
}
