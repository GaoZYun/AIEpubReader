import SwiftUI

struct DebugLogView: View {
    @ObservedObject var logger = DebugLogger.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debug Logs")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task { @MainActor in
                        logger.clear()
                    }
                }) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                
                Button(action: {
                    let text = logger.logs.joined(separator: "\n")
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy All")
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logger.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(log.contains("ERROR") ? .red : (log.contains("JS [") ? .blue : .primary))
                                .id(index)
                        }
                    }
                    .padding()
                    .onChange(of: logger.logs.count) { _ in
                        if let lastIndex = logger.logs.indices.last {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
