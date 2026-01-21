import Foundation
import SwiftData
import AppKit

@Model
final class BookItem: Identifiable {
    var id: UUID
    var title: String
    var author: String?
    var bookmarkData: Data
    var fileType: String
    var coverImageData: Data?
    var pageCount: Int?
    var addedAt: Date
    var lastOpenedAt: Date?
    var lastReadPage: Int?
    var lastReadLocation: String? // CFI for EPUB
    var filePath: String
    var themeColor: String? // Hex color string

    var bookmarkURL: URL? {
        resolveBookmark()
    }

    @Relationship(deleteRule: .cascade, inverse: \Annotation.book)
    var annotations: [Annotation] = []

    @Relationship(deleteRule: .cascade, inverse: \AIChat.book)
    var aiChats: [AIChat] = []

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        bookmarkData: Data,
        fileType: String,
        coverImageData: Data? = nil,
        pageCount: Int? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        lastReadPage: Int? = nil,
        lastReadLocation: String? = nil,
        filePath: String,
        themeColor: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.bookmarkData = bookmarkData
        self.fileType = fileType
        self.coverImageData = coverImageData
        self.pageCount = pageCount
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastReadPage = lastReadPage
        self.lastReadLocation = lastReadLocation
        self.filePath = filePath
        self.themeColor = themeColor
    }

    func resolveBookmark() -> URL? {
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }
}
