import Foundation

struct ReplyDraft: Codable, Equatable {
    let id: UUID
    let taskID: UUID
    let correctedActionID: UUID?
    var kind: ReplyKind
    private var sourceLanguage = CardLanguage.chinese
    var language: CardLanguage {
        get { sourceLanguage }
        set {
            guard newValue != sourceLanguage else { return }
            sourceLanguage = newValue
            invalidateSource()
        }
    }
    // The editable, confirmed source. originalText keeps the initial input verbatim.
    var original = "" {
        didSet {
            guard original != oldValue else { return }
            if case let .recognition(language, attached) = pending, attached != nil {
                // The user supplied words for the released recording while inference was pending.
                sourceLanguage = language
            }
            invalidateSource()
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
    private var acceptedManualTranslation: Bool?
    var hasTranslatedCurrentSource: Bool { receivedTranslation == true }
    var hasReviewedTranslation: Bool { hasTranslatedCurrentSource || acceptedManualTranslation == true }

    private enum Operation: Equatable {
        case recognition(CardLanguage, recordingRef: String?)
        case translation
    }
    private enum CodingKeys: String, CodingKey {
        case id, taskID, correctedActionID, kind, original, originalText
        case sourceLanguage = "language"
        case recordingRef, translation, speaker, fields, version, receivedTranslation, acceptedManualTranslation
    }

    var isTranslating: Bool { pending == .translation }
    var isRecognizing: Bool {
        if case .recognition = pending { return true }
        return false
    }

    var canReview: Bool { recordingRef != nil || !original.cleaned.isEmpty }

    var canConfirm: Bool {
        hasReviewedTranslation && pending == nil && !original.cleaned.isEmpty && !translation.cleaned.isEmpty
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
        acceptedManualTranslation = nil
        translation = ""
    }

    private var token: ReplyRequestToken {
        ReplyRequestToken(taskID: taskID, draftID: id, version: version)
    }

    mutating func beginRecognition(in language: CardLanguage? = nil) -> ReplyRequestToken {
        invalidateRequests()
        pending = .recognition(language ?? self.language, recordingRef: nil)
        return token
    }

    func expectsRecognition(_ request: ReplyRequestToken) -> Bool {
        isRecognizing && request == token
    }

    // The recorder hands ownership to the draft on release, before inference or further edits.
    mutating func attachRecording(_ reference: String, for request: ReplyRequestToken) -> Bool {
        guard request == token, case let .recognition(language, _) = pending,
              Self.isRelativeRecording(reference) else { return false }
        if original.cleaned.isEmpty { sourceLanguage = language }
        pending = .recognition(language, recordingRef: reference)
        recordingRef = reference
        originalText = nil
        receivedTranslation = nil
        acceptedManualTranslation = nil
        translation = ""
        return true
    }

    private static func isRelativeRecording(_ reference: String) -> Bool {
        !reference.isEmpty && !reference.contains(":") && !reference.contains("\\")
            && reference.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != ".." && $0 != "." }
    }

    @discardableResult
    mutating func receiveRecognition(
        text: String, language: CardLanguage, recordingRef: String, for request: ReplyRequestToken
    ) -> Bool {
        guard request == token, case let .recognition(expected, attached) = pending else { return false }
        guard language == expected, attached == nil || attached == recordingRef,
              !text.cleaned.isEmpty, Self.isRelativeRecording(recordingRef) else {
            invalidateRequests()
            return false
        }
        invalidateSource()
        sourceLanguage = language
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
        acceptedManualTranslation = nil
        return true
    }

    @discardableResult
    mutating func failTranslation(_ error: TranslationServiceError, for request: ReplyRequestToken) -> Bool {
        guard isTranslating, request == token else { return false }
        pending = nil
        translationError = error
        return true
    }

    @discardableResult
    mutating func acceptManualTranslation(_ text: String) -> Bool {
        guard !original.cleaned.isEmpty, !text.cleaned.isEmpty else { return false }
        captureOriginal()
        invalidateRequests()
        translation = text.cleaned
        receivedTranslation = nil
        acceptedManualTranslation = true
        return true
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

    mutating func editTranslation(_ text: String) {
        guard hasReviewedTranslation, translation != text else { return }
        invalidateRequests()
        translation = text
    }
}

struct FieldDraft: Codable, Equatable, Identifiable {
    var id = UUID()
    let kind: RequirementKind
    var text = BilingualText()
    var pendingReview: CardLanguage?
    var wasEditedDuringReview: Bool?
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
