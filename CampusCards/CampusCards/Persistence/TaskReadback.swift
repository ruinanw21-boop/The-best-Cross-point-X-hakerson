import Foundation

struct TaskReadback: Codable {
    struct TaskInfo: Codable, Identifiable {
        let id: UUID
        let scenarioCode: String
        let title: BilingualText
        let question: BilingualText
        let requestedFields: [RequirementKind]
        let isComplete: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct Turn: Codable, Identifiable {
        enum InputMode: String, Codable { case typed, voice }

        let id: UUID
        let taskID: UUID
        let kind: ReplyKind
        let inputMode: InputMode
        let originalLanguage: CardLanguage
        let originalText: String?
        let confirmedText: String
        let translation: String
        let speaker: String
        let recordingRef: String?
        let confirmedAt: Date
    }

    struct Action: Codable, Identifiable {
        let id: UUID
        let taskID: UUID
        let title: BilingualText
        let fields: [Field]
    }

    struct Field: Codable, Identifiable {
        let id: UUID
        let field: RequirementKind
        let value: BilingualText
        let time: ConfirmedTime?
        let isChecked: Bool
        let sourceTurnID: UUID
        let userEdited: Bool
    }

    let task: TaskInfo
    let turns: [Turn]
    let actions: [Action]

    // TaskStore supplies turns and field rows in chronological order.
    init(
        task: CampusTask, turns: [ConversationTurn], items: [ActionItem],
        actionIDForItem: (ActionItem) -> UUID
    ) {
        self.task = TaskInfo(
            id: task.id, scenarioCode: task.scenarioCode, title: task.title, question: task.question,
            requestedFields: task.fields, isComplete: task.isComplete,
            createdAt: task.createdAt, updatedAt: task.updatedAt
        )
        self.turns = turns.map { turn in
            Turn(
                id: turn.id, taskID: turn.taskID, kind: turn.kind,
                inputMode: turn.recordingRef == nil ? .typed : .voice,
                originalLanguage: turn.originalLanguage, originalText: turn.originalText,
                confirmedText: turn.original, translation: turn.translation, speaker: turn.speaker,
                recordingRef: turn.recordingRef, confirmedAt: turn.confirmedAt
            )
        }

        var groups: [(id: UUID, fields: [Field])] = []
        var indices: [UUID: Int] = [:]
        for item in items {
            let actionID = actionIDForItem(item)
            let field = Field(
                id: item.id, field: item.kind, value: item.text, time: item.time,
                isChecked: item.isChecked, sourceTurnID: item.sourceTurnID, userEdited: item.userEdited
            )
            if let index = indices[actionID] {
                groups[index].fields.append(field)
            } else {
                indices[actionID] = groups.count
                groups.append((actionID, [field]))
            }
        }
        self.actions = groups.map { group in
            let title = group.fields.first { $0.field == .material }?.value ?? task.title
            return Action(id: group.id, taskID: task.id, title: title, fields: group.fields)
        }
    }

    func source(for field: Field) -> Turn? {
        turns.first { $0.id == field.sourceTurnID }
    }
}
