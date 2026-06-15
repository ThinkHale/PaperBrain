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
