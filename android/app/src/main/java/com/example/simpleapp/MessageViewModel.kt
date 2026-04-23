package com.example.simpleapp

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MessageViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("message.auth", 0)
    private val api = ApiClient(application)
    private val tokenKey = "token"
    private val themeKey = "theme.dark"
    private val serverUrlKey = "server.url"
    private var heartbeatJob: Job? = null

    var sessionState by mutableStateOf(
        SessionUiState(
            isRestoring = true,
            token = prefs.getString(tokenKey, null),
        ),
    )
        private set

    var homeState by mutableStateOf(HomeUiState())
        private set

    var chatState by mutableStateOf(ChatUiState())
        private set

    var isDarkTheme by mutableStateOf(prefs.getBoolean(themeKey, false))
        private set

    var serverUrl by mutableStateOf(
        prefs.getString(serverUrlKey, BuildConfig.API_BASE_URL) ?: BuildConfig.API_BASE_URL,
    )
        private set

    init {
        api.setBaseUrl(serverUrl)
        val token = sessionState.token
        api.setToken(token)
        if (token == null) {
            sessionState = sessionState.copy(isRestoring = false)
        } else {
            viewModelScope.launch {
                runCatching { api.me() }
                    .onSuccess { user ->
                        sessionState = SessionUiState(isRestoring = false, token = token, user = user)
                        startHeartbeat()
                        refreshConversations()
                    }
                    .onFailure {
                        clearSession()
                    }
            }
        }
    }

    fun login(username: String, password: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                val auth = api.login(username, password)
                applyAuth(auth)
                refreshConversations()
            }
        }
    }

    fun register(username: String, email: String, password: String, displayName: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                val auth = api.register(username, email, password, displayName)
                applyAuth(auth)
                refreshConversations()
            }
        }
    }

    fun logout() {
        clearSession()
        homeState = HomeUiState()
        chatState = ChatUiState()
    }

    fun updateDarkTheme(enabled: Boolean) {
        isDarkTheme = enabled
        prefs.edit().putBoolean(themeKey, enabled).apply()
    }

    fun updateServerUrl(value: String) {
        val normalized = value.trim().ifBlank { BuildConfig.API_BASE_URL }
        serverUrl = normalized
        prefs.edit().putString(serverUrlKey, normalized).apply()
        api.setBaseUrl(normalized)
    }

    fun toggleSettings(visible: Boolean) {
        homeState = homeState.copy(settingsVisible = visible)
    }

    fun refreshConversations(onError: ((String) -> Unit)? = null) {
        viewModelScope.launch {
            runApi({ msg ->
                homeState = homeState.copy(error = msg)
                onError?.invoke(msg)
            }) {
                val conversations = api.conversations()
                val presence = api.presenceBatch(conversations.map { it.peer.id })
                homeState = homeState.copy(
                    conversations = conversations,
                    presence = homeState.presence + presence,
                    error = null,
                )
                val currentId = chatState.conversation?.id
                if (currentId != null) {
                    chatState = chatState.copy(conversation = conversations.firstOrNull { it.id == currentId } ?: chatState.conversation)
                }
            }
        }
    }

    fun searchUsers(query: String) {
        if (query.trim().length < 2) {
            homeState = homeState.copy(searchResults = emptyList())
            return
        }
        viewModelScope.launch {
            runApi({ }) {
                val users = api.searchUsers(query)
                val presence = api.presenceBatch(users.map { it.id })
                homeState = homeState.copy(
                    searchResults = users,
                    presence = homeState.presence + presence,
                )
            }
        }
    }

    fun openDirect(user: UserDto, onError: (String) -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                val conversation = api.createDirectConversation(user.id)
                refreshConversations()
                openConversation(conversation)
                homeState = homeState.copy(searchResults = emptyList(), error = null)
            }
        }
    }

    fun openConversation(conversation: ConversationDto) {
        chatState = ChatUiState(conversation = conversation)
        refreshMessages()
        refreshPeerPresence()
    }

    fun closeConversation() {
        chatState = ChatUiState()
    }

    fun refreshMessages() {
        val conversation = chatState.conversation ?: return
        viewModelScope.launch {
            runApi({ msg -> chatState = chatState.copy(error = msg) }) {
                val response = api.messages(conversation.id, limit = 50)
                val merged = mergeMessages(chatState.messages, response.messages)
                chatState = chatState.copy(
                    messages = merged,
                    hasMore = response.hasMore,
                    nextBeforeId = response.nextBeforeId,
                    error = null,
                )
                val myId = sessionState.user?.id
                val last = merged.lastOrNull()
                if (last != null && last.senderId != myId) {
                    api.markRead(conversation.id, last.id)
                }
            }
        }
    }

    fun loadMoreMessages() {
        val conversation = chatState.conversation ?: return
        val beforeId = chatState.nextBeforeId ?: return
        viewModelScope.launch {
            runApi({ msg -> chatState = chatState.copy(error = msg) }) {
                val response = api.messages(conversation.id, beforeId = beforeId, limit = 50)
                chatState = chatState.copy(
                    messages = mergeMessages(chatState.messages, response.messages),
                    hasMore = response.hasMore,
                    nextBeforeId = response.nextBeforeId,
                    error = null,
                )
            }
        }
    }

    fun refreshPeerPresence() {
        val peerId = chatState.conversation?.peer?.id ?: return
        viewModelScope.launch {
            runApi({ }) {
                val presence = api.presenceBatch(listOf(peerId))
                val state = presence[peerId]
                if (state != null) {
                    chatState = chatState.copy(peerPresence = state)
                }
            }
        }
    }

    fun sendText(text: String, onError: (String) -> Unit = {}) {
        val conversation = chatState.conversation ?: return
        val me = sessionState.user ?: return
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val clientMsgId = "android-${UUID.randomUUID()}"
        val placeholder = MessageDto(
            id = -System.currentTimeMillis().toInt(),
            senderId = me.id,
            body = trimmed,
            kind = "text",
            createdAt = java.time.Instant.now().toString(),
            clientMsgId = clientMsgId,
            isRead = false,
        )
        chatState = chatState.copy(messages = mergeMessages(chatState.messages, listOf(placeholder)))
        viewModelScope.launch {
            runApi({ msg ->
                chatState = chatState.copy(
                    messages = chatState.messages.filterNot { it.clientMsgId == clientMsgId && it.id < 0 },
                    error = msg,
                )
                onError(msg)
            }) {
                val message = api.sendText(conversation.id, trimmed, clientMsgId)
                chatState = chatState.copy(
                    messages = chatState.messages.map { old -> if (old.clientMsgId == clientMsgId) message else old },
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun uploadVoice(file: File, durationMs: Int, onError: (String) -> Unit) {
        val conversation = chatState.conversation ?: return
        chatState = chatState.copy(attachBusy = true)
        viewModelScope.launch {
            runApi({ msg ->
                chatState = chatState.copy(attachBusy = false, error = msg)
                onError(msg)
            }) {
                val message = api.uploadVoice(conversation.id, file, durationMs)
                chatState = chatState.copy(
                    messages = mergeMessages(chatState.messages, listOf(message)),
                    attachBusy = false,
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun uploadVideo(file: File, durationMs: Int, mimeType: String, onError: (String) -> Unit) {
        val conversation = chatState.conversation ?: return
        chatState = chatState.copy(attachBusy = true)
        viewModelScope.launch {
            runApi({ msg ->
                chatState = chatState.copy(attachBusy = false, error = msg)
                onError(msg)
            }) {
                val message = api.uploadVideoNote(conversation.id, file, durationMs, mimeType)
                chatState = chatState.copy(
                    messages = mergeMessages(chatState.messages, listOf(message)),
                    attachBusy = false,
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun uploadFile(file: File, originalName: String, mimeType: String, caption: String, onError: (String) -> Unit) {
        val conversation = chatState.conversation ?: return
        chatState = chatState.copy(attachBusy = true)
        viewModelScope.launch {
            runApi({ msg ->
                chatState = chatState.copy(attachBusy = false, error = msg)
                onError(msg)
            }) {
                val message = api.uploadFile(conversation.id, file, originalName, mimeType, caption)
                chatState = chatState.copy(
                    messages = mergeMessages(chatState.messages, listOf(message)),
                    attachBusy = false,
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun editMessage(messageId: Int, body: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                val updated = api.editMessage(messageId, body.trim())
                chatState = chatState.copy(
                    messages = chatState.messages.map { if (it.id == messageId) updated else it },
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun deleteMessage(messageId: Int, deleteForAll: Boolean, onError: (String) -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                api.deleteMessage(messageId, deleteForAll)
                chatState = chatState.copy(
                    messages = chatState.messages.filterNot { it.id == messageId },
                    error = null,
                )
                refreshConversations()
            }
        }
    }

    fun loadSessions(onError: (String) -> Unit = {}) {
        viewModelScope.launch {
            homeState = homeState.copy(sessionsBusy = true, sessionsError = null)
            runApi({ msg ->
                homeState = homeState.copy(sessionsBusy = false, sessionsError = msg)
                onError(msg)
            }) {
                homeState = homeState.copy(
                    sessions = api.sessions(),
                    sessionsBusy = false,
                    sessionsError = null,
                )
            }
        }
    }

    fun revokeOtherSessions(onError: (String) -> Unit = {}) {
        viewModelScope.launch {
            homeState = homeState.copy(sessionsBusy = true, sessionsError = null)
            runApi({ msg ->
                homeState = homeState.copy(sessionsBusy = false, sessionsError = msg)
                onError(msg)
            }) {
                api.revokeOtherSessions()
                homeState = homeState.copy(
                    sessions = api.sessions(),
                    sessionsBusy = false,
                    sessionsError = null,
                )
            }
        }
    }

    fun changePassword(oldPassword: String, newPassword: String, onError: (String) -> Unit, onSuccess: () -> Unit) {
        viewModelScope.launch {
            runApi(onError) {
                api.changePassword(oldPassword, newPassword)
                onSuccess()
                logout()
            }
        }
    }

    fun copyUriToCache(uri: android.net.Uri, preferredName: String? = null): File = api.copyUriToCache(uri, preferredName)

    fun mimeTypeForUri(uri: android.net.Uri): String = api.mimeTypeForUri(uri)

    suspend fun downloadMediaFile(messageId: Int, fileName: String, download: Boolean = false): File {
        return withContext(Dispatchers.IO) {
            val bytes = api.downloadMedia(messageId, download)
            val safeName = fileName.ifBlank { "attachment-$messageId" }
            val file = File(getApplication<Application>().cacheDir, safeName)
            file.writeBytes(bytes)
            file
        }
    }

    private fun applyAuth(auth: AuthResponse) {
        prefs.edit().putString(tokenKey, auth.token).apply()
        api.setToken(auth.token)
        sessionState = SessionUiState(isRestoring = false, token = auth.token, user = auth.user)
        startHeartbeat()
    }

    private fun clearSession() {
        heartbeatJob?.cancel()
        prefs.edit().remove(tokenKey).apply()
        api.setToken(null)
        sessionState = SessionUiState(isRestoring = false, token = null, user = null)
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = viewModelScope.launch {
            while (isActive && sessionState.token != null) {
                runCatching { api.presencePing() }
                delay(25_000)
            }
        }
    }

    private fun mergeMessages(existing: List<MessageDto>, incoming: List<MessageDto>): List<MessageDto> {
        val map = linkedMapOf<String, MessageDto>()
        (existing + incoming).forEach { message ->
            map["id:${message.id}"] = message
        }
        return map.values.sortedBy { it.id }
    }

    private suspend fun runApi(onError: (String) -> Unit, block: suspend () -> Unit) {
        try {
            block()
        } catch (error: Throwable) {
            val message = (error as? ApiException)?.message ?: (error.message ?: "Ошибка")
            if ((error as? ApiException)?.isUnauthorized == true) {
                logout()
            }
            onError(message)
        }
    }
}
