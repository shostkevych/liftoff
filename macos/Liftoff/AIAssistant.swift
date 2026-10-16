import Foundation
import Observation

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI, anthropic, grok, google, openAICompatible
    var id: Self { self }
    /// Self-hosted / third-party endpoint speaking OpenAI Chat Completions
    /// (AI-Gate, Ollama, vLLM, LM Studio…). The key is optional.
    var isCustom: Bool { self == .openAICompatible }
    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .grok: "Grok (xAI)"
        case .google: "Google"
        case .openAICompatible: "OpenAI-compatible"
        }
    }
    var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .grok: "https://api.x.ai/v1"
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        case .openAICompatible: AIAssistantSettings.customBaseURL
        }
    }
    var keyURL: URL? {
        let address = switch self {
        case .openAI: "https://platform.openai.com/api-keys"
        case .anthropic: "https://platform.claude.com/settings/keys"
        case .grok: "https://console.x.ai"
        case .google: "https://aistudio.google.com/apikey"
        case .openAICompatible: ""
        }
        return URL(string: address)
    }
    var keychainAccount: String { "aiAssistant.\(rawValue).apiKey" }
}

struct AIConfiguration: Sendable {
    let provider: AIProvider
    let model: String
    let key: String
    /// Overrides the provider's base URL (unsaved custom URL in Test).
    var baseURL: String? = nil
}

/// Shared across windows; terminal-layout persistence never rewrites AI keys.
@MainActor @Observable
final class AIAssistantSettings {
    static let shared = AIAssistantSettings()
    private(set) var provider: AIProvider
    private(set) var models: [String: String]
    private let defaults = UserDefaults.standard
    private let prefix = BuildVariant.settingsDirectoryName + ".aiAssistant."
    private nonisolated static let customBaseURLKey =
        BuildVariant.settingsDirectoryName + ".aiAssistant.customBaseURL"
    /// Base URL (…/v1) for the OpenAI-compatible provider, without trailing slash.
    nonisolated static var customBaseURL: String {
        (UserDefaults.standard.string(forKey: customBaseURLKey) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private init() {
        let defaults = UserDefaults.standard
        let prefix = BuildVariant.settingsDirectoryName + ".aiAssistant."
        provider = AIProvider(rawValue: defaults.string(forKey: prefix + "provider") ?? "") ?? .openAI
        models = defaults.dictionary(forKey: prefix + "models") as? [String: String] ?? [:]
    }
    func model(for provider: AIProvider) -> String { models[provider.rawValue] ?? "" }
    func key(for provider: AIProvider) -> String { KeychainHelper.read(key: provider.keychainAccount) ?? "" }
    var configuration: AIConfiguration? {
        let model = model(for: provider)
        guard !model.isEmpty else { return nil }
        let key = key(for: provider)
        if provider.isCustom {
            guard !Self.customBaseURL.isEmpty else { return nil }
        } else {
            guard !key.isEmpty else { return nil }
        }
        return AIConfiguration(provider: provider, model: model, key: key)
    }
    func save(provider: AIProvider, model: String, key: String, baseURL: String? = nil) throws {
        if key.isEmpty && provider.isCustom {
            _ = KeychainHelper.delete(key: provider.keychainAccount)
        } else if !KeychainHelper.store(key: provider.keychainAccount, value: key) {
            throw AIClient.Failure("Could not save the API key in Keychain. Your previous settings were kept.")
        }
        if let baseURL { defaults.set(baseURL, forKey: Self.customBaseURLKey) }
        models[provider.rawValue] = model
        self.provider = provider
        defaults.set(models, forKey: prefix + "models")
        defaults.set(provider.rawValue, forKey: prefix + "provider")
    }
    func removeKey(for provider: AIProvider) throws {
        guard KeychainHelper.delete(key: provider.keychainAccount) else {
            throw AIClient.Failure("Could not remove the API key from Keychain.")
        }
        models.removeValue(forKey: provider.rawValue)
        defaults.set(models, forKey: prefix + "models")
    }
}

enum AIClient {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    struct Model: Identifiable {
        let id: String
        let name: String
    }
    private static let session = URLSession(configuration: .ephemeral)

    private static func request(provider: AIProvider, key: String, path: String, baseURL: String? = nil) -> URLRequest {
        // A malformed custom base URL fails the request instead of crashing.
        let url = URL(string: (baseURL ?? provider.baseURL) + path) ?? URL(fileURLWithPath: "/")
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .openAI, .grok:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .openAICompatible:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            // Client identity required by AI-Gate; other servers ignore it.
            request.setValue("liftoff", forHTTPHeaderField: "X-AI-Gate-Client")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        return request
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw Failure("Could not reach the AI provider. Check your connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else { throw Failure("Invalid response from the AI provider.") }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw Failure("Access denied. Check the API key and its permissions in Settings → AI Assistant.")
        case 429: throw Failure("Provider rate limit or quota reached. Check your account or try again later.")
        case 400, 404, 422: throw Failure("The provider rejected this request. Reload models in Settings → AI Assistant and select a supported text model.")
        default: throw Failure("AI provider request failed (HTTP \(http.statusCode)). Try again later.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("Invalid response from the AI provider.")
        }
        return json
    }

    static func listModels(provider: AIProvider, key: String, baseURL: String? = nil) async throws -> [Model] {
        let root = baseURL ?? provider.baseURL
        guard URL(string: root + "/models") != nil else { throw Failure("Invalid base URL.") }
        var result: [Model] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            try Task.checkCancellation()
            var components = URLComponents(string: root + "/models")!
            switch provider {
            case .anthropic:
                components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                if let cursor { components.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
            case .google:
                components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                if let cursor { components.queryItems?.append(URLQueryItem(name: "pageToken", value: cursor)) }
            default: break
            }
            var request = request(provider: provider, key: key, path: "/models", baseURL: root)
            request.url = components.url
            let json = try await send(request)
            let rows = json[provider == .google ? "models" : "data"] as? [[String: Any]] ?? []
            for row in rows {
                guard let rawID = row[provider == .google ? "name" : "id"] as? String else { continue }
                let id = rawID.hasPrefix("models/") ? String(rawID.dropFirst(7)) : rawID
                let lower = id.lowercased()
                if provider == .google {
                    guard (row["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { continue }
                }
                if provider == .openAI {
                    // Legacy completion-only models cannot use the Responses endpoint.
                    if lower.hasPrefix("gpt-3.5") || lower == "gpt-4" || lower.hasPrefix("gpt-4-") || lower.hasPrefix("o1-mini") || lower.hasPrefix("o1-preview") { continue }
                    guard lower.hasPrefix("gpt-") || lower.hasPrefix("chatgpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.hasPrefix("ft:gpt-") else { continue }
                }
                if provider == .grok && !lower.hasPrefix("grok-") { continue }
                if ["embedding", "audio", "realtime", "transcribe", "tts", "image", "vision-only", "instruct", "deep-research", "search"].contains(where: lower.contains) { continue }
                result.append(Model(id: id, name: row["display_name"] as? String ?? row["displayName"] as? String ?? id))
            }
            cursor = nil
            if provider == .anthropic, json["has_more"] as? Bool == true { cursor = json["last_id"] as? String }
            if provider == .google { cursor = json["nextPageToken"] as? String }
            if let next = cursor, !seenCursors.insert(next).inserted { throw Failure("The provider returned an invalid model list. Try again.") }
        } while cursor != nil
        var seen = Set<String>()
        let models = result.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !models.isEmpty else { throw Failure("No supported text models were returned for this API key.") }
        return models
    }

    static func chat(configuration: AIConfiguration, system: String, user: String) async throws -> String {
        let provider = configuration.provider
        var path: String
        var body: [String: Any]
        switch provider {
        case .openAI:
            path = "/responses"
            body = ["model": configuration.model, "instructions": system, "input": user, "store": false]
        case .grok, .openAICompatible:
            path = "/chat/completions"
            body = ["model": configuration.model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]], "stream": false]
        case .anthropic:
            path = "/messages"
            body = ["model": configuration.model, "system": system, "max_tokens": 2048, "messages": [["role": "user", "content": user]]]
        case .google:
            let model = configuration.model.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            path = "/models/\(model):generateContent"
            body = ["systemInstruction": ["parts": [["text": system]]], "contents": [["role": "user", "parts": [["text": user]]]]]
        }
        var request = request(provider: provider, key: configuration.key, path: path, baseURL: configuration.baseURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(request)
        let text: String
        switch provider {
        case .openAI:
            let output = json["output"] as? [[String: Any]] ?? []
            text = output.filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .grok, .openAICompatible:
            let choices = json["choices"] as? [[String: Any]]
            text = (choices?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        case .anthropic:
            text = (json["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .google:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            text = (content?["parts"] as? [[String: Any]] ?? []).filter { $0["thought"] as? Bool != true }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure("The AI provider returned no text. Try again or select another model in Settings → AI Assistant.") }
        return trimmed
    }
}
