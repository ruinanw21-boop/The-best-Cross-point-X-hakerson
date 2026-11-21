import SwiftData
import SwiftUI

struct TaskDetailView: View {
    let task: CampusTask
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @Query private var actions: [ActionItem]
    @Query private var turns: [ConversationTurn]
    @State private var card: CardContent?
    @State private var reply: ReplyPresentation?
    @State private var savedTurnID: UUID?
    @State private var recordAfterCard = false
    @State private var saveError = false

    init(task: CampusTask) {
        self.task = task
        let id = task.id
        _actions = Query(filter: #Predicate<ActionItem> { $0.taskID == id }, sort: \ActionItem.createdAt)
        _turns = Query(filter: #Predicate<ConversationTurn> { $0.taskID == id }, sort: \ConversationTurn.confirmedAt)
    }

    private var lang: CardLanguage { language.wrappedValue }
    private var missing: [RequirementKind] {
        let answered = Set(actions.map(\.kind))
        return task.fields.filter { !answered.contains($0) }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 4, trailing: 0))

            Section(lang.text("Action checklist")) {
                if actions.isEmpty {
                    Text(lang.text("Confirmed requirements will appear here."))
                        .foregroundStyle(.secondary)
                }

                ForEach(actions) { item in
                    actionRow(item)
                }

                if !actions.isEmpty {
                    Button {
                        showChecklist()
                    } label: {
                        Label(lang.text("Show checklist"), systemImage: "text.rectangle")
                    }
                }
            }

            if !missing.isEmpty {
                Section(lang.text("To ask")) {
                    ForEach(missing) { kind in
                        Button {
                            card = .init(title: "Follow-up question", text: kind.question)
                        } label: {
                            Label(kind.question.preferred(lang), systemImage: "questionmark.bubble")
                        }
                    }
                }
            }

            Section(lang.text("Conversation history")) {
                if turns.isEmpty {
                    Text(lang.text("Saved replies will appear here."))
                        .foregroundStyle(.secondary)
                }
                ForEach(turns) { turn in
                    historyRow(turn)
                }
            }

            Section {
                Button {
                    change { try $0.setComplete(!task.isComplete, for: task) }
                } label: {
                    Label(
                        lang.text(task.isComplete ? "Reopen task" : "Mark complete"),
                        systemImage: task.isComplete ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
                .accessibilityIdentifier("toggle-complete")
            }
        }
        .navigationTitle(lang.text("Task details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
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
            })
            .id(presentation.id)
        }
        .modifier(SaveErrorAlert(presented: $saveError))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                lang.text(task.isComplete ? "Completed" : "In progress"),
                systemImage: task.isComplete ? "checkmark.circle.fill" : task.scenario.icon
            )
            .font(.caption.weight(.semibold))

            Text(verbatim: task.title.preferred(lang))
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { headerButtons }
                VStack(alignment: .leading, spacing: 10) { headerButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(CampusStyle.cardInk)
        .background(CampusStyle.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var headerButtons: some View {
        Button {
            card = .init(title: "Question card", text: task.question)
        } label: {
            Label(lang.text("Show card"), systemImage: "text.bubble")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("show-question")

        Button {
            reply = .init()
        } label: {
            Label(lang.text("Record reply"), systemImage: "plus.bubble")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("record-reply")
    }

    private func actionRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if item.kind == .material {
                Button {
                    change { try $0.toggleMaterial(item, for: task) }
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.text.preferred(lang))
                .accessibilityValue(lang.text(item.isChecked ? "Ready" : "To prepare"))
                .accessibilityIdentifier("material-check")
            }

            VStack(alignment: .leading, spacing: 6) {
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
            .buttonStyle(.borderless)
            .accessibilityLabel(lang.text("Requirement options"))
        }
    }

    private func historyRow(_ turn: ConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(lang.text(turn.kind.label), systemImage: turn.kind == .directions ? "location" : "bubble.left")
                .font(.subheadline.weight(.semibold))

            if turn.id == savedTurnID {
                Label(lang.text("Reply saved"), systemImage: "checkmark.circle")
                    .font(.caption)
                    .accessibilityIdentifier("reply-saved")
            }

            Text(turn.confirmedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)

            if !turn.speaker.isEmpty {
                Text(verbatim: turn.speaker).font(.caption).foregroundStyle(.secondary)
            }

            Text(verbatim: turn.original)
                .environment(\.locale, turn.originalLanguage.locale)
                .accessibilityIdentifier("history-original")

            if let initial = turn.originalText, initial != turn.original {
                DisclosureGroup(lang.text("Original wording")) {
                    Text(verbatim: initial)
                        .environment(\.locale, turn.originalLanguage.locale)
                        .textSelection(.enabled)
                }
                .font(.footnote)
            }

            if !turn.translation.isEmpty {
                Text(verbatim: turn.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .environment(\.locale, turn.originalLanguage.other.locale)
            }

            if let reference = turn.recordingRef {
                RecordingPlaybackButton(recordingRef: reference)
            }
        }
        .padding(.vertical, 5)
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

private struct ReplyPresentation: Identifiable {
    let id = UUID()
    var correction: ActionItem?
}
