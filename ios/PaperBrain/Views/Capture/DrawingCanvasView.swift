import SwiftUI
import PencilKit

/// Handwrite a note with Apple Pencil (or finger). On save the drawing is
/// rendered to an image, transcribed through the normal note pipeline, and the
/// raw strokes are kept so the note stays re-editable.
struct DrawingCanvasView: View {
    let onComplete: (Note) -> Void

    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var vm = ComposeViewModel()
    @State private var canvasView = PKCanvasView()
    @State private var isEmpty = true

    var body: some View {
        VStack(spacing: 0) {
            // Controls live at the top — the PencilKit tool palette docks along
            // the bottom of the screen, so bottom-bar buttons get covered.
            controlStrip
            PencilCanvas(canvasView: $canvasView, isEmpty: $isEmpty)
                .background(Color.white)
            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("Draw a Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { save() }
                    .disabled(vm.isProcessing || isEmpty)
            }
        }
        .overlay { if vm.isProcessing { ProcessingOverlay(message: vm.statusMessage) } }
    }

    private var controlStrip: some View {
        HStack(spacing: 22) {
            Button {
                canvasView.undoManager?.undo()
                isEmpty = canvasView.drawing.strokes.isEmpty
            } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!(canvasView.undoManager?.canUndo ?? false))

            Button {
                canvasView.undoManager?.redo()
                isEmpty = canvasView.drawing.strokes.isEmpty
            } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!(canvasView.undoManager?.canRedo ?? false))

            Spacer()

            Button(role: .destructive) {
                canvasView.drawing = PKDrawing()
                isEmpty = true
            } label: { Label("Clear", systemImage: "trash") }
                .disabled(isEmpty)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func save() {
        guard let userId = authVM.currentUser?.id else { return }
        let drawing = canvasView.drawing
        let bounds = canvasView.bounds
        // Render strokes over white so the AI sees a clean page.
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(bounds)
            drawing.image(from: bounds, scale: UIScreen.main.scale).draw(in: bounds)
        }
        let drawingData = drawing.dataRepresentation()
        Task {
            if let note = await vm.saveDrawing(image: image, drawingData: drawingData, userId: userId) {
                onComplete(note)
            }
        }
    }
}

// MARK: - PencilKit wrapper

private struct PencilCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var isEmpty: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isEmpty: $isEmpty) }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator

        // Show the system tool picker (pens, eraser, colors).
        let picker = context.coordinator.toolPicker
        picker.setVisible(true, forFirstResponder: canvasView)
        picker.addObserver(canvasView)
        DispatchQueue.main.async { canvasView.becomeFirstResponder() }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        private var isEmpty: Binding<Bool>

        init(isEmpty: Binding<Bool>) { self.isEmpty = isEmpty }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isEmpty.wrappedValue = canvasView.drawing.strokes.isEmpty
        }
    }
}
