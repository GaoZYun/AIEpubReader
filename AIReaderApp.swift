import SwiftUI
import SwiftData
import AppKit

// 自定义 AppDelegate 用于处理应用激活
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为常规应用模式
        NSApp.setActivationPolicy(.regular)

        // 延迟激活，等待窗口完全显示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)

            // 确保 key window 设置正确
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 应用激活时确保窗口是 key window
        if let window = NSApp.keyWindow, !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else if NSApp.windows.isEmpty == false, NSApp.keyWindow == nil {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct AIReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    /// SwiftData 共享模型容器
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BookItem.self,
            Annotation.self,
            AIChat.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme == "light" ? .light : (appTheme == "dark" ? .dark : nil))
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // 添加设置菜单
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // 设置窗口
        Settings {
            SettingsView()
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
