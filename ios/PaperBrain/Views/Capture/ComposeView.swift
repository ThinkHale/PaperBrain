import SwiftUI

/// Type a note; on save it's organized, tagged, and to-do-extracted by the AI.
struct ComposeView: View {
    let onComplete: (Note) -> Void

    @StateObject private var vm = ComposeViewModel()
    @State private var title = ""
    @State private var body_ = ""
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                        .font(.headline)
                }
                Section("Note") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 240)
                        .focused($bodyFocused)
                }
            }
            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
        }
        .navigationTitle("Type a Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { save() }
                    .disabled(vm.isProcessing || trimmedEmpty)
            }
        }
        .overlay { if vm.isProcessing { ProcessingOverlay(message: vm.statusMessage) } }
        .onAppear { bodyFocused = true }
    }

    private var trimmedEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        Task {
            if let note = await vm.saveTyped(title: title, body: body_) {
                onComplete(note)
            }
        }
    }
}

/// Shared translucent progress overlay for capture flows.
struct ProcessingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white)
                Text(message.isEmpty ? "Working…" : message)
                    .foregroundStyle(.white).font(.headline)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
