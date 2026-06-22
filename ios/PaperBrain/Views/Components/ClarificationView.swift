import SwiftUI

/// Presented as a sheet when an [unclear] word is found in a note's transcription.
/// Lets the user type the correct word so the AI can learn their handwriting.
struct ClarificationView: View {
    @ObservedObject var viewModel: NoteDetailViewModel
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBanner
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach($viewModel.unclearWords) { $item in
                            ClarificationCard(item: $item)
                        }
                    }
                    .padding()
                }
                submitButton
            }
            .navigationTitle("Help the AI learn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some words were unclear")
                    .font(.subheadline.bold())
                Text("Filling these in helps the AI read your handwriting better next time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08))
    }

    private var submitButton: some View {
        Button {
            onSubmit()
            dismiss()
        } label: {
            Text("Submit Corrections")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }
}

// MARK: - Card per unclear word

private struct ClarificationCard: View {
    @Binding var item: NoteDetailViewModel.UnclearWord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The cropped snippet from the note — the key bit of context.
            if let img = item.croppedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tint.opacity(0.4), lineWidth: 1))
            } else {
                Label("No image preview available", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // AI's best guess
            if item.word != "[unclear]" {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                    Text("AI guessed: ")
                        .font(.caption).foregroundStyle(.secondary)
                    + Text("“\(item.word)”").font(.caption.bold())
                }
            }

            // Context snippet
            if item.contextSnippet != "(no surrounding context)" {
                Text(item.contextSnippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            // Correction input
            Text("What does it actually say?")
                .font(.caption.bold())
            TextField("Type the correct word…", text: $item.correction)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}
