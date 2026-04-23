import AVFoundation
import SwiftUI
import UIKit

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
            let ext = voiceFileExtension(for: data)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(messageId).\(ext)")
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
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
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

    private func voiceFileExtension(for data: Data) -> String {
        if data.count >= 12 {
            let box = String(data: data.subdata(in: 4..<8), encoding: .ascii)
            if box == "ftyp" {
                return "m4a"
            }
        }
        if data.starts(with: Data("OggS".utf8)) {
            return "ogg"
        }
        if data.starts(with: Data("RIFF".utf8)) {
            return "wav"
        }
        if data.starts(with: Data([0x1A, 0x45, 0xDF, 0xA3])) {
            return "webm"
        }
        return "m4a"
    }
}

struct VideoCircleBubble: View {
    let messageId: Int
    let durationMs: Int?
    @EnvironmentObject var theme: ThemeStore

    private let bubbleSize: CGFloat = 212
    private let circleSize: CGFloat = 204
    private let videoSize: CGFloat = 192

    @State private var player: AVPlayer?
    @State private var hasError = false
    @State private var playing = false
    @State private var progress: CGFloat = 0
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if let player {
                ZStack {
                    Circle()
                        .stroke(theme.palette.blue.opacity(0.22), lineWidth: 4)
                        .frame(width: circleSize, height: circleSize)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            theme.palette.blue,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: circleSize, height: circleSize)
                        .animation(.linear(duration: 0.1), value: progress)

                    VideoNotePlayerView(player: player)
                        .frame(width: videoSize, height: videoSize)
                        .clipShape(Circle())
                        .contentShape(Circle())
                        .onTapGesture {
                            togglePlayback()
                        }
                        .overlay {
                            ZStack {
                                if !playing {
                                    Circle()
                                        .fill(.black.opacity(0.34))
                                        .frame(width: 54, height: 54)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .offset(x: 2)
                                }
                            }
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let durationMs {
                        Text(formattedDuration(durationMs))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.38))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
                .onDisappear {
                    teardownPlayer()
                }
                .frame(width: bubbleSize, height: bubbleSize)
            } else if hasError {
                Text("Видео недоступно")
                    .font(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                ProgressView()
                    .frame(width: bubbleSize, height: bubbleSize)
            }
        }
        .frame(width: bubbleSize, alignment: .leading)
        .padding(4)
        .task(id: messageId) {
            await load()
        }
    }

    private func load() async {
        do {
            let data = try await APIClient.shared.downloadMedia(messageId: messageId)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vid-\(messageId).mov")
            try data.write(to: url, options: .atomic)
            let avPlayer = AVPlayer(url: url)
            avPlayer.actionAtItemEnd = .pause
            player = avPlayer
            installObserver(for: avPlayer)
        } catch {
            hasError = true
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if playing {
            player.pause()
            playing = false
            return
        }
        if progress >= 0.999 {
            player.seek(to: .zero)
            progress = 0
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        playing = true
    }

    private func installObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard let item = player.currentItem else { return }
            let durationSeconds = item.duration.seconds
            guard durationSeconds.isFinite, durationSeconds > 0 else { return }
            progress = min(max(CGFloat(time.seconds / durationSeconds), 0), 1)
            if progress >= 0.999 {
                playing = false
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            playing = false
            progress = 1
        }
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        playing = false
    }

    private func formattedDuration(_ durationMs: Int) -> String {
        let totalSeconds = max(1, durationMs / 1000)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct VideoNotePlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct FileAttachmentBubble: View {
    let message: MessageDTO
    let bubbleMaxWidth: CGFloat
    @EnvironmentObject var theme: ThemeStore

    @State private var image: UIImage?
    @State private var hasError = false
    @State private var showImageViewer = false

    private var c: TelegramPalette { theme.palette }
    private var isImage: Bool { (message.fileMime ?? "").hasPrefix("image/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Button {
                    showImageViewer = true
                } label: {
                    let fittedSize = fittedImageSize(for: image)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(4)
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
                FullScreenImageView(image: image)
            }
        }
        .frame(
            width: imageBubbleWidth,
            alignment: .leading
        )
    }

    private func fittedImageSize(for image: UIImage) -> CGSize {
        let originalSize = image.size
        let maxWidth = min(bubbleMaxWidth - 8, 280)
        let maxHeight: CGFloat = 320
        let minWidth: CGFloat = 140

        guard originalSize.width > 0, originalSize.height > 0 else {
            return CGSize(width: maxWidth, height: min(maxHeight, maxWidth * 1.1))
        }

        let widthScale = maxWidth / originalSize.width
        let heightScale = maxHeight / originalSize.height
        let scale = min(widthScale, heightScale, 1)

        var fitted = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        if fitted.width < minWidth {
            let minWidthScale = minWidth / originalSize.width
            let adjustedScale = min(minWidthScale, heightScale, 1)
            fitted = CGSize(
                width: originalSize.width * adjustedScale,
                height: originalSize.height * adjustedScale
            )
        }

        return fitted
    }

    private var imageBubbleWidth: CGFloat? {
        guard isImage, let image else { return nil }
        return fittedImageSize(for: image).width + 8
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
}

private struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: dragOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(20)
            }
        }
        .statusBarHidden()
    }

    private var backgroundOpacity: Double {
        let progress = min(abs(dragOffset.height) / 240, 0.7)
        return 1 - progress
    }
}
