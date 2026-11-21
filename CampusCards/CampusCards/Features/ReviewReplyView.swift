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
    @Environment(\.dynamicTypeSize) private var dynamicType
    @FocusState private var focusedField: EditorField?
    @State private var detailsExpanded: Bool
    @State private var followUp: CardContent?
    @State private var saveError = false
    @State private var isSaving = false
    @State private var confirmCancel = false
    @State private var addressEditor: TranslationAddressEditor?
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

    private enum EditorField: Hashable { case source, translation }

    init(task: CampusTask, correcting action: ActionItem?, recognize: ReplyRecognizer? = nil,
         onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.task = task
        self.recognize = recognize
        self.onSaved = onSaved
        let id = task.id
        _detailsExpanded = State(initialValue: action != nil)
        _draft = State(initialValue: ReplyDraft(taskID: id, correcting: action))
        _existingActions = Query(filter: #Predicate<ActionItem> { $0.taskID == id })
    }

    private var lang: CardLanguage { language.wrappedValue }

    private var showingManualTranslation: Binding<Bool> {
        Binding(get: { draft.pendingManualTranslation != nil }, set: { presented in
            if !presented { draft.pendingManualTranslation = nil }
        })
    }

    private var missing: [RequirementKind] {
        let answered = Set(existingActions.map(\.kind) + draft.confirmedFields.map(\.kind))
        return task.fields.filter { !answered.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                CampusPage {
                    VStack(alignment: .leading, spacing: 14) {
                        replyContext
                        languageDirection
                        sourcePanel
                        translationPanel.id(EditorField.translation)
                        replyDetails
                    }
                }
                .onChange(of: draft.hasReviewedTranslation) { _, translated in
                    if translated { scroll.scrollTo(EditorField.translation, anchor: .bottom) }
                }
                .onChange(of: draft.translationError) { _, error in
                    if error != nil { scroll.scrollTo(EditorField.translation, anchor: .bottom) }
                }
            }
            .navigationTitle(lang.text("Translate reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Cancel")) {
                        if draft.hasDraftContent {
                            confirmCancel = true
                        } else {
                            close(.discard)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addressEditor = .init(translateOnSave: false)
                        } label: {
                            Label(lang.text("Translation service"), systemImage: "network")
                        }
                    } label: {
                        Label(lang.text("Translation settings"), systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("translation-settings")
                }
                ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .modifier(SaveErrorAlert(presented: $saveError))
            .confirmationDialog(lang.text("Close this draft?"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(lang.text("Keep draft and close")) { close(.keep) }
                Button(lang.text("Discard reply"), role: .destructive) { close(.discard) }
                Button(lang.text("Keep editing"), role: .cancel) {}
            }
            .sheet(item: $followUp) { content in
                ShowCardView(card: content)
            }
            .sheet(item: $draft.pendingField) { field in
                requirementEditor(for: field)
            }
            .sheet(isPresented: showingManualTranslation) {
                ManualTranslationSheet(text: Binding(
                    get: { draft.pendingManualTranslation ?? "" },
                    set: { if draft.pendingManualTranslation != nil { draft.pendingManualTranslation = $0 } }
                ), target: draft.language.other) { text in
                    stopWork()
                    draft.acceptManualTranslation(text)
                }
            }
            .sheet(item: $addressEditor) { editor in
                TranslationAddressView(address: serviceAddress, translateOnSave: editor.translateOnSave) { address in
                    if address != serviceAddress && draft.isTranslating { stopWork() }
                    serviceAddress = address
                    addressEditor = nil
                    if editor.translateOnSave { translate(using: address) }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .interactiveDismissDisabled(draft.hasDraftContent || press != nil || draft.kind == .correction)
        .onAppear {
            closing = false
            restoreDraft()
        }
        .onChange(of: draft) { _, current in
            if !closing { ReplyDraftCache().save(current) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !closing {
                if press != nil {
                    stopWork()
                    recognitionMessage = ReplyCaptureError.interrupted.messageKey
                }
                if draft.hasDraftContent { ReplyDraftCache().save(draft) }
            }
        }
        .onDisappear {
            if !closing {
                // A sheet can cover the whole editor in compact height.
                if draft.hasPendingEdits {
                    ReplyDraftCache().save(draft)
                    return
                }
                closing = true
                stopWork()
                if draft.hasDraftContent {
                    ReplyDraftCache().save(draft)
                } else {
                    ReplyDraftCache().remove(draft)
                }
            }
        }
    }

    private var replyContext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: task.title.preferred(lang))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if draft.kind == .correction {
                Label(lang.text("Correction"), systemImage: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Picker(lang.text("Reply type"), selection: $draft.kind) {
                        Text(lang.text("Directions")).tag(ReplyKind.directions)
                        Text(lang.text("Requirements")).tag(ReplyKind.requirements)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(lang.text(draft.kind.label))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(lang.text("Reply type"))
                .accessibilityValue(lang.text(draft.kind.label))
                .accessibilityIdentifier("reply-kind")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var languageDirection: some View {
        CampusLanguagePair(
            first: draft.language, firstLabel: lang.text("Source language"),
            secondLabel: lang.text("Target language"), swapLabel: lang.text("Swap translation languages"),
            swapIdentifier: "swap-translation-languages"
        ) {
            stopWork()
            recognitionMessage = nil
            draft.language = draft.language.other
        }
        .disabled(press != nil)
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang.text("Original reply"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            TextField(lang.text("Type what they said"), text: Binding(
                get: { draft.original },
                set: { updated in
                    guard draft.original != updated else { return }
                    draft.original = updated
                    worker?.cancel()
                    worker = nil
                    recognitionMessage = nil
                }
            ), axis: .vertical)
            .font(.title2)
            .lineLimit(2...8)
            .focused($focusedField, equals: .source)
            .disabled(press != nil)
            .accessibilityIdentifier("original-reply")

            if let reference = draft.recordingRef, press == nil {
                RecordingPlaybackButton(recordingRef: reference)
                    .font(.subheadline)
            }
            recognitionFeedback

            Divider()
            if dynamicType.isAccessibilitySize {
                VStack(spacing: 8) { microphones }
            } else {
                HStack(spacing: 8) { microphones }
            }
            if press == nil {
                Text(lang.text("Hold to speak"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .campusPanel()
    }

    @ViewBuilder
    private var microphones: some View {
        ForEach([CardLanguage.chinese, .english]) { source in
            let isHeld = press?.language == source
            let title = isHeld && capture.isRecording ? lang.text("Recording…") : source.name
            let label = source == .chinese ? "Hold to speak Chinese" : "Hold to speak English"
            HoldMicrophoneButton(title: title, isHeld: isHeld, label: lang.text(label),
                hint: lang.text("Double-tap to start or stop recording."),
                identifier: source == .chinese ? "microphone-zh" : "microphone-en",
                onPress: { beginPress(in: source) }, onRelease: { endPress(in: source) },
                onCancel: {
                    guard press?.language == source else { return }
                    if capture.isRecording { stopWork() } else { endPress(in: source) }
                })
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder
    private var recognitionFeedback: some View {
        if let message = recognitionMessage ?? (press == nil ? nil : capture.issue?.messageKey) {
            Text(lang.text(message))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("recognition-error")
        } else if draft.isRecognizing && press == nil {
            ProgressView(lang.text("Transcribing…"))
                .font(.footnote)
        }
    }

    private var translationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang.text(draft.language == .chinese ? "English translation" : "Chinese translation"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if draft.hasReviewedTranslation, !draft.translation.cleaned.isEmpty {
                    Button {
                        UIPasteboard.general.string = draft.translation
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lang.text("Copy translation"))
                }
            }
            .foregroundStyle(CampusStyle.accent)

            if draft.isTranslating {
                ProgressView(lang.text("Translating…"))
                    .frame(minHeight: 46, alignment: .leading)
            }

            if let error = draft.translationError {
                Label(lang.text(error.messageKey), systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(CampusStyle.muted)
                    .accessibilityIdentifier("translation-error")
                if error == .invalidAddress || error == .offline || error == .invalidResponse {
                    Button(lang.text("Change service address")) {
                        addressEditor = .init(translateOnSave: true)
                    }
                    .font(.subheadline)
                }
            }

            if draft.hasReviewedTranslation {
                TextField(lang.text("Edit translation"), text: Binding(
                    get: { draft.translation }, set: { draft.editTranslation($0) }
                ), axis: .vertical)
                .font(.body)
                .lineLimit(2...8)
                .focused($focusedField, equals: .translation)
                .disabled(draft.isTranslating || draft.isRecognizing || press != nil)
                .accessibilityIdentifier("reviewed-translation")
                if !draft.hasTranslatedCurrentSource {
                    Label(lang.text("Manually reviewed"), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(CampusStyle.accent)
                }
            } else if !draft.isTranslating && draft.translationError == nil {
                Text(lang.text("Translation will appear here."))
                    .foregroundStyle(CampusStyle.muted)
            }

            Button(lang.text("Enter translation manually")) {
                focusedField = nil
                stopWork()
                draft.pendingManualTranslation = draft.translation
            }
            .buttonStyle(DeskButtonStyle(tone: .soft))
            .disabled(draft.original.cleaned.isEmpty || press != nil || draft.isRecognizing)

            if draft.hasReviewedTranslation {
                Button(lang.text(translationButtonTitle), action: requestTranslation)
                    .font(.subheadline)
                    .disabled(!canTranslate || press != nil)
            }
        }
        .campusPanel(highlighted: true)
    }

    private var actionBar: some View {
        let saving = draft.hasReviewedTranslation && !draft.translation.cleaned.isEmpty
        let title = draft.isTranslating ? "Translating…" : (saving ? "Confirm and save" : translationButtonTitle)
        return CampusPrimaryAction(title: lang.text(title), icon: saving ? "checkmark" : "character.bubble",
                                   isBusy: draft.isTranslating) {
            focusedField = nil
            if saving {
                save()
            } else {
                requestTranslation()
            }
        }
        .disabled(isSaving || press != nil || (saving ? !draft.canConfirm : !canTranslate))
        .accessibilityIdentifier(saving ? "confirm-reply" : "translate-reply")
        .campusActionBar()
    }

    private var replyDetails: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                TextField(lang.text("Who replied? (optional)"), text: $draft.speaker)
                if draft.kind != .directions {
                    requirementFields
                }
            }
            .padding(.top, 12)
        } label: {
            Label(lang.text(draft.kind == .directions ? "Reply details" : "Action checklist"),
                  systemImage: draft.kind == .directions ? "person" : "checklist")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .campusPanel(inset: 12)
        .accessibilityIdentifier("reply-details")
    }

    @ViewBuilder
    private var requirementFields: some View {
        let fields = CampusStyle.ticketOrder.flatMap { kind in draft.fields.filter { $0.kind == kind } }
        TicketSurface {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(fields) { field in
                    if field.id != fields.first?.id { TicketRule() }
                    let needsAnswer = missing.contains(field.kind)
                    let layout = dynamicType.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(alignment: .top))
                    layout {
                        TicketField(kind: field.kind, text: field.effectiveText,
                                    emptyKey: needsAnswer ? "To ask" : "Not added in this reply",
                                    pending: needsAnswer, edited: field.userEdited)
                        Button(lang.text(field.effectiveText.isEmpty ? "Add" : "Edit")) {
                            draft.pendingField = field
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(Text(verbatim: "\(lang.text(field.kind.label)): \(lang.text(field.effectiveText.isEmpty ? "Add" : "Edit"))"))
                        .accessibilityIdentifier("review-field-\(field.kind.rawValue)")
                    }
                }
            }
        }
        if draft.kind == .requirements {
            Button {
                draft.pendingField = FieldDraft(kind: .material)
            } label: {
                Label(lang.text("Add another material"), systemImage: "plus")
            }
            .buttonStyle(DeskButtonStyle(tone: .soft))

            if let questions = CardContent.followUp(for: missing) {
                Button {
                    followUp = questions
                } label: {
                    Label(lang.text("Show follow-up questions"), systemImage: "questionmark.bubble")
                }
                .buttonStyle(DeskButtonStyle(tone: .soft))
                .accessibilityIdentifier("review-follow-up")
            }
        }
    }

    private func requirementEditor(for field: FieldDraft) -> some View {
        let exists = draft.fields.contains { $0.id == field.id }
        let removable = exists && field.kind == .material && draft.kind == .requirements
            && draft.fields.filter { $0.kind == .material }.count > 1
        // The sheet can still render during dismissal. Ignore late focus updates to a closed editor.
        let current = Binding(get: { draft.pendingField ?? field }, set: { updated in
            if draft.pendingField?.id == field.id { draft.pendingField = updated }
        })
        return RequirementEditorSheet(field: current, removable: removable, isCorrection: draft.kind == .correction) { updated in
            if let updated {
                draft.applyReviewedField(updated)
            } else {
                draft.fields.removeAll { $0.id == field.id }
                draft.pendingField = nil
            }
        }
    }

    private var canTranslate: Bool {
        !draft.original.cleaned.isEmpty && !draft.isTranslating && !draft.isRecognizing
    }

    private func requestTranslation() {
        guard canTranslate else { return }
        guard (try? TranslationClient(baseAddress: serviceAddress).endpoint()) != nil else {
            addressEditor = .init(translateOnSave: true)
            return
        }
        translate(using: serviceAddress)
    }

    private var translationButtonTitle: String {
        if let error = draft.translationError, error != .invalidRequest && error != .invalidAddress {
            return "Retry translation"
        }
        return draft.language == .chinese ? "Translate to English" : "Translate to Chinese"
    }

    private func translate(using address: String) {
        guard !closing, press == nil, canTranslate, let token = draft.beginTranslation() else { return }
        worker?.cancel()
        let client = TranslationClient(baseAddress: address)
        let text = draft.original
        let source = draft.language
        worker = Task { @MainActor in
            do {
                let translated = try await client.translate(text: text, source: source)
                draft.receiveTranslation(translated, for: token)
            } catch is CancellationError {
                return
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
        focusedField = nil
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

private struct ManualTranslationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardLanguage) private var language
    @Binding var text: String
    let target: CardLanguage
    let onApply: (String) -> Void

    var body: some View {
        let lang = language.wrappedValue
        NavigationStack {
            CampusPage {
                VStack(alignment: .leading, spacing: 12) {
                    DeskHeading(title: target.name)
                    TextField(lang.text("Edit translation"), text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .deskInput()
                }
            }
            .navigationTitle(lang.text("Enter translation manually"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.text("Cancel")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CampusPrimaryAction(title: lang.text("Use reviewed translation"), icon: "checkmark") {
                    onApply(text)
                }
                .disabled(text.cleaned.isEmpty)
                .campusActionBar()
            }
        }
    }
}

private struct RequirementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardLanguage) private var language
    @Binding var field: FieldDraft
    let removable: Bool
    let isCorrection: Bool
    let onApply: (FieldDraft?) -> Void

    var body: some View {
        let lang = language.wrappedValue
        NavigationStack {
            Form {
                Section { FieldEditor(field: $field, isCorrection: isCorrection) }
                if removable {
                    Button(lang.text("Remove material"), role: .destructive) { onApply(nil) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(lang.text(field.kind.label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.text("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(lang.text("Done")) { onApply(field) } }
            }
        }
    }
}

private struct TranslationAddressEditor: Identifiable {
    let id = UUID()
    let translateOnSave: Bool
}

struct TranslationAddressView: View {
    @Environment(\.cardLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State var address: String
    let translateOnSave: Bool
    let onSave: (String) -> Void

    private var lang: CardLanguage { language.wrappedValue }
    private var validAddress: Bool {
        (try? TranslationClient(baseAddress: address).endpoint()) != nil
    }

    var body: some View {
        NavigationStack {
            CampusPage {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.text("Service address"))
                        .font(.headline)
                    TextField(lang.text("Service address"), text: $address,
                              prompt: Text(verbatim: "http://192.168.1.23:8000"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("translation-address")
                    Text(lang.text(address.cleaned.isEmpty || validAddress
                                   ? "Enter the Wi-Fi address and port of the Windows translation service."
                                   : "Use the service base address, without /translate."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .campusPanel()
            }
            .navigationTitle(lang.text("Translation service"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Cancel")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CampusPrimaryAction(title: lang.text(translateOnSave ? "Save and translate" : "Save address")) {
                    onSave(address.cleaned)
                }
                .disabled(!validAddress)
                .campusActionBar()
            }
        }
    }
}

private struct MicrophonePress {
    let token: ReplyRequestToken
    let language: CardLanguage
}

// A control receives touch cancellation as well as release, including inside the scrolling editor.
private struct HoldMicrophoneButton: UIViewRepresentable {
    let title: String
    let isHeld: Bool
    let label: String
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
        config.cornerStyle = .capsule
        let foreground = isHeld ? UIColor.systemRed : UIColor(CampusStyle.accent)
        config.baseForegroundColor = foreground
        config.baseBackgroundColor = foreground
        config.titleTextAttributesTransformer = .init { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        button.configuration = config
        button.accessibilityLabel = isHeld ? title : label
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
