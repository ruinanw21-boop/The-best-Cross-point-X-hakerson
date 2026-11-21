import Foundation
import SwiftData

enum ReplyKind: String, Codable, CaseIterable, Identifiable {
    case directions, requirements, correction

    var id: Self { self }
    var label: String {
        switch self {
        case .directions: "Directions"
        case .requirements: "Requirements"
        case .correction: "Correction"
        }
    }
}

@Model
final class ConversationTurn {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var kindCode: String
    var original: String
    var originalText: String?
    var recordingRef: String?
    var originalLanguageCode: String
    var speaker: String
    var translation: String
    var confirmedAt: Date

    init(draft: ReplyDraft, confirmedAt: Date) {
        id = draft.id
        taskID = draft.taskID
        kindCode = draft.kind.rawValue
        original = draft.original.cleaned
        originalText = draft.originalText ?? draft.original
        recordingRef = draft.recordingRef
        originalLanguageCode = draft.language.rawValue
        speaker = draft.speaker.cleaned
        translation = draft.translation.cleaned
        self.confirmedAt = confirmedAt
    }

    var kind: ReplyKind { ReplyKind(rawValue: kindCode) ?? .requirements }
    var originalLanguage: CardLanguage { CardLanguage(rawValue: originalLanguageCode) ?? .chinese }
}
