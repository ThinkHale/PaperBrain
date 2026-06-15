import Foundation
import UIKit
import SwiftUI

@MainActor
final class NoteDetailViewModel: ObservableObject {
    @Published var note: Note
    @Published var images: [NoteImage] = []
    @Published var imageCache: [UUID: UIImage] = [:]
    @Published var annotations: [Annotation] = []
    @Published var relations: [Relation] = []
    @Published var relatedNotes: [UUID: Note] = [:]
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    // Editing state
    @Published var editingTitle: String
    @Published var editingOrganized: String
    @Published var isEditing = false

    // Clarification
    @Published var unclearWords: [UnclearWord] = []
    @Published var showClarification = false

    private let db = SupabaseService.shared
    private let storage = StorageService.shared
    private let edgeFunctions = EdgeFunctionService.shared

    struct UnclearWord: Identifiable {
        let id = UUID()
        let word: String
        let contextSnippet: String
        var correction: String = ""
        var croppedImage: UIImage?
    }

    init(note: Note) {
        self.note = note
        self.editingTitle = note.title
        self.editingOrganized = note.organized ?? ""
    }

    func loadAll() async {
        isLoading = true
        async let imgsTask = db.fetchNoteImages(noteId: note.id)
        async let annsTask = db.fetchAnnotations(noteId: note.id)
        async let relsTask = db.fetchRelations(noteId: note.id)

        do {
            let (imgs, anns, rels) = try await (imgsTask, annsTask, relsTask)
            images = imgs
            annotations = anns
            relations = rels
            await loadRelatedNoteTitles(relations: rels)
            await downloadImages(imgs)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        checkForUnclearWords()
    }

    // MARK: - Images

    private func downloadImages(_ noteImages: [NoteImage]) async {
        for ni in noteImages {
            guard imageCache[ni.id] == nil else { continue }
            if let url = try? await storage.signedURL(for: ni.storagePath),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                imageCache[ni.id] = img
            }
        }
    }

    // MARK: - Related notes

    private func loadRelatedNoteTitles(relations: [Relation]) async {
        for rel in relations {
            let otherId = rel.otherNoteId(relativeTo: note.id)
            if relatedNotes[otherId] == nil,
               let other = try? await db.fetchNote(id: otherId) {
                relatedNotes[otherId] = other
            }
        }
    }

    // MARK: - Editing

    func saveTitle() async {
        guard editingTitle != note.title, !editingTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        do {
            try await db.updateNoteTitle(noteId: note.id, title: editingTitle)
            note.title = editingTitle
        } catch {
            self.error = error.localizedDescription
            editingTitle = note.title
        }
        isSaving = false
    }

    func saveOrganized() async {
        isSaving = true
        do {
            try await db.updateNoteOrganized(noteId: note.id, organized: editingOrganized)
            note.organized = editingOrganized
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    func addTag(_ tag: String) async {
        let trimmed = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !(note.tags?.contains(trimmed) ?? false) else { return }
        var tags = note.tags ?? []
        tags.append(trimmed)
        do {
            try await db.updateNoteTags(noteId: note.id, tags: tags)
            note.tags = tags
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeTag(_ tag: String) async {
        var tags = note.tags ?? []
        tags.removeAll { $0 == tag }
        do {
            try await db.updateNoteTags(noteId: note.id, tags: tags)
            note.tags = tags
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Annotations

    func addAnnotation(_ annotation: Annotation) async {
        do {
            try await db.insertAnnotation(annotation)
            annotations.append(annotation)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAnnotation(_ annotation: Annotation) async {
        do {
            try await db.deleteAnnotation(id: annotation.id)
            annotations.removeAll { $0.id == annotation.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reprocessAnnotationRegion(_ annotation: Annotation, sourceImage: UIImage) async {
        guard let shapeData = annotation.shapeData as? Annotation.ShapeData,
              let x = shapeData.x, let y = shapeData.y,
              let w = shapeData.width, let h = shapeData.height else { return }

        let rect = CGRect(x: x, y: y, width: w, height: h)
        guard let croppedData = StorageService.crop(sourceImage, normalizedRect: rect),
              let dataURL = "data:image/jpeg;base64," + croppedData.base64EncodedString() as String? else { return }

        do {
            let result = try await edgeFunctions.processRegion(
                image: dataURL,
                tag: annotation.tag,
                noteId: note.id
            )
            if let content = result.content {
                try await db.updateAnnotationContent(id: annotation.id, regionContent: content)
                if let idx = annotations.firstIndex(where: { $0.id == annotation.id }) {
                    annotations[idx].regionContent = content
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Unclear words

    private func checkForUnclearWords() {
        guard let transcription = note.transcription else { return }
        let pattern = /\[unclear\]/
        let snippets = transcription.components(separatedBy: .newlines)
        unclearWords = snippets.compactMap { line in
            guard line.contains("[unclear]") else { return nil }
            return UnclearWord(word: "[unclear]", contextSnippet: line)
        }
        showClarification = !unclearWords.isEmpty
    }

    func submitClarifications(userId: UUID) async {
        let filledIn = unclearWords.filter { !$0.correction.isEmpty }
        guard !filledIn.isEmpty else {
            showClarification = false
            return
        }
        for item in filledIn {
            let correction = HandwritingCorrection(
                userId: userId,
                original: item.word,
                correction: item.correction,
                contextSnippet: item.contextSnippet,
                noteId: note.id
            )
            try? await db.insertCorrection(correction)
        }
        edgeFunctions.learnHandwriting(userId: userId)
        showClarification = false
    }
}
