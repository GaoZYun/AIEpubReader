import Foundation
import SwiftUI

class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    @Published var logs: [String] = []
    
    private init() {}
    
    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)"
        
        print(fullMessage) // Console backup
        
        Task { @MainActor in
            shared.addLog(fullMessage)
        }
    }
    
    @MainActor
    private func addLog(_ message: String) {
        logs.append(message)
        if logs.count > 1000 {
            logs.removeFirst()
        }
    }
    
    @MainActor
    func clear() {
        logs.removeAll()
    }
}
