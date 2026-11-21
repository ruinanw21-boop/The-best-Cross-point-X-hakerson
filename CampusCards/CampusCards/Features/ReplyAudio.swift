import AVFAudio
import AudioToolbox
import Combine
import SwiftUI

struct ReplyRecordingFiles {
    let root: URL

    init(root: URL = .applicationSupportDirectory) {
        self.root = root
    }

    func newReference() throws -> String {
        let reference = "Recordings/\(UUID().uuidString).wav"
        let directory = try url(for: reference).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return reference
    }

    func url(for reference: String) throws -> URL {
        let parts = reference.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Recordings",
              !parts[1].isEmpty, !parts[1].hasPrefix("."),
              !parts[1].contains("\\"), !parts[1].contains(":") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let directory = root.appendingPathComponent("Recordings", isDirectory: true)
        let url = directory.appendingPathComponent(String(parts[1]), isDirectory: false)
        guard ["wav", "m4a"].contains(url.pathExtension.lowercased()),
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return url
    }

    func remove(_ reference: String) {
        guard let url = try? url(for: reference),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum ReplyCaptureError: Error, Equatable {
    case permissionDenied, holdAgain, interrupted, recordingFailed, noAudio

    var messageKey: String {
        switch self {
        case .permissionDenied: "Microphone access is off. Allow it in Settings or type the reply."
        case .holdAgain: "Microphone access is ready. Hold the microphone again to record."
        case .interrupted: "Recording was interrupted. Hold the microphone again or type the reply."
        case .recordingFailed: "Couldn’t record audio. Try again or type the reply."
        case .noAudio: "No audio was recorded. Hold the microphone while speaking."
        }
    }
}

@MainActor
final class ReplyCapture: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var issue: ReplyCaptureError?

    private let files = ReplyRecordingFiles()
    private let requestPermission: () async -> Bool
    private var permissionTask: Task<Void, Never>?
    private var token: ReplyRequestToken?
    private var held = false
    private var recorder: AVAudioRecorder?
    private var workingReference: String?
    private var finishedReference: String?
    private var interruption: AnyCancellable?

    init(requestPermission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() }) {
        self.requestPermission = requestPermission
    }

    func begin(_ request: ReplyRequestToken) {
        cancel()
        token = request
        held = true
        let permission = requestPermission
        permissionTask = Task { [weak self] in
            let granted = await permission()
            guard let self, !Task.isCancelled, token == request else { return }
            guard granted else {
                issue = .permissionDenied
                return
            }
            guard held else {
                issue = .holdAgain
                return
            }
            startRecorder(for: request)
        }
    }

    private func startRecorder(for request: ReplyRequestToken) {
        let session = AVAudioSession.sharedInstance()
        ReplyPlayback.shared.stop()
        do {
            let reference = try files.newReference()
            workingReference = reference
            let url = try files.url(for: reference)
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            self.recorder = recorder
            guard recorder.record() else { throw ReplyCaptureError.recordingFailed }
            isRecording = true
            interruption = session.onInterruption { [weak self] in
                guard let self, token == request, isRecording else { return }
                stopRecorder()
                discardWorkingFile()
                issue = .interrupted
            }
        } catch {
            stopRecorder()
            discardWorkingFile()
            issue = .recordingFailed
        }
    }

    // Ownership transfers to the draft here, before inference. Editing the text or
    // cancelling inference must leave this recording available for review.
    func finish(_ request: ReplyRequestToken) -> String? {
        guard token == request else { return nil }
        guard held else { return finishedReference }
        held = false
        guard let recorder, let reference = workingReference else { return nil }
        let recording = recorder.isRecording
        let url = recorder.url
        stopRecorder()
        guard recording, let file = try? AVAudioFile(forReading: url), file.length > 0 else {
            discardWorkingFile()
            issue = recording ? .noAudio : .interrupted
            return nil
        }
        workingReference = nil
        finishedReference = reference
        return reference
    }

    func recognize(_ request: ReplyRequestToken, _ language: CardLanguage) async throws -> ReplyTranscription {
        guard token == request else { throw CancellationError() }
        await permissionTask?.value
        try Task.checkCancellation()
        guard token == request else { throw CancellationError() }
        if let issue { throw issue }
        guard let reference = finishedReference else { throw ReplyCaptureError.noAudio }
        let url = try files.url(for: reference)
        let text = try await OfflineTranscriber.shared.transcribe(file: url, language: language)
        try Task.checkCancellation()
        guard token == request else { throw CancellationError() }
        return ReplyTranscription(token: request, language: language, originalText: text, recordingRef: reference)
    }

    func cancel() {
        permissionTask?.cancel()
        permissionTask = nil
        token = nil
        held = false
        if recorder != nil { stopRecorder() }
        discardWorkingFile()
        finishedReference = nil
        issue = nil
    }

    private func stopRecorder() {
        interruption = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func discardWorkingFile() {
        if let reference = workingReference { files.remove(reference) }
        workingReference = nil
    }
}

private extension AVAudioSession {
    func onInterruption(_ action: @escaping () -> Void) -> AnyCancellable {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification, object: self)
            .receive(on: RunLoop.main)
            .sink { note in
                if let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   InterruptionType(rawValue: value) == .began { action() }
            }
    }
}

@MainActor
private final class ReplyPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ReplyPlayback()
    @Published private(set) var activeReference: String?
    @Published private(set) var failedReference: String?
    private var player: AVAudioPlayer?
    private var interruption: AnyCancellable?

    func toggle(_ reference: String) {
        let wasPlaying = reference == activeReference
        stop()
        failedReference = nil
        guard !wasPlaying else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            let url = try ReplyRecordingFiles().url(for: reference)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.delegate = self
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            activeReference = reference
            interruption = session.onInterruption { [weak self] in self?.stop() }
        } catch {
            stop()
            failedReference = reference
        }
    }

    func stop() {
        guard let player else { return }
        interruption = nil
        player.delegate = nil
        player.stop()
        self.player = nil
        activeReference = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            if !flag { failedReference = activeReference }
            stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}

struct RecordingPlaybackButton: View {
    let recordingRef: String
    @ObservedObject private var playback = ReplyPlayback.shared
    @Environment(\.cardLanguage) private var language

    var body: some View {
        let playing = playback.activeReference == recordingRef
        VStack(alignment: .leading) {
            Button {
                playback.toggle(recordingRef)
            } label: {
                Label(language.wrappedValue.text(playing ? "Stop playback" : "Play recording"),
                      systemImage: playing ? "stop.circle" : "play.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("play-recording")
            if playback.failedReference == recordingRef {
                Text(language.wrappedValue.text("Couldn’t play this recording."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            if playback.activeReference == recordingRef { playback.stop() }
        }
    }
}
