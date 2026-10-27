import AppKit
import Security

/// Ask Claude about a screenshot (#252): explain an error, summarize a chart, write alt text, or a question of the
/// user's own. The screenshot goes to Anthropic's Messages API with the user's own API key (kept in the Keychain), and
/// only when they press Ask. Without a key, Open in Claude hands the screenshot and question to Claude on the web,
/// which answers with the user's own Claude plan: Anthropic doesn't let other apps sign in with a Claude subscription.
/// This file holds the request and the reply handling; `AskClaudePanel` is the window.
enum AskClaude {
    enum Preset: Int, CaseIterable {
        case explain, summarize, altText, custom

        var title: String {
            switch self {
            case .explain: return "Explain"
            case .summarize: return "Summarize"
            case .altText: return "Alt Text"
            case .custom: return "Ask…"
            }
        }

        /// The instruction sent with the screenshot; nil for a custom question, which is the user's own text.
        var prompt: String? {
            switch self {
            case .explain:
                return "Explain what this screenshot shows. If it shows an error, warning or failure, say what it means, "
                    + "the likely cause and how to fix it."
            case .summarize:
                return "Summarize the content of this screenshot in a few sentences. For a chart or table, give the "
                    + "main figures and the trend or takeaway."
            case .altText:
                return "Write alt text for this screenshot, for someone who can't see it. Describe what matters in one "
                    + "to three sentences, include any important text it shows, and don't start with \"Image of\" or "
                    + "\"Screenshot of\". Reply with the alt text only."
            case .custom:
                return nil
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    /// Server-side fallback: a request the model's safeguards decline is retried on the model Anthropic recommends.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// A new chat on claude.ai with `q` filled in as the message.
    static let newChat = URL(string: "https://claude.ai/new")!
    /// Where to make an API key.
    static let keysPage = URL(string: "https://console.anthropic.com/settings/keys")!
    /// The API takes up to 5 MB per image; past about 1568 px on the long side it scales the image down anyway.
    static let maxImageBytes = 5 * 1024 * 1024
    static let maxImageSide = 1568

    struct Failure: LocalizedError, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// The text to send with the screenshot, or nil when a custom question is empty.
    static func question(_ preset: Preset, custom: String) -> String? {
        if let prompt = preset.prompt { return prompt }
        let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A new claude.ai chat with `question` already typed in, for Open in Claude.
    static func handoffURL(question: String) -> URL {
        // Everything but unreserved characters is encoded: URLComponents leaves "+" alone, which reads as a space.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let q = question.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        return URL(string: "\(newChat.absoluteString)?q=\(q)") ?? newChat
    }

    /// The screenshot as PNG, or JPEG when PNG is too big for the API, scaled so its long side is at most `maxSide`.
    static func imageData(_ image: NSImage, maxSide: Int = maxImageSide) -> (data: Data, mediaType: String)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0, cg.height > 0
        else { return nil }
        let scale = min(1, Double(maxSide) / Double(max(cg.width, cg.height)))
        let w = max(1, Int((Double(cg.width) * scale).rounded())), h = max(1, Int((Double(cg.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // On white, so transparent window corners don't read as black.
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: rect)
        guard let scaled = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        if let png = rep.representation(using: .png, properties: [:]), base64Size(png.count) <= maxImageBytes {
            return (png, "image/png")
        }
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        return (jpeg, "image/jpeg")
    }

    /// The image limit applies to the base64 text, which is a third bigger than the file.
    static func base64Size(_ bytes: Int) -> Int { (bytes + 2) / 3 * 4 }

    /// The Messages API request: the screenshot, then the question.
    static func request(image: Data, mediaType: String, question: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "system": "You answer questions about a screenshot the user took on their Mac. Answer in plain text, "
                + "without Markdown headings or tables, and keep it short unless asked for detail.",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": mediaType, "data": image.base64EncodedString()]],
                    ["type": "text", "text": question],
                ] as [[String: Any]],
            ] as [String: Any]],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The answer's text from a Messages API reply, or what went wrong in words the user can act on.
    static func answer(from data: Data, status: Int) -> Result<String, Failure> {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            let detail = ((json?["error"] as? [String: Any])?["message"] as? String).map { " (\($0))" } ?? ""
            switch status {
            case 401: return .failure(Failure("Anthropic didn't accept the API key. Check it in Settings → Ask Claude."))
            case 403: return .failure(Failure("This API key isn't allowed to do that\(detail)."))
            case 413: return .failure(Failure("The screenshot is too big to send."))
            case 429: return .failure(Failure("Too many requests, or the account is out of credit. Try again in a moment\(detail)."))
            case 500...599: return .failure(Failure("Anthropic's servers had a problem (\(status)). Try again in a moment."))
            default: return .failure(Failure("The request failed (\(status))\(detail)."))
            }
        }
        guard let json else { return .failure(Failure("Anthropic sent a reply Skreener couldn't read.")) }
        if json["stop_reason"] as? String == "refusal" {
            return .failure(Failure("Claude declined to answer this one."))
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(Failure("Claude didn't send an answer. Try again.")) }
        return .success(text)
    }

    /// Sends `request` (see `request(image:mediaType:question:apiKey:)`) and hands back the answer.
    static func send(_ request: URLRequest) async -> Result<String, Failure> {
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            return answer(from: body, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return .failure(Failure("Couldn't reach Anthropic: \(error.localizedDescription)"))
        }
    }
}

/// The Anthropic API key, kept in the login Keychain rather than in Skreener's settings file.
enum APIKeyStore {
    static let service = "com.skreener.anthropic-api-key"
    private static let account = "default"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var key: String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// Stores `key` (trimmed); an empty key removes it. Returns false when the Keychain refused.
    @discardableResult static func set(_ key: String?) -> Bool {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return true }
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    /// "sk-ant-…a1b2": enough to tell which key is stored without showing it.
    static func masked(_ key: String) -> String {
        key.count > 12 ? "\(key.prefix(7))…\(key.suffix(4))" : String(repeating: "•", count: key.count)
    }
}
