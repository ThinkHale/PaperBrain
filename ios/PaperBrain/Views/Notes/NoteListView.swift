import SwiftUI

struct NoteListView: View {
    @EnvironmentObject private var notesVM: NotesViewModel
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var noteToDelete: Note?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if notesVM.isLoading && notesVM.notes.isEmpty {
                    ProgressView("Loading notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notesVM.filteredNotes.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $notesVM.searchQuery, prompt: "Search notes…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    exportMenu
                }
            }
            .refreshable {
                guard let user = authVM.currentUser else { return }
                await notesVM.fetchNotes(userId: user.id)
            }
        }
    }

    // MARK: - Subviews

    private var noteList: some View {
        List {
            ForEach(notesVM.filteredNotes) { note in
                NavigationLink(destination: NoteDetailView(note: note)) {
                    NoteRowView(note: note)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        noteToDelete = note
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, presenting: noteToDelete) { note in
            Button("Delete "\(note.title)"", role: .destructive) {
                Task { await notesVM.deleteNote(note) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            if notesVM.searchQuery.isEmpty {
                Text("No notes yet")
                    .font(.title3.bold())
                Text("Tap **Scan** to upload your first handwritten note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No results for "\(notesVM.searchQuery)"")
                    .font(.title3.bold())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exportMenu: some View {
        Menu {
            ShareLink(
                item: notesExportData,
                preview: SharePreview("PaperBrain Export", image: Image(systemName: "square.and.arrow.up"))
            ) {
                Label("Export All (JSON)", systemImage: "arrow.down.doc")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var notesExportData: Data {
        notesVM.exportAllJSON(notes: notesVM.notes) ?? Data()
    }
}

// MARK: - Row

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if note.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(note.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary = note.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let tags = note.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
