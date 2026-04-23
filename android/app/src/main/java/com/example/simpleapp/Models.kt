package com.example.simpleapp

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AuthResponse(
    val token: String,
    val user: UserDto,
)

@Serializable
data class UserDto(
    val id: Int,
    val username: String,
    @SerialName("displayName") val displayName: String,
)

@Serializable
data class LastMessageDto(
    val body: String = "",
    val kind: String? = null,
    @SerialName("fileName") val fileName: String? = null,
    @SerialName("senderId") val senderId: Int? = null,
    @SerialName("createdAt") val createdAt: String? = null,
)

@Serializable
data class ConversationDto(
    val id: Int,
    val peer: UserDto,
    @SerialName("lastMessage") val lastMessage: LastMessageDto? = null,
    @SerialName("unreadCount") val unreadCount: Int = 0,
)

@Serializable
data class MessageDto(
    val id: Int,
    @SerialName("senderId") val senderId: Int,
    val body: String = "",
    val kind: String? = null,
    @SerialName("createdAt") val createdAt: String,
    @SerialName("voiceDurationMs") val voiceDurationMs: Int? = null,
    @SerialName("fileName") val fileName: String? = null,
    @SerialName("fileMime") val fileMime: String? = null,
    @SerialName("fileSize") val fileSize: Int? = null,
    @SerialName("videoDurationMs") val videoDurationMs: Int? = null,
    @SerialName("clientMsgId") val clientMsgId: String? = null,
    @SerialName("isRead") val isRead: Boolean? = null,
    @SerialName("editedAt") val editedAt: String? = null,
    @SerialName("deletedForSelf") val deletedForSelf: String? = null,
    @SerialName("deletedForAll") val deletedForAll: String? = null,
)

@Serializable
data class MessagesResponse(
    val messages: List<MessageDto> = emptyList(),
    val hasMore: Boolean = false,
    @SerialName("nextBeforeId") val nextBeforeId: Int? = null,
)

@Serializable
data class ConversationsResponse(
    val conversations: List<ConversationDto> = emptyList(),
)

@Serializable
data class UsersSearchResponse(
    val users: List<UserDto> = emptyList(),
)

@Serializable
data class DirectConversationResponse(
    val conversation: ConversationDto,
)

@Serializable
data class AuthSessionDto(
    val sid: String,
    @SerialName("clientType") val clientType: String,
    val device: String,
    @SerialName("createdAt") val createdAt: String,
    val current: Boolean,
)

@Serializable
data class SessionsResponse(
    val sessions: List<AuthSessionDto> = emptyList(),
)

@Serializable
data class PresenceStateDto(
    val online: Boolean,
    @SerialName("lastSeenAt") val lastSeenAt: String? = null,
)

@Serializable
data class PresenceBatchResponse(
    val presence: Map<String, PresenceStateDto> = emptyMap(),
)

@Serializable
data class MeResponse(
    val user: UserDto,
)

@Serializable
data class MessageWrapper(
    val message: MessageDto,
)

data class SessionUiState(
    val isRestoring: Boolean = true,
    val token: String? = null,
    val user: UserDto? = null,
)

data class HomeUiState(
    val conversations: List<ConversationDto> = emptyList(),
    val searchResults: List<UserDto> = emptyList(),
    val presence: Map<Int, PresenceStateDto> = emptyMap(),
    val error: String? = null,
    val settingsVisible: Boolean = false,
    val sessions: List<AuthSessionDto> = emptyList(),
    val sessionsBusy: Boolean = false,
    val sessionsError: String? = null,
)

data class ChatUiState(
    val conversation: ConversationDto? = null,
    val messages: List<MessageDto> = emptyList(),
    val hasMore: Boolean = false,
    val nextBeforeId: Int? = null,
    val peerPresence: PresenceStateDto? = null,
    val error: String? = null,
    val attachBusy: Boolean = false,
)

enum class SettingsTab {
    GENERAL,
    PASSWORD,
    SESSIONS,
}
