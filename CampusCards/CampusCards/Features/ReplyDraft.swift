import Foundation

struct ReplyDraft {
    let id = UUID()
    let taskID: UUID
    let correctedActionID: UUID?
    var kind: ReplyKind
    var language = CardLanguage.chinese
    var original = "" {
        didSet {
            if original != oldValue { translation = "" }
        }
    }
    var translation = ""
    var speaker = ""
    var fields: [FieldDraft]

    init(taskID: UUID, correcting action: ActionItem? = nil) {
        self.taskID = taskID
        correctedActionID = action?.id
        if let action {
            kind = .correction
            var field = FieldDraft(kind: action.kind)
            field.text = action.time == nil ? action.text : .init()
            if let time = action.time {
                field.useExactTime = true
                field.time = time
            }
            fields = [field]
        } else {
            kind = .requirements
            fields = RequirementKind.allCases.map { FieldDraft(kind: $0) }
        }
    }

    mutating func applyReviewedField(_ updated: FieldDraft) {
        guard let index = fields.firstIndex(where: { $0.id == updated.id }) else { return }
        let previous = fields[index]
        var field = updated
        if kind != .correction, !previous.effectiveText.isEmpty, !field.effectiveText.isEmpty,
           previous.effectiveText != field.effectiveText || previous.confirmedTime != field.confirmedTime {
            field.wasEditedDuringReview = true
        }
        fields[index] = field
    }

    var hasContent: Bool {
        !original.cleaned.isEmpty || !speaker.cleaned.isEmpty || !confirmedFields.isEmpty
    }

    var confirmedFields: [FieldDraft] {
        guard kind != .directions else { return [] }
        return fields.filter { !$0.effectiveText.isEmpty }
    }
}

struct FieldDraft: Identifiable {
    let id = UUID()
    let kind: RequirementKind
    var text = BilingualText()
    var pendingReview: CardLanguage?
    var wasEditedDuringReview = false
    var useExactTime = false
    var time = ConfirmedTime()

    var confirmedTime: ConfirmedTime? { useExactTime && kind == .deadline ? time : nil }

    var confirmedText: BilingualText {
        guard confirmedTime == nil else { return .init() }
        var result = text.cleaned
        if let pendingReview { result[pendingReview] = "" }
        return result
    }

    var effectiveText: BilingualText { confirmedTime?.text ?? confirmedText }

    mutating func edit(_ value: String, in language: CardLanguage) {
        let previous = text[language].cleaned
        let changed = previous != value.cleaned
        text[language] = value
        guard changed else { return }
        if value.cleaned.isEmpty || text[language.other].cleaned.isEmpty || pendingReview == language {
            pendingReview = nil
        } else if !previous.isEmpty {
            pendingReview = language.other
        }
    }
}
