import SwiftData
import SwiftUI

struct TaskDetailView: View {
    let task: CampusTask
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @Query private var actions: [ActionItem]
    @Query private var turns: [ConversationTurn]
    @State private var section: DetailSection = .checklist
    @State private var card: CardContent?
    @State private var reply: ReplyPresentation?
    @State private var savedTurnID: UUID?
    @State private var recordAfterCard = false
    @State private var saveError = false

    private enum DetailSection: String, CaseIterable {
        case checklist = "Checklist"
        case history = "Conversation history"
    }

    init(task: CampusTask) {
        self.task = task
        let id = task.id
        _actions = Query(filter: #Predicate<ActionItem> { $0.taskID == id }, sort: \ActionItem.createdAt)
        _turns = Query(filter: #Predicate<ConversationTurn> { $0.taskID == id },
                       sort: \ConversationTurn.confirmedAt, order: .reverse)
    }

    private var lang: CardLanguage { language.wrappedValue }
    private var missing: [RequirementKind] {
        let answered = Set(actions.map(\.kind))
        return task.fields.filter { !answered.contains($0) }
    }

    var body: some View {
        CampusPage {
            VStack(alignment: .leading, spacing: 14) {
                taskHeader
                Picker(lang.text("Task details"), selection: $section) {
                    ForEach(DetailSection.allCases, id: \.self) { item in
                        Text(lang.text(item.rawValue)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("task-details-section")

                switch section {
                case .checklist:
                    checklist
                    if !missing.isEmpty { followUpQuestions }
                    completionButton
                case .history:
                    history
                }
            }
        }
        .navigationTitle(lang.text("Task details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CampusPrimaryAction(title: lang.text("Translate reply"), icon: "character.bubble") {
                reply = .init()
            }
            .accessibilityIdentifier("record-reply")
            .campusActionBar()
        }
        .fullScreenCover(item: $card, onDismiss: {
            if recordAfterCard {
                recordAfterCard = false
                reply = .init()
            }
        }) { content in
            ShowCardView(card: content) {
                recordAfterCard = true
                card = nil
            }
        }
        .sheet(item: $reply) { presentation in
            ReviewReplyView(task: task, correcting: presentation.correction, onSaved: { id in
                savedTurnID = id
                section = .history
            })
            .id(presentation.id)
        }
        .modifier(SaveErrorAlert(presented: $saveError))
    }

    private var taskHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                lang.text(task.isComplete ? "Completed" : "In progress"),
                systemImage: task.isComplete ? "checkmark.circle.fill" : task.scenario.icon
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(CampusStyle.translationInk)

            Text(verbatim: task.title.preferred(lang))
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)

            Button {
                card = .init(title: "Question card", text: task.question)
            } label: {
                Label(lang.text("Show card"), systemImage: "text.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 24)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("show-question")
        }
        .campusPanel(highlighted: true, inset: 20)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            if actions.isEmpty {
                Label(lang.text("Confirmed requirements will appear here."), systemImage: "checklist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(actions) { item in
                    if item.id != actions.first?.id { Divider() }
                    actionRow(item)
                }
                Divider()
                Button(action: showChecklist) {
                    Label(lang.text("Show checklist"), systemImage: "text.rectangle")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("show-checklist")
            }
        }
        .campusPanel()
    }

    private var followUpQuestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.text("To ask"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(missing) { kind in
                Button {
                    card = .init(title: "Follow-up question", text: kind.question)
                } label: {
                    HStack(spacing: 10) {
                        Label(kind.question.preferred(lang), systemImage: kind.icon)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CampusStyle.translationInk)
                .accessibilityIdentifier("follow-up-\(kind.rawValue)")
            }
        }
        .campusPanel()
    }

    private var completionButton: some View {
        Button {
            change { try $0.setComplete(!task.isComplete, for: task) }
        } label: {
            Label(
                lang.text(task.isComplete ? "Reopen task" : "Mark complete"),
                systemImage: task.isComplete ? "arrow.uturn.backward" : "checkmark.circle"
            )
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityIdentifier("toggle-complete")
    }

    private func actionRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.kind == .material {
                Button {
                    change { try $0.toggleMaterial(item, for: task) }
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CampusStyle.translationInk)
                .accessibilityLabel(item.text.preferred(lang))
                .accessibilityValue(lang.text(item.isChecked ? "Ready" : "To prepare"))
                .accessibilityIdentifier("material-check")
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(lang.text(item.kind.label), systemImage: item.kind.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LanguageLines(text: item.text, primary: lang)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            Menu {
                Button {
                    reply = .init(correction: item)
                } label: {
                    Label(lang.text("Correct requirement"), systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CampusStyle.translationInk)
            .accessibilityLabel(lang.text("Requirement options"))
        }
    }

    @ViewBuilder
    private var history: some View {
        if turns.isEmpty {
            Label(lang.text("Saved replies will appear here."), systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .campusPanel()
        } else {
            ForEach(turns) { turn in
                ReplyHistoryCard(turn: turn, justSaved: turn.id == savedTurnID)
            }
        }
    }

    private func showChecklist() {
        var text = BilingualText()
        for cardLanguage in CardLanguage.allCases {
            text[cardLanguage] = actions.map { item in
                let value = item.text[cardLanguage]
                return "\(cardLanguage.text(item.kind.label)) · \(value.isEmpty ? cardLanguage.text("Translation needed") : value)"
            }.joined(separator: "\n\n")
        }
        card = .init(title: "Action checklist", text: text)
    }

    private func change(_ persist: (TaskStore) throws -> Void) {
        do {
            try persist(TaskStore(context: context))
        } catch {
            saveError = true
        }
    }
}

private struct ReplyHistoryCard: View {
    let turn: ConversationTurn
    let justSaved: Bool
    @Environment(\.cardLanguage) private var language

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(lang.text(turn.kind.label), systemImage: turn.kind == .directions ? "location" : "bubble.left")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(turn.confirmedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !turn.speaker.isEmpty {
                    Text(verbatim: turn.speaker).font(.caption).foregroundStyle(.secondary)
                }
                if justSaved {
                    Label(lang.text("Reply saved"), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(CampusStyle.translationInk)
                        .accessibilityIdentifier("reply-saved")
                }
            }

            quotedText(turn.original, in: turn.originalLanguage, prominent: false)
                .accessibilityIdentifier("history-original")

            if !turn.translation.isEmpty {
                quotedText(turn.translation, in: turn.originalLanguage.other, prominent: true)
            }

            if let initial = turn.originalText, initial != turn.original {
                DisclosureGroup(lang.text("Original wording")) {
                    Text(verbatim: initial)
                        .environment(\.locale, turn.originalLanguage.locale)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
                .font(.footnote)
            }

            if let reference = turn.recordingRef {
                RecordingPlaybackButton(recordingRef: reference)
            }
        }
        .campusPanel()
    }

    private func quotedText(_ text: String, in cardLanguage: CardLanguage, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: cardLanguage.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? CampusStyle.translationInk : .secondary)
            Text(verbatim: text)
                .font(prominent ? .body.weight(.medium) : .body)
                .environment(\.locale, cardLanguage.locale)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(prominent ? CampusStyle.translationSurface : CampusStyle.background,
                    in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReplyPresentation: Identifiable {
    let id = UUID()
    var correction: ActionItem?
}
