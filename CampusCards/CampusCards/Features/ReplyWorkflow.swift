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
        let key = key(taskID: taskID, correctedActionID: correctedActionID)
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(ReplyDraft.self, from: data),
              draft.taskID == taskID, draft.correctedActionID == correctedActionID else { return nil }
        return draft
    }

    func save(_ draft: ReplyDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(taskID: draft.taskID, correctedActionID: draft.correctedActionID))
    }

    func remove(_ draft: ReplyDraft) {
        let id = draft.taskID
        let action = draft.correctedActionID
        guard load(taskID: id, correctedActionID: action)?.id == draft.id else { return }
        defaults.removeObject(forKey: key(taskID: id, correctedActionID: action))
    }

    private func key(taskID: UUID, correctedActionID: UUID?) -> String {
        "pendingReply.\(taskID.uuidString).\(correctedActionID?.uuidString ?? "new")"
    }
}
