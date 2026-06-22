import Foundation

/// Owns the user's tag vocabulary (curated categories + finer topics).
@MainActor
final class TagsViewModel: ObservableObject {
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    @Published var error: String?

    private let db = SupabaseService.shared
    private var userId: UUID?

    var categories: [Tag] { tags.filter { $0.kind == .category } }
    var topics: [Tag] { tags.filter { $0.kind == .topic } }
    var categoryNames: [String] { categories.map(\.name) }

    func color(forCategory name: String) -> String? {
        categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.color
    }

    func load(userId: UUID) async {
        self.userId = userId
        isLoading = true
        error = nil
        do {
            tags = try await db.fetchTags(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        guard let userId else { return }
        await load(userId: userId)
    }

    func add(name: String, kind: TagKind, color: String? = nil) async {
        guard let userId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.kind == kind && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        do {
            let tag = try await db.insertTag(userId: userId, name: trimmed, kind: kind,
                                             color: color ?? (kind == .category ? Self.palette.randomElementStable(seed: trimmed) : nil))
            tags.append(tag)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func rename(_ tag: Tag, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = tags.firstIndex(of: tag) else { return }
        tags[idx].name = trimmed
        try? await db.renameTag(id: tag.id, name: trimmed)
    }

    func recolor(_ tag: Tag, hex: String) async {
        guard let idx = tags.firstIndex(of: tag) else { return }
        tags[idx].color = hex
        try? await db.updateTagColor(id: tag.id, color: hex)
    }

    func delete(_ tag: Tag) async {
        tags.removeAll { $0.id == tag.id }
        try? await db.deleteTag(id: tag.id)
    }

    static let palette = ["#3B82F6", "#EC4899", "#F59E0B", "#8B5CF6", "#10B981", "#22C55E", "#EF4444", "#06B6D4", "#64748B"]
}

private extension Array where Element == String {
    /// Deterministic pick so a category keeps a stable color without Date/random.
    func randomElementStable(seed: String) -> String? {
        guard !isEmpty else { return nil }
        let hash = seed.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return self[abs(hash) % count]
    }
}
