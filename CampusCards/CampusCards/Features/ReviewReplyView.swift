import SwiftData
import SwiftUI

struct ReviewReplyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var draft: ReplyDraft
    @State private var reviewing = false
    @State private var sheet: ReviewSheet?
    @State private var saveError = false
    @State private var isSaving = false
    @State private var confirmCancel = false
    @Query private var existingActions: [ActionItem]
    let task: CampusTask
    let onSaved: () -> Void

    init(task: CampusTask, correcting action: ActionItem?, onSaved: @escaping () -> Void = {}) {
        self.task = task
        self.onSaved = onSaved
        let id = task.id
        _draft = State(initialValue: ReplyDraft(taskID: id, correcting: action))
        _existingActions = Query(filter: #Predicate<ActionItem> { $0.taskID == id })
    }

    private var lang: CardLanguage { language.wrappedValue }
    private var canSave: Bool {
        !draft.original.cleaned.isEmpty && (draft.kind != .correction || !draft.confirmedFields.isEmpty)
    }
    private var missing: [RequirementKind] {
        let answered = Set(existingActions.map(\.kind) + draft.confirmedFields.map(\.kind))
        return CampusStyle.ticketOrder.filter { task.fields.contains($0) && !answered.contains($0) }
    }
    private var ticketFields: [FieldDraft] {
        CampusStyle.ticketOrder.flatMap { kind in draft.fields.filter { $0.kind == kind } }
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
            .scrollContentBackground(.hidden)
            .background(CampusStyle.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(lang.text(reviewing ? "Review reply" : "Record reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text(reviewing ? "Back" : "Cancel")) {
                        if reviewing {
                            reviewing = false
                        } else if draft.hasContent {
                            confirmCancel = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if reviewing { save() } else { reviewing = true }
                } label: {
                    Text(lang.text(reviewing ? "Confirm and save" : "Review reply"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CampusStyle.actionFill)
                .disabled(isSaving || (reviewing ? !canSave : draft.original.cleaned.isEmpty))
                .accessibilityIdentifier(reviewing ? "confirm-reply" : "review-reply")
                .campusActionBar()
            }
            .modifier(SaveErrorAlert(presented: $saveError))
            .confirmationDialog(lang.text("Discard this reply?"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(lang.text("Discard reply"), role: .destructive) { dismiss() }
                Button(lang.text("Keep editing"), role: .cancel) {}
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .field(let field):
                    fieldEditor(for: field)
                case .followUp(let card):
                    ShowCardView(card: card)
                }
            }
        }
        .interactiveDismissDisabled(draft.hasContent)
    }

    @ViewBuilder
    private var recordSections: some View {
        Section(lang.text("Original reply")) {
            TextField(lang.text("Type what they said"), text: $draft.original, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("original-reply")
        }

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

            Picker(lang.text("Reply language"), selection: $draft.language) {
                ForEach(CardLanguage.allCases) { choice in
                    Text(verbatim: choice.name).tag(choice)
                }
            }
            .onChange(of: draft.language) { _, _ in draft.translation = "" }

            TextField(lang.text("Who replied? (optional)"), text: $draft.speaker)
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section {
            Text(verbatim: draft.original)
                .environment(\.locale, draft.language.locale)
                .textSelection(.enabled)
        } header: {
            Text(lang.text("Original reply"))
        } footer: {
            if draft.kind != .directions {
                Text(lang.text("Checklist edits don’t change the original reply."))
            }
        }

        if draft.kind == .directions {
            Section {
                Text(lang.text("Directions are saved in the conversation history."))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                TicketSurface {
                    let fields = ticketFields
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(fields) { field in
                            if field.id != fields.first?.id { TicketRule() }
                            fieldRow(field)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text(lang.text("Check before you leave"))
            }

            if draft.kind == .requirements {
                Section {
                    Button {
                        let material = FieldDraft(kind: .material)
                        sheet = .field(material)
                    } label: {
                        Label(lang.text("Add another material"), systemImage: "plus")
                    }
                }
                if !missing.isEmpty {
                    Section(lang.text("To ask")) {
                        ForEach(missing) { kind in
                            Button {
                                sheet = .followUp(.init(title: "Follow-up question", text: kind.question))
                            } label: {
                                Label(kind.question.preferred(lang), systemImage: "questionmark.bubble")
                            }
                        }
                    }
                }
            }
        }

        Section(lang.text("Translation")) {
            let placeholder = draft.language == .chinese
                ? "English translation (optional)" : "Chinese translation (optional)"
            TextField(lang.text(placeholder), text: $draft.translation, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private func fieldRow(_ field: FieldDraft) -> some View {
        let pending = missing.contains(field.kind)
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            TicketField(
                kind: field.kind, text: field.effectiveText,
                emptyKey: pending ? "To ask" : "Not added in this reply",
                pending: pending, edited: field.wasEditedDuringReview
            )
            Button(lang.text(field.effectiveText.isEmpty ? "Add" : "Edit")) {
                sheet = .field(field)
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(Text(verbatim: "\(lang.text(field.kind.label)): \(lang.text(field.effectiveText.isEmpty ? "Add" : "Edit"))"))
            .accessibilityIdentifier("review-field-\(field.kind.rawValue)")
        }
    }

    private func fieldEditor(for field: FieldDraft) -> some View {
        let existing = draft.fields.contains { $0.id == field.id }
        let removable = existing && field.kind == .material && draft.kind == .requirements
            && draft.fields.filter { $0.kind == .material }.count > 1
        return FieldEditorSheet(field: field, removable: removable) { updated in
            if let updated {
                if existing {
                    draft.applyReviewedField(updated)
                } else if !updated.effectiveText.isEmpty {
                    draft.fields.append(updated)
                }
            } else {
                draft.fields.removeAll { $0.id == field.id }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        do {
            try TaskStore(context: context).confirmReply(draft)
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            saveError = true
        }
    }
}

private enum ReviewSheet: Identifiable {
    case field(FieldDraft)
    case followUp(CardContent)

    var id: UUID {
        switch self {
        case .field(let field): field.id
        case .followUp(let card): card.id
        }
    }
}

private struct FieldEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardLanguage) private var language
    @State private var field: FieldDraft
    let removable: Bool
    let onApply: (FieldDraft?) -> Void

    init(field: FieldDraft, removable: Bool, onApply: @escaping (FieldDraft?) -> Void) {
        _field = State(initialValue: field)
        self.removable = removable
        self.onApply = onApply
    }

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack {
            Form {
                if field.kind == .deadline {
                    Section {
                        Toggle(lang.text("Set an exact time"), isOn: $field.useExactTime)
                            .accessibilityIdentifier("exact-time")
                    }
                }
                if field.confirmedTime != nil {
                    timeFields
                } else {
                    textFields
                }
                if removable {
                    Section {
                        Button(lang.text("Remove material"), role: .destructive) {
                            onApply(nil)
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(lang.text(field.kind.label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.text("Done")) {
                        onApply(field)
                        dismiss()
                    }
                }
            }
        }
    }

    private var textFields: some View {
        Section {
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

    private var timeFields: some View {
        Section {
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

            VStack(alignment: .leading, spacing: 6) {
                Text(lang.text("Time on the checklist"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LanguageLines(text: field.time.text, primary: lang)
            }
            .padding(.vertical, 4)
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
