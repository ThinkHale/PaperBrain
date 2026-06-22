import SwiftUI

/// Record a voice note, then transcribe and process it like a written note.
struct VoiceRecorderView: View {
    let onComplete: (Note) -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var vm = VoiceRecorderViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(vm.elapsedString)
                .font(.system(size: 54, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(vm.isRecording ? .primary : .secondary)

            // Record / stop button
            Button {
                vm.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.15))
                        .frame(width: 120, height: 120)
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isRecording ? .red : Color.accentColor)
                }
            }
            .disabled(vm.isProcessing)

            Text(vm.isRecording ? "Tap to stop" : (vm.hasRecording ? "Recording ready" : "Tap to record"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if vm.hasRecording && !vm.isRecording {
                VStack(spacing: 12) {
                    Button {
                        guard let userId = authVM.currentUser?.id else { return }
                        Task {
                            if let note = await vm.process(userId: userId) { onComplete(note) }
                        }
                    } label: {
                        Label("Transcribe & Save", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.isProcessing)

                    Button("Discard", role: .destructive) { vm.discard() }
                        .disabled(vm.isProcessing)
                }
                .padding(.horizontal, 32)
            }

            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .padding()
        .navigationTitle("Voice Note")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.isProcessing { ProcessingOverlay(message: vm.statusMessage) } }
    }
}
