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
        let records = try fetchRecords(for: taskID)
        return TaskReadback(task: task, turns: records.turns, items: records.items) {
            records.actionIDs[$0.id] ?? $0.id
        }
    }

    private func fetchRecords(for taskID: UUID) throws -> (
        turns: [ConversationTurn], items: [ActionItem], actionIDs: [UUID: UUID]
    ) {
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
        return (turns, items, Self.actionIDs(for: items, turns: turns))
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
        guard !draft.original.cleaned.isEmpty, !draft.hasPendingEdits else { throw Failure.invalidReply }
        if draft.originalText != nil && !draft.canConfirm { throw Failure.invalidReply }

        let fields = draft.confirmedFields
        let actionID: UUID
        let writes: [FieldWrite]
        if draft.kind == .correction {
            (actionID, writes) = try correctionWrites(for: draft, fields: fields)
        } else {
            guard draft.correctedActionID == nil, draft.targetActionID == nil,
                  fields.allSatisfy({ $0.targetFieldID == nil }) else { throw Failure.invalidCorrection }
            actionID = UUID()
            writes = fields.map { FieldWrite(field: $0, item: nil) }
        }

        let now = Date()
        let turn = ConversationTurn(draft: draft, confirmedAt: now)
        context.insert(turn)
        for (index, write) in writes.enumerated() {
            if let item = write.item {
                item.revise(from: write.field, sourceTurnID: turn.id)
            } else {
                let order = now.addingTimeInterval(Double(index) * 0.000_001)
                context.insert(ActionItem(taskID: taskID, actionID: actionID, sourceTurnID: turn.id,
                                          field: write.field, createdAt: order))
            }
        }
        task.updatedAt = now
        try save()
        return turn
    }

    private struct FieldWrite {
        let field: FieldDraft
        let item: ActionItem?
    }

    private func correctionWrites(for draft: ReplyDraft, fields: [FieldDraft]) throws -> (UUID, [FieldWrite]) {
        guard !fields.isEmpty else { throw Failure.invalidCorrection }
        let records = try fetchRecords(for: draft.taskID)
        let actionID: UUID
        if let rowID = draft.correctedActionID {
            // Row-scoped UI and pre-upgrade drafts must correct exactly the selected row.
            guard fields.count == 1, let group = records.actionIDs[rowID],
                  draft.targetActionID == nil || draft.targetActionID == group,
                  fields[0].targetFieldID == nil || fields[0].targetFieldID == rowID else {
                throw Failure.invalidCorrection
            }
            actionID = group
        } else if let target = draft.targetActionID {
            actionID = target
        } else {
            throw Failure.invalidCorrection
        }

        let members = records.items.filter { records.actionIDs[$0.id] == actionID }
        guard !members.isEmpty else { throw Failure.invalidCorrection }
        var updated = Set<UUID>()
        var added = Set<RequirementKind>()
        let writes = try fields.map { field -> FieldWrite in
            let ofKind = members.filter { $0.kind == field.kind }
            let item: ActionItem?
            if let id = field.targetFieldID ?? draft.correctedActionID {
                guard let selected = ofKind.first(where: { $0.id == id }) else { throw Failure.invalidCorrection }
                item = selected
            } else {
                guard ofKind.count <= 1 else { throw Failure.invalidCorrection }
                item = ofKind.first
            }
            if let item {
                guard updated.insert(item.id).inserted else { throw Failure.invalidCorrection }
            } else {
                guard added.insert(field.kind).inserted else { throw Failure.invalidCorrection }
            }
            return FieldWrite(field: field, item: item)
        }
        return (actionID, writes)
    }

    func setTaskCompleted(taskID: UUID, completed: Bool) throws {
        try setComplete(completed, for: task(withID: taskID))
    }

    func setComplete(_ complete: Bool, for task: CampusTask) throws {
        guard task.isComplete != complete else { return }
        task.isComplete = complete
        task.updatedAt = .now
        try save()
    }

    /// An action ID checks all its fields together. A field ID checks only that field.
    /// Older actions reuse their first field's ID; the action takes precedence here.
    func setItemDone(itemID: UUID, done: Bool) throws {
        let matches = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.id == itemID || $0.actionID == itemID }
        ))
        guard let first = matches.first, matches.allSatisfy({ $0.taskID == first.taskID }) else {
            throw Failure.invalidTask
        }
        let task = try self.task(withID: first.taskID)
        let records = try fetchRecords(for: task.id)
        let group = records.items.filter { records.actionIDs[$0.id] == itemID }
        let selected = group.isEmpty ? matches.filter { $0.id == itemID } : group
        guard !selected.isEmpty else { throw Failure.invalidTask }
        try setChecked(done, for: selected, task: task)
    }

    func toggleMaterial(_ item: ActionItem, for task: CampusTask) throws {
        guard item.taskID == task.id, item.kind == .material else { throw Failure.invalidTask }
        try setChecked(!item.isChecked, for: [item], task: task)
    }

    private func setChecked(_ checked: Bool, for items: [ActionItem], task: CampusTask) throws {
        let changed = items.filter { $0.isChecked != checked }
        guard !changed.isEmpty else { return }
        for item in changed { item.isChecked = checked }
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
