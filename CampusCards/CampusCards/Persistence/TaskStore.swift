import Foundation
import SwiftData

@MainActor
struct TaskStore {
    let context: ModelContext

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
        var taskFetch = FetchDescriptor<CampusTask>(predicate: #Predicate { $0.id == taskID })
        taskFetch.fetchLimit = 1
        guard let task = try context.fetch(taskFetch).first else { throw Failure.invalidTask }
        guard !draft.original.cleaned.isEmpty else { throw Failure.invalidReply }

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
            for (index, field) in fields.enumerated() {
                let order = now.addingTimeInterval(Double(index) * 0.000_001)
                context.insert(ActionItem(taskID: taskID, sourceTurnID: turn.id, field: field, createdAt: order))
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
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
