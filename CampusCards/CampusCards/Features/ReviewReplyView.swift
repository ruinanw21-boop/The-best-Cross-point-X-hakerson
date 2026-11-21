import SwiftData
import SwiftUI

struct ReviewReplyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardLanguage) private var language
    @State private var draft: ReplyDraft
    @State private var reviewing = false
    @State private var followUp: CardContent?
    @State private var saveError = false
    @State private var isSaving = false
    @State private var confirmCancel = false
    @Query private var existingActions: [ActionItem]
    let task: CampusTask

    init(task: CampusTask, correcting action: ActionItem?) {
        self.task = task
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
                            reviewing = false
                        } else if draft.original.cleaned.isEmpty && draft.speaker.cleaned.isEmpty && draft.confirmedFields.isEmpty {
                            dismiss()
                        } else {
                            confirmCancel = true
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
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(isSaving || (reviewing ? !canSave : draft.original.cleaned.isEmpty))
                .accessibilityIdentifier(reviewing ? "confirm-reply" : "review-reply")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .modifier(SaveErrorAlert(presented: $saveError))
            .confirmationDialog(lang.text("Discard this reply?"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(lang.text("Discard reply"), role: .destructive) { dismiss() }
                Button(lang.text("Keep editing"), role: .cancel) {}
            }
            .sheet(item: $followUp) { content in
                ShowCardView(card: content)
            }
        }
        .interactiveDismissDisabled(!draft.original.cleaned.isEmpty || draft.kind == .correction)
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

            Picker(lang.text("Reply language"), selection: $draft.language) {
                ForEach(CardLanguage.allCases) { choice in
                    Text(verbatim: choice.name).tag(choice)
                }
            }
            .onChange(of: draft.language) { _, _ in draft.translation = "" }

            TextField(lang.text("Who replied? (optional)"), text: $draft.speaker)
        }

        Section(lang.text("Original reply")) {
            TextField(lang.text("Type what they said"), text: $draft.original, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("original-reply")
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section(lang.text("Original reply")) {
            Text(verbatim: draft.original)
                .environment(\.locale, draft.language.locale)

            let placeholder = draft.language == .chinese
                ? "English translation (optional)" : "Chinese translation (optional)"
            TextField(lang.text(placeholder), text: $draft.translation, axis: .vertical)
                .lineLimit(2...5)
        }

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

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        do {
            try TaskStore(context: context).confirmReply(draft)
            dismiss()
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
