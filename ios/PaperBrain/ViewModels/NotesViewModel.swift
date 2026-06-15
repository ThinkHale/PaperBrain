import Foundation
import Combine

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var filteredNotes: [Note] = []
    @Published var searchQuery = "" {
        didSet { applySearch() }
    }
    @Published var isLoading = false
    @Published var error: String?

    private let db = SupabaseService.shared

    func fetchNotes(userId: UUID) async {
        isLoading = true
        error = nil
        do {
            notes = try await db.fetchNotes(userId: userId)
            applySearch()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func deleteNote(_ note: Note) async {
        do {
            try await db.deleteNote(id: note.id)
            notes.removeAll { $0.id == note.id }
            applySearch()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Called after a new note is received from the edge function.
    func prepend(_ note: Note) {
        notes.insert(note, at: 0)
        applySearch()
    }

    /// Update a note in the local array (e.g. after edit).
    func replace(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        }
        applySearch()
    }

    // MARK: - Search

    private func applySearch() {
        guard !searchQuery.isEmpty else {
            filteredNotes = notes
            return
        }
        let q = searchQuery.lowercased()
        filteredNotes = notes.filter { note in
            note.title.lowercased().contains(q) ||
            (note.summary?.lowercased().contains(q) ?? false) ||
            (note.transcription?.lowercased().contains(q) ?? false) ||
            (note.tags?.joined(separator: " ").lowercased().contains(q) ?? false) ||
            (note.keyPoints?.joined(separator: " ").lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Export

    func exportMarkdown(for note: Note) -> String {
        var md = "# \(note.title)\n\n"
        if let summary = note.summary { md += "**Summary:** \(summary)\n\n" }
        if let tags = note.tags, !tags.isEmpty { md += "**Tags:** \(tags.joined(separator: ", "))\n\n" }
        if let kp = note.keyPoints, !kp.isEmpty {
            md += "## Key Points\n" + kp.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if let organized = note.organized { md += "## Organized\n\n\(organized)\n\n" }
        if let transcription = note.transcription { md += "## Transcription\n\n\(transcription)\n" }
        return md
    }

    func exportAllJSON(notes: [Note]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(notes)
    }
}
