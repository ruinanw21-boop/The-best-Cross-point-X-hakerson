import AVFAudio
import SwiftData
import XCTest
@testable import CampusCards

final class ReplyAudioTests: XCTestCase {
    @MainActor
    func testTwoRoundsCanBeDecodedIndependentlyAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ReplyRecordingFiles(root: directory)
        let first = try files.newReference()
        let second = try files.newReference()
        XCTAssertNotEqual(first, second)
        for (reference, frames) in [(first, 1600), (second, 3200)] {
            let url = try files.url(for: reference)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            buffer.frameLength = buffer.frameCapacity
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let schema = Schema([CampusTask.self, ConversationTurn.self, ActionItem.self])
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Audio.store"))
        let chinese = "请到一楼服务台"
        let english = "Which desk should I go to?"
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let store = TaskStore(context: container.mainContext)
            let task = try store.createTask(
                scenario: .enrollment, title: TaskScenario.enrollment.title,
                question: TaskScenario.enrollment.question(asking: [.location]), fields: [.location]
            )
            for (ref, language, words, translated) in [
                (first, CardLanguage.chinese, chinese, "Please go to the first-floor desk."),
                (second, CardLanguage.english, english, "我应该去哪个柜台？")
            ] {
                var draft = ReplyDraft(taskID: task.id)
                draft.language = language
                draft.kind = .directions
                let recognition = draft.beginRecognition()
                XCTAssertTrue(draft.receiveRecognition(text: words, language: language, recordingRef: ref, for: recognition))
                let translation = try XCTUnwrap(draft.beginTranslation())
                XCTAssertTrue(draft.receiveTranslation(translated, for: translation))
                try store.confirmReply(draft)
            }
        }
        let reopened = ReplyRecordingFiles(root: directory)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let history = try container.mainContext.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(history.count, 2)
        for (words, expectedRef, duration) in [(chinese, first, 0.1), (english, second, 0.2)] {
            let ref = try XCTUnwrap(history.first { $0.original == words }?.recordingRef)
            XCTAssertEqual(ref, expectedRef)
            let player = try AVAudioPlayer(contentsOf: reopened.url(for: ref))
            XCTAssertEqual(player.duration, duration, accuracy: 0.001)
        }
        let discarded = try files.newReference()
        try Data().write(to: files.url(for: discarded))
        reopened.remove(discarded)
        XCTAssertFalse(try FileManager.default.fileExists(atPath: reopened.url(for: discarded).path))
        XCTAssertTrue(try FileManager.default.fileExists(atPath: reopened.url(for: first).path))
        XCTAssertTrue(try FileManager.default.fileExists(atPath: reopened.url(for: second).path))
    }

    func testRejectsReferencesOutsideRecordingsAndDirectories() {
        let files = ReplyRecordingFiles()
        for path in ["/tmp/test.wav", "Recordings/../test.wav", "Recordings/", "Recordings/a/b.wav",
                     "Recordings/..", "Recordings/.", "Recordings/a\\b.wav", "Other/test.wav"] {
            XCTAssertThrowsError(try files.url(for: path), path)
        }
    }

    @MainActor
    func testReleasingBeforePermissionReturnsNeverStartsRecording() async {
        let token = ReplyRequestToken(taskID: UUID(), draftID: UUID(), version: 1)
        for granted in [true, false] {
            let capture = ReplyCapture(requestPermission: { granted })
            capture.begin(token)
            XCTAssertNil(capture.finish(token))
            do {
                _ = try await capture.recognize(token, .chinese)
                XCTFail("A released press cannot start recording after the permission response")
            } catch {
                XCTAssertEqual(error as? ReplyCaptureError, granted ? .holdAgain : .permissionDenied)
            }
            XCTAssertFalse(capture.isRecording)
        }
    }

    @MainActor
    func testCancelledPressCannotFinishNewRound() async {
        let first = ReplyRequestToken(taskID: UUID(), draftID: UUID(), version: 1)
        let second = ReplyRequestToken(taskID: UUID(), draftID: UUID(), version: 1)
        let capture = ReplyCapture(requestPermission: { false })
        capture.begin(first)
        capture.begin(second)
        XCTAssertNil(capture.finish(first))
        do {
            _ = try await capture.recognize(first, .english)
            XCTFail("A new press invalidates the previous microphone session")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(capture.finish(second))
        do {
            _ = try await capture.recognize(second, .english)
            XCTFail("Microphone denial must reach the current draft")
        } catch { XCTAssertEqual(error as? ReplyCaptureError, .permissionDenied) }
    }
}
