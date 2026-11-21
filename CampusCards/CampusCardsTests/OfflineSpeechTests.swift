import XCTest
@testable import CampusCards

final class OfflineSpeechTests: XCTestCase {
    // These 16 kHz mono WAVs contain the two acceptance sentences, synthesized
    // in Mandarin and US English. This exercises the bundled model on iOS.
    private static let transcriber = OfflineTranscriber(diagnosticLogging: true)

    func testBundledBaseTranscribesChinese() async throws {
        let text = try await transcribeSample("zh", language: .chinese)
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        XCTAssertTrue(simplified.contains("一楼") || simplified.contains("1楼"), text)
        XCTAssertTrue(simplified.contains("服务台"), text)
    }

    func testBundledBaseTranscribesEnglish() async throws {
        let text = try await transcribeSample("en", language: .english)
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        XCTAssertTrue(words.starts(with: ["which", "desk"]), text)
        XCTAssertTrue(words.contains("go"), text)
    }

    private func transcribeSample(_ name: String, language: CardLanguage) async throws -> String {
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "wav",
                                                            subdirectory: "SpeechSamples"))
        let text = try await Self.transcriber.transcribe(file: audio, language: language)
        print("WhisperKit fixture (\(name)): \(text)")
        let transcript = XCTAttachment(string: text)
        transcript.name = "WhisperKit transcript (\(name))"
        transcript.lifetime = .keepAlways
        add(transcript)
        return text
    }
}
