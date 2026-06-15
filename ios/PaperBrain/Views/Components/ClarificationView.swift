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
        VStack(alignment: .leading, spacing: 10) {
            // Context snippet
            Text("Context")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(item.contextSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            // Cropped image if available
            if let img = item.croppedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 100)
                    .cornerRadius(8)
            }

            // Correction input
            Text("What does it say?")
                .font(.caption.bold())
            TextField("Type the correct word…", text: $item.correction)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}
