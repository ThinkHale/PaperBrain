import SwiftUI

/// Small colored tag pill.
struct TagChip: View {
    let tag: String
    var deletable = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            if deletable {
                Button { onDelete?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tagColor(for: tag).opacity(0.18))
        .foregroundStyle(tagColor(for: tag))
        .clipShape(Capsule())
    }

    private func tagColor(for tag: String) -> Color {
        let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo]
        let idx = abs(tag.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return palette[idx]
    }
}

/// A high-level category pill — filled, using the category's vocabulary color.
struct CategoryChip: View {
    let name: String
    var color: Color = .accentColor
    var deletable = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 8))
            Text(name)
                .font(.caption.weight(.semibold))
            if deletable {
                Button { onDelete?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.gradient)
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

/// A dashed "suggested" chip the user can tap to accept.
struct SuggestionChip: View {
    let text: String
    let icon: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(text).font(.caption)
                Image(systemName: "plus").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.secondary)
            .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }
}
