import SwiftUI

/// The running To-Do tab: AI-extracted action items plus anything you add by hand.
struct TodoListView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var todosVM: TodosViewModel
    @EnvironmentObject private var notesVM: NotesViewModel
    @State private var showAdd = false
    @State private var newText = ""

    var body: some View {
        NavigationStack {
            Group {
                if todosVM.todos.isEmpty && !todosVM.isLoading {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("To-Do")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { newText = ""; showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                if let user = authVM.currentUser { await todosVM.load(userId: user.id) }
            }
            .alert("New to-do", isPresented: $showAdd) {
                TextField("What needs doing?", text: $newText)
                Button("Add") { Task { await todosVM.add(text: newText) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var list: some View {
        List {
            if !todosVM.open.isEmpty {
                Section("Open") {
                    ForEach(todosVM.open) { todo in row(todo) }
                }
            }
            if !todosVM.completed.isEmpty {
                Section("Completed") {
                    ForEach(todosVM.completed) { todo in row(todo) }
                }
            }
        }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await todosVM.toggle(todo) }
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.text)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                HStack(spacing: 8) {
                    if todo.source == .ai {
                        Label("AI", systemImage: "sparkles")
                            .font(.caption2).foregroundStyle(.tint)
                    }
                    if let note = sourceNote(for: todo) {
                        NavigationLink {
                            NoteDetailView(note: note)
                        } label: {
                            Label(note.displayTitle, systemImage: "note.text")
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await todosVM.delete(todo) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func sourceNote(for todo: Todo) -> Note? {
        guard let id = todo.noteId else { return nil }
        return notesVM.notes.first { $0.id == id }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundStyle(.tint.opacity(0.6))
            Text("No to-dos yet")
                .font(.title3.bold())
            Text("Action items the AI spots in your notes show up here. Tap + to add your own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
