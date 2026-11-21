import Foundation

struct ReplyRequestToken: Equatable {
    let taskID: UUID
    let draftID: UUID
    let version: Int
}

// One unfinished reply per task and correction target. Encoding omits active requests.
struct ReplyDraftCache {
    var defaults: UserDefaults = .standard

    func load(taskID: UUID, correctedActionID: UUID?) -> ReplyDraft? {
        load(taskID: taskID, rowID: correctedActionID, actionID: nil)
    }

    func load(for draft: ReplyDraft) -> ReplyDraft? {
        load(taskID: draft.taskID, rowID: draft.correctedActionID, actionID: draft.targetActionID)
    }

    private func load(taskID: UUID, rowID: UUID?, actionID: UUID?) -> ReplyDraft? {
        let key = key(taskID: taskID, rowID: rowID, actionID: actionID)
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(ReplyDraft.self, from: data),
              draft.taskID == taskID, draft.correctedActionID == rowID,
              rowID != nil || draft.targetActionID == actionID else { return nil }
        return draft
    }

    func save(_ draft: ReplyDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(taskID: draft.taskID, rowID: draft.correctedActionID,
                                       actionID: draft.targetActionID))
    }

    func remove(_ draft: ReplyDraft) {
        guard load(for: draft)?.id == draft.id else { return }
        defaults.removeObject(forKey: key(taskID: draft.taskID, rowID: draft.correctedActionID,
                                          actionID: draft.targetActionID))
    }

    private func key(taskID: UUID, rowID: UUID?, actionID: UUID?) -> String {
        // Preserve every old row key. A legacy action ID can equal its first row's ID.
        let slot = rowID?.uuidString ?? actionID.map { "action.\($0.uuidString)" } ?? "new"
        return "pendingReply.\(taskID.uuidString).\(slot)"
    }
}
