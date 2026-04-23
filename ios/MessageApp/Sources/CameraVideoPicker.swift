import AVFoundation
import Combine
import SwiftUI
import UIKit

struct CameraVideoPicker: View {
    @Binding var videoURL: URL?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VideoNoteRecorder()
    @State private var pendingDismissOnSend = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.1, blue: 0.14),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 10)
                        .frame(width: 278, height: 278)

                    Circle()
                        .trim(from: 0, to: recorder.progress)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 278, height: 278)
                        .animation(.linear(duration: 0.12), value: recorder.progress)

                    VideoNotePreviewView(session: recorder.session)
                        .frame(width: 250, height: 250)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }

                    if !recorder.isRecording {
                        Image(systemName: recorder.canSend ? "paperplane.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white.opacity(recorder.canSend ? 0.92 : 0.75))
                    }
                }

                VStack(spacing: 8) {
                    Text(recorder.isRecording ? "Запись видеосообщения" : (recorder.canSend ? "Готово к отправке" : "Не удалось записать"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(recorder.durationText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                HStack(spacing: 14) {
                    Button("Отмена") {
                        cancel()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())

                    Button(sendButtonTitle) {
                        send()
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(sendButtonEnabled ? Color.white : Color.white.opacity(0.2))
                    .clipShape(Capsule())
                    .disabled(!sendButtonEnabled)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 34)
        }
        .task {
            await recorder.prepareAndStart()
        }
        .onDisappear {
            recorder.cleanup()
        }
        .onChange(of: recorder.recordedOutputURL) { url in
            guard pendingDismissOnSend, let url else { return }
            videoURL = url
            pendingDismissOnSend = false
            dismiss()
        }
        .alert("Ошибка камеры", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.errorText ?? "Не удалось подготовить запись")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { recorder.errorText != nil },
            set: { show in
                if !show {
                    recorder.errorText = nil
                }
            }
        )
    }

    private func cancel() {
        pendingDismissOnSend = false
        recorder.cancel()
        dismiss()
    }

    private func send() {
        if recorder.isRecording || recorder.isStoppingRecording {
            pendingDismissOnSend = true
            recorder.finishRecordingForSending()
            return
        }
        guard let url = recorder.finalizeForSending() else { return }
        videoURL = url
        dismiss()
    }

    private var sendButtonEnabled: Bool {
        recorder.isRecording || recorder.isStoppingRecording || recorder.canSend
    }

    private var sendButtonTitle: String {
        (recorder.isRecording || recorder.isStoppingRecording) ? "Готово" : "Отправить"
    }
}

private struct VideoNotePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class VideoNoteRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()

    @Published var progress: CGFloat = 0
    @Published var isRecording = false
    @Published var canSend = false
    @Published var errorText: String?
    @Published var elapsedSeconds = 0
    @Published var recordedOutputURL: URL?
    @Published var isStoppingRecording = false

    private let sessionQueue = DispatchQueue(label: "videonote.session.queue")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let maxDuration: TimeInterval = 60

    private var configured = false
    private var currentRecordingURL: URL?
    private var recordedURL: URL?
    private var recordingStartDate: Date?
    private var timer: Timer?
    private var isCancelling = false
    private var shouldFinalizeForSending = false

    var durationText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    func prepareAndStart() async {
        if !configured {
            do {
                try await configureSessionIfNeeded()
            } catch {
                errorText = "Не удалось настроить камеру"
                return
            }
        }
        await startSessionIfNeeded()
        startRecording()
    }

    func cancel() {
        isCancelling = true
        shouldFinalizeForSending = false
        isStoppingRecording = false
        timer?.invalidate()
        timer = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        if !movieOutput.isRecording {
            cleanupRecordedFiles()
        }
        stopSession()
        resetState()
        errorText = nil
        recordedOutputURL = nil
    }

    func finalizeForSending() -> URL? {
        guard canSend, let recordedURL else { return nil }
        stopSession()
        let output = recordedURL
        self.recordedURL = nil
        recordedOutputURL = nil
        isStoppingRecording = false
        resetState(keepElapsed: true)
        return output
    }

    func finishRecordingForSending() {
        shouldFinalizeForSending = true
        if movieOutput.isRecording {
            isStoppingRecording = true
            stopRecording()
        } else if canSend, let url = finalizeForSending() {
            recordedOutputURL = url
            shouldFinalizeForSending = false
        } else {
            isStoppingRecording = true
        }
    }

    func cleanup() {
        if !canSend {
            cleanupRecordedFiles()
        }
        if !movieOutput.isRecording {
            stopSession()
        }
    }

    private func configureSessionIfNeeded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    DispatchQueue.main.async {
                        self.configured = true
                        continuation.resume(returning: ())
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func configureSession() throws {
        guard !configured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        else {
            session.commitConfiguration()
            throw RecorderError.noCamera
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        movieOutput.movieFragmentInterval = .invalid

        if
            let connection = movieOutput.connection(with: .video),
            connection.isVideoOrientationSupported
        {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    private func startSessionIfNeeded() async {
        guard !session.isRunning else { return }
        let session = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume(returning: ())
            }
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        let session = session
        sessionQueue.async {
            session.stopRunning()
        }
    }

    private func startRecording() {
        guard !movieOutput.isRecording else { return }

        cleanupRecordedFiles()
        isCancelling = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-note-\(UUID().uuidString).mov")

        currentRecordingURL = url
        recordedURL = nil
        canSend = false
        errorText = nil
        recordedOutputURL = nil
        isStoppingRecording = false
        elapsedSeconds = 0
        progress = 0
        recordingStartDate = Date()
        isRecording = true

        if
            let connection = movieOutput.connection(with: .video),
            connection.isVideoOrientationSupported
        {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        movieOutput.startRecording(to: url, recordingDelegate: self)
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.recordingStartDate else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            DispatchQueue.main.async {
                self.elapsedSeconds = Int(elapsed)
                self.progress = min(CGFloat(elapsed / self.maxDuration), 1)
            }
            if elapsed >= self.maxDuration {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func cleanupRecordedFiles() {
        [currentRecordingURL, recordedURL].forEach { url in
            guard let url else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        currentRecordingURL = nil
        recordedURL = nil
    }

    private func resetState(keepElapsed: Bool = false) {
        progress = 0
        isRecording = false
        canSend = false
        recordingStartDate = nil
        if !keepElapsed {
            elapsedSeconds = 0
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            timer?.invalidate()
            timer = nil
            isRecording = false
            recordingStartDate = nil

            if isCancelling {
                cleanupRecordedFiles()
                resetState()
                errorText = nil
                isCancelling = false
                recordedOutputURL = nil
                isStoppingRecording = false
                return
            }

            if let error {
                errorText = error.localizedDescription
                cleanupRecordedFiles()
                resetState()
                recordedOutputURL = nil
                isStoppingRecording = false
                shouldFinalizeForSending = false
                return
            }

            recordedURL = outputFileURL
            currentRecordingURL = nil
            canSend = true
            progress = 1
            if shouldFinalizeForSending {
                recordedOutputURL = finalizeForSending()
                shouldFinalizeForSending = false
            } else {
                isStoppingRecording = false
            }
        }
    }
}

private enum RecorderError: Error {
    case noCamera
}
