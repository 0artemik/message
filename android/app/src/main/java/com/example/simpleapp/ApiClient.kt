package com.example.simpleapp

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import java.io.File
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class ApiException(
    val statusCode: Int,
    override val message: String,
) : Exception(message) {
    val isUnauthorized: Boolean get() = statusCode == 401
}

class ApiClient(private val context: Context) {
    private val http = OkHttpClient()
    private val json = Json {
        ignoreUnknownKeys = true
    }

    @Volatile
    private var token: String? = null
    @Volatile
    private var baseUrl: String = BuildConfig.API_BASE_URL

    fun setToken(value: String?) {
        token = value
    }

    fun setBaseUrl(value: String) {
        baseUrl = normalizeBaseUrl(value)
    }

    fun currentBaseUrl(): String = baseUrl

    suspend fun me(): UserDto {
        return json.decodeFromString(MeResponse.serializer(), requestText("/api/auth/me"))
            .user
    }

    suspend fun login(username: String, password: String): AuthResponse {
        val payload = JSONObject()
            .put("username", username)
            .put("password", password)
        return json.decodeFromString(AuthResponse.serializer(), requestText("/api/auth/login", "POST", payload))
    }

    suspend fun register(
        username: String,
        email: String,
        password: String,
        displayName: String,
    ): AuthResponse {
        val payload = JSONObject()
            .put("username", username)
            .put("email", email)
            .put("password", password)
            .put("displayName", displayName)
        return json.decodeFromString(AuthResponse.serializer(), requestText("/api/auth/register", "POST", payload))
    }

    suspend fun conversations(): List<ConversationDto> {
        return json.decodeFromString(ConversationsResponse.serializer(), requestText("/api/conversations"))
            .conversations
    }

    suspend fun searchUsers(query: String): List<UserDto> {
        val escaped = URLEncoder.encode(query.trim(), "UTF-8")
        return json.decodeFromString(
            UsersSearchResponse.serializer(),
            requestText("/api/users/search?q=$escaped"),
        ).users
    }

    suspend fun createDirectConversation(userId: Int): ConversationDto {
        val payload = JSONObject().put("userId", userId.toString())
        return json.decodeFromString(
            DirectConversationResponse.serializer(),
            requestText("/api/conversations/direct", "POST", payload),
        ).conversation
    }

    suspend fun presenceBatch(userIds: List<Int>): Map<Int, PresenceStateDto> {
        val ids = userIds.distinct().filter { it > 0 }
        if (ids.isEmpty()) return emptyMap()
        val escaped = URLEncoder.encode(ids.sorted().joinToString(","), "UTF-8")
        val raw = json.decodeFromString(
            PresenceBatchResponse.serializer(),
            requestText("/api/presence/batch?ids=$escaped"),
        ).presence
        return raw.mapNotNull { (key, value) -> key.toIntOrNull()?.let { it to value } }.toMap()
    }

    suspend fun presencePing() {
        requestText("/api/presence/ping", "POST", JSONObject())
    }

    suspend fun changePassword(oldPassword: String, newPassword: String) {
        val payload = JSONObject()
            .put("oldPassword", oldPassword)
            .put("newPassword", newPassword)
        requestText("/api/auth/change-password", "POST", payload)
    }

    suspend fun sessions(): List<AuthSessionDto> {
        return json.decodeFromString(SessionsResponse.serializer(), requestText("/api/auth/sessions"))
            .sessions
    }

    suspend fun revokeOtherSessions() {
        requestText("/api/auth/sessions/revoke-others", "POST", JSONObject())
    }

    suspend fun messages(conversationId: Int, beforeId: Int? = null, limit: Int = 50): MessagesResponse {
        val builder = StringBuilder("/api/conversations/$conversationId/messages?limit=${limit.coerceIn(1, 100)}")
        if (beforeId != null && beforeId > 0) {
            builder.append("&beforeId=$beforeId")
        }
        return json.decodeFromString(MessagesResponse.serializer(), requestText(builder.toString()))
    }

    suspend fun markRead(conversationId: Int, upToMessageId: Int) {
        val payload = JSONObject().put("upToMessageId", upToMessageId.toString())
        requestText("/api/conversations/$conversationId/read", "POST", payload)
    }

    suspend fun sendText(conversationId: Int, text: String, clientMsgId: String?): MessageDto {
        val payload = JSONObject().put("body", text)
        if (!clientMsgId.isNullOrBlank()) {
            payload.put("clientMsgId", clientMsgId)
        }
        return json.decodeFromString(
            MessageWrapper.serializer(),
            requestText("/api/conversations/$conversationId/messages", "POST", payload),
        ).message
    }

    suspend fun uploadVoice(conversationId: Int, file: File, durationMs: Int): MessageDto {
        return uploadMultipart(
            path = "/api/conversations/$conversationId/messages/voice",
            fieldName = "audio",
            file = file,
            uploadName = "voice.m4a",
            mime = "audio/mp4",
            formFields = mapOf("durationMs" to durationMs.toString()),
        )
    }

    suspend fun uploadVideoNote(conversationId: Int, file: File, durationMs: Int, mimeType: String): MessageDto {
        val ext = if (mimeType == "video/quicktime") "mov" else "mp4"
        return uploadMultipart(
            path = "/api/conversations/$conversationId/messages/video-note",
            fieldName = "video",
            file = file,
            uploadName = "note.$ext",
            mime = mimeType,
            formFields = mapOf("durationMs" to durationMs.toString()),
        )
    }

    suspend fun uploadFile(
        conversationId: Int,
        file: File,
        originalName: String,
        mimeType: String,
        caption: String,
    ): MessageDto {
        val fields = mutableMapOf<String, String>()
        if (caption.isNotBlank()) {
            fields["caption"] = caption
        }
        return uploadMultipart(
            path = "/api/conversations/$conversationId/messages/file",
            fieldName = "file",
            file = file,
            uploadName = originalName.ifBlank { "file" },
            mime = mimeType.ifBlank { "application/octet-stream" },
            formFields = fields,
        )
    }

    suspend fun editMessage(messageId: Int, body: String): MessageDto {
        val payload = JSONObject().put("body", body)
        return json.decodeFromString(
            MessageWrapper.serializer(),
            requestText("/api/messages/$messageId", "PUT", payload),
        ).message
    }

    suspend fun deleteMessage(messageId: Int, deleteForAll: Boolean): MessageDto {
        val payload = JSONObject().put("deleteForAll", deleteForAll.toString())
        return json.decodeFromString(
            MessageWrapper.serializer(),
            requestText("/api/messages/$messageId", "DELETE", payload),
        ).message
    }

    suspend fun downloadMedia(messageId: Int, download: Boolean = false): ByteArray {
        val suffix = if (download) "?download=1" else ""
        return requestBytes("/api/messages/$messageId/media$suffix")
    }

    fun copyUriToCache(uri: Uri, preferredName: String? = null): File {
        val resolver = context.contentResolver
        val name = preferredName ?: queryDisplayName(resolver, uri) ?: "file-${System.currentTimeMillis()}"
        val ext = name.substringAfterLast('.', "")
        val prefix = name.substringBeforeLast('.', name).take(20).ifBlank { "upload" }
        val outFile = File.createTempFile(prefix, if (ext.isBlank()) "" else ".$ext", context.cacheDir)
        resolver.openInputStream(uri)?.use { input ->
            outFile.outputStream().use { output -> input.copyTo(output) }
        } ?: error("Cannot open file")
        return outFile
    }

    fun mimeTypeForUri(uri: Uri): String {
        return context.contentResolver.getType(uri)
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(
                MimeTypeMap.getFileExtensionFromUrl(uri.toString()).lowercase(),
            )
            ?: "application/octet-stream"
    }

    private suspend fun uploadMultipart(
        path: String,
        fieldName: String,
        file: File,
        uploadName: String,
        mime: String,
        formFields: Map<String, String>,
    ): MessageDto {
        return withContext(Dispatchers.IO) {
            val body = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .apply {
                    formFields.forEach { (key, value) -> addFormDataPart(key, value) }
                    addFormDataPart(
                        fieldName,
                        uploadName,
                        file.asRequestBody(mime.toMediaType()),
                    )
                }
                .build()

            val request = baseRequest(path, "POST")
                .post(body)
                .build()
            val response = http.newCall(request).execute()
            val bodyText = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw ApiException(response.code, decodeError(bodyText))
            }
            json.decodeFromString(MessageWrapper.serializer(), bodyText).message
        }
    }

    private suspend fun requestText(path: String, method: String = "GET", jsonBody: JSONObject? = null): String {
        return requestBytes(path, method, jsonBody).decodeToString()
    }

    private suspend fun requestBytes(
        path: String,
        method: String = "GET",
        jsonBody: JSONObject? = null,
    ): ByteArray {
        return withContext(Dispatchers.IO) {
            val builder = baseRequest(path, method)
            when (method) {
                "POST", "PUT", "DELETE" -> {
                    val body = (jsonBody?.toString() ?: "{}")
                        .toRequestBody("application/json; charset=utf-8".toMediaType())
                    builder.method(method, body)
                }
                else -> builder.get()
            }
            val response = http.newCall(builder.build()).execute()
            val bodyBytes = response.body?.bytes() ?: ByteArray(0)
            if (!response.isSuccessful) {
                throw ApiException(response.code, decodeError(bodyBytes.decodeToString()))
            }
            val contentType = response.header("Content-Type").orEmpty().lowercase()
            val bodyText = bodyBytes.decodeToString()
            if (contentType.contains("text/html") || bodyText.trimStart().startsWith("<!DOCTYPE html", ignoreCase = true)) {
                throw ApiException(
                    502,
                    "Туннель вернул HTML вместо API-ответа. Если используете ngrok, нужен bypass interstitial.",
                )
            }
            bodyBytes
        }
    }

    private fun baseRequest(path: String, method: String): Request.Builder {
        val builder = Request.Builder()
            .url(baseUrl.trimEnd('/') + path)
            .header("X-Client-Type", "android")
            .header("ngrok-skip-browser-warning", "1")
            .header("User-Agent", "MessageAndroid/1.0")
        token?.let { builder.header("Authorization", "Bearer $it") }
        if (method == "GET") {
            builder.get()
        }
        return builder
    }

    private fun normalizeBaseUrl(value: String): String {
        val trimmed = value.trim().trimEnd('/')
        if (trimmed.isEmpty()) {
            return BuildConfig.API_BASE_URL.trimEnd('/')
        }
        return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "http://$trimmed"
        }
    }

    private fun decodeError(text: String): String {
        return runCatching { JSONObject(text).optString("error") }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: text.trim().ifBlank { "Ошибка запроса" }
    }

    private fun queryDisplayName(resolver: ContentResolver, uri: Uri): String? {
        return resolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
    }
}
