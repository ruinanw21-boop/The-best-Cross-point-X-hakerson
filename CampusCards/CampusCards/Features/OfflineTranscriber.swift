import CoreML
import Foundation
import WhisperKit

enum OfflineTranscriptionError: Error {
    case resourcesUnavailable
    case noRecognizedSpeech
}

actor OfflineTranscriber {
    static let shared = OfflineTranscriber()

    private let diagnosticLogging: Bool
    private struct LoadedModel {
        let kit: WhisperKit
        let suppressedTokens: [Int]
    }

    private struct GenerationConfig: Decodable {
        let suppressTokens: [Int]

        enum CodingKeys: String, CodingKey {
            case suppressTokens = "suppress_tokens"
        }
    }

    private var engine: LoadedModel?
    private var lastDecode: Task<Void, Never>?

    init(diagnosticLogging: Bool = false) {
        self.diagnosticLogging = diagnosticLogging
    }

    func transcribe(file: URL, language: CardLanguage) async throws -> String {
        // WhisperKit mutates its decoder during inference. A cancelled request can still
        // be finishing a Core ML operation when the next recording is released.
        let previous = lastDecode
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await decode(file: file, language: language)
        }
        lastDecode = Task { _ = await work.result }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func decode(file: URL, language: CardLanguage) async throws -> String {
        let model = try await loadEngine()
        try Task.checkCancellation()
        // A released reply is a complete utterance, including replies shorter than a second.
        let options = DecodingOptions(task: .transcribe, language: language == .chinese ? "zh" : "en",
                                      detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true,
                                      windowClipTime: 0, suppressBlank: true, suppressTokens: model.suppressedTokens,
                                      firstTokenLogProbThreshold: nil)
        #if targetEnvironment(simulator)
        // WhisperKit sets CPU-only model execution on Simulator. Its iOS 18+
        // token sampler also uses MLTensor, which has a separate compute policy.
        let results = try await withMLTensorComputePolicy(.cpuOnly) {
            try await model.kit.transcribe(audioPath: file.path, decodeOptions: options)
        }
        #else
        let results = try await model.kit.transcribe(audioPath: file.path, decodeOptions: options)
        #endif
        try Task.checkCancellation()
        let text = results.map(\.text).joined(separator: " ").cleaned
        guard !text.isEmpty else { throw OfflineTranscriptionError.noRecognizedSpeech }
        return text
    }

    private func loadEngine() async throws -> LoadedModel {
        if let engine { return engine }
        guard let root = Bundle.main.url(forResource: "OfflineSpeech", withExtension: nil) else {
            throw OfflineTranscriptionError.resourcesUnavailable
        }
        let model = root.appendingPathComponent("openai_whisper-base", isDirectory: true)
        let tokenizer = root.appendingPathComponent("tokenizer", isDirectory: true)
        do {
            // WhisperKit 1.1.1 defaults to an empty suppression list. Use the base
            // model's generation config to exclude non-speech and subtitle markers.
            let generation = try JSONDecoder().decode(
                GenerationConfig.self, from: Data(contentsOf: model.appendingPathComponent("generation_config.json"))
            )
            let localTokenizer = try await AutoTokenizerWrapper.from(modelFolder: tokenizer)
            let config = WhisperKitConfig(modelFolder: model.path, verbose: diagnosticLogging, logLevel: .debug,
                                          load: false, download: false)
            let kit = try await WhisperKit(config)
            // v1.1.1 would otherwise fall back to the Hub after a local tokenizer error,
            // even with download: false. Injecting the local tokenizer bypasses that path.
            kit.tokenizer = try BundledWhisperTokenizer(localTokenizer)
            kit.textDecoder.isModelMultilingual = true
            try await kit.loadModels()
            guard kit.audioEncoder.embedSize == 512, kit.textDecoder.logitsSize == 51_865 else {
                throw OfflineTranscriptionError.resourcesUnavailable
            }
            let loaded = LoadedModel(kit: kit, suppressedTokens: generation.suppressTokens)
            engine = loaded
            return loaded
        } catch {
            try Task.checkCancellation()
            throw OfflineTranscriptionError.resourcesUnavailable
        }
    }
}

// The SDK's WhisperTokenizerWrapper initializer is internal in v1.1.1.
// Keep its BPE implementation and resolve the control tokens from the bundled vocabulary.
private struct BundledWhisperTokenizer: WhisperTokenizer {
    let base: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    init(_ base: TokenizerWrapper) throws {
        self.base = base
        func id(_ piece: String) throws -> Int {
            guard let token = base.convertTokenToId(piece), base.convertIdToToken(token) == piece else {
                throw OfflineTranscriptionError.resourcesUnavailable
            }
            return token
        }
        let end = try id("<|endoftext|>")
        specialTokens = try SpecialTokens(
            endToken: end, englishToken: id("<|en|>"), noSpeechToken: id("<|nocaptions|>"),
            noTimestampsToken: id("<|notimestamps|>"), specialTokenBegin: end,
            startOfPreviousToken: id("<|startofprev|>"), startOfTranscriptToken: id("<|startoftranscript|>"),
            timeTokenBegin: id("<|0.00|>"), transcribeToken: id("<|transcribe|>"),
            translateToken: id("<|translate|>"), whitespaceToken: id("Ġ")
        )
        allLanguageTokens = Set(Constants.languageCodes.compactMap { try? id("<|\($0)|>") })
        guard allLanguageTokens.contains(try id("<|zh|>")) else { throw OfflineTranscriptionError.resourcesUnavailable }
    }

    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    // Replies use segment-level transcription only. Treat the complete segment as the
    // alignment unit if the decoder asks for token groups.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        tokenIds.isEmpty ? ([], []) : ([decode(tokens: tokenIds)], [tokenIds])
    }
}
