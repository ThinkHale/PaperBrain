import Foundation
import UIKit

/// Drives in-app note creation: typed notes and Apple Pencil drawings.
@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var error: String?

    private let edge = EdgeFunctionService.shared
    private let db = SupabaseService.shared
    private let storage = StorageService.shared

    /// Organize and save a typed note. Returns the created note on success.
    func saveTyped(title: String, body: String) async -> Note? {
        let text = composedText(title: title, body: body)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Write something first."
            return nil
        }
        isProcessing = true
        statusMessage = "Organizing…"
        error = nil
        defer { isProcessing = false }
        do {
            let note = try await edge.processText(text: text, noteType: "typed")
            edge.findRelations(noteId: note.id)
            return note
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Save an Apple Pencil drawing: transcribe via the image pipeline, then
    /// stash the raw PKDrawing so it can be re-edited later.
    func saveDrawing(image: UIImage, drawingData: Data, userId: UUID) async -> Note? {
        isProcessing = true
        statusMessage = "Reading your note…"
        error = nil
        defer { isProcessing = false }

        guard let dataURL = StorageService.toDataURL(StorageService.resize(image)) else {
            error = "Could not encode the drawing."
            return nil
        }
        do {
            var note = try await edge.processNote(images: [dataURL])
            let path = "\(userId.uuidString)/\(note.id)/drawing.dat"
            try? await storage.uploadAsset(data: drawingData, contentType: "application/octet-stream", path: path)
            try? await db.setDrawingMeta(noteId: note.id, drawingPath: path)
            // Reflect the drawing kind locally so the list shows the right icon immediately.
            note.noteType = NoteType.drawing.rawValue
            note.sourceType = .drawing
            note.drawingPath = path
            edge.findRelations(noteId: note.id)
            return note
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func composedText(title: String, body: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return b }
        if b.isEmpty { return t }
        return "\(t)\n\n\(b)"
    }
}
