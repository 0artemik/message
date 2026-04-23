import Foundation

struct AuthResponse: Decodable, Sendable {
    let token: String
    let user: UserDTO
}

struct UserDTO: Decodable, Identifiable, Sendable {
    let id: Int
    let username: String
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "displayName"
        case avatarUrl = "avatarUrl"
    }
}

struct ConversationDTO: Decodable, Identifiable, Sendable {
    let id: Int
    let peer: UserDTO
    let lastMessage: LastMessageDTO?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, peer
        case lastMessage = "lastMessage"
        case unreadCount = "unreadCount"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        peer = try c.decode(UserDTO.self, forKey: .peer)
        lastMessage = try c.decodeIfPresent(LastMessageDTO.self, forKey: .lastMessage)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

struct LastMessageDTO: Decodable, Sendable {
    let body: String
    let kind: String?
    let fileName: String?
    let senderId: Int?

    enum CodingKeys: String, CodingKey {
        case body, kind
        case fileName = "fileName"
        case senderId = "senderId"
    }
}

struct MessageDTO: Decodable, Identifiable, Sendable {
    let id: Int
    let senderId: Int
    let body: String
    let kind: String?
    let createdAt: String
    let voiceDurationMs: Int?
    let fileName: String?
    let fileMime: String?
    let fileSize: Int?
    let videoDurationMs: Int?
    let clientMsgId: String?
    let isRead: Bool?

    init(
        id: Int,
        senderId: Int,
        body: String,
        kind: String?,
        createdAt: String,
        voiceDurationMs: Int? = nil,
        fileName: String? = nil,
        fileMime: String? = nil,
        fileSize: Int? = nil,
        videoDurationMs: Int? = nil,
        clientMsgId: String? = nil,
        isRead: Bool? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
        self.voiceDurationMs = voiceDurationMs
        self.fileName = fileName
        self.fileMime = fileMime
        self.fileSize = fileSize
        self.videoDurationMs = videoDurationMs
        self.clientMsgId = clientMsgId
        self.isRead = isRead
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "senderId"
        case body, kind
        case createdAt = "createdAt"
        case voiceDurationMs = "voiceDurationMs"
        case fileName = "fileName"
        case fileMime = "fileMime"
        case fileSize = "fileSize"
        case videoDurationMs = "videoDurationMs"
        case clientMsgId = "clientMsgId"
        case isRead = "isRead"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        senderId = try c.decode(Int.self, forKey: .senderId)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        voiceDurationMs = try c.decodeIfPresent(Int.self, forKey: .voiceDurationMs)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        fileMime = try c.decodeIfPresent(String.self, forKey: .fileMime)
        fileSize = try c.decodeIfPresent(Int.self, forKey: .fileSize)
        videoDurationMs = try c.decodeIfPresent(Int.self, forKey: .videoDurationMs)
        clientMsgId = try c.decodeIfPresent(String.self, forKey: .clientMsgId)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead)
    }
}

struct MessagesResponse: Decodable, Sendable {
    let messages: [MessageDTO]
    let hasMore: Bool
    let nextBeforeId: Int?

    enum CodingKeys: String, CodingKey {
        case messages, hasMore, nextBeforeId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decodeIfPresent([MessageDTO].self, forKey: .messages) ?? []
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextBeforeId = try c.decodeIfPresent(Int.self, forKey: .nextBeforeId)
    }
}

struct ConversationsResponse: Decodable, Sendable {
    let conversations: [ConversationDTO]
}

struct UsersSearchResponse: Decodable, Sendable {
    let users: [UserDTO]
}

struct DirectConversationResponse: Decodable, Sendable {
    let conversation: ConversationDTO
}

struct AuthSessionDTO: Decodable, Identifiable, Sendable {
    let sid: String
    let clientType: String
    let device: String
    let createdAt: String
    let current: Bool

    var id: String { sid }
}

struct SessionsResponse: Decodable, Sendable {
    let sessions: [AuthSessionDTO]
}

struct PresenceStateDTO: Decodable, Sendable {
    let online: Bool
    let lastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case online
        case lastSeenAt = "lastSeenAt"
    }
}

struct PresenceBatchResponse: Decodable, Sendable {
    let presence: [String: PresenceStateDTO]
}
