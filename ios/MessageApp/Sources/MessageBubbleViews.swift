import AVKit
import SwiftUI
import UIKit

// MARK: - Голос (с сервера обычно WebM — AVPlayer; свои записи с iOS — M4A)

struct VoiceMessageBubble: View {
    let messageId: Int
    let durationMs: Int?
    @EnvironmentObject var theme: ThemeStore

    @State private var fileURL: URL?
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var hasError = false

    private var c: TelegramPalette { theme.palette }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await togglePlay() }
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(c.blue)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Голосовое сообщение")
                    .font(.subheadline)
                    .foregroundStyle(c.text)
                if let durationMs, durationMs > 0 {
                    Text("\(max(1, durationMs / 1000)) с")
                        .font(.caption)
                        .foregroundStyle(c.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: messageId) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard fileURL == nil, !hasError else { return }
        do {
            let data = try await APIClient.shared.downloadMedia(messageId: messageId)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(messageId).webm")
            try data.write(to: url, options: .atomic)
            fileURL = url
        } catch {
            hasError = true
        }
    }

    private func togglePlay() async {
        if fileURL == nil {
            await loadIfNeeded()
        }
        guard let fileURL else { return }
        if player == nil {
            player = AVPlayer(url: fileURL)
        }
        guard let player else { return }
        if playing {
            player.pause()
            playing = false
        } else {
            player.play()
            playing = true
        }
    }
}

// MARK: - Видеокружок

struct VideoCircleBubble: View {
    let messageId: Int
    @EnvironmentObject var theme: ThemeStore

    @State private var player: AVPlayer?
    @State private var hasError = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.palette.blue, lineWidth: 2))
            } else if hasError {
                Text("Видео недоступно")
                    .font(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                ProgressView()
                    .frame(width: 240, height: 240)
            }
        }
        .task(id: messageId) {
            await load()
        }
    }

    private func load() async {
        do {
            let data = try await APIClient.shared.downloadMedia(messageId: messageId)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vid-\(messageId).mov")
            try data.write(to: url, options: .atomic)
            player = AVPlayer(url: url)
        } catch {
            hasError = true
        }
    }
}

// MARK: - Файл / картинка

struct FileAttachmentBubble: View {
    let message: MessageDTO
    @EnvironmentObject var theme: ThemeStore

    @State private var image: UIImage?
    @State private var hasError = false
    @State private var showImageViewer = false

    private var c: TelegramPalette { theme.palette }
    private var isImage: Bool { (message.fileMime ?? "").hasPrefix("image/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 300, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture {
                            showImageViewer = true
                        }
                    Text(shortTime(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.42))
                        .clipShape(Capsule())
                        .padding(8)
                }
            } else if !isImage {
                HStack(spacing: 8) {
                    Text("📎")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.fileName ?? "Файл")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(c.text)
                        if let s = message.fileSize, s > 0 {
                            Text(byteString(s))
                                .font(.caption)
                                .foregroundStyle(c.textSecondary)
                        }
                    }
                }
            } else if hasError {
                Text("Не удалось загрузить")
                    .font(.caption)
                    .foregroundStyle(c.textSecondary)
            } else {
                ProgressView()
            }

            if !message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(c.text)
            }

            if !isImage {
                Button("Скачать") {
                    Task { await saveFile() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(c.blue)
            }
        }
        .task(id: message.id) {
            await loadPreview()
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            if let image {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(12)
                    Button {
                        showImageViewer = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                .onTapGesture {
                    showImageViewer = false
                }
            }
        }
    }

    private func byteString(_ n: Int) -> String {
        if n < 1024 { return "\(n) Б" }
        if n < 1024 * 1024 { return String(format: "%.1f КБ", Double(n) / 1024) }
        return String(format: "%.1f МБ", Double(n) / 1024 / 1024)
    }

    private func loadPreview() async {
        guard isImage else { return }
        do {
            let data = try await APIClient.shared.downloadMedia(messageId: message.id)
            if let ui = UIImage(data: data) {
                image = ui
            } else {
                hasError = true
            }
        } catch {
            hasError = true
        }
    }

    @MainActor
    private func saveFile() async {
        do {
            let data = try await APIClient.shared.downloadFileAttachment(messageId: message.id)
            let name = message.fileName ?? "file"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            presentShare(url: url)
        } catch {
            hasError = true
        }
    }

    private func presentShare(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        root.present(av, animated: true)
    }

    private func shortTime(_ raw: String) -> String {
        let normalized = raw.contains("T") ? raw : raw.replacingOccurrences(of: " ", with: "T")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d =
            parser.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
            ?? DateFormatter.msgSqlite.date(from: raw)
        guard let d else { return raw }
        return DateFormatter.msgHm.string(from: d)
    }
}

private extension DateFormatter {
    static let msgSqlite: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let msgHm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
}
