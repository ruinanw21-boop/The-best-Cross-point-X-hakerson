import SwiftData
import SwiftUI

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Query(sort: \CampusTask.updatedAt, order: .reverse) private var tasks: [CampusTask]
    @State private var path: [Route] = []
    @State private var showingCompleted = false
    @State private var saveError = false

    private enum Route: Hashable {
        case prepare
        case task(UUID)
    }

    private var lang: CardLanguage { language.wrappedValue }
    private var visibleTasks: [CampusTask] { tasks.filter { $0.isComplete == showingCompleted } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    masthead
                    hero
                    taskFeed
                }
                .deskPage()
            }
            .background(CampusStyle.canvas.ignoresSafeArea())
            .modifier(SaveErrorAlert(presented: $saveError))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .prepare:
                    PrepareCardView { task in
                        showingCompleted = false
                        path = [.task(task.id)]
                    }
                    .toolbar(.visible, for: .navigationBar)
                case .task(let id):
                    if let task = tasks.first(where: { $0.id == id }) {
                        TaskDetailView(task: task)
                            .toolbar(.visible, for: .navigationBar)
                    }
                }
            }
        }
    }

    private var masthead: some View {
        HStack(spacing: 10) {
            DeskMark()
            Text(lang.text("Campus Cards"))
                .font(.headline.weight(.bold))
                .foregroundStyle(CampusStyle.ticketInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            LanguageMenu()
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(CampusStyle.paper, in: Circle())
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(lang.text("At the campus desk"), systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CampusStyle.signal)
            Text(lang.text("Take the question with you."))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(lang.text("Show your question in Chinese. Keep the answer in both languages."))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    path.append(.prepare)
                } label: {
                    Label(lang.text("New task"), systemImage: "plus")
                }
                .buttonStyle(DeskButtonStyle(tone: .signal))
                .accessibilityIdentifier("new-task")
                if !dynamicType.isAccessibilitySize {
                    Spacer(minLength: 10)
                    DeskRouteGraphic().frame(width: 94, height: 52)
                }
            }
            .padding(.top, 5)
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusStyle.actionFill, in: RoundedRectangle(cornerRadius: 26))
    }

    private var taskFeed: some View {
        VStack(alignment: .leading, spacing: 15) {
            DeskHeading(title: lang.text("My tasks"))
            if !tasks.isEmpty {
                Picker(lang.text("Task status"), selection: $showingCompleted) {
                    Text(lang.text("In progress")).tag(false)
                    Text(lang.text("Completed")).tag(true)
                }
                .pickerStyle(.segmented)
            }
            if visibleTasks.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleTasks) { task in
                        if task.id != visibleTasks.first?.id { TicketRule() }
                        NavigationLink(value: Route.task(task.id)) {
                            TaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.text(showingCompleted ? "No completed tasks yet" : "No tasks in progress"))
                .font(.headline)
                .foregroundStyle(CampusStyle.ticketInk)
            if tasks.isEmpty {
                Text(lang.text("Not sure where to start? Try the enrollment example."))
                    .font(.subheadline)
                    .foregroundStyle(CampusStyle.muted)
                Button(lang.text("Add enrollment example"), action: addEnrollmentExample)
                    .buttonStyle(DeskButtonStyle(tone: .soft))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

    private func addEnrollmentExample() {
        let scenario = TaskScenario.enrollment
        let fields = RequirementKind.allCases.filter(scenario.defaultFields.contains)
        do {
            let task = try TaskStore(context: context).createTask(
                scenario: scenario, title: scenario.title, question: scenario.question(asking: fields), fields: fields
            )
            showingCompleted = false
            path = [.task(task.id)]
        } catch {
            saveError = true
        }
    }
}

private struct TaskRow: View {
    let task: CampusTask
    @Query private var actions: [ActionItem]
    @Query private var turns: [ConversationTurn]
    @Environment(\.cardLanguage) private var language

    init(task: CampusTask) {
        self.task = task
        let id = task.id
        _actions = Query(filter: #Predicate<ActionItem> { $0.taskID == id }, sort: \ActionItem.createdAt)
        _turns = Query(filter: #Predicate<ConversationTurn> { $0.taskID == id }, sort: \ConversationTurn.confirmedAt, order: .reverse)
    }

    private var nextStep: String {
        let lang = language.wrappedValue
        if task.isComplete { return lang.text("Completed") }
        if let material = actions.first(where: { $0.kind == .material && !$0.isChecked }) {
            return material.text.preferred(lang)
        }
        let answered = Set(actions.map(\.kind))
        if let missing = task.fields.first(where: { !answered.contains($0) }) {
            return missing.question.preferred(lang)
        }
        if let location = actions.first(where: { $0.kind == .location }) {
            return location.text.preferred(lang)
        }
        if let directions = turns.first(where: { $0.kind == .directions }) {
            return directions.originalLanguage == lang || directions.translation.isEmpty
                ? directions.original : directions.translation
        }
        return lang.text("Ready to show")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: task.isComplete ? "checkmark" : task.scenario.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(CampusStyle.accent)
                .frame(width: 44, height: 44)
                .background(CampusStyle.mist, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: task.title.preferred(language.wrappedValue))
                    .font(.headline)
                    .foregroundStyle(CampusStyle.ticketInk)
                Text(verbatim: nextStep)
                    .font(.subheadline)
                    .foregroundStyle(CampusStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CampusStyle.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
