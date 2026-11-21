import SwiftData
import SwiftUI

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
    @Environment(\.cardLanguage) private var language
    @AppStorage("translationBaseAddress") private var serviceAddress = ""
    @State private var draft: ReplyDraft
    @State private var reviewing = false
    @State private var followUp: CardContent?
    @State private var saveError = false
    @State private var isSaving = false
    @State private var confirmCancel = false
    @State private var editingAddress = false
    @State private var recognitionFailed = false
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
                        } else if draft.original.cleaned.isEmpty && draft.speaker.cleaned.isEmpty
                                    && draft.confirmedFields.isEmpty {
                            close(keepingDraft: false)
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
                .disabled(isSaving || (reviewing ? !draft.canConfirm : draft.original.cleaned.isEmpty))
                .accessibilityIdentifier(reviewing ? "confirm-reply" : "review-reply")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .modifier(SaveErrorAlert(presented: $saveError))
            .confirmationDialog(lang.text("Close this draft?"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(lang.text("Keep draft and close")) { close(keepingDraft: true) }
                Button(lang.text("Discard reply"), role: .destructive) { close(keepingDraft: false) }
                Button(lang.text("Keep editing"), role: .cancel) {}
            }
            .sheet(item: $followUp) { content in
                ShowCardView(card: content)
            }
        }
        .interactiveDismissDisabled(!draft.original.cleaned.isEmpty || !draft.speaker.cleaned.isEmpty
                                    || draft.kind == .correction || !draft.confirmedFields.isEmpty)
        .onAppear {
            closing = false
            restoreDraft()
        }
        .onChange(of: draft) { _, current in
            if !closing { ReplyDraftCache().save(current) }
        }
        .onDisappear {
            if !closing {
                closing = true
                stopWork()
                if draft.original.cleaned.isEmpty && draft.speaker.cleaned.isEmpty && draft.confirmedFields.isEmpty {
                    ReplyDraftCache().remove(draft)
                } else {
                    ReplyDraftCache().save(draft)
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
            if let recognize {
                Button {
                    startRecognition(recognize)
                } label: {
                    Label(lang.text(draft.isRecognizing ? "Transcribing…" : "Record reply"), systemImage: "mic")
                }
                .disabled(draft.isRecognizing)
                if recognitionFailed {
                    Text(lang.text("Couldn’t transcribe. Try again or type the reply."))
                        .foregroundStyle(.secondary)
                }
            }
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
            .disabled(draft.original.cleaned.isEmpty || serviceAddress.cleaned.isEmpty || draft.isTranslating)
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
        .onChange(of: serviceAddress) { _, _ in stopWork() }

        if draft.kind == .directions {
            Section {
                Text(lang.text("Directions are saved in the conversation history."))
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach($draft.fields) { $field in
                Section {
                    FieldEditor(field: $field)
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

    private func startRecognition(_ recognize: @escaping ReplyRecognizer) {
        let token = draft.beginRecognition()
        let source = draft.language
        worker?.cancel()
        recognitionFailed = false
        worker = Task { @MainActor in
            do {
                let result = try await recognize(token, source)
                guard draft.isRecognizing, token.taskID == draft.taskID, token.draftID == draft.id,
                      token.version == draft.version else { return }
                if result.token == token, draft.receiveRecognition(
                    text: result.originalText, language: result.language, recordingRef: result.recordingRef, for: token
                ) {
                    reviewing = true
                } else {
                    draft.failRecognition(for: token)
                    recognitionFailed = true
                }
            } catch {
                if draft.failRecognition(for: token) { recognitionFailed = true }
            }
        }
    }

    private func restoreDraft() {
        guard !didRestore else { return }
        didRestore = true
        let cache = ReplyDraftCache()
        guard let saved = cache.load(taskID: task.id, correctedActionID: draft.correctedActionID) else { return }
        // A crash between the SwiftData commit and removing the cache can leave a confirmed draft.
        let id = saved.id
        let match = FetchDescriptor<ConversationTurn>(predicate: #Predicate { $0.id == id })
        if (try? context.fetchCount(match)) == 1 {
            cache.remove(saved)
        } else {
            draft = saved
            reviewing = saved.originalText != nil
        }
    }

    private func stopWork() {
        draft.invalidateRequests()
        worker?.cancel()
        worker = nil
    }

    private func close(keepingDraft: Bool) {
        closing = true
        stopWork()
        if keepingDraft { ReplyDraftCache().save(draft) } else { ReplyDraftCache().remove(draft) }
        dismiss()
    }

    private func save() {
        guard !closing, !isSaving, draft.canConfirm else { return }
        isSaving = true
        do {
            let turn = try TaskStore(context: context).confirmReply(draft)
            onSaved(turn.id)
            close(keepingDraft: false)
        } catch {
            isSaving = false
            saveError = true
        }
    }
}

private struct FieldEditor: View {
    @Binding var field: FieldDraft
    @Environment(\.cardLanguage) private var language
    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        if field.kind == .deadline {
            Toggle(lang.text("Set an exact time"), isOn: $field.useExactTime)
                .accessibilityIdentifier("exact-time")
        }

        if field.confirmedTime != nil {
            exactTimeEditor
        } else {
            ForEach(CardLanguage.allCases) { cardLanguage in
                TextField(lang.text(cardLanguage == .english ? "English value" : "Chinese value"), text: Binding {
                    field.text[cardLanguage]
                } set: { value in
                    field.edit(value, in: cardLanguage)
                }, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("\(field.kind.rawValue)-\(cardLanguage.rawValue)")
            }
            if field.pendingReview != nil {
                Text(lang.text("Review the other language before saving both versions."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(lang.text("Confirm both versions")) { field.pendingReview = nil }
            }
        }
    }

    private var exactTimeEditor: some View {
        Group {
            Picker(lang.text("Weekday"), selection: $field.time.weekday) {
                ForEach(Weekday.allCases) { day in
                    Text(lang.text(day.english)).tag(day)
                }
            }
            .accessibilityIdentifier("deadline-weekday")

            DatePicker(lang.text("Clock time"), selection: clock, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, .gmt)
                .accessibilityIdentifier("deadline-clock")

            Toggle(lang.text("Arrive by this time"), isOn: $field.time.isCutoff)

            LanguageLines(text: field.time.text, primary: lang)
        }
    }

    private var clock: Binding<Date> {
        Binding {
            Date(timeIntervalSinceReferenceDate: TimeInterval(field.time.minuteOfDay * 60))
        } set: { date in
            let minutes = Int(date.timeIntervalSinceReferenceDate / 60)
            field.time.minuteOfDay = (minutes % 1440 + 1440) % 1440
        }
    }
}
