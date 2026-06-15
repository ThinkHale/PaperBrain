import Foundation
import UIKit
import PDFKit

@MainActor
final class UploadViewModel: ObservableObject {
    @Published var selectedImages: [UIImage] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var error: String?
    @Published var completedNote: Note?

    private let edge = EdgeFunctionService.shared

    // MARK: - Image selection

    func addImages(_ images: [UIImage]) {
        selectedImages.append(contentsOf: images.map { StorageService.resize($0) })
    }

    func addPDF(data: Data) {
        guard let pdf = PDFDocument(data: data) else { return }
        var pages: [UIImage] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            pages.append(StorageService.resize(img))
        }
        selectedImages.append(contentsOf: pages)
    }

    func removePage(at index: Int) {
        guard selectedImages.indices.contains(index) else { return }
        selectedImages.remove(at: index)
    }

    func clearAll() {
        selectedImages = []
        completedNote = nil
        error = nil
        progress = 0
        statusMessage = ""
    }

    // MARK: - Process

    func process() async {
        guard !selectedImages.isEmpty else { return }
        isProcessing = true
        error = nil
        completedNote = nil
        progress = 0.1
        statusMessage = "Preparing images…"

        // Convert to base64 data-URLs
        let dataURLs = selectedImages.compactMap { StorageService.toDataURL($0) }
        guard dataURLs.count == selectedImages.count else {
            error = "Failed to encode one or more images"
            isProcessing = false
            return
        }

        progress = 0.3
        statusMessage = "Sending to AI…"

        do {
            let note = try await edge.processNote(images: dataURLs)
            progress = 0.9
            statusMessage = "Saving…"
            completedNote = note

            // Fire-and-forget relation finding
            edge.findRelations(noteId: note.id)

            progress = 1.0
            statusMessage = "Done"
        } catch {
            self.error = error.localizedDescription
        }

        isProcessing = false
    }
}
