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

    func testBundledModelsProcessDistinctFixtureSignals() async throws {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "OfflineSpeech", withExtension: nil))
        let model = root.appendingPathComponent("openai_whisper-base")
        let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: root.appendingPathComponent("tokenizer"))
        let extractor = FeatureExtractor()
        let encoder = AudioEncoder()
        let decoder = TextDecoder()
        try await extractor.loadModel(at: model.appendingPathComponent("MelSpectrogram.mlmodelc"), computeUnits: .cpuOnly)
        try await encoder.loadModel(at: model.appendingPathComponent("AudioEncoder.mlmodelc"), computeUnits: .cpuOnly)
        try await decoder.loadModel(at: model.appendingPathComponent("TextDecoder.mlmodelc"), computeUnits: .cpuOnly)
        for (name, rms, mel10, mel30) in [("en", 0.06453, -0.2326, -0.3048), ("zh", 0.05113, 0.2854, -0.1992),
                                           ("silence", 0.0, -0.8062, -0.8062)] {
            var pcm: [Float] = [0]
            if name != "silence" {
                let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "wav",
                                                                   subdirectory: "SpeechSamples"))
                pcm = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            }
            let energy = sqrt(pcm.reduce(0.0) { $0 + Double($1 * $1) } / Double(pcm.count))
            print("Fixture audio \(name) frames=\(pcm.count) rms=\(energy)")
            XCTAssertEqual(energy, rms, accuracy: 0.0005, name)
            let input = try XCTUnwrap(AudioProcessor.padOrTrimAudio(fromArray: pcm))
            let halfInput = try MLMultiArray(shape: input.shape, dataType: .float16)
            let halfSamples = halfInput.dataPointer.bindMemory(to: Float16.self, capacity: halfInput.count)
            halfSamples.initialize(repeating: 0, count: halfInput.count)
            for index in pcm.indices { halfSamples[index] = Float16(pcm[index]) }
            for (label, samples) in [("sdk", input), ("fp16", halfInput)] {
                let features = try await extractor.logMelSpectrogram(fromAudio: samples) as? MLMultiArray
                let mel = try XCTUnwrap(features)
                let bands = [10, 30].map { mel[[0, $0, 0, 60] as [NSNumber]].doubleValue }
                let embedding = try await encoder.encodeFeatures(mel)
                let embeds = try XCTUnwrap(embedding)
                let values = [0, 1, 2, 64, 256].map { embeds[[0, $0, 0, 30] as [NSNumber]].doubleValue }
                print("Fixture model \(name)/\(label) mel=\(bands) encoder=\(values)")
                XCTAssertEqual(bands[0], mel10, accuracy: 0.02, "\(name)/\(label)")
                XCTAssertEqual(bands[1], mel30, accuracy: 0.02, "\(name)/\(label)")
                if label == "sdk" {
                    let prompt = ["<|startoftranscript|>", name == "zh" ? "<|zh|>" : "<|en|>",
                                  "<|transcribe|>", "<|notimestamps|>"]
                    let tokens = try prompt.map { try XCTUnwrap(tokenizer.convertTokenToId($0)) }
                    try await logGreedyPredictions(name, decoder: decoder, embeddings: embeds,
                                                   prompt: tokens, tokenizer: tokenizer)
                }
            }
        }
    }

    private func logGreedyPredictions(_ name: String, decoder: TextDecoder, embeddings: MLMultiArray,
                                      prompt: [Int], tokenizer: TokenizerWrapper) async throws {
        let inputs = try XCTUnwrap(try decoder.prepareDecoderInputs(withPrompt: prompt) as? DecodingInputs)
        let expectedFirstWords = [" Which", "Which", " I", "請", "请", "我"]
        var rawToken = 0
        for step in 0..<(prompt.count + 2) {
            inputs.inputIds[0] = NSNumber(value: step < prompt.count ? prompt[step] : rawToken)
            inputs.cacheLength[0] = NSNumber(value: step)
            let prediction = try await decoder.predictLogits(inputIds: inputs.inputIds, cacheLength: inputs.cacheLength,
                                                            keyCache: inputs.keyCache, valueCache: inputs.valueCache,
                                                            kvCacheUpdateMask: inputs.kvCacheUpdateMask,
                                                            encoderOutputEmbeds: embeddings,
                                                            decoderKeyPaddingMask: inputs.decoderKeyPaddingMask)
            let logits = try XCTUnwrap(prediction?.logits)
            var bestScore = -Double.infinity
            for index in 0..<logits.count {
                let value = logits[index].doubleValue
                if value > bestScore {
                    bestScore = value
                    rawToken = index
                }
            }
            let wordScores = expectedFirstWords.compactMap { word -> String? in
                guard let id = tokenizer.encode(text: word).first(where: { $0 < 50257 }) else { return nil }
                return "\(word)=\(logits[id].doubleValue)"
            }
            print("Fixture logits \(name) step=\(step) best=\(rawToken) '\(tokenizer.decode(tokens: [rawToken]))' score=\(bestScore) candidates=\(wordScores)")
            let key = try XCTUnwrap(prediction?.cache?.keyCache)
            let value = try XCTUnwrap(prediction?.cache?.valueCache)
            TextDecoder.updateKVCache(keyTensor: inputs.keyCache, keySlice: key,
                                      valueTensor: inputs.valueCache, valueSlice: value, insertAtIndex: step)
            inputs.decoderKeyPaddingMask[step + 1] = 0
            inputs.kvCacheUpdateMask[step] = 0
            inputs.kvCacheUpdateMask[step + 1] = 1
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
