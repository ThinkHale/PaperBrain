import SwiftUI

/// Manage the tag vocabulary — the small curated set of Categories used to
/// cluster notes, plus the finer Topics the AI reuses.
struct TagManagerView: View {
    @EnvironmentObject private var tagsVM: TagsViewModel
    @State private var showAddCategory = false
    @State private var showAddTopic = false
    @State private var newName = ""
    @State private var renaming: Tag?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                ForEach(tagsVM.categories) { tag in
                    row(for: tag)
                }
                Button {
                    newName = ""
                    showAddCategory = true
                } label: {
                    Label("Add category", systemImage: "plus.circle")
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("High-level buckets the AI assigns notes to. These shape the mind map's clusters — keep them few and broad.")
            }

            Section {
                ForEach(tagsVM.topics) { tag in
                    row(for: tag)
                }
                Button {
                    newName = ""
                    showAddTopic = true
                } label: {
                    Label("Add topic", systemImage: "plus.circle")
                }
            } header: {
                Text("Topics")
            } footer: {
                Text("Finer labels the AI reuses when they fit, so tagging stays consistent instead of sprawling.")
            }
        }
        .navigationTitle("Tags & Categories")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New category", isPresented: $showAddCategory) {
            TextField("Name", text: $newName)
            Button("Add") { Task { await tagsVM.add(name: newName, kind: .category) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New topic", isPresented: $showAddTopic) {
            TextField("Name", text: $newName)
                .autocapitalization(.none)
            Button("Add") { Task { await tagsVM.add(name: newName, kind: .topic) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let tag = renaming { Task { await tagsVM.rename(tag, to: renameText) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(for tag: Tag) -> some View {
        HStack(spacing: 12) {
            if tag.kind == .category {
                Circle().fill(tag.swiftUIColor).frame(width: 14, height: 14)
            } else {
                Image(systemName: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(tag.name)
            Spacer()
            if tag.isDefault {
                Text("default").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await tagsVM.delete(tag) }
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                renaming = tag
                renameText = tag.name
            } label: { Label("Rename", systemImage: "pencil") }
            .tint(.blue)
        }
    }
}
