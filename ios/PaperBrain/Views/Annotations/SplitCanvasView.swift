import SwiftUI

/// Draw boxes around the distinct topics on a page, then split each region into
/// its own note. Reuses the annotation drawing engine (`CanvasOverlay`).
struct SplitCanvasView: View {
    let image: UIImage
    let isProcessing: Bool
    let onSplit: ([CGRect]) -> Void

    @State private var shapes: [PendingShape] = []
    @State private var tool: ShapeType = .rect
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructions
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        CanvasOverlay(
                            imageSize: image.size,
                            containerSize: geo.size,
                            tool: tool,
                            existingAnnotations: previewAnnotations,
                            onShapeFinished: { shapes.append($0) },
                            onDeleteAnnotation: { _ in }
                        )
                    }
                }
                .clipped()
                toolBar
            }
            .navigationTitle("Split into Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Split \(shapes.count)") {
                        onSplit(shapes.map(boundingRect))
                    }
                    .disabled(shapes.isEmpty || isProcessing)
                }
            }
            .overlay {
                if isProcessing {
                    ProcessingOverlay(message: "Creating \(shapes.count) notes…")
                }
            }
        }
    }

    private var instructions: some View {
        Text("Draw a box around each separate topic. Each box becomes its own note, linked to this one.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.08))
    }

    private var toolBar: some View {
        HStack(spacing: 20) {
            ForEach(ShapeType.allCases, id: \.self) { t in
                Button {
                    tool = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.iconName).font(.title3)
                        Text(t.displayName).font(.caption2)
                    }
                    .foregroundStyle(tool == t ? Color.accentColor : .secondary)
                    .padding(8)
                    .background(tool == t ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 28)
            Button {
                if !shapes.isEmpty { shapes.removeLast() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward").font(.title3)
                    Text("Undo").font(.caption2)
                }
            }
            .disabled(shapes.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// In-memory annotations purely for drawing the boxes the user has placed.
    private var previewAnnotations: [Annotation] {
        shapes.enumerated().map { idx, shape in
            Annotation(
                id: "split-\(idx)",
                noteId: "",
                userId: nil,
                imageIndex: 0,
                shapeType: shape.shapeType,
                shapeData: shape.shapeData,
                tag: "Note \(idx + 1)",
                label: nil,
                color: nil,
                regionContent: nil,
                createdAt: nil
            )
        }
    }

    /// Normalized bounding box for any shape kind.
    private func boundingRect(_ shape: PendingShape) -> CGRect {
        let d = shape.shapeData
        if let pts = d.points, !pts.isEmpty {
            let xs = pts.map { $0[0] }, ys = pts.map { $0[1] }
            let minX = xs.min() ?? 0, minY = ys.min() ?? 0
            return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
        }
        return CGRect(x: d.x ?? 0, y: d.y ?? 0, width: d.width ?? 0, height: d.height ?? 0)
    }
}
