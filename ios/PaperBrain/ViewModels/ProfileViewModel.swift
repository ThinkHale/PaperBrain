import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var displayName: String = ""
    @Published var selectedModel: String = Profile.availableModels[0]
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var saveSuccess = false

    private let db = SupabaseService.shared

    func load(userId: UUID) async {
        isLoading = true
        do {
            let p = try await db.fetchProfile(userId: userId)
            profile = p
            displayName = p.displayName ?? ""
            selectedModel = p.claudeModel
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func save(userId: UUID) async {
        isSaving = true
        saveSuccess = false
        do {
            try await db.updateProfile(
                id: userId,
                displayName: displayName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : displayName,
                claudeModel: selectedModel
            )
            saveSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Toast

@MainActor
final class ToastViewModel: ObservableObject {
    @Published var toasts: [ToastItem] = []

    struct ToastItem: Identifiable {
        let id = UUID()
        let message: String
        let style: Style
        enum Style { case info, success, error }
    }

    func show(_ message: String, style: ToastItem.Style = .info) {
        let item = ToastItem(message: message, style: style)
        toasts.append(item)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            toasts.removeAll { $0.id == item.id }
        }
    }
}
