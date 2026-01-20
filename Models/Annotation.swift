import Foundation
import SwiftData

@Model
final class Annotation: Identifiable {
    var id: UUID
    var content: String
    var cfi: String?
    var pageIndex: Int?
    var rect: Data?
    var color: String
    var createdAt: Date
    var note: String?

    @Relationship
    var book: BookItem?

    init(
        id: UUID = UUID(),
        content: String,
        cfi: String? = nil,
        pageIndex: Int? = nil,
        rect: Data? = nil,
        color: String = "yellow",
        createdAt: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.content = content
        self.cfi = cfi
        self.pageIndex = pageIndex
        self.rect = rect
        self.color = color
        self.createdAt = createdAt
        self.note = note
    }

    struct Rect: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
}
