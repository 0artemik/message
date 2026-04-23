package com.example.simpleapp

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import coil.compose.rememberAsyncImagePainter
import java.io.File
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.delay
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Videocam

class MainActivity : ComponentActivity() {
    private val viewModel by viewModels<MessageViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MessageTheme(darkTheme = viewModel.isDarkTheme) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MessageApp(viewModel)
                }
            }
        }
    }
}

@Composable
private fun MessageApp(viewModel: MessageViewModel) {
    val session = viewModel.sessionState
    val home = viewModel.homeState
    val chat = viewModel.chatState

    if (session.isRestoring) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    when {
        session.token == null -> AuthScreen(viewModel)
        chat.conversation != null -> ChatScreen(viewModel)
        else -> ConversationsScreen(viewModel, home)
    }

    if (home.settingsVisible) {
        SettingsDialog(viewModel)
    }
}

@Composable
private fun AuthScreen(viewModel: MessageViewModel) {
    var isRegister by rememberSaveable { mutableStateOf(false) }
    var username by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var displayName by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var errorText by rememberSaveable { mutableStateOf<String?>(null) }
    var showServerDialog by remember { mutableStateOf(false) }
    var serverDraft by remember(viewModel.serverUrl) { mutableStateOf(viewModel.serverUrl) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    listOf(Color(0xFF3A7BD5), Color(0xFF4A569D), Color(0xFF273469)),
                ),
            )
            .padding(24.dp),
    ) {
        TextButton(
            onClick = {
                serverDraft = viewModel.serverUrl
                showServerDialog = true
            },
            modifier = Modifier.align(Alignment.TopEnd),
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
        ) {
            Text("IP", color = Color.White)
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.Center)
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surface)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Message", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(
                "Сервер: ${displayServerLabel(viewModel.serverUrl)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { isRegister = false }, modifier = Modifier.weight(1f)) { Text("Вход") }
                Button(onClick = { isRegister = true }, modifier = Modifier.weight(1f)) { Text("Регистрация") }
            }
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("Логин") },
                modifier = Modifier.fillMaxWidth(),
            )
            if (isRegister) {
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Email") },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = displayName,
                    onValueChange = { displayName = it },
                    label = { Text("Имя") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Пароль") },
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            errorText?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Button(
                onClick = {
                    errorText = null
                    if (isRegister) {
                        viewModel.register(
                            username.trim(),
                            email.trim().lowercase(),
                            password,
                            displayName.trim().ifBlank { username.trim() },
                        ) { errorText = it }
                    } else {
                        viewModel.login(username.trim(), password) { errorText = it }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = if (isRegister) username.length >= 3 && email.contains("@") && password.length >= 6 else username.isNotBlank() && password.isNotBlank(),
            ) {
                Text(if (isRegister) "Создать аккаунт" else "Войти")
            }
        }
    }

    if (showServerDialog) {
        AlertDialog(
            onDismissRequest = { showServerDialog = false },
            title = { Text("Адрес сервера") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = serverDraft,
                        onValueChange = { serverDraft = it },
                        label = { Text("IP или URL") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "Пример: 192.168.1.10:3001 или http://192.168.1.10:3001",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.updateServerUrl(serverDraft)
                        showServerDialog = false
                    },
                ) {
                    Text("Сохранить")
                }
            },
            dismissButton = {
                TextButton(onClick = { showServerDialog = false }) {
                    Text("Отмена")
                }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConversationsScreen(viewModel: MessageViewModel, home: HomeUiState) {
    var query by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(Unit) {
        viewModel.refreshConversations()
        while (true) {
            delay(1_200)
            viewModel.refreshConversations()
        }
    }

    LaunchedEffect(query) {
        if (query.trim().length < 2) {
            viewModel.searchUsers("")
        } else {
            delay(250)
            viewModel.searchUsers(query)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Чаты")
                        Text(
                            viewModel.sessionState.user?.displayName.orEmpty(),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { viewModel.toggleSettings(true) }) {
                        Icon(Icons.Default.Menu, contentDescription = "Настройки")
                    }
                },
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text("Поиск пользователей") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                )
            }
            home.error?.let { message ->
                item {
                    Text(
                        message,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
            if (query.trim().length >= 2) {
                item {
                    Text(
                        "Люди",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                if (home.searchResults.isEmpty()) {
                    item { EmptyState("Никого не нашли") }
                } else {
                    items(home.searchResults, key = { "user-${it.id}" }) { user ->
                        ConversationRow(
                            title = user.displayName,
                            subtitle = "@${user.username}${presenceSuffix(home.presence[user.id])}",
                            online = home.presence[user.id]?.online == true,
                            unreadCount = 0,
                            onClick = { viewModel.openDirect(user) { } },
                        )
                    }
                }
            }
            item {
                Text(
                    "Чаты",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            if (home.conversations.isEmpty()) {
                item { EmptyState("Чатов пока нет") }
            } else {
                items(home.conversations, key = { it.id }) { conversation ->
                    ConversationRow(
                        title = conversation.peer.displayName,
                        subtitle = conversationSubtitle(conversation) + presenceSuffix(home.presence[conversation.peer.id]),
                        online = home.presence[conversation.peer.id]?.online == true,
                        unreadCount = conversation.unreadCount,
                        onClick = { viewModel.openConversation(conversation) },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatScreen(viewModel: MessageViewModel) {
    val chat = viewModel.chatState
    val conversation = chat.conversation ?: return
    val context = LocalContext.current
    val listState = rememberLazyListState()
    var draft by rememberSaveable(conversation.id) { mutableStateOf("") }
    var editTarget by remember { mutableStateOf<MessageDto?>(null) }
    var editText by remember { mutableStateOf("") }
    var errorToast by remember { mutableStateOf<String?>(null) }
    var recorder by remember { mutableStateOf<VoiceRecorder?>(null) }
    var isRecording by remember { mutableStateOf(false) }
    var recordSeconds by remember { mutableIntStateOf(0) }
    var recordStartAt by remember { mutableStateOf(0L) }
    var pendingVideoFile by remember { mutableStateOf<File?>(null) }
    val palette = messagePalette()

    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) {
            errorToast = "Нет доступа к микрофону"
            return@rememberLauncherForActivityResult
        }
        recorder = VoiceRecorder(context)
        runCatching {
            recorder?.start()
            isRecording = true
            recordStartAt = System.currentTimeMillis()
        }.onFailure {
            errorToast = "Не удалось начать запись"
        }
    }

    val captureVideo = rememberLauncherForActivityResult(ActivityResultContracts.CaptureVideo()) { success ->
        if (!success) return@rememberLauncherForActivityResult
        val file = pendingVideoFile ?: return@rememberLauncherForActivityResult
        val duration = videoDurationMs(file)
        viewModel.uploadVideo(file, duration, "video/mp4") { errorToast = it }
        pendingVideoFile = null
    }

    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) {
            errorToast = "Нет доступа к камере"
            return@rememberLauncherForActivityResult
        }
        val file = File.createTempFile("video-note", ".mp4", context.cacheDir)
        pendingVideoFile = file
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        captureVideo.launch(uri)
    }

    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val file = viewModel.copyUriToCache(uri)
        val mime = viewModel.mimeTypeForUri(uri)
        viewModel.uploadFile(file, file.name, mime, draft) { errorToast = it }
        if (draft.isNotBlank()) {
            draft = ""
        }
    }

    LaunchedEffect(conversation.id) {
        viewModel.refreshMessages()
        while (true) {
            delay(3_000)
            viewModel.refreshMessages()
        }
    }

    LaunchedEffect(conversation.id) {
        viewModel.refreshPeerPresence()
        while (true) {
            delay(15_000)
            viewModel.refreshPeerPresence()
        }
    }

    LaunchedEffect(chat.messages.size) {
        if (chat.messages.isNotEmpty()) {
            listState.animateScrollToItem(chat.messages.lastIndex)
        }
    }

    LaunchedEffect(isRecording, recordStartAt) {
        while (isRecording) {
            recordSeconds = ((System.currentTimeMillis() - recordStartAt) / 1000L).toInt()
            delay(250)
        }
    }

    BackHandler { viewModel.closeConversation() }

    errorToast = chat.error ?: errorToast

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(conversation.peer.displayName)
                        Text(
                            peerPresenceText(chat.peerPresence),
                            style = MaterialTheme.typography.labelMedium,
                            color = if (chat.peerPresence?.online == true) Color(0xFF33A46D) else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { viewModel.closeConversation() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Назад")
                    }
                },
            )
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(palette.chrome)
                    .navigationBarsPadding()
                    .padding(8.dp),
            ) {
                if (isRecording) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .clip(CircleShape)
                                .background(Color.Red),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(String.format("%02d:%02d", recordSeconds / 60, recordSeconds % 60))
                        Spacer(Modifier.weight(1f))
                        TextButton(onClick = {
                            recorder?.discard()
                            recorder = null
                            isRecording = false
                        }) { Text("Отмена") }
                        Button(onClick = {
                            val result = recorder?.stop()
                            recorder = null
                            isRecording = false
                            if (result == null || result.second < 100) {
                                errorToast = "Слишком короткая запись"
                            } else {
                                viewModel.uploadVoice(result.first, result.second) { errorToast = it }
                            }
                        }) { Text("Отправить") }
                    }
                }
                Row(verticalAlignment = Alignment.Bottom) {
                    IconButton(
                        onClick = { pickFile.launch(arrayOf("*/*")) },
                        enabled = !chat.attachBusy && !isRecording,
                    ) {
                        Icon(Icons.Default.AttachFile, contentDescription = "Файл")
                    }
                    IconButton(
                        onClick = { cameraPermission.launch(Manifest.permission.CAMERA) },
                        enabled = !chat.attachBusy && !isRecording,
                    ) {
                        Icon(Icons.Default.Videocam, contentDescription = "Видео")
                    }
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text("Сообщение") },
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(
                        onClick = { micPermission.launch(Manifest.permission.RECORD_AUDIO) },
                        enabled = !chat.attachBusy,
                    ) {
                        Icon(Icons.Default.Mic, contentDescription = "Голосовое", tint = if (isRecording) Color.Red else MaterialTheme.colorScheme.onSurface)
                    }
                    IconButton(
                        onClick = {
                            viewModel.sendText(draft) { errorToast = it }
                            draft = ""
                        },
                        enabled = draft.trim().isNotEmpty() && !isRecording && !chat.attachBusy,
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Отправить")
                    }
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            errorToast?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .background(palette.chatBackground)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (chat.hasMore) {
                    item {
                        TextButton(onClick = { viewModel.loadMoreMessages() }, modifier = Modifier.fillMaxWidth()) {
                            Text("Загрузить старые")
                        }
                    }
                }
                items(chat.messages, key = { it.id }) { message ->
                    MessageBubble(
                        message = message,
                        mine = message.senderId == viewModel.sessionState.user?.id,
                        viewModel = viewModel,
                        onEdit = {
                            editTarget = message
                            editText = message.body
                        },
                        onDelete = { deleteForAll ->
                            viewModel.deleteMessage(message.id, deleteForAll) { errorToast = it }
                        },
                    )
                }
            }
        }
    }

    if (editTarget != null) {
        AlertDialog(
            onDismissRequest = { editTarget = null },
            title = { Text("Редактирование") },
            text = {
                OutlinedTextField(
                    value = editText,
                    onValueChange = { editText = it },
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val target = editTarget ?: return@TextButton
                        viewModel.editMessage(target.id, editText) { errorToast = it }
                        editTarget = null
                    },
                    enabled = editText.trim().isNotEmpty(),
                ) {
                    Text("Сохранить")
                }
            },
            dismissButton = {
                TextButton(onClick = { editTarget = null }) { Text("Отмена") }
            },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    message: MessageDto,
    mine: Boolean,
    viewModel: MessageViewModel,
    onEdit: () -> Unit,
    onDelete: (Boolean) -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }
    val palette = messagePalette()
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        Column(horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(18.dp))
                    .background(if (mine) palette.outgoingBubble else palette.incomingBubble)
                    .combinedClickable(
                        onClick = {},
                        onLongClick = { menuExpanded = true },
                    )
                    .padding(12.dp),
            ) {
                when (message.kind ?: "text") {
                    "voice" -> VoiceBubble(message, viewModel)
                    "video_note" -> VideoBubble(message, viewModel)
                    "file" -> FileBubble(message, viewModel)
                    else -> Text(
                        buildString {
                            append(message.body)
                            if (message.editedAt != null) append(" (изменено)")
                        },
                        color = palette.messageText,
                    )
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    if (mine && (message.kind ?: "text") == "text") {
                        DropdownMenuItem(text = { Text("Изменить") }, onClick = {
                            menuExpanded = false
                            onEdit()
                        })
                    }
                    if (mine) {
                        DropdownMenuItem(text = { Text("Удалить у себя") }, onClick = {
                            menuExpanded = false
                            onDelete(false)
                        })
                        DropdownMenuItem(text = { Text("Удалить у всех") }, onClick = {
                            menuExpanded = false
                            onDelete(true)
                        })
                    }
                }
            }
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(messageTime(message.createdAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (mine) {
                    Spacer(Modifier.width(4.dp))
                    Text(if (message.isRead == true) "✓✓" else "✓", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun VoiceBubble(message: MessageDto, viewModel: MessageViewModel) {
    val context = LocalContext.current
    val palette = messagePalette()
    var fileUri by remember(message.id) { mutableStateOf<Uri?>(null) }
    var playing by remember { mutableStateOf(false) }
    val player = remember(message.id) { ExoPlayer.Builder(context).build() }

    DisposableEffect(player) {
        onDispose { player.release() }
    }

    LaunchedEffect(message.id) {
        val file = viewModel.downloadMediaFile(message.id, "voice-${message.id}.webm")
        fileUri = file.toUri()
    }

    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(
            onClick = {
                val uri = fileUri ?: return@IconButton
                if (!playing) {
                    player.setMediaItem(MediaItem.fromUri(uri))
                    player.prepare()
                    player.play()
                } else {
                    player.pause()
                }
                playing = !playing
            },
        ) {
            Icon(
                if (playing) Icons.Default.PauseCircle else Icons.Default.PlayCircle,
                contentDescription = null,
                tint = palette.accent,
            )
        }
        Column {
            Text("Голосовое сообщение", color = palette.messageText)
            message.voiceDurationMs?.let {
                Text(
                    "${maxOf(1, it / 1000)} с",
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.messageSecondary,
                )
            }
        }
    }
}

@Composable
private fun VideoBubble(message: MessageDto, viewModel: MessageViewModel) {
    val context = LocalContext.current
    var fileUri by remember(message.id) { mutableStateOf<Uri?>(null) }
    val player = remember(message.id) { ExoPlayer.Builder(context).build() }

    DisposableEffect(player) {
        onDispose { player.release() }
    }

    LaunchedEffect(message.id) {
        val file = viewModel.downloadMediaFile(message.id, "video-${message.id}.mp4")
        fileUri = file.toUri()
        player.setMediaItem(MediaItem.fromUri(fileUri!!))
        player.prepare()
    }

    if (fileUri == null) {
        CircularProgressIndicator(modifier = Modifier.size(48.dp))
    } else {
        AndroidView(
            factory = {
                PlayerView(it).apply {
                    useController = true
                    this.player = player
                }
            },
            modifier = Modifier
                .size(220.dp)
                .clip(CircleShape),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileBubble(message: MessageDto, viewModel: MessageViewModel) {
    val context = LocalContext.current
    val palette = messagePalette()
    var file by remember(message.id) { mutableStateOf<File?>(null) }
    var imageOpen by remember { mutableStateOf(false) }
    val isImage = message.fileMime?.startsWith("image/") == true

    LaunchedEffect(message.id) {
        val targetName = message.fileName ?: "attachment-${message.id}"
        file = viewModel.downloadMediaFile(message.id, targetName)
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            file == null -> CircularProgressIndicator(modifier = Modifier.size(32.dp))
            isImage -> {
                Image(
                    painter = rememberAsyncImagePainter(file),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(220.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .combinedClickable(onClick = { imageOpen = true }, onLongClick = { }),
                    contentScale = ContentScale.Crop,
                )
            }
            else -> {
                Text("📎 ${message.fileName ?: "Файл"}", color = palette.messageText)
                message.fileSize?.let {
                    Text(
                        byteString(it),
                        style = MaterialTheme.typography.labelMedium,
                        color = palette.messageSecondary,
                    )
                }
                TextButton(onClick = { shareFile(context, file ?: return@TextButton, message.fileMime ?: "application/octet-stream") }) {
                    Text("Скачать", color = palette.accent)
                }
            }
        }
        if (message.body.isNotBlank()) {
            Text(message.body, color = palette.messageText)
        }
    }

    if (imageOpen && file != null) {
        AlertDialog(
            onDismissRequest = { imageOpen = false },
            confirmButton = {
                TextButton(onClick = { imageOpen = false }) { Text("Закрыть") }
            },
            text = {
                Image(
                    painter = rememberAsyncImagePainter(file),
                    contentDescription = null,
                    modifier = Modifier.fillMaxWidth(),
                    contentScale = ContentScale.Fit,
                )
            },
        )
    }
}

@Composable
private fun SettingsDialog(viewModel: MessageViewModel) {
    var tab by remember { mutableStateOf(SettingsTab.GENERAL) }
    var oldPassword by rememberSaveable { mutableStateOf("") }
    var newPassword by rememberSaveable { mutableStateOf("") }
    var confirmPassword by rememberSaveable { mutableStateOf("") }
    var passwordError by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { viewModel.toggleSettings(false) },
        confirmButton = {
            TextButton(onClick = { viewModel.toggleSettings(false) }) { Text("Закрыть") }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TabRow(selectedTabIndex = tab.ordinal) {
                    SettingsTab.entries.forEach { item ->
                        Tab(
                            selected = item == tab,
                            onClick = {
                                tab = item
                                if (item == SettingsTab.SESSIONS) {
                                    viewModel.loadSessions()
                                }
                            },
                            text = {
                                Text(
                                    when (item) {
                                        SettingsTab.GENERAL -> "Общие"
                                        SettingsTab.PASSWORD -> "Пароль"
                                        SettingsTab.SESSIONS -> "Сеансы"
                                    },
                                )
                            },
                        )
                    }
                }
                when (tab) {
                    SettingsTab.GENERAL -> {
                        Text(viewModel.sessionState.user?.displayName.orEmpty(), fontWeight = FontWeight.Bold)
                        Text("@${viewModel.sessionState.user?.username.orEmpty()}")
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text("Тёмная тема")
                            Switch(
                                checked = viewModel.isDarkTheme,
                                onCheckedChange = { viewModel.updateDarkTheme(it) },
                            )
                        }
                        Button(onClick = {
                            viewModel.logout()
                            viewModel.toggleSettings(false)
                        }) {
                            Text("Выйти")
                        }
                    }
                    SettingsTab.PASSWORD -> {
                        OutlinedTextField(value = oldPassword, onValueChange = { oldPassword = it }, label = { Text("Старый пароль") }, visualTransformation = PasswordVisualTransformation())
                        OutlinedTextField(value = newPassword, onValueChange = { newPassword = it }, label = { Text("Новый пароль") }, visualTransformation = PasswordVisualTransformation())
                        OutlinedTextField(value = confirmPassword, onValueChange = { confirmPassword = it }, label = { Text("Подтвердите пароль") }, visualTransformation = PasswordVisualTransformation())
                        passwordError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                        Button(onClick = {
                            val oldValue = oldPassword.trim()
                            val newValue = newPassword.trim()
                            val confirmValue = confirmPassword.trim()
                            passwordError = when {
                                oldValue.isEmpty() -> "Введите старый пароль"
                                newValue.length < 6 -> "Новый пароль не короче 6 символов"
                                newValue != confirmValue -> "Подтверждение не совпадает"
                                else -> null
                            }
                            if (passwordError == null) {
                                viewModel.changePassword(oldValue, newValue, onError = { passwordError = it }) {
                                    viewModel.toggleSettings(false)
                                }
                            }
                        }) {
                            Text("Сменить пароль")
                        }
                    }
                    SettingsTab.SESSIONS -> {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { viewModel.loadSessions() }, enabled = !viewModel.homeState.sessionsBusy) { Text("Обновить") }
                            Button(onClick = { viewModel.revokeOtherSessions() }, enabled = !viewModel.homeState.sessionsBusy) { Text("Завершить другие") }
                        }
                        viewModel.homeState.sessionsError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                        if (viewModel.homeState.sessions.isEmpty()) {
                            Text("Активных сеансов нет")
                        } else {
                            viewModel.homeState.sessions.forEach { session ->
                                Column {
                                    Text(clientTitle(session.clientType), fontWeight = FontWeight.Bold)
                                    Text(session.device, style = MaterialTheme.typography.bodySmall)
                                    Text("Вход: ${session.createdAt}", style = MaterialTheme.typography.labelSmall)
                                    if (session.current) {
                                        Text("Текущий", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
                                    }
                                }
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        },
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConversationRow(
    title: String,
    subtitle: String,
    online: Boolean,
    unreadCount: Int,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = {})
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Box(
                modifier = Modifier
                    .size(50.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF3A7BD5)),
                contentAlignment = Alignment.Center,
            ) {
                Text(initials(title), color = Color.White, fontWeight = FontWeight.Bold)
            }
            if (online) {
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF33A46D)),
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (unreadCount > 0) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text(unreadCount.toString(), color = Color.White, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun EmptyState(text: String) {
    Text(
        text,
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
    )
}

private fun conversationSubtitle(conversation: ConversationDto): String {
    val last = conversation.lastMessage ?: return "Нет сообщений"
    return when (last.kind) {
        "voice" -> "Голосовое сообщение"
        "video_note" -> "Видеосообщение"
        "file" -> "📎 ${last.fileName ?: "Файл"}"
        else -> last.body.ifBlank { "Новое сообщение" }
    }
}

private fun peerPresenceText(state: PresenceStateDto?): String {
    if (state == null) return "статус неизвестен"
    if (state.online) return "в сети"
    val lastSeen = state.lastSeenAt ?: return "не в сети"
    return "был(а) ${compactSeen(lastSeen)}"
}

private fun presenceSuffix(state: PresenceStateDto?): String {
    if (state == null) return ""
    if (state.online) return " · в сети"
    val lastSeen = state.lastSeenAt ?: return ""
    return " · был(а) ${compactSeen(lastSeen)}"
}

private fun compactSeen(raw: String): String {
    val instant = parseInstant(raw) ?: return raw
    val now = Instant.now()
    val seconds = now.epochSecond - instant.epochSecond
    return when {
        seconds < 60 -> "только что"
        seconds < 3600 -> "${seconds / 60} мин назад"
        else -> {
            val dt = LocalDateTime.ofInstant(instant, MOSCOW_ZONE)
            val today = LocalDateTime.ofInstant(now, MOSCOW_ZONE)
            if (dt.toLocalDate() == today.toLocalDate()) {
                "сегодня в ${dt.format(DateTimeFormatter.ofPattern("HH:mm"))}"
            } else {
                dt.format(DateTimeFormatter.ofPattern("dd.MM HH:mm"))
            }
        }
    }
}

private fun messageTime(raw: String): String {
    val instant = parseInstant(raw) ?: return raw
    return DateTimeFormatter.ofPattern("HH:mm").withZone(MOSCOW_ZONE).format(instant)
}

private fun parseInstant(raw: String): Instant? {
    return runCatching { Instant.parse(raw) }.getOrNull()
        ?: runCatching {
            val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            formatter.timeZone = TimeZone.getTimeZone("UTC")
            formatter.parse(raw)?.toInstant()
        }.getOrNull()
}

private val MOSCOW_ZONE: ZoneId = ZoneId.of("Europe/Moscow")

private fun initials(name: String): String {
    val parts = name.split(" ").filter { it.isNotBlank() }
    val first = parts.firstOrNull()?.firstOrNull()?.toString() ?: "?"
    val second = parts.drop(1).firstOrNull()?.firstOrNull()?.toString() ?: ""
    return (first + second).uppercase()
}

private fun byteString(size: Int): String {
    return when {
        size < 1024 -> "$size Б"
        size < 1024 * 1024 -> String.format(Locale.US, "%.1f КБ", size / 1024f)
        else -> String.format(Locale.US, "%.1f МБ", size / 1024f / 1024f)
    }
}

private fun clientTitle(type: String): String {
    return when (type.lowercase()) {
        "ios" -> "iOS"
        "android" -> "Android"
        else -> "Web"
    }
}

private fun shareFile(context: Context, file: File, mimeType: String) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND)
        .setType(mimeType)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    try {
        context.startActivity(Intent.createChooser(intent, "Поделиться файлом"))
    } catch (_: ActivityNotFoundException) {
    }
}

private fun videoDurationMs(file: File): Int {
    val mmr = MediaMetadataRetriever()
    return try {
        mmr.setDataSource(file.absolutePath)
        val raw = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 1L
        raw.toInt().coerceAtLeast(1)
    } finally {
        mmr.release()
    }
}

private class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L

    fun start() {
        val target = File.createTempFile("voice-note", ".m4a", context.cacheDir)
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else MediaRecorder()
        mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        mediaRecorder.setOutputFile(target.absolutePath)
        mediaRecorder.prepare()
        mediaRecorder.start()
        recorder = mediaRecorder
        file = target
        startedAt = System.currentTimeMillis()
    }

    fun stop(): Pair<File, Int>? {
        val mediaRecorder = recorder ?: return null
        return runCatching {
            mediaRecorder.stop()
            mediaRecorder.release()
            recorder = null
            val output = file ?: return null
            output to (System.currentTimeMillis() - startedAt).toInt().coerceAtLeast(1)
        }.getOrNull()
    }

    fun discard() {
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        file?.delete()
        file = null
    }
}

@Composable
private fun MessageTheme(darkTheme: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) {
            darkColorScheme(
                primary = Color(0xFF7AB8FF),
                background = Color(0xFF101418),
                surface = Color(0xFF1A1F24),
                surfaceVariant = Color(0xFF222A31),
            )
        } else {
            lightColorScheme(
                primary = Color(0xFF4E8EF7),
                background = Color(0xFFF5F7FB),
                surface = Color(0xFFFFFFFF),
                surfaceVariant = Color(0xFFEAEFF7),
            )
        },
        content = content,
    )
}

private data class MessagePalette(
    val chrome: Color,
    val chatBackground: Color,
    val incomingBubble: Color,
    val outgoingBubble: Color,
    val messageText: Color,
    val messageSecondary: Color,
    val accent: Color,
)

@Composable
private fun messagePalette(): MessagePalette {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < 0.5f
    return if (dark) {
        MessagePalette(
            chrome = Color(0xFF1A1F24),
            chatBackground = Color(0xFF101418),
            incomingBubble = Color(0xFF222A31),
            outgoingBubble = Color(0xFF16384C),
            messageText = Color(0xFFF3F7FB),
            messageSecondary = Color(0xFF9AA8B6),
            accent = Color(0xFF7AB8FF),
        )
    } else {
        MessagePalette(
            chrome = Color(0xFFFFFFFF),
            chatBackground = Color(0xFFF5F7FB),
            incomingBubble = Color(0xFFFFFFFF),
            outgoingBubble = Color(0xFFD8F4FF),
            messageText = Color(0xFF1B1F24),
            messageSecondary = Color(0xFF7B8794),
            accent = Color(0xFF4E8EF7),
        )
    }
}

private fun displayServerLabel(raw: String): String {
    return raw.removePrefix("http://").removePrefix("https://")
}
