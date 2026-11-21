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
    @State private var replySource: ConversationTurn?
    @State private var recordAfterCard = false
    @State private var saveError = false
    @State private var showHistory = false
    @State private var savedNotice: UUID?

    init(task: CampusTask) {
        self.task = task
        let id = task.id
        _actions = Query(filter: #Predicate<ActionItem> { $0.taskID == id }, sort: \ActionItem.createdAt)
        _turns = Query(filter: #Predicate<ConversationTurn> { $0.taskID == id }, sort: \ConversationTurn.confirmedAt)
    }

    private var lang: CardLanguage { language.wrappedValue }
    private var checklist: [ChecklistRow] {
        CampusStyle.ticketOrder.flatMap { kind -> [ChecklistRow] in
            let items = actions.filter { $0.kind == kind }
            if items.isEmpty && task.fields.contains(kind) { return [.pending(kind)] }
            return items.map { .confirmed($0) }
        }
    }

    var body: some View {
        List {
            Section {
                header
            }

            Section(lang.text("Action checklist")) {
                if savedNotice != nil {
                    Label(lang.text("Reply saved"), systemImage: "checkmark.circle")
                        .foregroundStyle(CampusStyle.accent)
                }

                if checklist.isEmpty {
                    Text(lang.text("Confirmed requirements will appear here."))
                        .foregroundStyle(.secondary)
                } else {
                    TicketSurface {
                        let rows = checklist
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(rows) { row in
                                if row.id != rows.first?.id { TicketRule() }
                                switch row {
                                case .confirmed(let item):
                                    actionRow(item)
                                case .pending(let kind):
                                    pendingRow(kind)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !actions.isEmpty {
                    Button(action: showChecklist) {
                        Label(lang.text("Show checklist"), systemImage: "text.rectangle")
                    }
                }
            }

            Section {
                if turns.isEmpty {
                    Text(lang.text("Saved replies will appear here."))
                        .foregroundStyle(.secondary)
                } else {
                    DisclosureGroup(isExpanded: $showHistory) {
                        ForEach(turns) { turn in
                            historyRow(turn)
                        }
                    } label: {
                        Label(lang.text("Conversation history"), systemImage: "bubble.left.and.bubble.right")
                    }
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CampusStyle.canvas)
        .navigationTitle(lang.text("Task details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
        .navigationDestination(item: $replySource) { turn in
            ReplySourceView(turn: turn)
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
            ReviewReplyView(task: task, correcting: presentation.correction) {
                savedNotice = UUID()
            }
        }
        .task(id: savedNotice) {
            guard let notice = savedNotice else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            if savedNotice == notice { savedNotice = nil }
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
        .padding(.vertical, 8)
        .controlSize(.large)
    }

    @ViewBuilder
    private var headerButtons: some View {
        Button {
            card = .init(title: "Question card", text: task.question)
        } label: {
            Label(lang.text("Show card"), systemImage: "text.bubble")
        }
        .buttonStyle(.borderedProminent)
        .tint(CampusStyle.actionFill)
        .accessibilityIdentifier("show-question")

        Button {
            reply = .init()
        } label: {
            Label(lang.text("Record reply"), systemImage: "plus.bubble")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("record-reply")
    }

    private func pendingRow(_ kind: RequirementKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TicketField(kind: kind, text: .init())
            Button {
                card = .init(title: "Follow-up question", text: kind.question)
            } label: {
                Label(kind.question.preferred(lang), systemImage: "questionmark.bubble")
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
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
                TicketField(kind: item.kind, text: item.text, edited: item.wasEditedDuringReview == true)

                if let turn = turns.first(where: { $0.id == item.sourceTurnID }) {
                    Button {
                        replySource = turn
                    } label: {
                        Label(lang.text("View source"), systemImage: "text.bubble")
                            .font(.subheadline)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("requirement-source-\(item.kind.rawValue)")
                }
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
            ReplyMetadata(turn: turn)

            Text(verbatim: turn.original)
                .environment(\.locale, turn.originalLanguage.locale)
                .accessibilityIdentifier("history-original")

            if !turn.translation.isEmpty {
                Text(verbatim: turn.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .environment(\.locale, turn.originalLanguage.other.locale)
            }
        }
        .padding(.vertical, 5)
    }

    private func showChecklist() {
        let confirmed: [ActionItem] = checklist.compactMap { row in
            if case .confirmed(let item) = row { return item }
            return nil
        }
        var text = BilingualText()
        for cardLanguage in CardLanguage.allCases {
            text[cardLanguage] = confirmed.map { item in
                let value = item.text[cardLanguage]
                return "\(cardLanguage.text(item.kind.label)) · \(value.isEmpty ? cardLanguage.text("Translation needed") : value)"
            }.joined(separator: "\n\n")
        }
        card = .init(title: "Action checklist", text: text, usesLargeType: false)
    }

    private func change(_ persist: (TaskStore) throws -> Void) {
        do {
            try persist(TaskStore(context: context))
        } catch {
            saveError = true
        }
    }
}

private enum ChecklistRow: Identifiable {
    case confirmed(ActionItem)
    case pending(RequirementKind)

    var id: String {
        switch self {
        case .confirmed(let item): item.id.uuidString
        case .pending(let kind): kind.rawValue
        }
    }
}

private struct ReplySourceView: View {
    @Environment(\.cardLanguage) private var language
    let turn: ConversationTurn

    var body: some View {
        let lang = language.wrappedValue
        List {
            Section {
                ReplyMetadata(turn: turn)
            }
            Section(lang.text("Original reply")) {
                Text(verbatim: turn.original)
                    .environment(\.locale, turn.originalLanguage.locale)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("source-original")
            }
            if !turn.translation.isEmpty {
                Section(lang.text("Translation")) {
                    Text(verbatim: turn.translation)
                        .environment(\.locale, turn.originalLanguage.other.locale)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(lang.text("Reply source"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
    }
}

private struct ReplyMetadata: View {
    @Environment(\.cardLanguage) private var language
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.wrappedValue.text(turn.kind.label), systemImage: turn.kind == .directions ? "location" : "bubble.left")
                .font(.subheadline.weight(.semibold))
            Text(turn.confirmedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if !turn.speaker.isEmpty {
                Text(verbatim: turn.speaker)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReplyPresentation: Identifiable {
    let id = UUID()
    var correction: ActionItem?
}
