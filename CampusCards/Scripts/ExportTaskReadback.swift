import Foundation
import SwiftData

// Standalone macOS exporter. The translated text is an input fixture.
@main
@MainActor
struct ExportTaskReadback {
    enum ExportError: Error {
        case rejectedTranslation, missingDeadline, rejectedRecording
    }

    struct Export: Encodable {
        let sameTurnEdit: TaskReadback
        let beforeCorrection: TaskReadback
        let twoTurnCorrection: TaskReadback
        let afterRetry: TaskReadback
        let inputNote = "示例使用预设译文。第二轮使用模拟转写和录音相对路径，未生成音频文件。"
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("CampusCards.store")

        let sameTurnID = try saveFirstTask(
            at: url, title: "补交材料（同轮手改）", editDeadline: true
        )
        let sameTurnEdit = try readTask(sameTurnID, at: url)
        let correctedID = try saveFirstTask(at: url, title: "补交材料", editDeadline: false)
        let beforeCorrection = try readTask(correctedID, at: url)
        try correctDeadline(for: correctedID, at: url)
        let twoTurnCorrection = try readTask(correctedID, at: url)
        try addStudentID(for: correctedID, at: url)
        let afterRetry = try readTask(correctedID, at: url)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Export(
            sameTurnEdit: sameTurnEdit, beforeCorrection: beforeCorrection,
            twoTurnCorrection: twoTurnCorrection, afterRetry: afterRetry
        ))
        print(String(decoding: data, as: UTF8.self))
    }

    static func container(at url: URL) throws -> ModelContainer {
        let schema = Schema([CampusTask.self, ConversationTurn.self, ActionItem.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
    }

    static func readTask(_ id: UUID, at url: URL) throws -> TaskReadback {
        let reopened = try container(at: url)
        return try TaskStore(context: reopened.mainContext).loadTask(id)
    }

    static func applyTranslation(_ translation: String, to draft: inout ReplyDraft) throws {
        guard let token = draft.beginTranslation(),
              draft.receiveTranslation(translation, for: token) else {
            throw ExportError.rejectedTranslation
        }
    }

    static func correctDeadline(for taskID: UUID, at url: URL) throws {
        let database = try container(at: url)
        let store = TaskStore(context: database.mainContext)
        let snapshot = try store.loadTask(taskID)
        guard let action = snapshot.actions.first,
              let deadline = action.fields.first(where: { $0.field == .deadline }),
              var time = deadline.time else {
            throw ExportError.missingDeadline
        }
        time.minuteOfDay = 15 * 60 + 30
        var change = FieldDraft(kind: .deadline)
        change.targetFieldID = deadline.id
        change.confirmExactTime(time)
        var draft = ReplyDraft(taskID: taskID, correctingActionID: action.id, changes: [change])
        let token = draft.beginRecognition(in: .chinese)
        let path = "Recordings/ECF93A77-1A58-47F6-893D-994AA7A00B28.wav"
        guard draft.attachRecording(path, for: token),
              draft.receiveRecognition(
                text: "改到下午三点半，地点不变", language: .chinese, recordingRef: path, for: token
              ) else { throw ExportError.rejectedRecording }
        try applyTranslation("Change the time to 3:30 p.m. The location stays the same.", to: &draft)
        try store.confirmReply(draft)
        try store.confirmReply(draft)
    }

    static func addStudentID(for taskID: UUID, at url: URL) throws {
        let database = try container(at: url)
        let store = TaskStore(context: database.mainContext)
        var draft = ReplyDraft(taskID: taskID)
        draft.original = "还要带学生证"
        try applyTranslation("Also bring your student ID.", to: &draft)
        var material = FieldDraft(kind: .material)
        material.text = .init(english: "Student ID", chinese: "学生证")
        draft.fields = [material]
        try store.confirmReply(draft)
        try store.confirmReply(draft)
    }

    static func saveFirstTask(at url: URL, title: String, editDeadline: Bool) throws -> UUID {
        let database = try container(at: url)
        let store = TaskStore(context: database.mainContext)
        let task = try store.createTask(
            scenario: .custom, title: .init(chinese: title),
            question: .init(chinese: "护照复印件该何时交到哪里？"), fields: [.location, .material, .deadline]
        )
        var draft = ReplyDraft(taskID: task.id)
        draft.original = "周五四点前，把护照复印件交到一楼服务台"
        try applyTranslation(
            "Submit a photocopy of your passport to the service desk on the first floor by 4 p.m. on Friday.",
            to: &draft
        )
        var location = FieldDraft(kind: .location)
        location.text = .init(english: "First-floor service desk", chinese: "一楼服务台")
        var material = FieldDraft(kind: .material)
        material.text = .init(english: "Passport photocopy", chinese: "护照复印件")
        var deadline = FieldDraft(kind: .deadline)
        var time = ConfirmedTime(weekday: .friday, minuteOfDay: 16 * 60)
        deadline.confirmExactTime(time)
        if editDeadline {
            time.minuteOfDay = 15 * 60 + 30
            deadline.confirmExactTime(time)
        }
        draft.fields = [location, material, deadline]
        try store.confirmReply(draft)
        return task.id
    }
}
