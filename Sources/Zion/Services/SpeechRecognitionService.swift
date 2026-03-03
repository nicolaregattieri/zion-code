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

    private(set) var state: State = .idle
    private(set) var currentTranscript: String = ""

    /// The terminal session ID captured at recording start (not at send time).
    private(set) var targetSessionID: UUID?

    var selectedEngine: Engine = .apple
    var selectedLocale: Locale = .current

    /// Whether an OpenAI key is configured (determines if Whisper option shows).
    var isWhisperAvailable: Bool {
        AIClient.loadAPIKey(for: .openai) != nil
    }

    var isActive: Bool {
        state == .listening || state == .recording || state == .processing
    }

    // MARK: - Private

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
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    continuation.resume(returning: status == .authorized)
                }
            }
        }

        guard speechAuthorized else {
            state = .idle
            return false
        }

        let micAuthorized: Bool
        if #available(macOS 14.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = true // Pre-14, mic permission prompt triggers on first use
        }

        if !micAuthorized {
            state = .idle
        }
        return speechAuthorized && micAuthorized
    }

    func startListening(locale: Locale, targetSessionID: UUID?) {
        guard state == .idle else { return }
        self.targetSessionID = targetSessionID

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            state = .idle
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        self.audioEngine = engine
        self.recognitionRequest = request
        self.currentTranscript = ""

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()

        do {
            try engine.start()
            state = .listening
        } catch {
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
        guard state == .idle else { return }
        self.targetSessionID = targetSessionID

        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.audioBufferFrames = []
        self.currentTranscript = ""

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.audioBufferFrames.append(buffer)
            }
        }

        engine.prepare()

        do {
            try engine.start()
            state = .recording
        } catch {
            cleanup()
        }
    }

    func stopAndTranscribe() async -> (transcript: String, sessionID: UUID?) {
        let sessionID = targetSessionID

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        state = .processing

        guard let wavData = encodeWAV() else {
            cleanup()
            return ("", sessionID)
        }

        guard let apiKey = AIClient.loadAPIKey(for: .openai) else {
            cleanup()
            return ("", sessionID)
        }

        let transcript = await transcribeWithWhisper(wavData: wavData, apiKey: apiKey)
        cleanup()
        return (transcript, sessionID)
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

    private func transcribeWithWhisper(wavData: Data, apiKey: String) async -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

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

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text
            }
        } catch {
            // Transcription failed silently
        }

        return ""
    }
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
