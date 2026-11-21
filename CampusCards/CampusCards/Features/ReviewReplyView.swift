import SwiftData
import SwiftUI
import UIKit

// Task 03 returns the same token it received when local recognition began.
struct ReplyTranscription {
    let token: ReplyRequestToken
    let language: CardLanguage
    let originalText: String
    let recordingRef: String
}

typealias ReplyRecognizer = (ReplyRequestToken, CardLanguage) async throws -> ReplyTranscription

struct ReviewReplyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.cardLanguage) private var language
    @AppStorage("translationBaseAddress") private var serviceAddress = ""
    @State private var draft: ReplyDraft
    @State private var reviewing = false
    @State private var followUp: CardContent?
    @State private var saveError = false
    @State private var isSaving = false
    @State private var confirmCancel = false
    @State private var editingAddress = false
    @StateObject private var capture = ReplyCapture()
    @State private var press: MicrophonePress?
    @State private var recognitionMessage: String?
    @State private var worker: Task<Void, Never>?
    @State private var closing = false
    @State private var didRestore = false
    @Query private var existingActions: [ActionItem]
    let task: CampusTask
    let recognize: ReplyRecognizer?
    let onSaved: (UUID) -> Void

    init(task: CampusTask, correcting action: ActionItem?, recognize: ReplyRecognizer? = nil,
         onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.task = task
        self.recognize = recognize
        self.onSaved = onSaved
        let id = task.id
        _draft = State(initialValue: ReplyDraft(taskID: id, correcting: action))
        _existingActions = Query(filter: #Predicate<ActionItem> { $0.taskID == id })
    }

    private var lang: CardLanguage { language.wrappedValue }

    private var hasDraftContent: Bool {
        draft.recordingRef != nil || !draft.original.cleaned.isEmpty || !draft.speaker.cleaned.isEmpty
            || !draft.confirmedFields.isEmpty
    }

    private var missing: [RequirementKind] {
        let answered = Set(existingActions.map(\.kind) + draft.confirmedFields.map(\.kind))
        return task.fields.filter { !answered.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if reviewing {
                    reviewSections
                } else {
                    recordSections
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(lang.text(reviewing ? "Review reply" : "Record reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text(reviewing ? "Back" : "Cancel")) {
                        if reviewing {
                            stopWork()
                            reviewing = false
                        } else if !hasDraftContent {
                            close(.discard)
                        } else {
                            confirmCancel = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if reviewing {
                        save()
                    } else {
                        stopWork()
                        draft.captureOriginal()
                        reviewing = true
                    }
                } label: {
                    Text(lang.text(reviewing ? "Confirm and save" : "Review reply"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(isSaving || (reviewing ? !draft.canConfirm : !draft.canReview))
                .accessibilityIdentifier(reviewing ? "confirm-reply" : "review-reply")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .modifier(SaveErrorAlert(presented: $saveError))
            .confirmationDialog(lang.text("Close this draft?"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(lang.text("Keep draft and close")) { close(.keep) }
                Button(lang.text("Discard reply"), role: .destructive) { close(.discard) }
                Button(lang.text("Keep editing"), role: .cancel) {}
            }
            .sheet(item: $followUp) { content in
                ShowCardView(card: content)
            }
        }
        .interactiveDismissDisabled(hasDraftContent || press != nil || draft.kind == .correction)
        .onAppear {
            closing = false
            restoreDraft()
        }
        .onChange(of: draft) { _, current in
            if !closing { ReplyDraftCache().save(current) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, press != nil {
                stopWork()
                recognitionMessage = ReplyCaptureError.interrupted.messageKey
            }
        }
        .onDisappear {
            if !closing {
                closing = true
                stopWork()
                if hasDraftContent {
                    ReplyDraftCache().save(draft)
                } else {
                    ReplyDraftCache().remove(draft)
                }
            }
        }
    }

    @ViewBuilder
    private var recordSections: some View {
        Section(lang.text("Reply details")) {
            if draft.kind == .correction {
                Label(lang.text("Correction"), systemImage: "pencil")
            } else {
                Picker(lang.text("Reply type"), selection: $draft.kind) {
                    Text(lang.text("Directions")).tag(ReplyKind.directions)
                    Text(lang.text("Requirements")).tag(ReplyKind.requirements)
                }
                .accessibilityIdentifier("reply-kind")
            }
            languagePicker
            TextField(lang.text("Who replied? (optional)"), text: $draft.speaker)
        }

        Section(lang.text("Original reply")) {
            sourceField
            ForEach([CardLanguage.chinese, .english]) { source in
                let isHeld = press?.language == source
                let title = isHeld && capture.isRecording ? "Recording… Release to review."
                    : (source == .chinese ? "Hold to speak Chinese" : "Hold to speak English")
                HoldMicrophoneButton(title: lang.text(title), isHeld: isHeld,
                    hint: lang.text("Double-tap to start or stop recording."),
                    identifier: source == .chinese ? "microphone-zh" : "microphone-en",
                    onPress: { beginPress(in: source) }, onRelease: { endPress(in: source) },
                    onCancel: {
                        guard press?.language == source else { return }
                        // The system permission sheet may cancel the touch before the user can lift.
                        if capture.isRecording { stopWork() } else { endPress(in: source) }
                    })
                    .frame(minHeight: 44)
            }
            recognitionFeedback
        }
    }

    @ViewBuilder
    private var recognitionFeedback: some View {
        if let message = recognitionMessage ?? (press == nil ? nil : capture.issue?.messageKey) {
            Text(lang.text(message))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("recognition-error")
        } else if draft.isRecognizing && reviewing {
            ProgressView(lang.text("Transcribing…"))
        }
    }

    private var languagePicker: some View {
        Picker(lang.text("Reply language"), selection: $draft.language) {
            ForEach(CardLanguage.allCases) { choice in
                Text(verbatim: choice.name).tag(choice)
            }
        }
    }

    private var sourceField: some View {
        TextField(lang.text("Type what they said"), text: $draft.original, axis: .vertical)
            .lineLimit(3...8)
            .accessibilityIdentifier("original-reply")
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section(lang.text("Review source text")) {
            languagePicker
            sourceField
            if let reference = draft.recordingRef {
                RecordingPlaybackButton(recordingRef: reference)
            }
            recognitionFeedback
        }

        Section(lang.text(draft.language == .chinese ? "English translation" : "Chinese translation")) {
            if serviceAddress.cleaned.isEmpty || editingAddress || draft.translationError == .invalidAddress {
                TextField(lang.text("Service address"), text: $serviceAddress,
                          prompt: Text(verbatim: "http://192.168.1.23:8000"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("translation-address")
                    .onAppear { editingAddress = true }
                Text(lang.text("Enter the Wi-Fi address and port of the Windows translation service."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button(lang.text("Change service address")) { editingAddress = true }
            }

            Button {
                translate()
            } label: {
                if draft.isTranslating {
                    HStack {
                        ProgressView()
                        Text(lang.text("Translating…"))
                    }
                } else {
                    Label(lang.text(translationButtonTitle), systemImage: "character.bubble")
                }
            }
            .disabled(draft.original.cleaned.isEmpty || serviceAddress.cleaned.isEmpty || draft.isTranslating || draft.isRecognizing)
            .accessibilityIdentifier("translate-reply")

            if let error = draft.translationError {
                Text(lang.text(translationMessage(error)))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("translation-error")
            }

            if draft.hasTranslatedCurrentSource {
                TextField(lang.text("Edit translation"), text: Binding(
                    get: { draft.translation }, set: { draft.editTranslation($0) }
                ), axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("reviewed-translation")
            }
        }
        .onChange(of: serviceAddress) { _, _ in
            if draft.isTranslating { stopWork() }
        }

        if draft.kind == .directions {
            Section {
                Text(lang.text("Directions are saved in the conversation history."))
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach($draft.fields) { $field in
                Section {
                    FieldEditor(field: $field, isCorrection: draft.kind == .correction)
                    if field.kind == .material, draft.kind == .requirements,
                       draft.fields.filter({ $0.kind == .material }).count > 1 {
                        Button(lang.text("Remove material"), role: .destructive) {
                            draft.fields.removeAll { $0.id == field.id }
                        }
                    }
                } header: {
                    Label(lang.text(field.kind.label), systemImage: field.kind.icon)
                }
            }

            if draft.kind == .requirements {
                Section {
                    Button {
                        draft.fields.append(FieldDraft(kind: .material))
                    } label: {
                        Label(lang.text("Add another material"), systemImage: "plus")
                    }
                }

                if !missing.isEmpty {
                    Section(lang.text("To ask")) {
                        ForEach(missing) { kind in
                            Button {
                                followUp = .init(title: "Follow-up question", text: kind.question)
                            } label: {
                                Label(kind.question.preferred(lang), systemImage: "questionmark.bubble")
                            }
                        }
                    }
                }
            }
        }
    }

    private var translationButtonTitle: String {
        if let error = draft.translationError, error != .invalidRequest && error != .invalidAddress {
            return "Retry translation"
        }
        return draft.language == .chinese ? "Translate to English" : "Translate to Chinese"
    }

    private func translationMessage(_ error: TranslationServiceError) -> String {
        switch error {
        case .invalidAddress: "Enter a service address with http:// or https:// and a port if needed."
        case .invalidRequest: "Check the source text and language, then translate again."
        case .unavailable: "The translation service is unavailable. Try again."
        case .timeout: "The translation service timed out. Try again."
        case .offline: "Couldn’t reach the service. Check Wi-Fi and the service address, then retry."
        case .invalidResponse: "The service returned an unreadable response. Check the address and retry."
        }
    }

    private func translate() {
        guard let token = draft.beginTranslation() else { return }
        worker?.cancel()
        editingAddress = false
        let client = TranslationClient(baseAddress: serviceAddress)
        let text = draft.original
        let source = draft.language
        worker = Task { @MainActor in
            do {
                let translated = try await client.translate(text: text, source: source)
                draft.receiveTranslation(translated, for: token)
            } catch let error as TranslationServiceError {
                draft.failTranslation(error, for: token)
            } catch {
                draft.failTranslation(.unavailable, for: token)
            }
        }
    }

    private func beginPress(in source: CardLanguage) {
        guard !closing, press == nil else { return }
        worker?.cancel()
        recognitionMessage = nil
        let token = draft.beginRecognition(in: source)
        press = MicrophonePress(token: token, language: source)
        if recognize == nil { capture.begin(token) }
    }

    private func endPress(in source: CardLanguage) {
        guard let current = press, current.language == source else { return }
        press = nil
        let token = current.token
        guard !closing, draft.expectsRecognition(token) else {
            capture.cancel()
            return
        }
        let previous = draft.recordingRef
        let reference = recognize == nil ? capture.finish(token) : nil
        if let reference {
            guard draft.attachRecording(reference, for: token) else {
                ReplyRecordingFiles().remove(reference)
                capture.cancel()
                draft.failRecognition(for: token)
                recognitionMessage = "Couldn’t transcribe. Try again or type the reply."
                return
            }
            cacheRecording(replacing: previous)
        }
        reviewing = true
        let recognizer: ReplyRecognizer = recognize ?? { try await capture.recognize($0, $1) }
        worker = Task { @MainActor in
            do {
                let result = try await recognizer(token, source)
                guard !closing, draft.expectsRecognition(token) else { return }
                guard result.token == token, reference == nil || reference == result.recordingRef,
                      draft.receiveRecognition(text: result.originalText, language: result.language,
                                               recordingRef: result.recordingRef, for: token) else {
                    draft.failRecognition(for: token)
                    recognitionMessage = "Couldn’t transcribe. Try again or type the reply."
                    return
                }
                if reference == nil { cacheRecording(replacing: previous) }
            } catch {
                guard !closing, draft.failRecognition(for: token) else { return }
                if let error = error as? ReplyCaptureError {
                    recognitionMessage = error.messageKey
                } else if case .resourcesUnavailable = error as? OfflineTranscriptionError {
                    recognitionMessage = "Offline speech resources are unavailable. You can type the reply."
                } else {
                    recognitionMessage = "Couldn’t transcribe. Try again or type the reply."
                }
            }
        }
    }

    private func cacheRecording(replacing previous: String?) {
        // Persist the new reference before retiring its predecessor.
        ReplyDraftCache().save(draft)
        if let previous, previous != draft.recordingRef { removeUnsavedRecording(previous) }
    }

    private func removeUnsavedRecording(_ reference: String) {
        let uses = FetchDescriptor<ConversationTurn>(predicate: #Predicate { $0.recordingRef == reference })
        guard (try? context.fetchCount(uses)) == 0 else { return }
        ReplyRecordingFiles().remove(reference)
    }

    private func restoreDraft() {
        guard !didRestore else { return }
        didRestore = true
        let cache = ReplyDraftCache()
        guard let saved = cache.load(for: draft) else { return }
        // A crash between the SwiftData commit and removing the cache can leave a confirmed draft.
        let id = saved.id
        let match = FetchDescriptor<ConversationTurn>(predicate: #Predicate { $0.id == id })
        if (try? context.fetchCount(match)) == 1 {
            cache.remove(saved)
        } else {
            draft = saved
            reviewing = saved.originalText != nil || saved.recordingRef != nil
        }
    }

    private func stopWork() {
        press = nil
        capture.cancel()
        draft.invalidateRequests()
        worker?.cancel()
        worker = nil
    }

    private enum CloseAction { case keep, discard, saved }

    private func close(_ action: CloseAction) {
        closing = true
        stopWork()
        switch action {
        case .keep:
            ReplyDraftCache().save(draft)
        case .discard, .saved:
            ReplyDraftCache().remove(draft)
            if action == .discard, let reference = draft.recordingRef {
                removeUnsavedRecording(reference)
            }
        }
        dismiss()
    }

    private func save() {
        guard !closing, !isSaving, draft.canConfirm else { return }
        isSaving = true
        do {
            let turn = try TaskStore(context: context).confirmReply(draft)
            onSaved(turn.id)
            close(.saved)
        } catch {
            isSaving = false
            saveError = true
        }
    }
}

private struct MicrophonePress {
    let token: ReplyRequestToken
    let language: CardLanguage
}

// A control receives touch cancellation as well as release, including inside a scrolling Form.
private struct HoldMicrophoneButton: UIViewRepresentable {
    let title: String
    let isHeld: Bool
    let hint: String
    let identifier: String
    let onPress: () -> Void
    let onRelease: () -> Void
    let onCancel: () -> Void

    final class Control: UIButton {
        var toggleRecording: (() -> Void)?

        override func accessibilityActivate() -> Bool {
            toggleRecording?()
            return true
        }
    }

    func makeUIView(context: Context) -> Control {
        Control()
    }

    func updateUIView(_ button: Control, context: Context) {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: isHeld ? "mic.fill" : "mic")
        config.imagePadding = 8
        button.configuration = config
        button.accessibilityHint = hint
        button.accessibilityIdentifier = identifier
        button.toggleRecording = isHeld ? onRelease : onPress
        // Reusing identifiers replaces the actions on updates without multiplying handlers.
        button.addAction(UIAction(identifier: .init(rawValue: "press")) { _ in onPress() }, for: .touchDown)
        button.addAction(UIAction(identifier: .init(rawValue: "release")) { _ in onRelease() },
                         for: [.touchUpInside, .touchUpOutside])
        button.addAction(UIAction(identifier: .init(rawValue: "cancel")) { _ in onCancel() }, for: .touchCancel)
    }
}

private struct FieldEditor: View {
    @Binding var field: FieldDraft
    let isCorrection: Bool
    @FocusState private var focusedLanguage: CardLanguage?
    @State private var textAtFocus = ""
    @State private var editingTime = false
    @State private var timeSelection = ConfirmedTime()
    @Environment(\.cardLanguage) private var language
    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        if field.kind == .deadline {
            Toggle(lang.text("Set an exact time"), isOn: Binding(
                get: { field.useExactTime || editingTime },
                set: { enabled in
                    if enabled { editTime() } else { field.useExactTime = false }
                }
            ))
                .accessibilityIdentifier("exact-time")
                .sheet(isPresented: $editingTime) { exactTimeEditor }
        }

        if let time = field.confirmedTime {
            LanguageLines(text: time.text, primary: lang)
            Button(lang.text("Edit time")) { editTime() }
                .accessibilityIdentifier("edit-deadline")
        } else {
            ForEach(CardLanguage.allCases) { cardLanguage in
                TextField(lang.text(cardLanguage == .english ? "English value" : "Chinese value"), text: Binding {
                    field.text[cardLanguage]
                } set: { value in
                    field.edit(value, in: cardLanguage)
                }, axis: .vertical)
                .focused($focusedLanguage, equals: cardLanguage)
                .lineLimit(1...4)
                .accessibilityIdentifier("\(field.kind.rawValue)-\(cardLanguage.rawValue)")
            }
            .onChange(of: focusedLanguage) { previous, current in
                if let previous, field.text[previous] != textAtFocus {
                    field.rememberReviewedText(in: previous)
                }
                if let current {
                    textAtFocus = field.text[current]
                    if !isCorrection { field.rememberReviewedText(in: current) }
                }
            }
            if field.pendingReview != nil {
                Text(lang.text("Review the other language before saving both versions."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(lang.text("Confirm both versions")) { field.pendingReview = nil }
            }
        }

        if !field.effectiveText.isEmpty {
            Toggle(lang.text("Edited during this review"), isOn: $field.userEdited)
                .accessibilityIdentifier("\(field.kind.rawValue)-user-edited")
        }
    }

    private func editTime() {
        timeSelection = field.time
        editingTime = true
    }

    private var exactTimeEditor: some View {
        NavigationStack {
            Form {
                Picker(lang.text("Weekday"), selection: $timeSelection.weekday) {
                    ForEach(Weekday.allCases) { day in
                        Text(lang.text(day.english)).tag(day)
                    }
                }
                .accessibilityIdentifier("deadline-weekday")

                DatePicker(lang.text("Clock time"), selection: clock, displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, .gmt)
                    .accessibilityIdentifier("deadline-clock")

                Toggle(lang.text("Arrive by this time"), isOn: $timeSelection.isCutoff)
                LanguageLines(text: timeSelection.text, primary: lang)
            }
            .navigationTitle(lang.text("Time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Cancel")) { editingTime = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.text("Use time")) {
                        field.confirmExactTime(timeSelection)
                        editingTime = false
                    }
                    .accessibilityIdentifier("confirm-deadline")
                }
            }
        }
    }

    private var clock: Binding<Date> {
        Binding {
            Date(timeIntervalSinceReferenceDate: TimeInterval(timeSelection.minuteOfDay * 60))
        } set: { date in
            let minutes = Int(date.timeIntervalSinceReferenceDate / 60)
            timeSelection.minuteOfDay = (minutes % 1440 + 1440) % 1440
        }
    }
}
