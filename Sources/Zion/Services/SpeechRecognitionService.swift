import AVFoundation
import Foundation
import Speech

/// Hybrid speech-to-text service: Apple Speech (free, real-time) or OpenAI Whisper (optional, batch).
@MainActor @Observable
final class SpeechRecognitionService {

    // MARK: - State

    enum State: Equatable {
        case idle
        case requesting       // Waiting for permission
        case listening        // Apple Speech: streaming transcription
        case recording        // Whisper: recording audio
        case processing       // Whisper: uploading + transcribing
    }

    enum Engine: String, CaseIterable, Identifiable {
        case apple
        case whisper

        var id: String { rawValue }

        var label: String {
            switch self {
            case .apple: return L10n("speech.engine.apple")
            case .whisper: return L10n("speech.engine.whisper")
            }
        }
    }

    enum RecoveryIssue: Equatable {
        case whisperMissingKey
        case whisperQuotaExceeded
        case whisperTemporarilyUnavailable
        case whisperFailed

        var message: String {
            switch self {
            case .whisperMissingKey:
                return L10n("speech.recovery.whisperMissingKey")
            case .whisperQuotaExceeded:
                return L10n("speech.recovery.whisperQuotaExceeded")
            case .whisperTemporarilyUnavailable:
                return L10n("speech.recovery.whisperTemporarilyUnavailable")
            case .whisperFailed:
                return L10n("speech.recovery.whisperFailed")
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var currentTranscript: String = ""
    private(set) var recoveryIssue: RecoveryIssue?

    /// The terminal session ID captured at recording start (not at send time).
    private(set) var targetSessionID: UUID?

    var selectedEngine: Engine {
        get {
            SpeechEngineSupport.effectiveEngine(
                storedValue: UserDefaults.standard.string(forKey: "speech.engine")
            )
        }
        set {
            let effective = SpeechEngineSupport.effectiveEngine(storedValue: newValue.rawValue)
            UserDefaults.standard.set(effective.rawValue, forKey: "speech.engine")
        }
    }

    var selectedLocale: Locale {
        get { Locale(identifier: UserDefaults.standard.string(forKey: "speech.locale") ?? Locale.current.identifier) }
        set { UserDefaults.standard.set(newValue.identifier, forKey: "speech.locale") }
    }

    /// Whether an OpenAI key is configured (determines if Whisper option shows).
    var isWhisperAvailable: Bool {
        SpeechEngineSupport.isWhisperAvailable()
    }

    var isActive: Bool {
        state == .listening || state == .recording || state == .processing
    }

    // MARK: - Private

    @ObservationIgnored private let logger = DiagnosticLogger.shared
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var audioBufferFrames: [AVAudioPCMBuffer] = []

    // MARK: - Apple Speech

    var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { $0.identifier < $1.identifier }
    }

    func requestPermission() async -> Bool {
        state = .requesting

        // Whisper only needs microphone, not Speech Recognition
        if selectedEngine == .apple {
            logger.log(.info, "Requesting speech authorization…", context: "Speech")
            let speechAuthorized = await Self.requestSpeechAuthorization()
            logger.log(.info, "Speech authorization: \(speechAuthorized)", context: "Speech")

            guard speechAuthorized else {
                state = .idle
                return false
            }
        } else {
            logger.log(.info, "Whisper engine — skipping speech authorization", context: "Speech")
        }

        let micAuthorized: Bool
        if #available(macOS 14.0, *) {
            logger.log(.info, "Requesting mic permission (macOS 14+)…", context: "Speech")
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = true // Pre-14, mic permission prompt triggers on first use
        }
        logger.log(.info, "Mic authorization: \(micAuthorized)", context: "Speech")

        state = .idle
        return micAuthorized
    }

    /// Isolated from @MainActor so the TCC callback doesn't inherit actor context.
    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening(locale: Locale, targetSessionID: UUID?) {
        guard state == .idle else {
            logger.log(.warn, "startListening: state is \(state), expected .idle — skipping", context: "Speech")
            return
        }
        recoveryIssue = nil
        self.targetSessionID = targetSessionID

        logger.log(.info, "Creating SFSpeechRecognizer for locale \(locale.identifier)…", context: "Speech")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            logger.log(.error, "SFSpeechRecognizer unavailable for locale \(locale.identifier)", context: "Speech")
            state = .idle
            return
        }

        logger.log(.info, "Creating AVAudioEngine…", context: "Speech")
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        self.audioEngine = engine
        self.recognitionRequest = request
        self.currentTranscript = ""

        logger.log(.info, "Accessing inputNode…", context: "Speech")
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.log(.info, "Format: channels=\(recordingFormat.channelCount), sampleRate=\(recordingFormat.sampleRate)", context: "Speech")

        // Audio hardware may not be ready right after first permission grant
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            logger.log(.error, "Invalid audio format — hardware not ready", context: "Speech")
            cleanup()
            return
        }

        logger.log(.info, "Installing tap…", context: "Speech")
        Self.installSpeechTap(on: inputNode, format: recordingFormat, request: request)

        logger.log(.info, "Starting engine…", context: "Speech")
        engine.prepare()

        do {
            try engine.start()
            state = .listening
            logger.log(.info, "Listening started", context: "Speech")
        } catch {
            logger.log(.error, "Engine start failed: \(error.localizedDescription)", context: "Speech")
            cleanup()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.cleanup()
                    }
                } else if error != nil {
                    self.logger.log(.error, "Recognition error: \(error!.localizedDescription)", context: "Speech")
                    self.cleanup()
                }
            }
        }
    }

    func stopListening() -> (transcript: String, sessionID: UUID?) {
        let transcript = currentTranscript.trimmingTrailingWhitespace()
        let sessionID = targetSessionID

        recognitionRequest?.endAudio()
        cleanup()

        return (transcript, sessionID)
    }

    // MARK: - Whisper

    func startRecording(targetSessionID: UUID?) {
        guard state == .idle else {
            logger.log(.warn, "startRecording: state is \(state), expected .idle — skipping", context: "Speech")
            return
        }
        recoveryIssue = nil
        self.targetSessionID = targetSessionID

        logger.log(.info, "Creating AVAudioEngine for Whisper recording…", context: "Speech")
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.audioBufferFrames = []
        self.currentTranscript = ""

        logger.log(.info, "Accessing inputNode (Whisper)…", context: "Speech")
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logger.log(.info, "Format: channels=\(recordingFormat.channelCount), sampleRate=\(recordingFormat.sampleRate)", context: "Speech")

        // Audio hardware may not be ready right after first permission grant
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            logger.log(.error, "Invalid audio format — hardware not ready (Whisper)", context: "Speech")
            cleanup()
            return
        }

        logger.log(.info, "Installing tap (Whisper)…", context: "Speech")
        Self.installRecordingTap(on: inputNode, format: recordingFormat) { [weak self] buffer in
            // Wrap buffer to cross isolation boundary — safe because we only read it on MainActor
            let wrapped = UncheckedSendableBox(buffer)
            Task { @MainActor in
                self?.audioBufferFrames.append(wrapped.value)
            }
        }

        logger.log(.info, "Starting engine (Whisper)…", context: "Speech")
        engine.prepare()

        do {
            try engine.start()
            state = .recording
            logger.log(.info, "Recording started", context: "Speech")
        } catch {
            logger.log(.error, "Engine start failed (Whisper): \(error.localizedDescription)", context: "Speech")
            cleanup()
        }
    }

    func stopAndTranscribe() async -> (transcript: String, sessionID: UUID?) {
        let sessionID = targetSessionID

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        state = .processing
        recoveryIssue = nil

        guard let wavData = encodeWAV() else {
            recoveryIssue = .whisperFailed
            cleanup()
            return ("", sessionID)
        }

        guard let apiKey = AIClient.loadAPIKey(for: .openai) else {
            recoveryIssue = .whisperMissingKey
            cleanup()
            return ("", sessionID)
        }

        do {
            let transcript = try await transcribeWithWhisper(wavData: wavData, apiKey: apiKey)
            cleanup()
            return (transcript, sessionID)
        } catch let error as AIError {
            switch error {
            case .quotaExceeded:
                recoveryIssue = .whisperQuotaExceeded
            case .temporarilyUnavailable:
                recoveryIssue = .whisperTemporarilyUnavailable
            default:
                recoveryIssue = .whisperFailed
            }
            cleanup()
            return ("", sessionID)
        } catch {
            recoveryIssue = .whisperFailed
            cleanup()
            return ("", sessionID)
        }
    }

    func clearRecoveryIssue() {
        recoveryIssue = nil
    }

    // MARK: - Toggle (convenience for UI)

    func toggle(locale: Locale, targetSessionID: UUID?) {
        switch (selectedEngine, state) {
        case (.apple, .idle):
            startListening(locale: locale, targetSessionID: targetSessionID)
        case (.apple, .listening):
            _ = stopListening()
        case (.whisper, .idle):
            startRecording(targetSessionID: targetSessionID)
        case (.whisper, .recording):
            Task { _ = await stopAndTranscribe() }
        default:
            break
        }
    }

    // MARK: - Audio Tap Helpers (nonisolated to avoid MainActor assertion on realtime thread)

    /// Must be nonisolated so the tap closure doesn't inherit @MainActor isolation.
    /// The audio engine calls this closure on its realtime thread — NOT the main thread.
    private nonisolated static func installSpeechTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    /// Must be nonisolated so the tap closure doesn't inherit @MainActor isolation.
    private nonisolated static func installRecordingTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        handler: @Sendable @escaping (AVAudioPCMBuffer) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            handler(buffer)
        }
    }

    // MARK: - Private Helpers

    private func cleanup() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioBufferFrames = []
        state = .idle
    }

    private func encodeWAV() -> Data? {
        guard !audioBufferFrames.isEmpty,
              let format = audioBufferFrames.first?.format else { return nil }

        let totalFrames = audioBufferFrames.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return nil }

        let sampleRate = Int(format.sampleRate)
        let channels = Int(format.channelCount)
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = totalFrames * channels * bytesPerSample

        var data = Data()

        // WAV header
        data.append(contentsOf: "RIFF".utf8)
        data.append(UInt32(36 + dataSize).littleEndianBytes)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(UInt32(16).littleEndianBytes)           // Subchunk1Size
        data.append(UInt16(1).littleEndianBytes)            // PCM
        data.append(UInt16(channels).littleEndianBytes)
        data.append(UInt32(sampleRate).littleEndianBytes)
        data.append(UInt32(sampleRate * channels * bytesPerSample).littleEndianBytes)
        data.append(UInt16(channels * bytesPerSample).littleEndianBytes)
        data.append(UInt16(bitsPerSample).littleEndianBytes)
        data.append(contentsOf: "data".utf8)
        data.append(UInt32(dataSize).littleEndianBytes)

        // Audio samples (convert Float32 → Int16)
        for buffer in audioBufferFrames {
            guard let floatData = buffer.floatChannelData else { continue }
            let frameCount = Int(buffer.frameLength)
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let sample = floatData[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    let int16 = Int16(clamped * Float(Int16.max))
                    data.append(int16.littleEndianBytes)
                }
            }
        }

        return data
    }

    private func transcribeWithWhisper(wavData: Data, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()
        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode == 401 { throw AIError.invalidKey }
        if http.statusCode == 503 { throw AIError.temporarilyUnavailable }
        if http.statusCode == 429 { throw AIError.quotaExceeded }
        guard http.statusCode == 200 else {
            throw AIError.apiError("OpenAI Whisper request failed (\(http.statusCode)).")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = json?["text"] as? String else {
            throw AIError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Sendable Wrapper

/// Wraps a non-Sendable value for transfer across isolation boundaries.
/// Caller must ensure the value is not accessed concurrently.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Helpers

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while result.last?.isWhitespace == true || result.last?.isNewline == true {
            result.removeLast()
        }
        return result
    }
}

private extension UInt16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

private extension UInt32 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension Int16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Int16>.size)
    }
}
