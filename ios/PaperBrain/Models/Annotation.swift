import Foundation

enum ShapeType: String, Codable {
    case rect = "rect"
    case ellipse = "ellipse"
    case freehand = "freehand"
}

struct ShapeData: Codable {
    // rect
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?
    // ellipse
    var cx: Double?
    var cy: Double?
    var rx: Double?
    var ry: Double?
    // freehand
    var points: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case x, y, w, h, cx, cy, rx, ry, points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        w = try container.decodeIfPresent(Double.self, forKey: .w)
        h = try container.decodeIfPresent(Double.self, forKey: .h)
        cx = try container.decodeIfPresent(Double.self, forKey: .cx)
        cy = try container.decodeIfPresent(Double.self, forKey: .cy)
        rx = try container.decodeIfPresent(Double.self, forKey: .rx)
        ry = try container.decodeIfPresent(Double.self, forKey: .ry)
        points = try container.decodeIfPresent([[Double]].self, forKey: .points)
    }

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    init(cx: Double, cy: Double, rx: Double, ry: Double) {
        self.cx = cx; self.cy = cy; self.rx = rx; self.ry = ry
    }

    init(points: [[Double]]) {
        self.points = points
    }
}

struct Annotation: Codable, Identifiable {
    let id: String
    let noteId: String
    let userId: String?
    var imageIndex: Int
    var shapeType: ShapeType
    var shapeData: ShapeData
    var tag: String?
    var label: String?
    var color: String?
    var regionContent: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case userId = "user_id"
        case imageIndex = "image_index"
        case shapeType = "shape_type"
        case shapeData = "shape_data"
        case tag
        case label
        case color
        case regionContent = "region_content"
        case createdAt = "created_at"
    }
}

struct AnnotationCreate: Encodable {
    let noteId: String
    let userId: String
    let imageIndex: Int
    let shapeType: ShapeType
    let shapeData: ShapeData
    var tag: String?
    var label: String?
    var color: String?
    var regionContent: String?

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case userId = "user_id"
        case imageIndex = "image_index"
        case shapeType = "shape_type"
        case shapeData = "shape_data"
        case tag
        case label
        case color
        case regionContent = "region_content"
    }
}
