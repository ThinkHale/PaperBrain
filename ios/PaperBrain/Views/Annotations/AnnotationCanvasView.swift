import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct AnnotationCanvasView: View {
    let image: UIImage
    let noteImage: NoteImage
    let existingAnnotations: [Annotation]
    let onAdd: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    @State private var selectedTool: Annotation.ShapeType = .rect
    @State private var tagInput = ""
    @State private var showTagPrompt = false
    @State private var pendingShape: PendingShape?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image + canvas overlay
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        CanvasOverlay(
                            imageSize: image.size,
                            containerSize: geo.size,
                            tool: selectedTool,
                            existingAnnotations: existingAnnotations,
                            onShapeFinished: { shape in
                                pendingShape = shape
                                showTagPrompt = true
                            },
                            onDeleteAnnotation: onDelete
                        )
                    }
                }
                .clipped()

                // Tool picker
                toolBar
            }
            .navigationTitle("Annotate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Tag this region", isPresented: $showTagPrompt) {
                TextField("e.g. formula, diagram, todo", text: $tagInput)
                    .autocapitalization(.none)
                Button("Save") { saveAnnotation() }
                Button("Skip") { saveAnnotation(withTag: nil) }
                Button("Cancel", role: .cancel) {
                    pendingShape = nil
                    tagInput = ""
                }
            }
        }
    }

    // MARK: - Tool bar

    private var toolBar: some View {
        HStack(spacing: 24) {
            ForEach(Annotation.ShapeType.allCases, id: \.self) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.iconName)
                            .font(.title3)
                        Text(tool.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(selectedTool == tool ? .tint : .secondary)
                    .padding(10)
                    .background(selectedTool == tool ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Save

    private func saveAnnotation(withTag tag: String? = tagInput.isEmpty ? nil : tagInput) {
        defer {
            pendingShape = nil
            tagInput = ""
        }
        guard let pending = pendingShape else { return }

        let annotation = Annotation(
            id: UUID(),
            noteId: noteImage.noteId,
            imageId: noteImage.id,
            shapeType: pending.shapeType,
            shapeData: pending.shapeData,
            tag: tag?.trimmingCharacters(in: .whitespaces).lowercased(),
            regionContent: nil,
            createdAt: Date()
        )
        onAdd(annotation)
    }
}

// MARK: - PendingShape

struct PendingShape {
    let shapeType: Annotation.ShapeType
    let shapeData: Annotation.ShapeData
}

// MARK: - Canvas UIView overlay

struct CanvasOverlay: UIViewRepresentable {
    let imageSize: CGSize
    let containerSize: CGSize
    let tool: Annotation.ShapeType
    let existingAnnotations: [Annotation]
    let onShapeFinished: (PendingShape) -> Void
    let onDeleteAnnotation: (Annotation) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(imageSize: imageSize, containerSize: containerSize,
                    onShapeFinished: onShapeFinished, onDeleteAnnotation: onDeleteAnnotation)
    }

    func makeUIView(context: Context) -> AnnotationDrawingView {
        let view = AnnotationDrawingView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: AnnotationDrawingView, context: Context) {
        context.coordinator.imageSize = imageSize
        context.coordinator.containerSize = containerSize
        context.coordinator.currentTool = tool
        context.coordinator.existingAnnotations = existingAnnotations
        uiView.setNeedsDisplay()
    }

    // MARK: - Coordinator

    final class Coordinator {
        var imageSize: CGSize
        var containerSize: CGSize
        var currentTool: Annotation.ShapeType = .rect
        var existingAnnotations: [Annotation] = []
        let onShapeFinished: (PendingShape) -> Void
        let onDeleteAnnotation: (Annotation) -> Void
        weak var view: AnnotationDrawingView?

        var drawStart: CGPoint?
        var drawCurrent: CGPoint?
        var freehandPoints: [CGPoint] = []
        var isDrawing = false

        init(imageSize: CGSize, containerSize: CGSize,
             onShapeFinished: @escaping (PendingShape) -> Void,
             onDeleteAnnotation: @escaping (Annotation) -> Void) {
            self.imageSize = imageSize
            self.containerSize = containerSize
            self.onShapeFinished = onShapeFinished
            self.onDeleteAnnotation = onDeleteAnnotation
        }

        /// Convert view-space point → normalized 0-1 coords based on image display rect
        func normalize(_ point: CGPoint) -> CGPoint {
            let rect = imageDisplayRect
            return CGPoint(
                x: (point.x - rect.minX) / rect.width,
                y: (point.y - rect.minY) / rect.height
            )
        }

        /// Compute the actual rect the image occupies inside the container (aspect-fit)
        var imageDisplayRect: CGRect {
            let scale = min(containerSize.width / imageSize.width,
                            containerSize.height / imageSize.height)
            let w = imageSize.width * scale
            let h = imageSize.height * scale
            let x = (containerSize.width - w) / 2
            let y = (containerSize.height - h) / 2
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}

// MARK: - Drawing UIView

final class AnnotationDrawingView: UIView {
    var coordinator: CanvasOverlay.Coordinator?

    // Tag color palette
    static let tagColors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed]
    private var tagColorMap: [String: UIColor] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self), let coord = coordinator else { return }
        coord.isDrawing = true
        coord.drawStart = pt
        coord.drawCurrent = pt
        if coord.currentTool == .freehand { coord.freehandPoints = [pt] }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self), let coord = coordinator else { return }
        coord.drawCurrent = pt
        if coord.currentTool == .freehand { coord.freehandPoints.append(pt) }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let coord = coordinator else { return }
        coord.isDrawing = false
        commitShape(coord)
        setNeedsDisplay()
    }

    private func commitShape(_ coord: CanvasOverlay.Coordinator) {
        switch coord.currentTool {
        case .rect, .ellipse:
            guard let start = coord.drawStart, let end = coord.drawCurrent else { return }
            let n0 = coord.normalize(start)
            let n1 = coord.normalize(end)
            let x = min(n0.x, n1.x), y = min(n0.y, n1.y)
            let w = abs(n1.x - n0.x), h = abs(n1.y - n0.y)
            guard w > 0.01, h > 0.01 else { return }
            let data = Annotation.ShapeData(x: x, y: y, width: w, height: h, points: nil)
            coord.onShapeFinished(PendingShape(shapeType: coord.currentTool, shapeData: data))

        case .freehand:
            let normalized = coord.freehandPoints.map { p -> [Double] in
                let n = coord.normalize(p)
                return [n.x, n.y]
            }
            guard normalized.count > 2 else { return }
            let data = Annotation.ShapeData(x: nil, y: nil, width: nil, height: nil, points: normalized)
            coord.onShapeFinished(PendingShape(shapeType: .freehand, shapeData: data))
        }
        coord.drawStart = nil
        coord.drawCurrent = nil
        coord.freehandPoints = []
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let coord = coordinator else { return }
        ctx.clear(rect)
        let imageRect = coord.imageDisplayRect

        // Draw existing annotations
        for ann in coord.existingAnnotations {
            let color = colorForTag(ann.tag)
            ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
            ctx.setFillColor(color.withAlphaComponent(0.15).cgColor)
            ctx.setLineWidth(2)

            switch ann.shapeType {
            case .rect:
                if let x = ann.shapeData.x, let y = ann.shapeData.y,
                   let w = ann.shapeData.width, let h = ann.shapeData.height {
                    let r = CGRect(
                        x: imageRect.minX + x * imageRect.width,
                        y: imageRect.minY + y * imageRect.height,
                        width: w * imageRect.width,
                        height: h * imageRect.height
                    )
                    ctx.fill(r); ctx.stroke(r)
                    if let tag = ann.tag { drawLabel(tag, at: CGPoint(x: r.minX + 4, y: r.minY - 16), ctx: ctx) }
                }
            case .ellipse:
                if let x = ann.shapeData.x, let y = ann.shapeData.y,
                   let w = ann.shapeData.width, let h = ann.shapeData.height {
                    let r = CGRect(
                        x: imageRect.minX + x * imageRect.width,
                        y: imageRect.minY + y * imageRect.height,
                        width: w * imageRect.width,
                        height: h * imageRect.height
                    )
                    ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
                    if let tag = ann.tag { drawLabel(tag, at: CGPoint(x: r.minX + 4, y: r.minY - 16), ctx: ctx) }
                }
            case .freehand:
                if let pts = ann.shapeData.points, pts.count > 1 {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(
                        x: imageRect.minX + pts[0][0] * imageRect.width,
                        y: imageRect.minY + pts[0][1] * imageRect.height
                    ))
                    for pt in pts.dropFirst() {
                        ctx.addLine(to: CGPoint(
                            x: imageRect.minX + pt[0] * imageRect.width,
                            y: imageRect.minY + pt[1] * imageRect.height
                        ))
                    }
                    ctx.drawPath(using: .stroke)
                }
            }
        }

        // Draw in-progress shape
        if coord.isDrawing {
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.8).cgColor)
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.1).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])

            switch coord.currentTool {
            case .rect:
                if let s = coord.drawStart, let e = coord.drawCurrent {
                    let r = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                                   width: abs(e.x - s.x), height: abs(e.y - s.y))
                    ctx.fill(r); ctx.stroke(r)
                }
            case .ellipse:
                if let s = coord.drawStart, let e = coord.drawCurrent {
                    let r = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                                   width: abs(e.x - s.x), height: abs(e.y - s.y))
                    ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
                }
            case .freehand:
                let pts = coord.freehandPoints
                if pts.count > 1 {
                    ctx.beginPath()
                    ctx.move(to: pts[0])
                    pts.dropFirst().forEach { ctx.addLine(to: $0) }
                    ctx.drawPath(using: .stroke)
                }
            }
        }
    }

    private func colorForTag(_ tag: String?) -> UIColor {
        let key = tag ?? "__default__"
        if let c = tagColorMap[key] { return c }
        let c = Self.tagColors[tagColorMap.count % Self.tagColors.count]
        tagColorMap[key] = c
        return c
    }

    private func drawLabel(_ text: String, at point: CGPoint, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let bg = CGRect(x: point.x - 2, y: point.y - 1, width: size.width + 4, height: size.height + 2)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
        ctx.fill(bg)
        str.draw(at: point)
    }
}

// MARK: - Tool display helpers

extension Annotation.ShapeType {
    var iconName: String {
        switch self {
        case .rect: return "rectangle"
        case .ellipse: return "oval"
        case .freehand: return "scribble"
        }
    }

    var displayName: String {
        switch self {
        case .rect: return "Rect"
        case .ellipse: return "Oval"
        case .freehand: return "Draw"
        }
    }
}
