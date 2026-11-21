import Foundation

struct ReplyDraft: Codable, Equatable {
    let id: UUID
    let taskID: UUID
    let correctedActionID: UUID?
    var kind: ReplyKind
    var language = CardLanguage.chinese {
        didSet {
            if language != oldValue { invalidateSource() }
        }
    }
    // The editable, confirmed source. originalText keeps the initial input verbatim.
    var original = "" {
        didSet {
            if original != oldValue { invalidateSource() }
        }
    }
    private(set) var originalText: String?
    private(set) var recordingRef: String?
    private(set) var translation = ""
    var speaker = ""
    var fields: [FieldDraft]

    private(set) var version = 0
    private var pending: Operation?
    private(set) var translationError: TranslationServiceError?
    // Older cache entries lack this evidence and must be translated before confirmation.
    private var receivedTranslation: Bool?
    var hasTranslatedCurrentSource: Bool { receivedTranslation == true }

    private enum Operation { case recognition, translation }
    private enum CodingKeys: String, CodingKey {
        case id, taskID, correctedActionID, kind, language, original, originalText
        case recordingRef, translation, speaker, fields, version, receivedTranslation
    }

    var isTranslating: Bool { pending == .translation }
    var isRecognizing: Bool { pending == .recognition }

    var canConfirm: Bool {
        hasTranslatedCurrentSource && pending == nil && !original.cleaned.isEmpty && !translation.cleaned.isEmpty
            && (kind != .correction || !confirmedFields.isEmpty)
    }

    init(taskID: UUID, correcting action: ActionItem? = nil) {
        self.id = UUID()
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

    var confirmedFields: [FieldDraft] {
        guard kind != .directions else { return [] }
        return fields.filter { !$0.effectiveText.isEmpty }
    }

    mutating func captureOriginal() {
        if originalText == nil, !original.cleaned.isEmpty { originalText = original }
    }

    mutating func invalidateRequests() {
        version += 1
        pending = nil
        translationError = nil
    }

    private mutating func invalidateSource() {
        invalidateRequests()
        receivedTranslation = nil
        translation = ""
    }

    private var token: ReplyRequestToken {
        ReplyRequestToken(taskID: taskID, draftID: id, version: version)
    }

    mutating func beginRecognition() -> ReplyRequestToken {
        invalidateRequests()
        pending = .recognition
        return token
    }

    @discardableResult
    mutating func receiveRecognition(
        text: String, language: CardLanguage, recordingRef: String, for request: ReplyRequestToken
    ) -> Bool {
        guard isRecognizing, request == token else { return false }
        guard language == self.language, !text.cleaned.isEmpty, !recordingRef.isEmpty,
              !recordingRef.contains(":"), !recordingRef.contains("\\"),
              recordingRef.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." }) else {
            invalidateRequests()
            return false
        }
        invalidateSource()
        original = text
        originalText = text
        self.recordingRef = recordingRef
        return true
    }

    @discardableResult
    mutating func failRecognition(for request: ReplyRequestToken) -> Bool {
        guard isRecognizing, request == token else { return false }
        invalidateRequests()
        return true
    }

    mutating func beginTranslation() -> ReplyRequestToken? {
        guard !original.cleaned.isEmpty else { return nil }
        captureOriginal()
        invalidateRequests()
        pending = .translation
        return token
    }

    @discardableResult
    mutating func receiveTranslation(_ value: String, for request: ReplyRequestToken) -> Bool {
        guard isTranslating, request == token else { return false }
        guard !value.cleaned.isEmpty else { return failTranslation(.invalidResponse, for: request) }
        pending = nil
        translation = value
        receivedTranslation = true
        return true
    }

    @discardableResult
    mutating func failTranslation(_ error: TranslationServiceError, for request: ReplyRequestToken) -> Bool {
        guard isTranslating, request == token else { return false }
        pending = nil
        translationError = error
        return true
    }

    mutating func editTranslation(_ text: String) {
        guard hasTranslatedCurrentSource, translation != text else { return }
        invalidateRequests()
        translation = text
    }
}

struct FieldDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    let kind: RequirementKind
    var text = BilingualText()
    var pendingReview: CardLanguage?
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
