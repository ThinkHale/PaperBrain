import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @StateObject private var vm: NoteDetailViewModel
    @State private var selectedTab = 0
    @State private var showAnnotationCanvas = false
    @State private var annotationImageIndex = 0
    @State private var showAddTag = false
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
                    existingAnnotations: vm.annotations.filter { $0.imageId == vm.images[annotationImageIndex].id }
                ) { newAnnotation in
                    Task { await vm.addAnnotation(newAnnotation) }
                } onDelete: { annotation in
                    Task { await vm.deleteAnnotation(annotation) }
                }
            }
        }
        .overlay {
            if let img = lightboxImage {
                lightbox(img)
            }
        }
        .onChange(of: vm.completedNote) { _, note in
            if let note { notesVM.replace(note) }
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
                Text(vm.note.title)
                    .font(.title2.bold())
            }
            Text(vm.note.createdAt, format: .dateTime)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.note.tags ?? [], id: \.self) { tag in
                    TagChip(tag: tag, deletable: vm.isEditing) {
                        Task { await vm.removeTag(tag) }
                    }
                }
                if vm.isEditing {
                    Button {
                        showAddTag = true
                    } label: {
                        Label("Add tag", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
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
                                let annCount = vm.annotations.filter { $0.imageId == ni.id }.count
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
                                Button("Annotate") {
                                    annotationImageIndex = idx
                                    showAnnotationCanvas = true
                                }
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

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Notes")
                .font(.headline)
            ForEach(vm.relations) { rel in
                let otherId = rel.otherNoteId(relativeTo: vm.note.id)
                if let other = vm.relatedNotes[otherId] {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.title)
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
                      preview: SharePreview(vm.note.title)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    // Needed to forward completed note back to list
    private var completedNoteBinding: Binding<Note?> {
        Binding(get: { nil }, set: { _ in })
    }
}

// Workaround: expose completed note up to NotesViewModel
extension NoteDetailViewModel {
    var completedNote: Note? { nil } // placeholder — update triggers handled via replace()
}
