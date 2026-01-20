import Foundation
import OSLog

// MARK: - Stream Part

/// 流式响应的部分内容
enum StreamPart {
    case thinking(String)
    case content(String)
    case done
}

/// AI 提供商配置
enum AIProvider {
    case openAI(apiKey: String, baseURL: String?)
    case ollama(baseURL: URL)

    /// 获取基础 URL
    func getBaseURL() -> URL {
        switch self {
        case .openAI(_, let baseURL):
            return URL(string: baseURL ?? "https://api.openai.com") ?? URL(string: "https://api.openai.com")!
        case .ollama(let baseURL):
            return baseURL
        }
    }
}

/// AI 服务错误
enum AIServiceError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(Error)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "未配置 API Key"
        case .invalidResponse:
            return "无效的服务器响应"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .encodingFailed:
            return "编码请求失败"
        case .decodingFailed:
            return "解码响应失败"
        }
    }
}

/// AI 服务 - Actor 保证线程安全
actor AIService {
    // MARK: - Configuration

    private var provider: AIProvider?
    private var model: String = "gpt-4o-mini"
    private var temperature: Double = 0.7

    // MARK: - Configuration Methods

    // MARK: - Configuration Methods

    /// 配置 AI 提供商
    func configure(provider: AIProvider) {
        self.provider = provider
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIService")
        logger.info("Configured provider: \(String(describing: provider))")
    }

    /// 设置模型名称
    func setModel(_ model: String) {
        self.model = model
    }

    /// 设置温度参数
    func setTemperature(_ temperature: Double) {
        self.temperature = temperature
    }

    // MARK: - Generation

    /// 生成补全（非流式）
    func generateCompletion(prompt: String) async throws -> String {
        guard let provider = provider else {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIService")
            logger.error("[Service] generateCompletion: No API Key configured")
            throw AIServiceError.noAPIKey
        }

        switch provider {
        case .openAI(let apiKey, let baseURL):
            return try await callOpenAI(prompt: prompt, apiKey: apiKey, baseURL: baseURL)
        case .ollama(let baseURL):
            return try await callOllama(prompt: prompt, baseURL: baseURL)
        }
    }

    /// 生成补全（流式）- 支持 StreamPart
    func streamCompletion(prompt: String) -> AsyncThrowingStream<StreamPart, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let provider = provider else {
                    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIReader", category: "AIService")
                    logger.error("[Service] streamCompletion: No API Key configured")
                    continuation.finish(throwing: AIServiceError.noAPIKey)
                    return
                }

                switch provider {
                case .openAI(let apiKey, let baseURL):
                    do {
                        let stream = try await callOpenAIStream(prompt: prompt, apiKey: apiKey, baseURL: baseURL)
                        for try await part in stream {
                            continuation.yield(part)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                case .ollama(let baseURL):
                    // Ollama 暂时使用非流式实现
                    do {
                        let response = try await callOllama(prompt: prompt, baseURL: baseURL)
                        continuation.yield(.content(response))
                        continuation.yield(.done)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// 生成补全（流式）- 简化版本，返回字符串
    func streamCompletionSimple(prompt: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = streamCompletion(prompt: prompt)
                    for try await part in stream {
                        switch part {
                        case .content(let text):
                            continuation.yield(text)
                        case .thinking:
                            break
                        case .done:
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - OpenAI API

    /// OpenAI 流式请求
    private func callOpenAIStream(
        prompt: String,
        apiKey: String,
        baseURL: String?
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        // 使用自定义端点或默认端点
        var base = baseURL ?? "https://api.openai.com"
        
        // 移除末尾斜杠
        if base.hasSuffix("/") {
            base.removeLast()
        }

        let endpoint: String
        // 如果用户直接提供了完整路径（包含 /chat/completions），直接通过
        if base.hasSuffix("/chat/completions") {
             endpoint = base
        } else if base.hasSuffix("/v1") {
            // 如果以 /v1 结尾
            endpoint = "\(base)/chat/completions"
        } else {
            // 默认补全 /v1/chat/completions
            endpoint = "\(base)/v1/chat/completions"
        }

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OpenAIStreamRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: "你是一个帮助读者理解书籍内容的 AI 助手。"),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: temperature,
            stream: true
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIServiceError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        // 返回解析 SSE 流的异步流
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let dataString = String(line.dropFirst(6))
                            if dataString == "[DONE]" {
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }

                            if let data = dataString.data(using: .utf8) {
                                do {
                                    let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: data)
                                    if let delta = chunk.choices.first?.delta {
                                        // 检查是否有推理内容 (reasoning_content 用于 deepseek 等模型)
                                        if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                            continuation.yield(.thinking(reasoning))
                                        }
                                        // 检查是否有内容
                                        if let content = delta.content, !content.isEmpty {
                                            continuation.yield(.content(content))
                                        }
                                    }
                                } catch {
                                    // 解码失败时跳过该行
                                    continue
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func callOpenAI(prompt: String, apiKey: String, baseURL: String?) async throws -> String {
        // 使用自定义端点或默认端点
        var base = baseURL ?? "https://api.openai.com"
        
        // 移除末尾斜杠
        if base.hasSuffix("/") {
            base.removeLast()
        }

        let endpoint: String
        // 如果用户直接提供了完整路径（包含 /chat/completions），直接通过
        if base.hasSuffix("/chat/completions") {
             endpoint = base
        } else if base.hasSuffix("/v1") {
            // 如果以 /v1 结尾
            endpoint = "\(base)/chat/completions"
        } else {
            // 默认补全 /v1/chat/completions
            endpoint = "\(base)/v1/chat/completions"
        }

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: "你是一个帮助读者理解书籍内容的 AI 助手。"),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: temperature
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIServiceError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = decoded.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }

        return content
    }

    // MARK: - Ollama API

    private func callOllama(prompt: String, baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model.isEmpty ? "llama2" : model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": temperature
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Ollama error: \(errorString)")
            }
            throw AIServiceError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)

        return decoded.response
    }
}

// MARK: - OpenAI Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
}

private struct OpenAIStreamRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let stream: Bool
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - OpenAI Stream Models

/// 流式响应块
private struct OpenAIStreamChunk: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [StreamChoice]
}

/// 流式选择
private struct StreamChoice: Codable {
    let index: Int?
    let delta: StreamDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

/// 流式增量内容
private struct StreamDelta: Codable {
    let content: String?
    let role: String?
    /// 推理内容 (用于 deepseek-r1 等推理模型)
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case role
        case reasoningContent = "reasoning_content"
    }
}

// MARK: - Ollama Models

private struct OllamaResponse: Codable {
    let model: String
    let response: String
    let done: Bool
}
