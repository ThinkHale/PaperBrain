import SwiftUI
import AVFoundation

/// Compact play/pause control for a voice note stored in the note-assets bucket.
struct AudioPlayerView: View {
    let storagePath: String

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            VStack(alignment: .leading, spacing: 2) {
                Label("Voice recording", systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                if isLoading { Text("Loading…").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .onDisappear { player?.pause(); isPlaying = false }
    }

    private func toggle() async {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if player == nil {
            isLoading = true
            defer { isLoading = false }
            do {
                let url = try await StorageService.shared.signedURL(for: storagePath, bucket: "note-assets")
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                player = AVPlayer(url: url)
            } catch {
                self.error = "Couldn't load audio."
                return
            }
        }
        player?.seek(to: .zero, completionHandler: { _ in })
        player?.play()
        isPlaying = true
    }
}
