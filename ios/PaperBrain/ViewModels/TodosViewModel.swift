import Foundation

@MainActor
final class TodosViewModel: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var isLoading = false
    @Published var error: String?

    private let db = SupabaseService.shared
    private var userId: UUID?

    var open: [Todo] { todos.filter { !$0.done } }
    var completed: [Todo] { todos.filter { $0.done } }
    var openCount: Int { open.count }

    func load(userId: UUID) async {
        self.userId = userId
        isLoading = true
        error = nil
        do {
            todos = try await db.fetchTodos(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        guard let userId else { return }
        await load(userId: userId)
    }

    func add(text: String, noteId: String? = nil, dueDate: String? = nil) async {
        guard let userId else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let create = TodoCreate(userId: userId.uuidString, noteId: noteId, text: trimmed,
                                dueDate: dueDate, source: TodoSource.manual.rawValue,
                                position: (open.map(\.position).max() ?? 0) + 1)
        do {
            let todo = try await db.insertTodo(create)
            todos.insert(todo, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggle(_ todo: Todo) async {
        guard let idx = todos.firstIndex(of: todo) else { return }
        let newValue = !todos[idx].done
        todos[idx].done = newValue
        do {
            try await db.setTodoDone(id: todo.id, done: newValue)
        } catch {
            todos[idx].done = !newValue   // revert
            self.error = error.localizedDescription
        }
    }

    func updateText(_ todo: Todo, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(of: todo) else { return }
        todos[idx].text = trimmed
        try? await db.updateTodoText(id: todo.id, text: trimmed)
    }

    func delete(_ todo: Todo) async {
        todos.removeAll { $0.id == todo.id }
        try? await db.deleteTodo(id: todo.id)
    }
}
