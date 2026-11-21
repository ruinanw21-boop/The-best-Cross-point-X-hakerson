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
    @State private var savedTurnID: UUID?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                checklistFeed
                historyFeed
                Button {
                    change { try $0.setComplete(!task.isComplete, for: task) }
                } label: {
                    Label(lang.text(task.isComplete ? "Reopen task" : "Mark complete"),
                          systemImage: task.isComplete ? "arrow.uturn.backward" : "checkmark.circle")
                }
                .buttonStyle(DeskButtonStyle(tone: .soft))
                .accessibilityIdentifier("toggle-complete")
            }
            .deskPage()
        }
        .background(CampusStyle.canvas.ignoresSafeArea())
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
            ReviewReplyView(task: task, correcting: presentation.correction, onSaved: { turnID in
                savedTurnID = turnID
                savedNotice = UUID()
                showHistory = true
            })
            .id(presentation.id)
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

    private var checklistFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeskHeading(title: lang.text("Action checklist"))
            if savedNotice != nil {
                Label(lang.text("Reply saved"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CampusStyle.accent)
            }
            if checklist.isEmpty {
                Text(lang.text("Confirmed requirements will appear here."))
                    .foregroundStyle(CampusStyle.muted)
            } else {
                let rows = checklist
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        TicketRule()
                        switch row {
                        case .confirmed(let item): actionRow(item)
                        case .pending(let kind): pendingRow(kind)
                        }
                    }
                    TicketRule()
                }
            }
            if !actions.isEmpty {
                Button(action: showChecklist) {
                    Label(lang.text("Show checklist"), systemImage: "text.rectangle")
                }
                .buttonStyle(DeskButtonStyle(tone: .soft))
            }
        }
    }

    private var historyFeed: some View {
        VStack(alignment: .leading, spacing: 12) {
            if turns.isEmpty {
                DeskHeading(title: lang.text("Conversation history"), subtitle: lang.text("Saved replies will appear here."))
            } else {
                DisclosureGroup(isExpanded: $showHistory) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(turns) { turn in
                            Button { replySource = turn } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(CampusStyle.accent)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 8)
                                        .accessibilityHidden(true)
                                    historyRow(turn)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(CampusStyle.rule).frame(width: 1).padding(.leading, 3.5)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                } label: {
                    DeskHeading(title: lang.text("Conversation history"))
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                lang.text(task.isComplete ? "Completed" : "In progress"),
                systemImage: task.isComplete ? "checkmark.circle.fill" : task.scenario.icon
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(CampusStyle.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(CampusStyle.mist, in: Capsule())

            Text(verbatim: task.title.preferred(lang))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(CampusStyle.ticketInk)
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
        .buttonStyle(DeskButtonStyle(tone: .primary))
        .accessibilityIdentifier("show-question")

        Button {
            reply = .init()
        } label: {
            Label(lang.text("Record reply"), systemImage: "plus.bubble")
        }
        .buttonStyle(DeskButtonStyle(tone: .soft))
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
            if turn.id == savedTurnID {
                Label(lang.text("Reply saved"), systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CampusStyle.accent)
                    .accessibilityIdentifier("reply-saved")
            }
            if turn.recordingRef != nil {
                Label(lang.text("Play recording"), systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(CampusStyle.accent)
            }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReplyMetadata(turn: turn)
                DeskHeading(title: lang.text("Original reply"))
                Text(verbatim: turn.original)
                    .font(.title3)
                    .environment(\.locale, turn.originalLanguage.locale)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("source-original")
                if !turn.translation.isEmpty {
                    TicketRule()
                    DeskHeading(title: lang.text("Translation"))
                    Text(verbatim: turn.translation)
                        .environment(\.locale, turn.originalLanguage.other.locale)
                        .textSelection(.enabled)
                }
                if let initial = turn.originalText, initial != turn.original {
                    DisclosureGroup(lang.text("Original wording")) {
                        Text(verbatim: initial)
                            .environment(\.locale, turn.originalLanguage.locale)
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    }
                }
                if let reference = turn.recordingRef {
                    RecordingPlaybackButton(recordingRef: reference)
                }
            }
            .deskPage()
        }
        .background(CampusStyle.canvas.ignoresSafeArea())
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
