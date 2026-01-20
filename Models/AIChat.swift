import Foundation
import SwiftData

@Model
final class AIChat: Identifiable {
    var id: UUID
    var prompt: String
    var response: String
    var relatedText: String
    var createdAt: Date
    var modelName: String?
    var temperature: Double?
    var tokenCount: Int?
    var annotationCfi: String?
    var annotationPageIndex: Int?
    var actionType: String? // explain, summarize, translate, analyze

    @Relationship
    var book: BookItem?

    init(
        id: UUID = UUID(),
        prompt: String,
        response: String,
        relatedText: String,
        createdAt: Date = Date(),
        modelName: String? = nil,
        temperature: Double? = nil,
        tokenCount: Int? = nil,
        annotationCfi: String? = nil,
        annotationPageIndex: Int? = nil,
        actionType: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.response = response
        self.relatedText = relatedText
        self.createdAt = createdAt
        self.modelName = modelName
        self.temperature = temperature
        self.tokenCount = tokenCount
        self.annotationCfi = annotationCfi
        self.annotationPageIndex = annotationPageIndex
        self.actionType = actionType
    }
}
