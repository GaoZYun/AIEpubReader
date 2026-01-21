import Foundation

class FileLogger {
    static let logFileURL: URL? = {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsURL.appendingPathComponent("aireader_debug.txt")
    }()

    static func log(_ message: String) {
        guard let fileURL = logFileURL else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        print(message)
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
    
    static func clear() {
        guard let fileURL = logFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
