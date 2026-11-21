import Foundation
import SwiftData

// Standalone macOS exporter. The translated text is an input fixture.
@main
@MainActor
struct ExportTaskReadback {
    enum ExportError: Error {
        case rejectedTranslation
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(["sameTurnEdit": sameTurnEdit])
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
