import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @EnvironmentObject private var tagsVM: TagsViewModel
    @StateObject private var vm: NoteDetailViewModel
    @State private var selectedTab = 0
    @State private var showAnnotationCanvas = false
    @State private var showSplitCanvas = false
    @State private var annotationImageIndex = 0
    @State private var showAddTag = false
    @State private var showAddCategory = false
    @State private var newTagText = ""
    @State private var lightboxImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    init(note: Note) {
        _vm = StateObject(wrappedValue: NoteDetailViewModel(note: note))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection
                tagsSection
                imageStrip
                if let audioPath = vm.note.audioPath, !audioPath.isEmpty {
                    AudioPlayerView(storagePath: audioPath)
                }
                if !vm.noteTodos.isEmpty { todosSection }
                tabSection
                if !vm.relations.isEmpty { relationsSection }
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.loadAll() }
        .sheet(isPresented: $vm.showClarification) {
            ClarificationView(viewModel: vm) {
                if let user = authVM.currentUser {
                    Task { await vm.submitClarifications(userId: user.id) }
                }
            }
        }
        .sheet(isPresented: $showAnnotationCanvas) {
            if !vm.images.isEmpty {
                AnnotationCanvasView(
                    image: vm.imageCache[vm.images[annotationImageIndex].id] ?? UIImage(),
                    noteImage: vm.images[annotationImageIndex],
                    existingAnnotations: vm.annotations.filter { $0.imageIndex == (vm.images[annotationImageIndex].pageNumber ?? 0) }
                ) { newAnnotation in
                    Task { await vm.addAnnotation(newAnnotation) }
                } onDelete: { annotation in
                    Task { await vm.deleteAnnotation(annotation) }
                }
            }
        }
        .sheet(isPresented: $showSplitCanvas) {
            if !vm.images.isEmpty,
               let img = vm.imageCache[vm.images[annotationImageIndex].id] {
                SplitCanvasView(image: img, isProcessing: vm.isSplitting) { rects in
                    guard let user = authVM.currentUser else { return }
                    Task {
                        let created = await vm.splitIntoNotes(rects: rects, sourceImage: img, userId: user.id)
                        for note in created { notesVM.prepend(note) }
                        await vm.loadAll()   // refresh relations to the new notes
                        showSplitCanvas = false
                        if !created.isEmpty {
                            toastVM.show("Created \(created.count) note\(created.count == 1 ? "" : "s")", style: .success)
                        }
                    }
                }
            }
        }
        .overlay {
            if let img = lightboxImage {
                lightbox(img)
            }
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Group {
            if vm.isEditing {
                TextField("Title", text: $vm.editingTitle)
                    .font(.title2.bold())
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(vm.note.displayTitle)
                    .font(.title2.bold())
            }
            Text(vm.note.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryRow
            topicRow
        }
        .alert("Add tag", isPresented: $showAddTag) {
            TextField("Tag name", text: $newTagText)
                .autocapitalization(.none)
            Button("Add") {
                Task {
                    await vm.addTag(newTagText)
                    newTagText = ""
                }
            }
            Button("Cancel", role: .cancel) { newTagText = "" }
        }
        .alert("Add category", isPresented: $showAddCategory) {
            TextField("Category name", text: $newTagText)
            Button("Add") {
                Task {
                    await vm.addCategory(newTagText)
                    await tagsVM.add(name: newTagText, kind: .category)
                    newTagText = ""
                }
            }
            Button("Cancel", role: .cancel) { newTagText = "" }
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.note.categories ?? [], id: \.self) { cat in
                    CategoryChip(name: cat,
                                 color: Color(hex: tagsVM.color(forCategory: cat) ?? "") ?? .accentColor,
                                 deletable: vm.isEditing) {
                        Task { await vm.removeCategory(cat) }
                    }
                }
                if vm.isEditing {
                    // Suggest curated categories the note doesn't have yet.
                    ForEach(suggestedCategories, id: \.self) { cat in
                        SuggestionChip(text: cat, icon: "square.stack.3d.up") {
                            Task { await vm.addCategory(cat) }
                        }
                    }
                    Button { showAddCategory = true } label: {
                        Label("New", systemImage: "plus").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private var topicRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.note.tags ?? [], id: \.self) { tag in
                    TagChip(tag: tag, deletable: vm.isEditing) {
                        Task { await vm.removeTag(tag) }
                    }
                }
                if vm.isEditing {
                    Button { showAddTag = true } label: {
                        Label("Tag", systemImage: "plus").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private var suggestedCategories: [String] {
        let current = Set((vm.note.categories ?? []).map { $0.lowercased() })
        return tagsVM.categoryNames.filter { !current.contains($0.lowercased()) }.prefix(4).map { $0 }
    }

    private var imageStrip: some View {
        Group {
            if !vm.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(vm.images.enumerated()), id: \.element.id) { idx, ni in
                            ZStack(alignment: .topTrailing) {
                                if let img = vm.imageCache[ni.id] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 180)
                                        .clipped()
                                        .cornerRadius(10)
                                        .onTapGesture {
                                            if !vm.isEditing { lightboxImage = img }
                                        }
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.quaternary)
                                        .frame(width: 140, height: 180)
                                        .overlay(ProgressView())
                                }
                                // Annotation count badge
                                let annCount = vm.annotations.filter { $0.imageIndex == (ni.pageNumber ?? 0) }.count
                                if annCount > 0 {
                                    Text("\(annCount)")
                                        .font(.caption2.bold())
                                        .padding(4)
                                        .background(.tint)
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())
                                        .padding(6)
                                }
                            }
                            .contextMenu {
                                Button {
                                    annotationImageIndex = idx
                                    showAnnotationCanvas = true
                                } label: { Label("Annotate", systemImage: "pencil.tip.crop.circle") }
                                Button {
                                    annotationImageIndex = idx
                                    showSplitCanvas = true
                                } label: { Label("Split into notes", systemImage: "rectangle.split.2x1") }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var tabSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Organized").tag(0)
                Text("Transcription").tag(1)
                Text("Summary").tag(2)
                Text("Key Points").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 16)

            switch selectedTab {
            case 0: organizedTab
            case 1: transcriptionTab
            case 2: summaryTab
            default: keyPointsTab
            }
        }
    }

    private var organizedTab: some View {
        Group {
            if vm.isEditing {
                TextEditor(text: $vm.editingOrganized)
                    .frame(minHeight: 300)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            } else {
                MarkdownView(text: vm.note.organized ?? "")
            }
        }
    }

    private var transcriptionTab: some View {
        if let t = vm.note.transcription, !t.isEmpty {
            return AnyView(Text(t).font(.body).textSelection(.enabled))
        }
        return AnyView(Text("No transcription").foregroundStyle(.secondary))
    }

    private var summaryTab: some View {
        if let s = vm.note.summary, !s.isEmpty {
            return AnyView(Text(s).font(.body).textSelection(.enabled))
        }
        return AnyView(Text("No summary").foregroundStyle(.secondary))
    }

    private var keyPointsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(vm.note.keyPoints ?? [], id: \.self) { point in
                Label(point, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
            if vm.note.keyPoints?.isEmpty ?? true {
                Text("No key points").foregroundStyle(.secondary)
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("To-Dos", systemImage: "checklist")
                .font(.headline)
            ForEach(vm.noteTodos) { todo in
                Button {
                    Task { await vm.toggleNoteTodo(todo) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(todo.done ? Color.accentColor : .secondary)
                        Text(todo.text)
                            .strikethrough(todo.done)
                            .foregroundStyle(todo.done ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Notes")
                .font(.headline)
            ForEach(vm.relations) { rel in
                let otherId = rel.otherNoteId(relativeTo: vm.note.id)
                if let other = vm.relatedNotes[otherId] {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.displayTitle)
                                .font(.subheadline.bold())
                            if let reason = rel.reason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(Int(rel.score * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Lightbox

    private func lightbox(_ image: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
                .onTapGesture { lightboxImage = nil }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(24)
        }
        .transition(.opacity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if vm.isEditing {
                Button("Done") {
                    Task {
                        await vm.saveTitle()
                        await vm.saveOrganized()
                        vm.isEditing = false
                        toastVM.show("Saved", style: .success)
                    }
                }
            } else {
                Button { vm.isEditing = true } label: {
                    Image(systemName: "pencil")
                }
            }

            ShareLink(item: notesVM.exportMarkdown(for: vm.note),
                      preview: SharePreview(vm.note.displayTitle)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }
}
