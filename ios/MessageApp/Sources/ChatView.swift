import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let conversation: ConversationDTO
    let peerName: String

    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore

    @State private var messages: [MessageDTO] = []
    @State private var hasMoreMessages = false
    @State private var nextBeforeId: Int?
    @State private var sendingPending = false
    @State private var pendingQueue: [(clientMsgId: String, text: String)] = []
    @State private var draft = ""
    @State private var errorText: String?
    @State private var attachBusy = false
    @State private var peerPresence: PresenceStateDTO?

    @State private var isRecording = false
    @State private var recordSecs = 0
    @State private var recordStarted: Date?
    @State private var voiceEngine = VoiceRecorderEngine()

    @State private var showCamera = false
    @State private var pickedVideoURL: URL?
    @State private var showFileImporter = false

    private var c: TelegramPalette { theme.palette }
    private var myId: Int { session.user?.id ?? -1 }

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(c.header)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if hasMoreMessages {
                            Button("Загрузить старые") {
                                Task { await loadMore() }
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(messages) { m in
                            messageBubble(m)
                                .id(m.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(c.chatBg)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if isRecording {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text(String(format: "%02d:%02d", recordSecs / 60, recordSecs % 60))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(c.text)
                    Text("Запись…")
                        .font(.subheadline)
                        .foregroundStyle(c.textSecondary)
                    Spacer()
                    Button("Отмена") {
                        Task { await finishRecording(send: false) }
                    }
                    .foregroundStyle(c.text)
                    Button {
                        Task { await finishRecording(send: true) }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(c.header)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .disabled(attachBusy || isRecording)

                Button {
                    Task { await openVideoPicker() }
                } label: {
                    Image(systemName: "record.circle")
                        .font(.title3)
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .disabled(attachBusy || isRecording)

                TextField(
                    "",
                    text: $draft,
                    prompt: Text("Сообщение").foregroundStyle(theme.isDark ? Color.white.opacity(0.7) : c.textSecondary),
                    axis: .vertical
                )
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(c.inputBg)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.border, lineWidth: 1))
                    )
                    .foregroundColor(theme.isDark ? .white : c.text)
                    .tint(c.blue)
                    .disabled(isRecording)

                Button {
                    Task { await startOrStopVoice() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .foregroundStyle(isRecording ? .red : c.textSecondary)
                        .frame(width: 40, height: 40)
                }
                .disabled(attachBusy)

                Button {
                    Task { await sendText() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(c.blue))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRecording || attachBusy)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(c.header)
        }
        .navigationTitle(peerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(c.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(peerName)
                        .font(.headline)
                        .foregroundStyle(c.text)
                    Text(peerPresenceText())
                        .font(.caption)
                        .foregroundStyle(peerPresence?.online == true ? c.online : c.textSecondary)
                }
            }
        }
        .tint(c.blue)
        .task {
            await refresh()
            await refreshPeerPresence()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await refreshPeerPresence()
            }
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard isRecording, let t = recordStarted else { return }
            recordSecs = Int(Date().timeIntervalSince(t))
        }
        .sheet(isPresented: $showCamera) {
            CameraVideoPicker(videoURL: $pickedVideoURL)
        }
        .onChange(of: pickedVideoURL) { _, url in
            guard let url else { return }
            Task {
                await uploadPickedVideo(url)
                await MainActor.run { pickedVideoURL = nil }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await uploadPickedFile(url) }
            case .failure:
                break
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ m: MessageDTO) -> some View {
        let mine = m.senderId == myId
        let k = m.kind ?? "text"
        HStack {
            if mine { Spacer(minLength: 24) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Group {
                    switch k {
                    case "voice":
                        VoiceMessageBubble(messageId: m.id, durationMs: m.voiceDurationMs)
                            .environmentObject(theme)
                    case "video_note":
                        VideoCircleBubble(messageId: m.id)
                            .environmentObject(theme)
                    case "file":
                        FileAttachmentBubble(message: m)
                            .environmentObject(theme)
                    default:
                        Text(m.body)
                            .font(.body)
                            .foregroundStyle(c.text)
                            .multilineTextAlignment(mine ? .trailing : .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(mine ? c.bubbleOut : c.bubbleIn)
                        .shadow(color: .black.opacity(theme.isDark ? 0.25 : 0.06), radius: 1, y: 1)
                )
                Text(m.createdAt)
                    .font(.caption2)
                    .foregroundStyle(c.textSecondary)
                if mine {
                    Text(m.isRead == true ? "✓✓" : "✓")
                        .font(.caption2)
                        .foregroundStyle(c.textSecondary)
                }
            }
            if !mine { Spacer(minLength: 24) }
        }
    }

    private func refresh() async {
        do {
            let res = try await APIClient.shared.messages(conversationId: conversation.id, limit: 50)
            messages = mergeMessages(existing: messages, incoming: res.messages)
            hasMoreMessages = res.hasMore
            nextBeforeId = res.nextBeforeId
            if let last = messages.last, last.senderId != myId {
                try? await APIClient.shared.markRead(conversationId: conversation.id, upToMessageId: last.id)
            }
            errorText = nil
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Ошибка загрузки"
        }
    }

    private func refreshPeerPresence() async {
        do {
            let batch = try await APIClient.shared.presenceBatch(userIds: [conversation.peer.id])
            peerPresence = batch[conversation.peer.id]
        } catch {
            /* ignore presence errors */
        }
    }

    private func peerPresenceText() -> String {
        guard let p = peerPresence else { return "статус неизвестен" }
        if p.online { return "в сети" }
        guard let seen = p.lastSeenAt, !seen.isEmpty else { return "не в сети" }
        return "был(а) \(compactSeen(seen))"
    }

    private func compactSeen(_ raw: String) -> String {
        let normalized = raw.contains("T") ? raw : raw.replacingOccurrences(of: " ", with: "T")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date =
            parser.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
            ?? DateFormatter.chatSqlite.date(from: raw)
        guard let d = date else { return raw }
        let now = Date()
        let sec = Int(now.timeIntervalSince(d))
        if sec < 60 { return "только что" }
        if sec < 3600 { return "\(sec / 60) мин назад" }
        if Calendar.current.isDateInToday(d) {
            return "сегодня в \(DateFormatter.chatHm.string(from: d))"
        }
        return DateFormatter.chatDmhm.string(from: d)
    }

    private func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        let clientMsgId = "ios-\(UUID().uuidString)"
        let local = MessageDTO(
            id: -Int.random(in: 1000...999999),
            senderId: myId,
            body: text,
            kind: "text",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            clientMsgId: clientMsgId,
            isRead: false
        )
        messages.append(local)
        pendingQueue.append((clientMsgId, text))
        await flushPendingQueue()
    }

    private func flushPendingQueue() async {
        guard !sendingPending else { return }
        guard !pendingQueue.isEmpty else { return }
        sendingPending = true
        defer { sendingPending = false }
        while !pendingQueue.isEmpty {
            let item = pendingQueue.removeFirst()
            do {
                let m = try await APIClient.shared.sendText(
                    conversationId: conversation.id,
                    text: item.text,
                    clientMsgId: item.clientMsgId
                )
                messages = messages.map { old in
                    if old.clientMsgId == item.clientMsgId { return m }
                    return old
                }
            } catch {
                pendingQueue.append(item)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                break
            }
        }
    }

    private func loadMore() async {
        guard let beforeId = nextBeforeId else { return }
        do {
            let res = try await APIClient.shared.messages(conversationId: conversation.id, beforeId: beforeId, limit: 50)
            messages = mergeMessages(existing: messages, incoming: res.messages + messages)
            hasMoreMessages = res.hasMore
            nextBeforeId = res.nextBeforeId
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Ошибка загрузки"
        }
    }

    private func mergeMessages(existing: [MessageDTO], incoming: [MessageDTO]) -> [MessageDTO] {
        var map: [String: MessageDTO] = [:]
        for m in existing {
            map["id:\(m.id)"] = m
        }
        for m in incoming {
            map["id:\(m.id)"] = m
        }
        return map.values.sorted { $0.id < $1.id }
    }

    private func startOrStopVoice() async {
        if isRecording {
            await finishRecording(send: true)
            return
        }
        let ok = await voiceEngine.requestPermission()
        guard ok else {
            errorText = "Нет доступа к микрофону"
            return
        }
        do {
            _ = try voiceEngine.prepareFile()
            guard voiceEngine.start() else {
                errorText = "Не удалось начать запись"
                return
            }
            errorText = nil
            recordStarted = Date()
            recordSecs = 0
            isRecording = true
        } catch {
            errorText = "Ошибка записи"
        }
    }

    private func openVideoPicker() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let hasCameraAccess: Bool
        switch cameraStatus {
        case .authorized:
            hasCameraAccess = true
        case .notDetermined:
            hasCameraAccess = await AVCaptureDevice.requestAccess(for: .video)
        default:
            hasCameraAccess = false
        }

        guard hasCameraAccess else {
            errorText = "Нет доступа к камере"
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let hasMicAccess: Bool
        switch micStatus {
        case .authorized:
            hasMicAccess = true
        case .notDetermined:
            hasMicAccess = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            hasMicAccess = false
        }

        guard hasMicAccess else {
            errorText = "Нет доступа к микрофону для записи видео"
            return
        }

        errorText = nil
        showCamera = true
    }

    private func finishRecording(send: Bool) async {
        guard isRecording else { return }
        isRecording = false
        recordStarted = nil
        guard send else {
            _ = voiceEngine.stop()
            return
        }
        guard let (url, ms) = voiceEngine.stop(), ms >= 100 else {
            errorText = "Слишком короткая запись"
            return
        }
        attachBusy = true
        defer { attachBusy = false }
        do {
            let m = try await APIClient.shared.uploadVoice(conversationId: conversation.id, fileURL: url, durationMs: ms)
            if !messages.contains(where: { $0.id == m.id }) {
                messages.append(m)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не удалось отправить голос"
        }
    }

    private func uploadPickedVideo(_ url: URL) async {
        attachBusy = true
        defer { attachBusy = false }
        let asset = AVURLAsset(url: url)
        do {
            let dur = try await asset.load(.duration)
            let ms = max(1, Int(CMTimeGetSeconds(dur) * 1000))
            let ext = url.pathExtension.lowercased()
            let mime = ext == "mov" ? "video/quicktime" : "video/mp4"
            let m = try await APIClient.shared.uploadVideoNote(
                conversationId: conversation.id,
                fileURL: url,
                durationMs: ms,
                mimeType: mime
            )
            if !messages.contains(where: { $0.id == m.id }) {
                messages.append(m)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не удалось отправить видео"
        }
    }

    private func uploadPickedFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        attachBusy = true
        defer { attachBusy = false }
        do {
            let name = url.lastPathComponent
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            let ext = dest.pathExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            let cap = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let m = try await APIClient.shared.uploadFile(
                conversationId: conversation.id,
                fileURL: dest,
                originalName: name,
                mimeType: mime,
                caption: cap
            )
            if !cap.isEmpty { draft = "" }
            if !messages.contains(where: { $0.id == m.id }) {
                messages.append(m)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Не удалось отправить файл"
        }
    }
}

private extension DateFormatter {
    static let chatSqlite: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let chatHm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let chatDmhm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM HH:mm"
        return f
    }()
}
