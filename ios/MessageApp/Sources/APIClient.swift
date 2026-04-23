import Foundation

extension Notification.Name {
    static let apiUnauthorized = Notification.Name("apiUnauthorized")
}

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case status(Int, String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Некорректный URL"
        case .status(let code, let msg): return msg ?? "Ошибка \(code)"
        case .decoding: return "Ошибка разбора ответа"
        }
    }
}

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let lock = NSLock()
    private var token: String?

    private init() {}

    private func notifyUnauthorizedIfNeeded(statusCode: Int) {
        guard statusCode == 401 else { return }
        NotificationCenter.default.post(name: .apiUnauthorized, object: nil)
    }

    private func applyDefaultHeaders(to req: inout URLRequest) {
        req.setValue("ios", forHTTPHeaderField: "X-Client-Type")
        req.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        req.setValue("MessageiOS/1.0", forHTTPHeaderField: "User-Agent")
        if let h = bearerHeader() {
            req.setValue(h, forHTTPHeaderField: "Authorization")
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        if
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let msg = obj["error"] as? String,
            !msg.isEmpty
        {
            return msg
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private func isHTMLResponse(data: Data, response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") { return true }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
    }

    private func validateNonHTML(data: Data, response: HTTPURLResponse) throws {
        guard !isHTMLResponse(data: data, response: response) else {
            throw APIError.status(502, "Туннель вернул HTML вместо API-ответа. Если используете ngrok, нужен bypass interstitial.")
        }
    }

    func setToken(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        token = value
    }

    private func bearerHeader() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let token else { return nil }
        return "Bearer \(token)"
    }

    private func request(
        _ path: String,
        method: String = "GET",
        jsonBody: [String: String]? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        applyDefaultHeaders(to: &req)
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.status(-1, nil) }
        if http.statusCode >= 400 {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        try validateNonHTML(data: data, response: http)
        return data
    }

    /// Загрузка медиа с авторизацией (голос / видеокружок / файл).
    func downloadMedia(messageId: Int) async throws -> Data {
        guard let url = URL(string: "/api/messages/\(messageId)/media", relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        applyDefaultHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.status(-1, nil) }
        if http.statusCode >= 400 {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        try validateNonHTML(data: data, response: http)
        return data
    }

    func downloadFileAttachment(messageId: Int) async throws -> Data {
        guard let url = URL(string: "/api/messages/\(messageId)/media?download=1", relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        applyDefaultHeaders(to: &req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.status(-1, nil) }
        if http.statusCode >= 400 {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        try validateNonHTML(data: data, response: http)
        return data
    }

    func register(username: String, email: String, password: String, displayName: String) async throws -> AuthResponse {
        let data = try await request(
            "/api/auth/register",
            method: "POST",
            jsonBody: [
                "username": username,
                "email": email,
                "password": password,
                "displayName": displayName,
            ]
        )
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        let data = try await request(
            "/api/auth/login",
            method: "POST",
            jsonBody: ["username": username, "password": password]
        )
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func conversations() async throws -> [ConversationDTO] {
        let data = try await request("/api/conversations")
        let res = try JSONDecoder().decode(ConversationsResponse.self, from: data)
        return res.conversations
    }

    func searchUsers(query: String) async throws -> [UserDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?"))
        let escaped = q.addingPercentEncoding(withAllowedCharacters: allowed) ?? q
        let data = try await request("/api/users/search?q=\(escaped)")
        let res = try JSONDecoder().decode(UsersSearchResponse.self, from: data)
        return res.users
    }

    func presenceBatch(userIds: [Int]) async throws -> [Int: PresenceStateDTO] {
        let ids = Array(Set(userIds)).filter { $0 > 0 }
        guard !ids.isEmpty else { return [:] }
        let key = ids.sorted().map(String.init).joined(separator: ",")
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let data = try await request("/api/presence/batch?ids=\(escaped)")
        let res = try JSONDecoder().decode(PresenceBatchResponse.self, from: data)
        var out: [Int: PresenceStateDTO] = [:]
        for (k, v) in res.presence {
            if let id = Int(k) {
                out[id] = v
            }
        }
        return out
    }

    func createDirectConversation(userId: Int) async throws -> ConversationDTO {
        let data = try await request(
            "/api/conversations/direct",
            method: "POST",
            jsonBody: ["userId": "\(userId)"]
        )
        let res = try JSONDecoder().decode(DirectConversationResponse.self, from: data)
        return res.conversation
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        _ = try await request(
            "/api/auth/change-password",
            method: "POST",
            jsonBody: ["oldPassword": oldPassword, "newPassword": newPassword]
        )
    }

    func updateProfile(displayName: String) async throws -> UserDTO {
        let data = try await request(
            "/api/auth/profile",
            method: "PUT",
            jsonBody: ["displayName": displayName]
        )
        struct Response: Decodable, Sendable {
            let user: UserDTO
        }
        return try JSONDecoder().decode(Response.self, from: data).user
    }

    func uploadAvatar(data: Data, fileName: String = "avatar.jpg", mimeType: String = "image/jpeg") async throws -> UserDTO {
        guard let url = URL(string: "/api/auth/avatar", relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyDefaultHeaders(to: &req)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (responseData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.status(-1, nil) }
        if http.statusCode >= 400 {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw APIError.status(http.statusCode, decodeErrorMessage(from: responseData))
        }
        try validateNonHTML(data: responseData, response: http)
        struct Response: Decodable, Sendable {
            let user: UserDTO
        }
        return try JSONDecoder().decode(Response.self, from: responseData).user
    }

    func downloadAvatar(path: String) async throws -> Data {
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        return try await request(normalized)
    }

    func sessions() async throws -> [AuthSessionDTO] {
        let data = try await request("/api/auth/sessions")
        let res = try JSONDecoder().decode(SessionsResponse.self, from: data)
        return res.sessions
    }

    func revokeOtherSessions() async throws {
        _ = try await request("/api/auth/sessions/revoke-others", method: "POST")
    }

    func presencePing() async throws {
        _ = try await request("/api/presence/ping", method: "POST")
    }

    func registerPushToken(platform: String = "ios", token: String) async throws {
        _ = try await request(
            "/api/push/register",
            method: "POST",
            jsonBody: ["platform": platform, "token": token]
        )
    }

    func messages(conversationId: Int, beforeId: Int? = nil, limit: Int = 50) async throws -> MessagesResponse {
        var path = "/api/conversations/\(conversationId)/messages?limit=\(max(1, min(100, limit)))"
        if let beforeId, beforeId > 0 {
            path += "&beforeId=\(beforeId)"
        }
        let data = try await request(path)
        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }

    func sendText(conversationId: Int, text: String, clientMsgId: String? = nil) async throws -> MessageDTO {
        var body: [String: String] = ["body": text]
        if let clientMsgId, !clientMsgId.isEmpty {
            body["clientMsgId"] = clientMsgId
        }
        let data = try await request(
            "/api/conversations/\(conversationId)/messages",
            method: "POST",
            jsonBody: body
        )
        struct Wrap: Decodable, Sendable {
            let message: MessageDTO
        }
        let w = try JSONDecoder().decode(Wrap.self, from: data)
        return w.message
    }

    func markRead(conversationId: Int, upToMessageId: Int) async throws {
        _ = try await request(
            "/api/conversations/\(conversationId)/read",
            method: "POST",
            jsonBody: ["upToMessageId": "\(upToMessageId)"]
        )
    }

    // MARK: - Multipart

    private func multipartRequest(
        path: String,
        fields: [String: String],
        fileField: String,
        fileURL: URL,
        fileName: String,
        mimeType: String
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let crlf = Data("\r\n".utf8)

        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(crlf)
        }

        let fileData = try Data(contentsOf: fileURL)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n"
                    .utf8
            )
        )
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(crlf)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyDefaultHeaders(to: &req)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.status(-1, nil) }
        if http.statusCode >= 400 {
            notifyUnauthorizedIfNeeded(statusCode: http.statusCode)
            throw APIError.status(http.statusCode, decodeErrorMessage(from: data))
        }
        try validateNonHTML(data: data, response: http)
        return data
    }

    private func decodeMessageWrapper(_ data: Data) throws -> MessageDTO {
        struct Wrap: Decodable, Sendable {
            let message: MessageDTO
        }
        return try JSONDecoder().decode(Wrap.self, from: data).message
    }

    func uploadVoice(conversationId: Int, fileURL: URL, durationMs: Int) async throws -> MessageDTO {
        let data = try await multipartRequest(
            path: "/api/conversations/\(conversationId)/messages/voice",
            fields: ["durationMs": "\(durationMs)"],
            fileField: "audio",
            fileURL: fileURL,
            fileName: "voice.m4a",
            mimeType: "audio/mp4"
        )
        return try decodeMessageWrapper(data)
    }

    func uploadVideoNote(conversationId: Int, fileURL: URL, durationMs: Int, mimeType: String) async throws -> MessageDTO {
        let ext = (mimeType == "video/quicktime") ? "mov" : "mp4"
        let data = try await multipartRequest(
            path: "/api/conversations/\(conversationId)/messages/video-note",
            fields: ["durationMs": "\(durationMs)"],
            fileField: "video",
            fileURL: fileURL,
            fileName: "note.\(ext)",
            mimeType: mimeType
        )
        return try decodeMessageWrapper(data)
    }

    func uploadFile(conversationId: Int, fileURL: URL, originalName: String, mimeType: String, caption: String) async throws -> MessageDTO {
        var fields: [String: String] = [:]
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["caption"] = caption
        }
        let safeName = (originalName as NSString).lastPathComponent
        let data = try await multipartRequest(
            path: "/api/conversations/\(conversationId)/messages/file",
            fields: fields,
            fileField: "file",
            fileURL: fileURL,
            fileName: safeName.isEmpty ? "file" : safeName,
            mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType
        )
        return try decodeMessageWrapper(data)
    }
    
    func editMessage(messageId: Int, body: String) async throws -> MessageDTO {
        let data = try await request(
            "/api/messages/\(messageId)",
            method: "PUT",
            jsonBody: ["body": body]
        )
        return try decodeMessageWrapper(data)
    }
    
    func deleteMessage(messageId: Int, deleteForAll: Bool = false) async throws -> MessageDTO {
        let data = try await request(
            "/api/messages/\(messageId)",
            method: "DELETE",
            jsonBody: ["deleteForAll": deleteForAll ? "true" : "false"]
        )
        return try decodeMessageWrapper(data)
    }
}
