import Foundation
import SwiftUI

enum TagKind: String, Codable {
    case category
    case topic
}

/// A user's tag-vocabulary entry. Categories are the small curated set used to
/// cluster notes; topics are finer, more specific labels.
struct Tag: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var kind: TagKind
    var color: String?
    var isDefault: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case color
        case isDefault = "is_default"
        case createdAt = "created_at"
    }

    var swiftUIColor: Color {
        guard let hex = color, let c = Color(hex: hex) else {
            return kind == .category ? .accentColor : .secondary
        }
        return c
    }
}

struct TagCreate: Encodable {
    let userId: String
    let name: String
    let kind: String
    var color: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case kind
        case color
    }
}

extension Color {
    /// Hex string → Color. Supports `#RRGGBB` and `#RRGGBBAA`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
