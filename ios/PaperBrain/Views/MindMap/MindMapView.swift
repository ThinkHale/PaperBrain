import SwiftUI

struct MindMapView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @StateObject private var vm = MindMapViewModel()

    // Pan / zoom
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1.0

    // Interaction
    @State private var draggingNodeId: String?
    @State private var draggingNodeStart: CGPoint?

    // Simulation timer
    @State private var simulationTask: Task<Void, Never>?
    @State private var isSimulating = true

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if vm.isLoading {
                        ProgressView("Building map…")
                    } else {
                        graphCanvas(in: geo)
                    }
                }
                .onAppear {
                    startSimulation(canvasSize: geo.size)
                }
                .onDisappear {
                    simulationTask?.cancel()
                }
            }
            .navigationTitle("Mind Map")
            .toolbar { toolbarContent }
        }
        .task {
            guard let user = authVM.currentUser else { return }
            await vm.load(userId: user.id, notes: notesVM.notes)
        }
        .onChange(of: notesVM.notes) { _, notes in
            guard let user = authVM.currentUser else { return }
            Task { await vm.load(userId: user.id, notes: notes) }
        }
    }

    // MARK: - Graph canvas

    private func graphCanvas(in geo: GeometryProxy) -> some View {
        let cx = geo.size.width / 2
        let cy = geo.size.height / 2

        return Canvas { ctx, size in
            let transform = CGAffineTransform(translationX: offset.width + dragTranslation.width, y: offset.height + dragTranslation.height)
                .scaledBy(x: scale * magnification, y: scale * magnification)

            // Apply transform via ctx.environment changes
            ctx.concatenate(CGAffineTransform(translationX: cx, y: cy))
            ctx.concatenate(transform)
            ctx.concatenate(CGAffineTransform(translationX: -cx, y: -cy))

            let nodeMap = Dictionary(uniqueKeysWithValues: vm.visibleNodes.map { ($0.id, $0) })

            // Draw edges
            for edge in vm.visibleEdges {
                guard let src = nodeMap[edge.sourceId], let dst = nodeMap[edge.targetId] else { continue }
                let srcPt = CGPoint(x: src.x + cx, y: src.y + cy)
                let dstPt = CGPoint(x: dst.x + cx, y: dst.y + cy)

                var path = Path()
                path.move(to: srcPt)
                path.addLine(to: dstPt)

                let opacity = 0.3 + edge.weight * 0.4
                let lineWidth = edge.isManual ? 2.5 : 1.5
                let color = edge.isManual
                ? Color.orange.opacity(opacity)
                : Color.secondary.opacity(opacity)

                if edge.isManual {
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
                } else {
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))
                }
            }

            // Draw nodes
            for node in vm.visibleNodes {
                let pt = CGPoint(x: node.x + cx, y: node.y + cy)
                let isSelected = vm.selectedNodeId == node.id

                switch node.kind {
                case .note:
                    let r: CGFloat = isSelected ? 28 : 22
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(isSelected ? .tint : .blue.opacity(0.7)))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.6)),
                               style: StrokeStyle(lineWidth: node.isPinned ? 2.5 : 1))

                case .tag:
                    let r: CGFloat = isSelected ? 18 : 14
                    let hexPath = hexagonPath(center: pt, radius: r)
                    ctx.fill(hexPath, with: .color(isSelected ? .tint : .purple.opacity(0.6)))
                    ctx.stroke(hexPath, with: .color(.white.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1))
                }
            }
        }
        .overlay {
            // Node labels drawn as SwiftUI overlay for text rendering
            GeometryReader { g in
                ForEach(vm.visibleNodes) { node in
                    let transform = CGAffineTransform(translationX: offset.width + dragTranslation.width, y: offset.height + dragTranslation.height)
                        .scaledBy(x: scale * magnification, y: scale * magnification)
                    let raw = CGPoint(x: node.x + g.size.width / 2, y: node.y + g.size.height / 2)
                    let center = raw.applying(
                        CGAffineTransform(translationX: g.size.width / 2, y: g.size.height / 2)
                            .concatenating(transform)
                            .concatenating(CGAffineTransform(translationX: -g.size.width / 2, y: -g.size.height / 2))
                    )
                    Text(node.label)
                        .font(.system(size: 9 * (scale * magnification), weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .frame(width: 60)
                        .position(center)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if let nodeId = draggingNodeId {
                            // Move node
                            guard let start = draggingNodeStart,
                                  let idx = vm.nodes.firstIndex(where: { $0.id == nodeId }) else { return }
                            let dx = value.translation.width / (scale * magnification)
                            let dy = value.translation.height / (scale * magnification)
                            vm.nodes[idx].x = start.x + dx
                            vm.nodes[idx].y = start.y + dy
                        }
                    }
                    .onEnded { value in
                        if let nodeId = draggingNodeId, let user = authVM.currentUser,
                           let node = vm.nodes.first(where: { $0.id == nodeId }) {
                            vm.pin(nodeId: nodeId, x: node.x, y: node.y, userId: user.id)
                            draggingNodeId = nil
                            draggingNodeStart = nil
                        }
                    },
                MagnificationGesture()
                    .updating($magnification) { val, state, _ in state = val }
                    .onEnded { val in scale = min(max(scale * val, 0.3), 3.0) }
            )
        )
        .simultaneousGesture(
            DragGesture()
                .updating($dragTranslation) { v, state, _ in
                    if draggingNodeId == nil { state = v.translation }
                }
                .onEnded { v in
                    if draggingNodeId == nil {
                        offset.width += v.translation.width
                        offset.height += v.translation.height
                    }
                }
        )
        .onTapGesture { location in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let s = scale * magnification
            let worldX = (location.x - cx - offset.width) / s
            let worldY = (location.y - cy - offset.height) / s
            let tapped = vm.visibleNodes.first { node in
                let dx = node.x - worldX, dy = node.y - worldY
                return sqrt(dx * dx + dy * dy) < 28
            }
            vm.selectedNodeId = tapped?.id == vm.selectedNodeId ? nil : tapped?.id
        }
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10) { pressing in
            // handled by onEnded
        } perform: { }
    }

    // MARK: - Simulation

    private func startSimulation(canvasSize: CGSize) {
        simulationTask?.cancel()
        simulationTask = Task {
            while !Task.isCancelled {
                if isSimulating {
                    vm.simulationStep(canvasSize: canvasSize)
                }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
            }
        }
    }

    // MARK: - Hexagon path

    private func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: center.x + cos(angle) * radius,
                             y: center.y + sin(angle) * radius)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Tag filter
            Menu {
                Button("All tags") { vm.tagFilter = nil }
                ForEach(vm.allTags, id: \.self) { tag in
                    Button(tag) { vm.tagFilter = tag }
                }
            } label: {
                Label(vm.tagFilter ?? "Filter", systemImage: "tag")
            }

            // Toggle tag links
            Button {
                vm.showTagLinks.toggle()
            } label: {
                Image(systemName: vm.showTagLinks ? "link" : "link.badge.plus")
            }

            // Reset layout
            Button {
                offset = .zero
                scale = 1.0
                vm.nodes.indices.forEach {
                    vm.nodes[$0].isPinned = false
                    vm.nodes[$0].vx = 0
                    vm.nodes[$0].vy = 0
                }
                isSimulating = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
        }
    }
}
