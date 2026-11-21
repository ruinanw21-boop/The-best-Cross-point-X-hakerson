import Foundation
import SwiftData

@MainActor
struct TaskStore {
    let context: ModelContext
    private let saveChanges: () throws -> Void

    init(context: ModelContext, saveChanges: (() throws -> Void)? = nil) {
        self.context = context
        self.saveChanges = saveChanges ?? { try context.save() }
    }

    enum Failure: Error {
        case invalidTask, invalidReply, invalidCorrection
    }

    func createTask(
        scenario: TaskScenario, title: BilingualText, question: BilingualText, fields: [RequirementKind]
    ) throws -> CampusTask {
        guard !title.cleaned.isEmpty, !question.cleaned.isEmpty else { throw Failure.invalidTask }
        let task = CampusTask(scenario: scenario, title: title.cleaned, question: question.cleaned, fields: fields)
        context.insert(task)
        try save()
        return task
    }

    func listTasks() throws -> [CampusTask] {
        let tasks = try context.fetch(FetchDescriptor<CampusTask>())
        return tasks.sorted {
            if $0.isComplete != $1.isComplete { return !$0.isComplete }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func task(withID id: UUID) throws -> CampusTask {
        var fetch = FetchDescriptor<CampusTask>(predicate: #Predicate { $0.id == id })
        fetch.fetchLimit = 1
        guard let task = try context.fetch(fetch).first else { throw Failure.invalidTask }
        return task
    }

    func loadTask(_ taskID: UUID) throws -> TaskReadback {
        let task = try self.task(withID: taskID)
        let turns = try context.fetch(FetchDescriptor<ConversationTurn>(
            predicate: #Predicate { $0.taskID == taskID }
        )).sorted {
            if $0.confirmedAt != $1.confirmedAt { return $0.confirmedAt < $1.confirmedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let items = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.taskID == taskID }
        )).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let groups = Self.actionIDs(for: items, turns: turns)
        return TaskReadback(task: task, turns: turns, items: items) { groups[$0.id] ?? $0.id }
    }

    @discardableResult
    func confirmReply(_ draft: ReplyDraft) throws -> ConversationTurn {
        let draftID = draft.id
        var existing = FetchDescriptor<ConversationTurn>(predicate: #Predicate { $0.id == draftID })
        existing.fetchLimit = 1
        if let turn = try context.fetch(existing).first {
            guard turn.taskID == draft.taskID else { throw Failure.invalidTask }
            return turn
        }

        let taskID = draft.taskID
        let task = try self.task(withID: taskID)
        guard !draft.original.cleaned.isEmpty else { throw Failure.invalidReply }
        if draft.originalText != nil && !draft.canConfirm { throw Failure.invalidReply }

        let correction: ActionItem?
        let fields = draft.confirmedFields
        if draft.kind == .correction {
            guard let actionID = draft.correctedActionID, fields.count == 1, let field = fields.first else {
                throw Failure.invalidCorrection
            }
            var targetFetch = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.id == actionID })
            targetFetch.fetchLimit = 1
            guard let item = try context.fetch(targetFetch).first,
                  item.taskID == taskID, item.kind == field.kind else {
                throw Failure.invalidCorrection
            }
            correction = item
        } else {
            guard draft.correctedActionID == nil else { throw Failure.invalidCorrection }
            correction = nil
        }

        let now = Date()
        let turn = ConversationTurn(draft: draft, confirmedAt: now)
        context.insert(turn)
        if let correction, let field = fields.first {
            correction.revise(from: field, sourceTurnID: turn.id)
        } else {
            let actionID = UUID()
            for (index, field) in fields.enumerated() {
                let order = now.addingTimeInterval(Double(index) * 0.000_001)
                context.insert(ActionItem(taskID: taskID, actionID: actionID, sourceTurnID: turn.id,
                                          field: field, createdAt: order))
            }
        }
        task.updatedAt = now
        try save()
        return turn
    }

    func setComplete(_ complete: Bool, for task: CampusTask) throws {
        task.isComplete = complete
        task.updatedAt = .now
        try save()
    }

    func toggleMaterial(_ item: ActionItem, for task: CampusTask) throws {
        guard item.taskID == task.id, item.kind == .material else { throw Failure.invalidTask }
        item.isChecked.toggle()
        task.updatedAt = .now
        try save()
    }

    private func save() throws {
        do {
            try saveChanges()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension TaskStore {
    /// Older saves timestamped each field exactly one microsecond after the previous field.
    /// A correction replaced its source turn but preserved this creation timestamp.
    private static func actionIDs(for items: [ActionItem], turns: [ConversationTurn]) -> [UUID: UUID] {
        var groups = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.actionID ?? $0.id) })
        guard items.contains(where: { $0.actionID == nil }) else { return groups }

        // Both fetches are scoped to the same task. Only uninterrupted, unique creation
        // stamps identify an old action after its individual fields have been corrected.
        let rowsByDate = Dictionary(grouping: items, by: \.createdAt)
        var originByDate: [Date: Date] = [:]
        var ambiguous = Set<Date>()
        for turn in turns where turn.kind == .requirements {
            var index = 0
            var stamp = turn.confirmedAt
            var uniquePrefix = true
            while let rows = rowsByDate[stamp] {
                uniquePrefix = uniquePrefix && rows.count == 1
                if originByDate.updateValue(turn.confirmedAt, forKey: stamp) != nil || !uniquePrefix {
                    ambiguous.insert(stamp)
                }
                index += 1
                stamp = turn.confirmedAt.addingTimeInterval(Double(index) * 0.000_001)
            }
        }

        for row in items where row.actionID == nil {
            guard let origin = originByDate[row.createdAt], !ambiguous.contains(origin),
                  !ambiguous.contains(row.createdAt), let first = rowsByDate[origin]?.first else { continue }
            groups[row.id] = first.actionID ?? first.id
        }
        return groups
    }
}
