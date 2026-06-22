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
            Button("Delete \"\(note.displayTitle)\"", role: .destructive) {
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
                Text("Tap the **+** tab to type, draw, scan, or record your first note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No results for \"\(notesVM.searchQuery)\"")
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
                preview: SharePreview("Illuminote Export", image: Image(systemName: "square.and.arrow.up"))
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

    private var hasChips: Bool {
        !(note.categories ?? []).isEmpty || !(note.tags ?? []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: note.noteTypeValue.iconName)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if note.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(note.formattedDate)
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

            if hasChips {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.categories ?? [], id: \.self) { cat in
                            CategoryChip(name: cat)
                        }
                        ForEach(note.tags ?? [], id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
