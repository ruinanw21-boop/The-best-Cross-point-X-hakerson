import SwiftData
import SwiftUI

struct TaskListView: View {
    @Environment(\.cardLanguage) private var language
    @Query(sort: \CampusTask.updatedAt, order: .reverse) private var tasks: [CampusTask]
    @State private var path: [Route] = []
    @State private var filter: TaskFilter = .active

    private enum TaskFilter: String, CaseIterable {
        case active = "In progress"
        case completed = "Completed"
    }

    private enum Route: Hashable {
        case prepare
        case task(UUID)
    }

    private var lang: CardLanguage { language.wrappedValue }

    var body: some View {
        NavigationStack(path: $path) {
            CampusPage {
                if tasks.isEmpty {
                    emptyState("No tasks yet", icon: "text.bubble",
                               description: "Create a task to show a bilingual question and save the reply.")
                } else {
                    taskBrowser
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CampusPrimaryAction(title: lang.text("New task"), icon: "plus") {
                    path.append(.prepare)
                }
                .accessibilityIdentifier("new-task")
                .campusActionBar()
            }
            .navigationTitle(lang.text("My tasks"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { LanguageMenu() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .prepare:
                    PrepareCardView { task in
                        filter = .active
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

    private var taskBrowser: some View {
        let matchingTasks = tasks.filter { $0.isComplete == (filter == .completed) }
        return VStack(spacing: 16) {
            Picker(lang.text("Task status"), selection: $filter) {
                ForEach(TaskFilter.allCases, id: \.self) { option in
                    Text(lang.text(option.rawValue)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("task-status-filter")

            if matchingTasks.isEmpty {
                if filter == .active {
                    emptyState("No tasks in progress", icon: "tray")
                } else {
                    emptyState("No completed tasks", icon: "checkmark.circle")
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(matchingTasks) { task in
                        NavigationLink(value: Route.task(task.id)) {
                            TaskRow(task: task)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, icon: String, description: String? = nil) -> some View {
        ContentUnavailableView {
            Label(lang.text(title), systemImage: icon)
        } description: {
            if let description { Text(lang.text(description)) }
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

    private var nextStep: String? {
        let lang = language.wrappedValue
        if task.isComplete { return nil }
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
        HStack(spacing: 12) {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : task.scenario.icon)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(CampusStyle.translationInk)
                .background(CampusStyle.translationSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: task.title.preferred(language.wrappedValue)).font(.headline)
                if let nextStep {
                    Text(verbatim: nextStep).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(task.updatedAt, format: .dateTime.month().day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .campusPanel()
        .accessibilityElement(children: .combine)
    }
}
