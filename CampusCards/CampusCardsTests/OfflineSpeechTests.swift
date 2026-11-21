import CoreML
import WhisperKit
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

    func testEnglishEncoderMatchesBundledWeights() async throws {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "OfflineSpeech", withExtension: nil))
        let model = root.appendingPathComponent("openai_whisper-base")
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "en", withExtension: "wav",
                                                            subdirectory: "SpeechSamples"))
        let pcm = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let input = try XCTUnwrap(AudioProcessor.padOrTrimAudio(fromArray: pcm))
        let extractor = FeatureExtractor()
        try await extractor.loadModel(at: model.appendingPathComponent("MelSpectrogram.mlmodelc"), computeUnits: .cpuOnly)
        let features = try await extractor.logMelSpectrogram(fromAudio: input) as? MLMultiArray
        let mel = try XCTUnwrap(features)
        let channels = [0, 1, 2, 64, 256]
        // Reference values from the bundled weights evaluated in float32.
        let reference = [1.3633, 0.1955, 1.3726, 0.0648, 2.1413]
        let url = model.appendingPathComponent("AudioEncoder.mlmodelc")
        for (label, units, optimize) in [("selected", OfflineTranscriber.computeOptions.audioEncoderCompute, false),
                                          ("gpu", MLComputeUnits.cpuAndGPU, false), ("optimizedCPU", .cpuOnly, true),
                                          ("optimizedAll", .all, true)] {
            let config = MLModelConfiguration()
            config.computeUnits = units
            if optimize { config.optimizationHints.specializationStrategy = .fastPrediction }
            let encoder = AudioEncoder()
            encoder.model = try await MLModel.load(contentsOf: url, configuration: config)
            let embedding = try await encoder.encodeFeatures(mel)
            let values = try XCTUnwrap(embedding)
            let readings = channels.map { values[[0, $0, 0, 30] as [NSNumber]].doubleValue }
            print("Fixture encoder \(label) mel=\(mel[[0, 10, 0, 60]].doubleValue) values=\(readings)")
            if label == "selected" {
                for (result, expected) in zip(readings, reference) {
                    XCTAssertEqual(result, expected, accuracy: 0.15)
                }
            }
        }
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
