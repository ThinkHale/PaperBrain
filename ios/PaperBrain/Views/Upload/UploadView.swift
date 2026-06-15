import SwiftUI
import PhotosUI
import PDFKit

struct UploadView: View {
    @EnvironmentObject private var notesVM: NotesViewModel
    @EnvironmentObject private var toastVM: ToastViewModel
    @StateObject private var vm = UploadViewModel()
    @State private var showPhotoPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if vm.selectedImages.isEmpty {
                    dropZone
                } else {
                    pagePreview
                }
                actionButtons
            }
            .padding()
            .navigationTitle("Scan Notes")
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $pickerItems,
                          maxSelectionCount: 20,
                          matching: .any(of: [.images, .screenshots]))
            .onChange(of: pickerItems) { _, items in
                loadPickerItems(items)
            }
            .fileImporter(isPresented: $showDocumentPicker,
                          allowedContentTypes: [.pdf],
                          allowsMultipleSelection: false) { result in
                if case .success(let url) = result, url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        vm.addPDF(data: data)
                    }
                }
            }
            .overlay {
                if vm.isProcessing { processingOverlay }
            }
            .sheet(item: $vm.completedNote) { note in
                NavigationStack {
                    NoteDetailView(note: note)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    notesVM.prepend(note)
                                    vm.clearAll()
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.tint.opacity(0.7))

            VStack(spacing: 8) {
                Text("Upload handwritten notes")
                    .font(.title3.bold())
                Text("Photos, camera shots, or PDF files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // Camera capture
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                // PDF
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Import PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Page preview

    private var pagePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(vm.selectedImages.count) page\(vm.selectedImages.count == 1 ? "" : "s") selected")
                    .font(.headline)
                Spacer()
                Button("Clear") { vm.clearAll() }
                    .foregroundStyle(.red)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(vm.selectedImages.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 160)
                                .clipped()
                                .cornerRadius(10)
                            Button {
                                vm.removePage(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .padding(6)
                            }
                        }
                    }
                    // Add more button
                    Button {
                        showPhotoPicker = true
                    } label: {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title)
                            Text("Add more")
                                .font(.caption)
                        }
                        .frame(width: 120, height: 160)
                        .background(.quaternary)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !vm.selectedImages.isEmpty {
                Button {
                    Task { await vm.process() }
                } label: {
                    Label("Process with AI", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(vm.isProcessing)
            }

            if let error = vm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Processing overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView(value: vm.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                    .tint(.white)
                Text(vm.statusMessage)
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Helpers

    private func loadPickerItems(_ items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    images.append(img)
                }
            }
            vm.addImages(images)
            pickerItems = []
        }
    }
}

// Make Note Identifiable for .sheet(item:)
extension Note: @retroactive Identifiable {}
