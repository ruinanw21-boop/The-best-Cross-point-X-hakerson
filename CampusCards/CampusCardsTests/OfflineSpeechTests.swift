import XCTest
@testable import CampusCards

final class OfflineSpeechTests: XCTestCase {
    // These 16 kHz mono WAVs contain the two acceptance sentences, synthesized
    // in Mandarin and US English. This exercises the bundled model on iOS.
    func testBundledBaseTranscribesChineseAndEnglish() async throws {
        let bundle = Bundle(for: Self.self)
        let samples: [(String, CardLanguage)] = [("zh", .chinese), ("en", .english)]
        for (name, language) in samples {
            let audio = try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav",
                                                subdirectory: "SpeechSamples"))
            let text = try await OfflineTranscriber.shared.transcribe(file: audio, language: language)
            let transcript = XCTAttachment(string: text)
            transcript.name = "WhisperKit transcript (\(name))"
            transcript.lifetime = .keepAlways
            add(transcript)
            if language == .chinese {
                let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
                XCTAssertTrue(simplified.contains("一楼") || simplified.contains("1楼"), text)
                XCTAssertTrue(simplified.contains("服务台"), text)
            } else {
                let words = text.lowercased().split { !$0.isLetter }.map(String.init)
                XCTAssertTrue(words.starts(with: ["which", "desk"]), text)
                XCTAssertTrue(words.contains("go"), text)
            }
        }
    }
}
