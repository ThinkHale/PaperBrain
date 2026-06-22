import SwiftUI

struct MindMapView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @StateObject private var vm = MindMapViewModel()

    @State private var cameraOffset: CGSize = .zero
    @State private var cameraScale: CGFloat = 0.94
    @GestureState private var panTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @State private var simulationTask: Task<Void, Never>?
    @State private var openedNoteId: String?

    private var currentScale: CGFloat {
        min(3.2, max(0.34, cameraScale * pinchScale))
    }

    private var currentOffset: CGSize {
        CGSize(
            width: cameraOffset.width + panTranslation.width,
            height: cameraOffset.height + panTranslation.height
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    cerebralBackground

                    if vm.isLoading {
                        loadingView
                    } else if vm.visibleNodes.isEmpty {
                        emptyState
                    } else {
                        mapSurface(in: geo)
                    }

                    VStack {
                        mapControls
                        Spacer()
                        if let node = vm.selectedNode {
                            selectionTray(for: node)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .ignoresSafeArea(edges: .bottom)
                .onAppear { startSimulation() }
                .onDisappear {
                    simulationTask?.cancel()
                    simulationTask = nil
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(item: $openedNoteId) { noteId in
                if let note = vm.note(id: noteId) {
                    NoteDetailView(note: note)
                        .environmentObject(notesVM)
                }
            }
        }
        .task {
            guard let user = authVM.currentUser else { return }
            await vm.load(userId: user.id, notes: notesVM.notes)
        }
        .onChange(of: noteSignature) { _, _ in
            guard let user = authVM.currentUser else { return }
            Task { await vm.load(userId: user.id, notes: notesVM.notes) }
        }
    }

    private var noteSignature: String {
        notesVM.notes
            .map { note in
                [
                    note.id,
                    note.updatedAt ?? "",
                    note.title ?? "",
                    note.summary ?? "",
                    note.tags?.joined(separator: ",") ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "||")
    }

    // MARK: - Canvas

    private func mapSurface(in geo: GeometryProxy) -> some View {
        ZStack {
            Canvas { ctx, size in
                drawConstellation(in: &ctx, size: size)
            }
            .overlay {
                labelLayer(in: geo.size)
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
            .onTapGesture { location in
                let tapped = hitNode(at: location, in: geo.size)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    vm.select(nodeId: tapped?.id == vm.selectedNodeId ? nil : tapped?.id)
                }
            }
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    if let selected = vm.selectedNode {
                        focusCamera(on: selected, in: geo.size)
                    } else {
                        cameraOffset = .zero
                        cameraScale = 0.94
                    }
                }
            }

            minimap(in: geo.size)
                .frame(width: 92, height: 92)
                .padding(.trailing, 16)
                .padding(.bottom, vm.selectedNode == nil ? 18 : 162)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
    }

    private func drawConstellation(in ctx: inout GraphicsContext, size: CGSize) {
        let projected = projectedNodes(in: size)
        let projectedById = Dictionary(uniqueKeysWithValues: projected.map { ($0.node.id, $0) })

        drawDepthGrid(in: &ctx, size: size)

        for edge in vm.visibleEdges {
            guard let source = projectedById[edge.sourceId], let target = projectedById[edge.targetId] else { continue }
            let active = vm.isEdgeActive(edge)
            let path = threadPath(from: source.point, to: target.point, curve: edgeCurve(for: edge, source: source, target: target))
            let stroke = StrokeStyle(
                lineWidth: edgeLineWidth(edge, active: active, depth: (source.depth + target.depth) / 2),
                lineCap: .round,
                lineJoin: .round,
                dash: edge.isManual ? [7, 5] : []
            )

            ctx.stroke(
                path,
                with: .color(edgeColor(edge, active: active, depth: (source.depth + target.depth) / 2)),
                style: stroke
            )
        }

        for item in projected.sorted(by: { $0.depth < $1.depth }) {
            drawNode(item, in: &ctx)
        }
    }

    private func drawDepthGrid(in ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2 + currentOffset.width * 0.12, y: size.height / 2 + currentOffset.height * 0.12)
        let rings: [CGFloat] = [92, 168, 268, 392, 540]

        for (index, radius) in rings.enumerated() {
            let rect = CGRect(x: center.x - radius * currentScale, y: center.y - radius * currentScale, width: radius * 2 * currentScale, height: radius * 2 * currentScale)
            let opacity = 0.12 - Double(index) * 0.014
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(max(0.035, opacity))), style: StrokeStyle(lineWidth: 0.8))
        }

        var vertical = Path()
        vertical.move(to: CGPoint(x: center.x, y: 0))
        vertical.addLine(to: CGPoint(x: center.x, y: size.height))
        ctx.stroke(vertical, with: .color(.white.opacity(0.035)), style: StrokeStyle(lineWidth: 1))

        var horizontal = Path()
        horizontal.move(to: CGPoint(x: 0, y: center.y))
        horizontal.addLine(to: CGPoint(x: size.width, y: center.y))
        ctx.stroke(horizontal, with: .color(.white.opacity(0.035)), style: StrokeStyle(lineWidth: 1))
    }

    private func drawNode(_ item: ProjectedNode, in ctx: inout GraphicsContext) {
        let node = item.node
        let active = vm.isNodeActive(node)
        let selected = vm.selectedNodeId == node.id
        let radius = item.radius
        let coreRect = CGRect(x: item.point.x - radius, y: item.point.y - radius, width: radius * 2, height: radius * 2)
        let glowRect = coreRect.insetBy(dx: -radius * 0.58, dy: -radius * 0.58)

        let color = nodeColor(node, active: active, selected: selected, depth: item.depth)
        let glowOpacity = selected ? 0.48 : active ? 0.24 : 0.07
        ctx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(glowOpacity)))

        switch node.kind {
        case .note:
            ctx.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(active ? 0.9 : 0.34)))
            ctx.stroke(Path(ellipseIn: coreRect), with: .color(.white.opacity(selected ? 0.84 : active ? 0.34 : 0.12)), style: StrokeStyle(lineWidth: selected ? 2.2 : 1.1))
            let inner = coreRect.insetBy(dx: radius * 0.38, dy: radius * 0.38)
            ctx.fill(Path(ellipseIn: inner), with: .color(.white.opacity(active ? 0.55 : 0.16)))

        case .tag:
            let path = hexagonPath(center: item.point, radius: radius * 1.05)
            ctx.fill(path, with: .color(color.opacity(active ? 0.84 : 0.28)))
            ctx.stroke(path, with: .color(.white.opacity(selected ? 0.78 : active ? 0.28 : 0.1)), style: StrokeStyle(lineWidth: selected ? 2 : 1))
        }
    }

    private func labelLayer(in size: CGSize) -> some View {
        let projected = projectedNodes(in: size)
        return ZStack {
            ForEach(projected) { item in
                let node = item.node
                let active = vm.isNodeActive(node)
                let selected = vm.selectedNodeId == node.id

                VStack(spacing: 2) {
                    Text(node.label)
                        .font(.system(size: labelSize(for: item), weight: selected ? .semibold : .medium, design: .rounded))
                        .lineLimit(node.kind == .tag ? 1 : 2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(active ? 0.96 : 0.34))
                        .shadow(color: .black.opacity(0.6), radius: 5, y: 2)

                    if selected, let subtitle = node.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.66))
                            .frame(width: 170)
                    }
                }
                .frame(width: node.kind == .tag ? 112 : selected ? 190 : 128)
                .position(x: item.point.x, y: item.point.y + item.radius + (selected ? 22 : 15))
                .opacity(labelOpacity(for: item, active: active, selected: selected))
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Controls

    private var mapControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))

                TextField("Search the map", text: $vm.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)

                if !vm.searchQuery.isEmpty {
                    Button {
                        vm.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.white.opacity(0.58))
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(.white.opacity(0.105), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

            HStack(spacing: 8) {
                metricPill("\(vm.visibleNodes.filter { $0.kind == .note }.count)", "notes", "circle.grid.cross")
                metricPill("\(vm.visibleEdges.count)", "links", "point.3.connected.trianglepath.dotted")

                Spacer(minLength: 8)

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        vm.isFocusMode.toggle()
                    }
                } label: {
                    Image(systemName: vm.isFocusMode ? "scope" : "scope")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(MapIconButtonStyle(isSelected: vm.isFocusMode))

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        cameraOffset = .zero
                        cameraScale = 0.94
                    }
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(MapIconButtonStyle())
            }
        }
    }

    private func metricPill(_ value: String, _ label: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.085), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func selectionTray(for node: MapNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                nodeGlyph(for: node)

                VStack(alignment: .leading, spacing: 5) {
                    Text(node.kind == .tag ? "Category" : "Note")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.5))

                    Text(node.label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let note = vm.selectedNote {
                        Text(note.summary ?? note.formattedDate)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(2)
                    } else {
                        Text("\(connectedCount(for: node.id)) connected notes")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                        vm.select(nodeId: nil)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(MapIconButtonStyle())
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        focusCamera(on: node, in: UIScreen.main.bounds.size)
                    }
                } label: {
                    Label("Focus", systemImage: "scope")
                }
                .buttonStyle(MapActionButtonStyle())

                if let note = vm.selectedNote {
                    Button {
                        openedNoteId = note.id
                    } label: {
                        Label("Open", systemImage: "doc.text")
                    }
                    .buttonStyle(MapActionButtonStyle(isPrimary: true))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }

    private func nodeGlyph(for node: MapNode) -> some View {
        ZStack {
            Circle()
                .fill(node.kind == .note ? Color.cyan.opacity(0.22) : Color.purple.opacity(0.2))
            Image(systemName: node.kind == .note ? "note.text" : "number")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(node.kind == .note ? .cyan : .purple)
        }
        .frame(width: 42, height: 42)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Building map...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No map yet", systemImage: "circle.hexagongrid")
        } description: {
            Text("Add notes and tags to grow the constellation.")
        }
        .foregroundStyle(.white)
    }

    private var cerebralBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.021, blue: 0.036),
                    Color(red: 0.025, green: 0.055, blue: 0.075),
                    Color(red: 0.045, green: 0.025, blue: 0.058)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.cyan.opacity(0.2), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )

            RadialGradient(
                colors: [.purple.opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($panTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                cameraOffset.width += value.translation.width
                cameraOffset.height += value.translation.height
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                cameraScale = min(3.2, max(0.34, cameraScale * value))
            }
    }

    // MARK: - Projection

    private func projectedNodes(in size: CGSize) -> [ProjectedNode] {
        vm.visibleNodes.map { node in
            let depth = normalizedDepth(node.z)
            let depthScale = 0.78 + depth * 0.34
            let parallax = CGFloat(node.z) * 0.05
            let x = size.width / 2 + currentOffset.width + CGFloat(node.x) * currentScale * depthScale
            let y = size.height / 2 + currentOffset.height + (CGFloat(node.y) + parallax) * currentScale * depthScale
            let radius = CGFloat(node.radius) * currentScale * (0.78 + depth * 0.42)
            return ProjectedNode(node: node, point: CGPoint(x: x, y: y), radius: max(8, min(54, radius)), depth: depth)
        }
    }

    private func normalizedDepth(_ z: Double) -> CGFloat {
        CGFloat(min(1, max(0, (z + 260) / 520)))
    }

    private func hitNode(at location: CGPoint, in size: CGSize) -> MapNode? {
        projectedNodes(in: size)
            .sorted { $0.radius > $1.radius }
            .first { item in
                let dx = item.point.x - location.x
                let dy = item.point.y - location.y
                return sqrt(dx * dx + dy * dy) <= max(30, item.radius + 12)
            }?
            .node
    }

    private func focusCamera(on node: MapNode, in size: CGSize) {
        let depth = normalizedDepth(node.z)
        let depthScale = 0.78 + depth * 0.34
        cameraScale = min(1.72, max(0.92, 1.4 - depth * 0.12))
        cameraOffset = CGSize(
            width: -CGFloat(node.x) * cameraScale * depthScale,
            height: -CGFloat(node.y) * cameraScale * depthScale - 42
        )
    }

    private func edgeCurve(for edge: MapEdge, source: ProjectedNode, target: ProjectedNode) -> CGFloat {
        let depthDelta = target.depth - source.depth
        let kindCurve: CGFloat
        switch edge.kind {
        case .relation:
            kindCurve = edge.isManual ? 0.2 : 0.13
        case .tag:
            kindCurve = -0.08
        case .sharedTag:
            kindCurve = 0.08
        }
        return kindCurve + depthDelta * 0.18
    }

    private func threadPath(from source: CGPoint, to target: CGPoint, curve: CGFloat) -> Path {
        let mid = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
        let dx = target.x - source.x
        let dy = target.y - source.y
        let control = CGPoint(x: mid.x - dy * curve, y: mid.y + dx * curve)
        var path = Path()
        path.move(to: source)
        path.addQuadCurve(to: target, control: control)
        return path
    }

    private func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 6
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Style

    private func nodeColor(_ node: MapNode, active: Bool, selected: Bool, depth: CGFloat) -> Color {
        if selected { return .white }
        let alpha = active ? 0.88 : 0.32
        switch node.kind {
        case .note:
            // Notes glow with the hue of their cluster, so each constellation reads as one family.
            guard let key = node.clusterKey, !key.isEmpty else {
                return Color(red: 0.24 + depth * 0.16, green: 0.84, blue: 0.92).opacity(alpha)
            }
            let hue = clusterHue(for: key)
            return Color(hue: hue, saturation: 0.62, brightness: 0.92 + Double(depth) * 0.06).opacity(alpha)
        case .tag:
            // Category "suns" — brighter, distinctly hued per category.
            let hue = clusterHue(for: node.label)
            return Color(hue: hue, saturation: 0.78, brightness: 1.0).opacity(alpha)
        }
    }

    /// Stable hue (0-1) per category label so clusters keep consistent colors.
    private func clusterHue(for key: String) -> Double {
        let hash = key.lowercased().utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return Double(hash % 360) / 360.0
    }

    private func edgeColor(_ edge: MapEdge, active: Bool, depth: CGFloat) -> Color {
        let opacity = active ? 0.24 + depth * 0.2 : 0.055
        switch edge.kind {
        case .relation:
            return edge.isManual ? .orange.opacity(opacity + 0.16) : .cyan.opacity(opacity)
        case .tag:
            return .purple.opacity(opacity)
        case .sharedTag:
            return .mint.opacity(opacity * 0.72)
        }
    }

    private func edgeLineWidth(_ edge: MapEdge, active: Bool, depth: CGFloat) -> CGFloat {
        let base: CGFloat
        switch edge.kind {
        case .relation:
            base = edge.isManual ? 2.1 : 1.45
        case .tag:
            base = 0.9
        case .sharedTag:
            base = 0.7
        }
        return active ? base + depth * 0.8 : max(0.45, base * 0.55)
    }

    private func labelSize(for item: ProjectedNode) -> CGFloat {
        let base: CGFloat = item.node.kind == .tag ? 11 : 10
        return min(15, max(8, base * currentScale * (0.86 + item.depth * 0.28)))
    }

    private func labelOpacity(for item: ProjectedNode, active: Bool, selected: Bool) -> Double {
        if selected { return 1 }
        if !active { return 0.34 }
        if currentScale < 0.58 && item.node.kind == .note { return 0.35 }
        return 0.76 + Double(item.depth) * 0.18
    }

    private func connectedCount(for nodeId: String) -> Int {
        vm.visibleEdges.filter { $0.sourceId == nodeId || $0.targetId == nodeId }.count
    }

    // MARK: - Minimap

    private func minimap(in size: CGSize) -> some View {
        Canvas { ctx, mapSize in
            let nodes = vm.visibleNodes
            guard !nodes.isEmpty else { return }

            let xs = nodes.map(\.x)
            let ys = nodes.map(\.y)
            let minX = (xs.min() ?? -1) - 80
            let maxX = (xs.max() ?? 1) + 80
            let minY = (ys.min() ?? -1) - 80
            let maxY = (ys.max() ?? 1) + 80
            let width = max(1, maxX - minX)
            let height = max(1, maxY - minY)
            let scale = min(mapSize.width / width, mapSize.height / height)

            for edge in vm.visibleEdges {
                guard
                    let source = nodes.first(where: { $0.id == edge.sourceId }),
                    let target = nodes.first(where: { $0.id == edge.targetId })
                else { continue }

                var path = Path()
                path.move(to: CGPoint(x: (source.x - minX) * scale, y: (source.y - minY) * scale))
                path.addLine(to: CGPoint(x: (target.x - minX) * scale, y: (target.y - minY) * scale))
                ctx.stroke(path, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 0.7))
            }

            for node in nodes {
                let point = CGPoint(x: (node.x - minX) * scale, y: (node.y - minY) * scale)
                let rect = CGRect(x: point.x - 2.2, y: point.y - 2.2, width: 4.4, height: 4.4)
                ctx.fill(Path(ellipseIn: rect), with: .color(node.kind == .note ? .cyan.opacity(0.75) : .purple.opacity(0.75)))
            }
        }
        .padding(9)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Simulation

    private func startSimulation() {
        simulationTask?.cancel()
        simulationTask = Task { @MainActor in
            while !Task.isCancelled {
                vm.simulationStep()
                try? await Task.sleep(nanoseconds: 24_000_000)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button("All categories") { vm.tagFilter = nil }
                ForEach(vm.allTags, id: \.self) { tag in
                    Button(tag) { vm.tagFilter = tag }
                }
            } label: {
                Image(systemName: vm.tagFilter == nil ? "tag" : "tag.fill")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.showTagLinks.toggle()
                }
            } label: {
                Image(systemName: vm.showTagLinks ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
            }

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    cameraOffset = .zero
                    cameraScale = 0.94
                    vm.resetLayout()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
        }
    }
}

private struct ProjectedNode: Identifiable {
    var id: String { node.id }
    let node: MapNode
    let point: CGPoint
    let radius: CGFloat
    let depth: CGFloat
}

private struct MapIconButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .black : .white.opacity(0.82))
            .frame(width: 34, height: 34)
            .background(isSelected ? .white.opacity(0.86) : .white.opacity(configuration.isPressed ? 0.18 : 0.095), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct MapActionButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isPrimary ? .black : .white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isPrimary ? .white.opacity(0.92) : .white.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(isPrimary ? 0 : 0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
