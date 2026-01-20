import Foundation
import SwiftUI

// MARK: - AIReaderError 枚举
enum AIReaderError: Error, LocalizedError {
    case epubParsingFailed(String)
    case aiServiceError(String)
    case networkError(String)
    case fileAccessError(String)
    case annotationError(String)

    // MARK: - LocalizedError 协议实现
    var errorDescription: String? {
        switch self {
        case .epubParsingFailed(let details):
            return "EPUB 解析失败: \(details)"
        case .aiServiceError(let details):
            return "AI 服务错误: \(details)"
        case .networkError(let details):
            return "网络错误: \(details)"
        case .fileAccessError(let details):
            return "文件访问错误: \(details)"
        case .annotationError(let details):
            return "笔注错误: \(details)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .epubParsingFailed:
            return "请尝试使用其他 EPUB 文件或联系技术支持"
        case .aiServiceError:
            return "请稍后重试或检查您的网络连接"
        case .networkError:
            return "请检查您的网络连接并重试"
        case .fileAccessError:
            return "请确保应用具有访问文件的权限"
        case .annotationError:
            return "请重试或清除笔注后重新操作"
        }
    }
}

// MARK: - ErrorBanner 视图组件
struct ErrorBanner: View {
    let error: Error
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)

                VStack(alignment: .leading) {
                    Text(error.localizedDescription)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let localizedError = error as? LocalizedError,
                       let suggestion = localizedError.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .transition(.move(edge: .top))
        .animation(.easeInOut(duration: 0.3), value: error.localizedDescription)
    }
}

// MARK: - 错误处理器单例
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()

    @Published var currentError: Error?
    @Published var showError = false

    private init() {}

    // MARK: - 公开方法
    func handleError(_ error: Error) {
        currentError = error
        showError = true

        // 可选：记录错误日志
        logError(error)
    }

    func dismissError() {
        currentError = nil
        showError = false
    }

    // MARK: - 私有方法
    private func logError(_ error: Error) {
        // 这里可以添加错误日志记录逻辑
        print("Error occurred: \(error.localizedDescription)")
    }

    // MARK: - 便捷方法
    func showEPUBParsingError(_ details: String) {
        handleError(AIReaderError.epubParsingFailed(details))
    }

    func showAIServiceError(_ details: String) {
        handleError(AIReaderError.aiServiceError(details))
    }

    func showNetworkError(_ details: String) {
        handleError(AIReaderError.networkError(details))
    }

    func showFileAccessError(_ details: String) {
        handleError(AIReaderError.fileAccessError(details))
    }

    func showAnnotationError(_ details: String) {
        handleError(AIReaderError.annotationError(details))
    }
}

// MARK: - 预览
struct ErrorBanner_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack {
                Spacer()

                ErrorBanner(
                    error: AIReaderError.networkError("无法连接到服务器"),
                    onDismiss: {}
                )
            }
            .ignoresSafeArea()
        }
    }
}