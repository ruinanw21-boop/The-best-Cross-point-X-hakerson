import SwiftData
import SwiftUI

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cardLanguage) private var language
    @Query(sort: \CampusTask.updatedAt, order: .reverse) private var tasks: [CampusTask]
    @State private var path: [Route] = []
    @State private var saveError = false

    private enum Route: Hashable {
        case prepare
        case task(UUID)
    }

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if tasks.isEmpty {
                    emptyState
                } else {
                    List {
                        taskSection("In progress", tasks: tasks.filter { !$0.isComplete })
                        taskSection("Completed", tasks: tasks.filter(\.isComplete))
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) {
                        newTaskButton.campusActionBar()
                    }
                }
            }
            .background(CampusStyle.canvas.ignoresSafeArea())
            .modifier(SaveErrorAlert(presented: $saveError))
            .navigationTitle(lang.text("My tasks"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .prepare:
                    PrepareCardView { task in
                        path = [.task(task.id)]
                    }
                case .task(let id):
                    if let task = tasks.first(where: { $0.id == id }) {
                        TaskDetailView(task: task)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(lang.text("No tasks yet"), systemImage: "list.clipboard")
        } description: {
            Text(lang.text("Show a question in Chinese and save the next steps in both languages."))
        } actions: {
            newTaskButton
                .controlSize(.large)
            Button(lang.text("Add enrollment example"), action: addEnrollmentExample)
                .buttonStyle(.borderless)
        }
    }

    private func addEnrollmentExample() {
        let scenario = TaskScenario.enrollment
        let fields = RequirementKind.allCases.filter(scenario.defaultFields.contains)
        do {
            let task = try TaskStore(context: context).createTask(
                scenario: scenario, title: scenario.title, question: scenario.question(asking: fields), fields: fields
            )
            path = [.task(task.id)]
        } catch {
            saveError = true
        }
    }

    private var newTaskButton: some View {
        Button {
            path.append(.prepare)
        } label: {
            Label(lang.text("New task"), systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CampusStyle.actionFill)
        .accessibilityIdentifier("new-task")
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [CampusTask]) -> some View {
        if !tasks.isEmpty {
            Section(lang.text(title)) {
                ForEach(tasks) { task in
                    NavigationLink(value: Route.task(task.id)) {
                        TaskRow(task: task)
                    }
                }
            }
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
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: task.title.preferred(language.wrappedValue)).font(.headline)
                Text(verbatim: nextStep).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        } icon: {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : task.scenario.icon)
                .foregroundStyle(CampusStyle.accent)
                .accessibilityHidden(true)
        }
    }
}
