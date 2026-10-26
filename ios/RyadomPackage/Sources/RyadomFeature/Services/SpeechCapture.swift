import Foundation
import Observation
import Speech
import AVFoundation

enum SpeechAccess: Equatable {
    case granted, denied, restricted, unavailable
}

/// Источник речи: системное распознавание или симулятор в отладочных сборках.
@MainActor
protocol SpeechEngine: AnyObject {
    func requestAccess() async -> SpeechAccess
    /// Начинает слушать. `onEnd` вызывается, когда распознавание закончилось само или по ошибке.
    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onEnd: @escaping @MainActor (Error?) -> Void) throws
    func stop()
}

enum SpeechEngines {
    @MainActor static func make() -> any SpeechEngine {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RYVoicePhrase") || args.contains("-RYVoiceDenied") || args.contains("-RYVoiceUnavailable") {
            return SimulatedSpeechEngine()
        }
        #endif
        return AppleSpeechEngine()
    }
}

/// Запись и расшифровка речи. Текст можно править руками: он же служит запасным вариантом без микрофона.
@Observable
@MainActor
final class SpeechCapture {
    enum State: Equatable { case idle, requesting, listening, denied, restricted, unavailable, failed }

    private(set) var state: State = .idle
    var transcript = "" {
        didSet { if transcript != oldValue { lastChange = .now } }
    }
    /// Громкость 0…1 для анимации.
    private(set) var level: Float = 0
    /// Вызывается, когда фраза закончилась (тишина или конец распознавания) и текст не пуст.
    var onFinished: (() -> Void)?

    private let engine: any SpeechEngine
    private var lastChange = Date.now
    private var watcher: Task<Void, Never>?

    /// Сколько тишины после слов считаем концом фразы, сек. И предел длины записи.
    static let silenceTimeout: TimeInterval = 2.2
    static let maxDuration: TimeInterval = 60

    init(engine: any SpeechEngine) { self.engine = engine }

    var isListening: Bool { state == .listening }

    func start() async {
        guard state != .listening, state != .requesting else { return }
        state = .requesting
        switch await engine.requestAccess() {
        case .granted: break
        case .denied: state = .denied; return
        case .restricted: state = .restricted; return
        case .unavailable: state = .unavailable; return
        }
        do {
            try engine.start(
                onTranscript: { [weak self] text in self?.transcript = text },
                onLevel: { [weak self] value in
                    guard let self else { return }
                    level = max(value, level * 0.85)
                },
                onEnd: { [weak self] error in self?.engineEnded(error) })
            state = .listening
            lastChange = .now
            watch()
        } catch {
            state = .failed
        }
    }

    /// Останавливает запись, текст остаётся.
    func stop() {
        guard state == .listening || state == .requesting else { return }
        engine.stop()
        watcher?.cancel()
        level = 0
        state = .idle
    }

    private func engineEnded(_ error: Error?) {
        guard state == .listening else { return }
        engine.stop()
        watcher?.cancel()
        level = 0
        state = .idle
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onFinished?() }
    }

    /// Конец фразы по тишине: после слов — `silenceTimeout`; общий предел — `maxDuration`.
    private func watch() {
        watcher?.cancel()
        let began = Date.now
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, state == .listening else { return }
                let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let silent = Date.now.timeIntervalSince(lastChange) > Self.silenceTimeout
                let tooLong = Date.now.timeIntervalSince(began) > Self.maxDuration
                if (hasText && silent) || tooLong {
                    stop()
                    if hasText { onFinished?() }
                    return
                }
            }
        }
    }
}

// MARK: Системное распознавание

/// Передаёт звук из аудиопотока в запрос распознавания. Нужен, чтобы не тянуть несовместимые с потоками типы в изолированный код.
private final class AudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let onLevel: @Sendable (Float) -> Void

    init(request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Float) -> Void) {
        self.request = request
        self.onLevel = onLevel
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = (sum / Float(count)).squareRoot()
        onLevel(min(1, rms * 12))
    }
}

@MainActor
final class AppleSpeechEngine: SpeechEngine {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAccess() async -> SpeechAccess {
        guard let recognizer, recognizer.isAvailable else { return .unavailable }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: break
        case .restricted: return .restricted
        default: return .denied
        }
        return await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onEnd: @escaping @MainActor (Error?) -> Void) throws {
        guard let recognizer else { throw SpeechError.unavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // Где возможно — распознаём на устройстве: звук никуда не отправляется.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audio.inputNode
        let sink = AudioSink(request: request) { level in Task { @MainActor in onLevel(level) } }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in sink.handle(buffer) }
        audio.prepare()
        try audio.start()

        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                if let text { onTranscript(text) }
                if finished { onEnd(error) }
            }
        }
    }

    func stop() {
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum SpeechError: Error { case unavailable }
}

#if DEBUG
/// Симулятор речи для UI-тестов: «произносит» фразу из `-RYVoicePhrase "…"` слово за словом.
/// `-RYVoiceDenied` и `-RYVoiceUnavailable` имитируют отказ в доступе и отсутствие распознавания.
@MainActor
final class SimulatedSpeechEngine: SpeechEngine {
    private let args = ProcessInfo.processInfo.arguments
    private var task: Task<Void, Never>?

    func requestAccess() async -> SpeechAccess {
        if args.contains("-RYVoiceDenied") { return .denied }
        if args.contains("-RYVoiceUnavailable") { return .unavailable }
        return .granted
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onEnd: @escaping @MainActor (Error?) -> Void) throws {
        let phrase = args.firstIndex(of: "-RYVoicePhrase").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? ""
        task = Task {
            try? await Task.sleep(for: .milliseconds(400))
            var spoken: [String] = []
            for word in phrase.split(separator: " ") {
                if Task.isCancelled { return }
                spoken.append(String(word))
                onTranscript(spoken.joined(separator: " "))
                onLevel(0.6)
                try? await Task.sleep(for: .milliseconds(60))
            }
            onEnd(nil)
        }
    }

    func stop() { task?.cancel() }
}
#endif
