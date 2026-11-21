import SwiftData
import XCTest
@testable import CampusCards

@MainActor
final class TaskStoreTests: XCTestCase {
    func testDuplicateReplyAndCorrectionKeepTheOriginalHistory() throws {
        let container = try makeContainer()
        let store = TaskStore(context: container.mainContext)
        let enrollment = try create(.enrollment, in: store)
        let lost = try create(.lostProperty, in: store)

        var directions = ReplyDraft(taskID: enrollment.id)
        directions.kind = .directions
        directions.original = "去学生服务中心"
        directions.fields[0].text = .init(english: "Student Services", chinese: "学生服务中心")
        let first = try store.confirmReply(directions)
        let duplicate = try store.confirmReply(directions)
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ActionItem>()).isEmpty)

        var reply = ReplyDraft(taskID: enrollment.id)
        reply.original = "周五下午四点前，把护照复印件交到一楼服务台。"
        reply.fields[0].text = .init(english: "Service desk, Level 1", chinese: "一楼服务台")
        reply.fields[1].text = .init(english: "A photocopy of your passport", chinese: "护照复印件")
        reply.fields[2].useExactTime = true
        reply.fields[2].time = .init(weekday: .friday, minuteOfDay: 15 * 60 + 30)
        let replyTurn = try store.confirmReply(reply)
        XCTAssertTrue(replyTurn.original.contains("四点"))

        let items = try container.mainContext.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(items.count, 3)
        let deadline = try XCTUnwrap(items.first { $0.kind == .deadline })
        XCTAssertEqual(deadline.text, .init(english: "By 3:30 p.m. on Friday", chinese: "周五下午三点半前"))

        var crossTask = ReplyDraft(taskID: lost.id, correcting: deadline)
        crossTask.original = "请四点再来。"
        XCTAssertThrowsError(try store.confirmReply(crossTask))

        var correction = ReplyDraft(taskID: enrollment.id, correcting: deadline)
        correction.original = "改到周五下午三点。"
        correction.fields[0].time.minuteOfDay = 15 * 60
        let correctionTurn = try store.confirmReply(correction)
        XCTAssertEqual(deadline.sourceTurnID, correctionTurn.id)
        XCTAssertEqual(deadline.text.english, "By 3:00 p.m. on Friday")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ActionItem>()), 3)
        let turns = try container.mainContext.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(turns.count, 3)
        XCTAssertTrue(turns.allSatisfy { $0.taskID == enrollment.id })
    }

    func testReconfirmingALegacyFieldKeepsItsEditFlagSourceAndChecklistState() throws {
        let container = try makeContainer()
        let store = TaskStore(context: container.mainContext)
        let task = try create(.enrollment, in: store)
        var reply = ReplyDraft(taskID: task.id)
        reply.original = "Bring a passport"
        let material = try XCTUnwrap(reply.fields.firstIndex { $0.kind == .material })
        reply.fields[material].text = .init(english: "Passport", chinese: "")
        let first = try store.confirmReply(reply)
        let item = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ActionItem>()).first)
        item.wasEditedDuringReview = true
        try store.toggleMaterial(item, for: task)

        var unchanged = ReplyDraft(taskID: task.id, correcting: item)
        unchanged.original = "Yes, a passport"
        try store.confirmReply(unchanged)
        let saved = try XCTUnwrap(store.loadTask(task.id).actions.first?.fields.first)
        XCTAssertEqual(saved.sourceTurnID, first.id)
        XCTAssertTrue(saved.isChecked)
        XCTAssertTrue(saved.userEdited)

        var changed = ReplyDraft(taskID: task.id, correcting: item)
        changed.original = "Bring a passport copy"
        var replacement = changed.fields[0]
        replacement.edit("Passport copy", in: .english)
        changed.applyReviewedField(replacement)
        let latest = try store.confirmReply(changed)
        let revised = try XCTUnwrap(store.loadTask(task.id).actions.first?.fields.first)
        XCTAssertEqual(revised.id, saved.id)
        XCTAssertEqual(revised.sourceTurnID, latest.id)
        XCTAssertFalse(revised.isChecked)
        XCTAssertFalse(revised.userEdited)
    }

    func testDeadlineFormatChangesSurviveReopenAndRevertingRestoresTheOriginalFlag() throws {
        let exact = ConfirmedTime(weekday: .friday, minuteOfDay: 960)
        for startsExact in [true, false] {
            var draft = ReplyDraft(taskID: UUID())
            let index = try XCTUnwrap(draft.fields.firstIndex { $0.kind == .deadline })
            var original = draft.fields[index]
            if startsExact { original.confirmExactTime(exact) }
            else { original.edit("After class", in: .english) }
            draft.applyReviewedField(original)
            XCTAssertFalse(draft.fields[index].userEdited)

            var changed = draft.fields[index]
            if startsExact {
                changed.useExactTime = false
                changed.edit("After class", in: .english)
                changed.rememberReviewedText(in: .english)
            } else {
                changed.confirmExactTime(exact)
            }
            draft.applyReviewedField(changed)
            draft = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(draft))
            XCTAssertTrue(draft.fields[index].userEdited)
            var overridden = draft.fields[index]
            overridden.userEdited = false
            XCTAssertFalse(overridden.userEdited)

            var reverted = draft.fields[index]
            if startsExact { reverted.confirmExactTime(exact) }
            else { reverted.useExactTime = false }
            draft.applyReviewedField(reverted)
            XCTAssertFalse(draft.fields[index].userEdited)
        }
    }

    func testDeadlineFormatChangeAfterOpeningAnOlderCachedDraft() throws {
        let exact = ConfirmedTime(weekday: .friday, minuteOfDay: 960)
        var original = FieldDraft(kind: .deadline)
        original.useExactTime = true
        original.time = exact
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for hasBothLegacyBaselines in [false, true] {
            var stored = json
            if hasBothLegacyBaselines {
                stored["reviewTimeBaseline"] = stored["time"]
                stored["reviewTextBaseline"] = ["english": "After class", "chinese": ""]
            }
            var draft = ReplyDraft(taskID: UUID())
            let index = try XCTUnwrap(draft.fields.firstIndex { $0.kind == .deadline })
            draft.fields[index] = try JSONDecoder().decode(FieldDraft.self, from: JSONSerialization.data(withJSONObject: stored))
            var text = draft.fields[index]
            text.useExactTime = false
            text.edit("After class", in: .english)
            draft.applyReviewedField(text)
            XCTAssertTrue(draft.fields[index].userEdited)
            var reverted = draft.fields[index]
            reverted.confirmExactTime(exact)
            draft.applyReviewedField(reverted)
            XCTAssertFalse(draft.fields[index].userEdited)
        }
    }

    func testFirstCorrectionCanReplaceAnExactDeadlineWithTextWithoutAnEditFlag() {
        let exact = ConfirmedTime(weekday: .friday, minuteOfDay: 960)
        var older = FieldDraft(kind: .deadline)
        older.useExactTime = true
        older.time = exact
        var correction = ReplyDraft(taskID: UUID(), correctingActionID: UUID(), changes: [older])
        var unchanged = correction.fields[0]
        unchanged.confirmExactTime(exact)
        correction.applyReviewedField(unchanged)

        var replacement = correction.fields[0]
        replacement.useExactTime = false
        replacement.edit("After class", in: .english)
        correction.applyReviewedField(replacement)
        XCTAssertFalse(correction.fields[0].userEdited)
        var rechecked = correction.fields[0]
        rechecked.confirmExactTime(exact)
        correction.applyReviewedField(rechecked)
        XCTAssertTrue(correction.fields[0].userEdited)
    }

    func testDiskRoundTripRetainsTwoTasksAndMaterialProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("CampusCards.store"))
        try writeDiskFixtures(configuration)

        let container = try makeContainer(configuration)
        let context = container.mainContext
        let tasks = try context.fetch(FetchDescriptor<CampusTask>())
        XCTAssertEqual(tasks.count, 2)
        let lost = try XCTUnwrap(tasks.first { $0.scenario == .lostProperty })
        let enrollment = try XCTUnwrap(tasks.first { $0.scenario == .enrollment })
        XCTAssertTrue(lost.isComplete)
        XCTAssertFalse(enrollment.isComplete)
        let items = try context.fetch(FetchDescriptor<ActionItem>())
        let lostMaterial = try XCTUnwrap(items.first { $0.taskID == lost.id && $0.kind == .material })
        XCTAssertTrue(lostMaterial.isChecked)
        XCTAssertEqual(lostMaterial.text.english, "Student ID")
        let enrollmentTime = try XCTUnwrap(items.first { $0.taskID == enrollment.id && $0.kind == .deadline })
        XCTAssertEqual(enrollmentTime.time?.minuteOfDay, 930)
        let turns = try context.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(turns.filter { $0.taskID == lost.id }.count, 2)
        XCTAssertEqual(turns.first { $0.taskID == enrollment.id }?.original, "周五下午四点前。")
        try TaskStore(context: context).setComplete(false, for: lost)
        XCTAssertFalse(lost.isComplete)
        XCTAssertTrue(lostMaterial.isChecked)
    }

    func testPendingEditorsCannotFinalizeAnUnreviewedDraft() throws {
        let container = try makeContainer()
        let store = TaskStore(context: container.mainContext)
        let task = try create(.enrollment, in: store)
        var draft = ReplyDraft(taskID: task.id)
        draft.original = "Bring your passport"
        draft.pendingManualTranslation = "请带护照"
        XCTAssertThrowsError(try store.confirmReply(draft))

        draft.pendingManualTranslation = nil
        draft.pendingField = FieldDraft(kind: .material)
        XCTAssertThrowsError(try store.confirmReply(draft))
        XCTAssertTrue(try store.loadTask(task.id).turns.isEmpty)
    }

    func testEditingOneLanguageDoesNotSaveAnOutdatedTranslation() {
        var field = FieldDraft(kind: .material)
        field.text = .init(english: "Passport", chinese: "护照")
        field.edit("A photocopy of your passport", in: .english)
        XCTAssertEqual(field.pendingReview, .chinese)
        XCTAssertTrue(field.effectiveText.chinese.isEmpty)
        field.edit("护照复印件", in: .chinese)
        XCTAssertNil(field.pendingReview)
        XCTAssertEqual(field.effectiveText.chinese, "护照复印件")
        field.edit("", in: .english)
        XCTAssertEqual(field.effectiveText.chinese, "护照复印件")
    }

    private func makeContainer(
        _ configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
    ) throws -> ModelContainer {
        let schema = Schema([CampusTask.self, ConversationTurn.self, ActionItem.self])
        let container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }

    private func create(_ scenario: TaskScenario, in store: TaskStore) throws -> CampusTask {
        let fields = RequirementKind.allCases.filter(scenario.defaultFields.contains)
        return try store.createTask(scenario: scenario, title: scenario.title, question: scenario.question(asking: fields), fields: fields)
    }

    private func writeDiskFixtures(_ configuration: ModelConfiguration) throws {
        let container = try makeContainer(configuration)
        let store = TaskStore(context: container.mainContext)
        let enrollment = try create(.enrollment, in: store)
        let lost = try create(.lostProperty, in: store)
        var enrollmentReply = ReplyDraft(taskID: enrollment.id)
        enrollmentReply.original = "周五下午四点前。"
        enrollmentReply.fields[2].useExactTime = true
        enrollmentReply.fields[2].time = .init(weekday: .friday, minuteOfDay: 930)
        try store.confirmReply(enrollmentReply)

        var pickupReply = ReplyDraft(taskID: lost.id)
        pickupReply.original = "到图书馆前台。"
        pickupReply.fields[0].text = .init(english: "Library reception", chinese: "图书馆前台")
        try store.confirmReply(pickupReply)
        var followUp = ReplyDraft(taskID: lost.id)
        followUp.original = "请带学生证。"
        followUp.fields[1].text = .init(english: "Student ID", chinese: "学生证")
        try store.confirmReply(followUp)
        let items = try container.mainContext.fetch(FetchDescriptor<ActionItem>())
        let material = try XCTUnwrap(items.first { $0.taskID == lost.id && $0.kind == .material })
        try store.toggleMaterial(material, for: lost)
        try store.setComplete(true, for: lost)
    }
}
