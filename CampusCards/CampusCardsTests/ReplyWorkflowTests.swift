import Foundation
import XCTest
#if canImport(SwiftData)
import SwiftData
#endif
@testable import CampusCards

final class ReplyWorkflowTests: XCTestCase {
    func testOnlyServiceTranslationMakesCurrentSourceEditableAndConfirmable() throws {
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "周五 16:00 前"
        draft.editTranslation("An unverified translation")
        XCTAssertTrue(draft.translation.isEmpty)
        XCTAssertFalse(draft.canConfirm)
        let request = try XCTUnwrap(draft.beginTranslation())
        draft.receiveTranslation("By Friday at 16:00", for: request)
        draft.editTranslation("")
        XCTAssertFalse(draft.canConfirm)
        draft.editTranslation("By 4 p.m. on Friday")
        XCTAssertTrue(draft.canConfirm)

        let encoded = try JSONEncoder().encode(draft)
        let restored = try JSONDecoder().decode(ReplyDraft.self, from: encoded)
        XCTAssertTrue(restored.hasTranslatedCurrentSource)
        XCTAssertTrue(restored.canConfirm)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "receivedTranslation")
        let legacy = try JSONDecoder().decode(ReplyDraft.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.id, draft.id)
        XCTAssertEqual(legacy.original, draft.original)
        XCTAssertFalse(legacy.hasTranslatedCurrentSource)
        XCTAssertFalse(legacy.canConfirm)

        draft.original = "周五 15:30 前"
        draft.editTranslation("By 4 p.m. on Friday")
        XCTAssertTrue(draft.translation.isEmpty)
        XCTAssertFalse(draft.hasTranslatedCurrentSource)
        let second = try XCTUnwrap(draft.beginTranslation())
        draft.receiveTranslation("By 3:30 p.m.", for: second)
        draft.language = .english
        draft.editTranslation("不能在更改方向之后沿用上一个译文")
        XCTAssertTrue(draft.translation.isEmpty)
        XCTAssertFalse(draft.canConfirm)
    }

    func testManualTranslationRequiresExplicitReviewAndSurvivesReopening() throws {
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "周五 16:00 前"
        XCTAssertFalse(draft.acceptManualTranslation("   "))
        XCTAssertFalse(draft.canConfirm)
        let pending = try XCTUnwrap(draft.beginTranslation())

        XCTAssertTrue(draft.acceptManualTranslation("By 4 p.m. on Friday"))
        XCTAssertFalse(draft.hasTranslatedCurrentSource)
        XCTAssertTrue(draft.canConfirm)
        XCTAssertFalse(draft.receiveTranslation("Late result", for: pending))
        XCTAssertFalse(draft.failTranslation(.timeout, for: pending))
        XCTAssertEqual(draft.translation, "By 4 p.m. on Friday")
        XCTAssertEqual(draft.originalText, "周五 16:00 前")

        var restored = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertTrue(restored.canConfirm)
        XCTAssertFalse(restored.hasTranslatedCurrentSource)
        restored.original = "周五 15:30 前"
        XCTAssertFalse(restored.canConfirm)
        XCTAssertTrue(restored.translation.isEmpty)
        XCTAssertTrue(restored.acceptManualTranslation("By 3:30 p.m. on Friday"))
        restored.language = .english
        XCTAssertFalse(restored.hasReviewedTranslation)
        XCTAssertFalse(restored.canConfirm)
    }

    func testSavingAFieldSheetTracksEditsAcrossReopens() throws {
        var draft = ReplyDraft(taskID: UUID())
        var material = FieldDraft(kind: .material)
        material.edit("Passport", in: .english)
        draft.applyReviewedField(material)
        XCTAssertFalse(try XCTUnwrap(draft.fields.last).userEdited)

        var cached = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(draft))
        var reopened = try XCTUnwrap(cached.fields.last)
        XCTAssertEqual(reopened.id, material.id)
        reopened.edit("Passport copy", in: .english)
        cached.applyReviewedField(reopened)
        XCTAssertTrue(try XCTUnwrap(cached.fields.last).userEdited)

        var original = FieldDraft(kind: .material)
        original.edit("Old requirement", in: .english)
        var correction = ReplyDraft(taskID: UUID(), correctingActionID: UUID(), changes: [original])
        correction.applyReviewedField(original)
        var replacement = correction.fields[0]
        replacement.edit("New requirement", in: .english)
        correction.applyReviewedField(replacement)
        XCTAssertFalse(correction.fields[0].userEdited)
        replacement = correction.fields[0]
        replacement.edit("Reviewed replacement", in: .english)
        correction.applyReviewedField(replacement)
        XCTAssertTrue(correction.fields[0].userEdited)
    }

    func testExplicitReviewChoiceOverridesAnOlderCachedEditedFlag() throws {
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            FieldDraft(kind: .material)
        )) as? [String: Any])
        legacy["wasEditedDuringReview"] = true
        var field = try JSONDecoder().decode(FieldDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(field.userEdited)
        field.userEdited = false
        XCTAssertFalse(try JSONDecoder().decode(FieldDraft.self, from: JSONEncoder().encode(field)).userEdited)
    }

    func testLateSuccessAndErrorCannotReplaceEditedSourceOrTranslation() throws {
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "周五 16:00 前"
        draft.captureOriginal()
        let first = try XCTUnwrap(draft.beginTranslation())
        draft.original = "周五 15:30 前"
        let second = try XCTUnwrap(draft.beginTranslation())
        XCTAssertNotEqual(first.version, second.version)
        XCTAssertTrue(draft.receiveTranslation("Before 3:30 on Friday", for: second))
        draft.editTranslation("By 3:30 p.m. on Friday")
        XCTAssertFalse(draft.receiveTranslation("By 4 on Friday", for: first))
        XCTAssertFalse(draft.failTranslation(.timeout, for: first))
        XCTAssertNil(draft.translationError)
        XCTAssertEqual(draft.originalText, "周五 16:00 前")
        XCTAssertEqual(draft.original, "周五 15:30 前")
        XCTAssertEqual(draft.translation, "By 3:30 p.m. on Friday")
        XCTAssertTrue(draft.canConfirm)

        let retry = try XCTUnwrap(draft.beginTranslation())
        draft.editTranslation("Please arrive by 3:30 p.m. on Friday.")
        XCTAssertFalse(draft.receiveTranslation("By 4", for: retry))
        draft.original = "周五 16:00 前"
        XCTAssertFalse(draft.canConfirm)
        XCTAssertEqual(draft.translation, "")
        XCTAssertFalse(draft.receiveTranslation("By 4", for: first))
    }

    func testLeavingDraftChangingLanguageAndSwitchingTaskRejectResponses() throws {
        var first = ReplyDraft(taskID: UUID())
        first.original = "Which desk should I go to?"
        first.language = .english
        let request = try XCTUnwrap(first.beginTranslation())
        var next = ReplyDraft(taskID: first.taskID)
        next.original = "同一个事项的新草稿"
        _ = next.beginTranslation()
        XCTAssertFalse(next.receiveTranslation("迟到", for: request))
        var otherTask = ReplyDraft(taskID: UUID())
        otherTask.original = "不同事项"
        _ = otherTask.beginTranslation()
        XCTAssertFalse(otherTask.failTranslation(.offline, for: request))
        first.invalidateRequests()
        XCTAssertFalse(first.receiveTranslation("迟到", for: request))
        let afterReturn = try XCTUnwrap(first.beginTranslation())
        first.language = .chinese
        first.language = .english
        XCTAssertFalse(first.failTranslation(.timeout, for: afterReturn))
        XCTAssertNil(first.translationError)
        XCTAssertFalse(first.canConfirm)
    }

    func testRecordingUsesTheSameDraftAndNeverOverwritesKeyboardEdits() throws {
        var draft = ReplyDraft(taskID: UUID())
        let first = draft.beginRecognition()
        draft.original = "我正在自己修改原文"
        XCTAssertFalse(draft.receiveRecognition(
            text: "旧识别", language: .chinese, recordingRef: "Recordings/old.m4a", for: first
        ))
        XCTAssertFalse(draft.failRecognition(for: first))
        XCTAssertEqual(draft.original, "我正在自己修改原文")
        XCTAssertNil(draft.recordingRef)
        let second = draft.beginRecognition()
        let spoken = "请把护照复印件交到一楼服务台"
        XCTAssertTrue(draft.receiveRecognition(
            text: spoken, language: .chinese, recordingRef: "Recordings/passport.m4a", for: second
        ))
        draft.original += "。"
        let request = try XCTUnwrap(draft.beginTranslation())
        XCTAssertTrue(draft.receiveTranslation("Take a copy of your passport to the desk on the first floor.", for: request))
        XCTAssertEqual(draft.originalText, spoken)
        XCTAssertEqual(draft.recordingRef, "Recordings/passport.m4a")
        XCTAssertTrue(draft.canConfirm)
        XCTAssertFalse(draft.isRecognizing)
    }

    func testReleasedRecordingSurvivesEditsAndReopenWhileRecognitionIsPending() throws {
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "已有的文字"
        let token = draft.beginRecognition(in: .english)
        let reference = "Recordings/first.wav"
        XCTAssertTrue(draft.attachRecording(reference, for: token))
        XCTAssertEqual(draft.language, .chinese)
        XCTAssertEqual(draft.original, "已有的文字")
        draft.original = "Which desk should I go to?"
        XCTAssertEqual(draft.language, .english)
        XCTAssertFalse(draft.receiveRecognition(text: "stale", language: .english, recordingRef: reference, for: token))
        let restored = try JSONDecoder().decode(ReplyDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.recordingRef, reference)
        XCTAssertEqual(restored.original, "Which desk should I go to?")
        XCTAssertFalse(restored.isRecognizing)
    }

    func testFailedInferenceAndBackPreserveExistingTypedLanguage() {
        for leaveReview in [true, false] {
            var draft = ReplyDraft(taskID: UUID())
            draft.original = "请到一楼服务台"
            let press = draft.beginRecognition(in: .english)
            XCTAssertTrue(draft.attachRecording("Recordings/english.wav", for: press))
            if leaveReview { draft.invalidateRequests() }
            else { XCTAssertTrue(draft.failRecognition(for: press)) }
            XCTAssertEqual(draft.original, "请到一楼服务台")
            XCTAssertEqual(draft.language, .chinese)
            XCTAssertEqual(draft.recordingRef, "Recordings/english.wav")
        }
        var empty = ReplyDraft(taskID: UUID())
        let press = empty.beginRecognition(in: .english)
        XCTAssertTrue(empty.attachRecording("Recordings/english.wav", for: press))
        XCTAssertEqual(empty.language, .english)
        XCTAssertTrue(empty.canReview)
    }

    func testSwitchingDraftOrTaskRejectsLateRecordingAndTranscript() {
        var first = ReplyDraft(taskID: UUID())
        let old = first.beginRecognition(in: .chinese)
        for taskID in [first.taskID, UUID()] {
            var next = ReplyDraft(taskID: taskID)
            _ = next.beginRecognition(in: .chinese)
            XCTAssertFalse(next.attachRecording("Recordings/old.wav", for: old))
            XCTAssertFalse(next.receiveRecognition(
                text: "请到一楼服务台", language: .chinese, recordingRef: "Recordings/old.wav", for: old
            ))
            XCTAssertTrue(next.isRecognizing)
            XCTAssertNil(next.recordingRef)
            XCTAssertEqual(next.original, "")
        }
    }

    func testUnsuccessfulPressKeepsTypedLanguageAndExistingTranslation() throws {
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "请到一楼服务台"
        let translation = try XCTUnwrap(draft.beginTranslation())
        draft.receiveTranslation("Go to the first-floor service desk.", for: translation)
        let press = draft.beginRecognition(in: .english)
        XCTAssertTrue(draft.failRecognition(for: press))
        XCTAssertEqual(draft.language, .chinese)
        XCTAssertEqual(draft.original, "请到一楼服务台")
        XCTAssertNil(draft.recordingRef)
        XCTAssertTrue(draft.canConfirm)
    }

    func testOfflineAndTimeoutDraftsRestoreAndRetryWithCurrentText() throws {
        let suite = "ReplyWorkflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = ReplyDraftCache(defaults: defaults)
        var draft = ReplyDraft(taskID: UUID())
        draft.language = .english
        draft.original = "Which desk should I go to?"
        let first = try XCTUnwrap(draft.beginTranslation())
        XCTAssertTrue(draft.failTranslation(.offline, for: first))
        XCTAssertEqual(draft.translationError, .offline)
        draft.original = "Which desk is open?"
        draft.fields[0].text = .init(english: "Library", chinese: "图书馆")
        let second = try XCTUnwrap(draft.beginTranslation())
        XCTAssertTrue(draft.failTranslation(.timeout, for: second))
        XCTAssertEqual(draft.translationError, .timeout)
        XCTAssertFalse(draft.canConfirm)
        cache.save(draft)
        let reopened = ReplyDraftCache(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        var restored = try XCTUnwrap(reopened.load(taskID: draft.taskID, correctedActionID: nil))
        XCTAssertEqual(restored.id, draft.id)
        XCTAssertEqual(restored.originalText, "Which desk should I go to?")
        XCTAssertEqual(restored.original, "Which desk is open?")
        XCTAssertEqual(restored.fields, draft.fields)
        XCTAssertNil(restored.recordingRef)
        let third = try XCTUnwrap(restored.beginTranslation())
        cache.save(restored)
        XCTAssertFalse(try XCTUnwrap(cache.load(taskID: draft.taskID, correctedActionID: nil)).isTranslating)
        XCTAssertTrue(restored.receiveTranslation("哪个柜台开放？", for: third))
        XCTAssertTrue(restored.canConfirm)
        cache.remove(restored)
        XCTAssertNil(cache.load(taskID: draft.taskID, correctedActionID: nil))
    }

    #if canImport(SwiftData)
    @MainActor
    func testNewestDeadlineWinsInFormalHistory() throws {
        let schema = Schema([CampusTask.self, ConversationTurn.self, ActionItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let store = TaskStore(context: container.mainContext)
        let task = try store.createTask(
            scenario: .enrollment, title: TaskScenario.enrollment.title,
            question: TaskScenario.enrollment.question(asking: [.deadline]), fields: [.deadline]
        )
        var draft = ReplyDraft(taskID: task.id)
        draft.original = "周五 16:00 前"
        let first = try XCTUnwrap(draft.beginTranslation())
        draft.original = "周五 15:30 前"
        let second = try XCTUnwrap(draft.beginTranslation())
        draft.receiveTranslation("By 15:30 Friday", for: second)
        draft.receiveTranslation("By 16:00 Friday", for: first)
        let field = try XCTUnwrap(draft.fields.firstIndex { $0.kind == .deadline })
        draft.fields[field].useExactTime = true
        draft.fields[field].time = .init(weekday: .friday, minuteOfDay: 930)
        XCTAssertTrue(draft.canConfirm)
        try store.confirmReply(draft)
        let turns = try container.mainContext.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(turns.map(\.original), ["周五 15:30 前"])
        XCTAssertEqual(turns.map(\.translation), ["By 15:30 Friday"])
        let items = try container.mainContext.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(items.compactMap { $0.time?.minuteOfDay }, [930])
    }

    @MainActor
    func testOnlyConfirmationPersistsBothDirectionsAndFailedSaveRollsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Review.store"))
        let schema = Schema([CampusTask.self, ConversationTurn.self, ActionItem.self])
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            context.autosaveEnabled = false
            let store = TaskStore(context: context)
            let task = try store.createTask(
                scenario: .enrollment, title: TaskScenario.enrollment.title,
                question: TaskScenario.enrollment.question(asking: [.location]), fields: [.location]
            )
            var typed = ReplyDraft(taskID: task.id)
            typed.kind = .directions
            typed.language = .english
            typed.original = "Which desk should I go to?"
            let english = try XCTUnwrap(typed.beginTranslation())
            XCTAssertThrowsError(try store.confirmReply(typed))
            typed.receiveTranslation("应该去哪个柜台？", for: english)
            typed.editTranslation("我应该去哪个服务台？")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationTurn>()), 0)
            let typedTurn = try store.confirmReply(typed)
            XCTAssertNil(typedTurn.recordingRef)
            XCTAssertEqual(typedTurn.originalText, typed.original)

            var spoken = ReplyDraft(taskID: task.id)
            let recognition = spoken.beginRecognition()
            let raw = "请把护照复印件交到一楼服务台"
            spoken.receiveRecognition(
                text: raw, language: .chinese, recordingRef: "Recordings/test.m4a", for: recognition
            )
            spoken.original += "。"
            let chinese = try XCTUnwrap(spoken.beginTranslation())
            spoken.receiveTranslation("Bring a copy of your passport to the first-floor desk.", for: chinese)
            spoken.editTranslation("Please bring a passport copy to the first-floor desk.")
            spoken.fields[0].text = .init(english: "First-floor desk", chinese: "一楼服务台")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationTurn>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActionItem>()), 0)
            let failing = TaskStore(context: context, saveChanges: { throw CocoaError(.fileWriteOutOfSpace) })
            XCTAssertThrowsError(try failing.confirmReply(spoken))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationTurn>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActionItem>()), 0)
            XCTAssertEqual(try store.confirmReply(spoken).id, spoken.id)
            XCTAssertEqual(try store.confirmReply(spoken).id, spoken.id)
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let turns = try reopened.mainContext.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(turns.count, 2)
        let typed = try XCTUnwrap(turns.first { $0.originalLanguage == .english })
        XCTAssertEqual(typed.translation, "我应该去哪个服务台？")
        let spoken = try XCTUnwrap(turns.first { $0.originalLanguage == .chinese })
        XCTAssertEqual(spoken.originalText, "请把护照复印件交到一楼服务台")
        XCTAssertEqual(spoken.original, "请把护照复印件交到一楼服务台。")
        XCTAssertEqual(spoken.translation, "Please bring a passport copy to the first-floor desk.")
        XCTAssertEqual(spoken.recordingRef, "Recordings/test.m4a")
        let actions = try reopened.mainContext.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.sourceTurnID, spoken.id)
    }
    #endif
}
