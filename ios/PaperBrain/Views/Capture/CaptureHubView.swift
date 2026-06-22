import SwiftUI

/// The "+" capture hub: create a note by typing, drawing (Apple Pencil),
/// scanning a photo/PDF, or recording your voice.
struct CaptureHubView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @EnvironmentObject private var todosVM: TodosViewModel
    @EnvironmentObject private var tagsVM: TagsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink {
                        ComposeView(onComplete: complete)
                    } label: {
                        CaptureOption(icon: "keyboard", title: "Type a note",
                                      subtitle: "Write it out — we'll organize and tag it", tint: .blue)
                    }

                    NavigationLink {
                        DrawingCanvasView(onComplete: complete)
                    } label: {
                        CaptureOption(icon: "pencil.and.scribble", title: "Draw a note",
                                      subtitle: "Apple Pencil or finger — handwriting becomes text", tint: .purple)
                    }

                    NavigationLink {
                        UploadView(onComplete: complete)
                    } label: {
                        CaptureOption(icon: "camera.viewfinder", title: "Scan paper",
                                      subtitle: "Photos or a PDF of existing notes", tint: .orange)
                    }

                    NavigationLink {
                        VoiceRecorderView(onComplete: complete)
                    } label: {
                        CaptureOption(icon: "waveform", title: "Record a voice note",
                                      subtitle: "Speak it — we'll transcribe and process it", tint: .pink)
                    }
                }
                .padding()
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Shared completion for every capture flow.
    private func complete(_ note: Note) {
        notesVM.prepend(note)
        Task {
            await todosVM.refresh()
            await tagsVM.refresh()
        }
        toastVM.show("Note created", style: .success)
        dismiss()
    }
}

private struct CaptureOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
