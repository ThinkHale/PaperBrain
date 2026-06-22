import Foundation
import UIKit
import SwiftUI

@MainActor
final class NoteDetailViewModel: ObservableObject {
    @Published var note: Note
    @Published var images: [NoteImage] = []
    @Published var imageCache: [String: UIImage] = [:]
    @Published var annotations: [Annotation] = []
    @Published var relations: [Relation] = []
    @Published var relatedNotes: [String: Note] = [:]
    @Published var noteTodos: [Todo] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isSplitting = false
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
        let word: String            // the AI's best guess (or "[unclear]")
        let contextSnippet: String
        var correction: String = ""
        var croppedImage: UIImage?
    }

    init(note: Note) {
        self.note = note
        self.editingTitle = note.displayTitle
        self.editingOrganized = note.organized ?? ""
    }

    func loadAll() async {
        isLoading = true
        async let imgsTask = db.fetchNoteImages(noteId: note.id)
        async let annsTask = db.fetchAnnotations(noteId: note.id)
        async let relsTask = db.fetchRelations(noteId: note.id)
        async let todosTask = db.fetchTodos(noteId: note.id)

        do {
            let (imgs, anns, rels, todos) = try await (imgsTask, annsTask, relsTask, todosTask)
            images = imgs
            annotations = anns
            relations = rels
            noteTodos = todos
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
        guard editingTitle != note.displayTitle, !editingTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        do {
            try await db.updateNoteTitle(noteId: note.id, title: editingTitle)
            note.title = editingTitle
        } catch {
            self.error = error.localizedDescription
            editingTitle = note.displayTitle
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

    func addCategory(_ category: String) async {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !(note.categories?.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? false) else { return }
        var categories = note.categories ?? []
        categories.append(trimmed)
        do {
            try await db.updateNoteCategories(noteId: note.id, categories: categories)
            note.categories = categories
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeCategory(_ category: String) async {
        var categories = note.categories ?? []
        categories.removeAll { $0 == category }
        do {
            try await db.updateNoteCategories(noteId: note.id, categories: categories)
            note.categories = categories
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
        let shapeData = annotation.shapeData
        guard let x = shapeData.x, let y = shapeData.y,
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

    // MARK: - To-dos

    func toggleNoteTodo(_ todo: Todo) async {
        guard let idx = noteTodos.firstIndex(of: todo) else { return }
        let newValue = !noteTodos[idx].done
        noteTodos[idx].done = newValue
        do {
            try await db.setTodoDone(id: todo.id, done: newValue)
        } catch {
            noteTodos[idx].done = !newValue
            self.error = error.localizedDescription
        }
    }

    // MARK: - Note separation

    /// Crop each region from the page and turn it into its own note, linked back
    /// to this note. Returns the newly created notes.
    func splitIntoNotes(rects: [CGRect], sourceImage: UIImage, userId: UUID) async -> [Note] {
        guard !rects.isEmpty else { return [] }
        isSplitting = true
        defer { isSplitting = false }

        var created: [Note] = []
        for rect in rects {
            guard let cropped = StorageService.cropImage(sourceImage, normalizedRect: rect),
                  let dataURL = StorageService.toDataURL(StorageService.resize(cropped)) else { continue }
            do {
                let newNote = try await edgeFunctions.processNote(images: [dataURL])
                try? await db.insertManualRelation(fromId: note.id, toId: newNote.id, userId: userId)
                edgeFunctions.findRelations(noteId: newNote.id)
                created.append(newNote)
            } catch {
                self.error = error.localizedDescription
            }
        }
        return created
    }

    // MARK: - Unclear words

    private func checkForUnclearWords() {
        // Preferred path: the AI returned located regions, so we can show a crop.
        if let regions = note.unclearRegions, !regions.isEmpty {
            unclearWords = regions.map { region in
                let guess = region.guess?.trimmingCharacters(in: .whitespaces) ?? ""
                let context = region.context?.trimmingCharacters(in: .whitespaces) ?? ""
                return UnclearWord(
                    word: guess.isEmpty ? "[unclear]" : guess,
                    contextSnippet: context.isEmpty ? "(no surrounding context)" : context,
                    correction: guess,   // prefill the guess; user confirms or fixes it
                    croppedImage: croppedImage(for: region)
                )
            }
            showClarification = !unclearWords.isEmpty
            return
        }

        // Fallback for notes processed before bounding boxes existed.
        guard let transcription = note.transcription else { return }
        let snippets = transcription.components(separatedBy: .newlines)
        unclearWords = snippets.compactMap { line in
            guard line.contains("[unclear]") else { return nil }
            return UnclearWord(word: "[unclear]", contextSnippet: line)
        }
        showClarification = !unclearWords.isEmpty
    }

    /// Crop the page image to an unclear word's bounding box (padded for legibility).
    private func croppedImage(for region: UnclearRegion) -> UIImage? {
        guard let x = region.x, let y = region.y, let w = region.w, let h = region.h,
              w > 0, h > 0 else { return nil }
        let page = region.page ?? 0
        guard let noteImage = images.first(where: { ($0.pageNumber ?? 0) == page }) ?? images.first,
              let source = imageCache[noteImage.id] else { return nil }

        // Pad the box by ~8% of its size (min 2% of the page) so the word is readable.
        let padX = max(w * 0.18, 0.02)
        let padY = max(h * 0.5, 0.02)
        let rect = CGRect(x: x - padX, y: y - padY, width: w + padX * 2, height: h + padY * 2)
        return StorageService.cropImage(source, normalizedRect: rect)
    }

    func submitClarifications(userId: UUID) async {
        // Only learn from words the user actually changed away from the AI's guess.
        let filledIn = unclearWords.filter {
            let corrected = $0.correction.trimmingCharacters(in: .whitespaces)
            return !corrected.isEmpty && corrected != $0.word
        }
        guard !filledIn.isEmpty else {
            showClarification = false
            return
        }
        for item in filledIn {
            let correction = HandwritingCorrection(
                userId: userId,
                original: item.word,                // AI's guess
                correction: item.correction,        // what it actually said
                contextSnippet: item.contextSnippet,
                noteId: note.id
            )
            try? await db.insertCorrection(correction)
        }
        edgeFunctions.learnHandwriting(userId: userId)
        showClarification = false
    }
}
