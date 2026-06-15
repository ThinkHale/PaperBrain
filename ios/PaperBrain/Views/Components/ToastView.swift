import SwiftUI

// MARK: - Toast item view

private struct ToastItemView: View {
    let item: ToastViewModel.ToastItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.style.iconName)
                .foregroundStyle(item.style.color)
            Text(item.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Stack displayed at the bottom of the screen

struct ToastStack: View {
    @EnvironmentObject private var toastVM: ToastViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastVM.toasts) { item in
                ToastItemView(item: item)
            }
        }
        .padding(.bottom, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastVM.toasts.count)
    }
}

// MARK: - Style helpers

private extension ToastViewModel.ToastItem.Style {
    var iconName: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}
