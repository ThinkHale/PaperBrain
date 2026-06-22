import Foundation
import AVFoundation

/// Records a voice memo, uploads it, transcribes it, and turns the transcript
/// into a fully-processed note.
@MainActor
final class VoiceRecorderViewModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var isProcessing = false
    @Published var elapsed: TimeInterval = 0
    @Published var statusMessage = ""
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    private let edge = EdgeFunctionService.shared
    private let db = SupabaseService.shared
    private let storage = StorageService.shared

    var elapsedString: String {
        let s = Int(elapsed)
        return String(format: "%01d:%02d", s / 60, s % 60)
    }

    // MARK: - Recording

    func toggleRecording() {
        isRecording ? stop() : requestAndStart()
    }

    private func requestAndStart() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted { self.start() }
                else { self.error = "Microphone access is needed to record voice notes. Enable it in Settings." }
            }
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record()

            self.recorder = recorder
            self.fileURL = url
            self.isRecording = true
            self.hasRecording = false
            self.elapsed = 0
            self.error = nil

            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder else { return }
                    self.elapsed = r.currentTime
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        hasRecording = (fileURL != nil)
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func discard() {
        stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        hasRecording = false
        elapsed = 0
    }

    // MARK: - Process

    func process(userId: UUID) async -> Note? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            error = "No recording to process."
            return nil
        }
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let path = "\(userId.uuidString)/voice/\(fileURL.lastPathComponent)"
        do {
            statusMessage = "Uploading…"
            try await storage.uploadAsset(data: data, contentType: "audio/m4a", path: path)

            statusMessage = "Transcribing…"
            let transcript = try await edge.transcribeAudio(audioPath: path)

            statusMessage = "Organizing…"
            let note = try await edge.processText(text: transcript, noteType: "voice")
            try? await db.updateNoteAssetPath(noteId: note.id, audioPath: path)
            edge.findRelations(noteId: note.id)
            return note
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

extension VoiceRecorderViewModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in if !flag { self.error = "Recording failed." } }
    }
}
