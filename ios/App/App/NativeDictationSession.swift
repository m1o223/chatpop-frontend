import AVFoundation
import Speech
import UIKit

@MainActor
final class NativeDictationSession: NSObject {
    enum State {
        case requestingPermission
        case listening
        case recognizing
        case transcriptAvailable
        case noSpeech
        case permissionDenied(String)
        case unavailable(String)
    }

    struct Snapshot {
        let state: State
        let transcript: String
    }

    var onChange: ((Snapshot) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let locale: Locale
    private var generation = UUID()
    private var isActive = false
    private var isFinishing = false
    private var pendingStartRun: UUID?
    private var transcript = ""
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var capture: DictationAudioCapture?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var audioEnded = false
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var previousAudioSession: AudioSessionConfiguration?
    private var ownsAudioSession = false
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var lastVoiceAt: TimeInterval = 0
    private var lastTranscriptAt: TimeInterval = 0
    private var finishingAt: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    init(locale: Locale = .current) {
        self.locale = locale
        super.init()
        observeLifecycle()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
        // The sheet calls stop on every exit. This also protects an unexpected owner release.
        capture?.close()
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        if !audioEnded { request?.endAudio() }
        task?.cancel()
        if ownsAudioSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            if let previousAudioSession {
                try? session.setCategory(previousAudioSession.category,
                                         mode: previousAudioSession.mode,
                                         options: previousAudioSession.options)
            }
        }
    }

    func start() {
        stop()
        transcript = ""
        isActive = true
        let run = generation
        publish(.requestingPermission)

        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            requestSpeechPermission(run: run)
        case .denied:
            finish(.permissionDenied("Allow microphone access for ChatPop in iOS Settings to dictate a message."))
        case .undetermined:
            let completion: @Sendable (Bool) -> Void = { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(run) else { return }
                    if granted {
                        self.requestSpeechPermission(run: run)
                    } else {
                        self.finish(.permissionDenied("Allow microphone access for ChatPop in iOS Settings to dictate a message."))
                    }
                }
            }
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission(completionHandler: completion)
            } else {
                session.requestRecordPermission(completion)
            }
        @unknown default:
            finish(.unavailable("Microphone access is unavailable right now. Please try again."))
        }
    }

    // Cancellation is synchronous on the main actor; stale permission/results callbacks cannot restart capture.
    func stop() {
        generation = UUID()
        isActive = false
        isFinishing = false
        pendingStartRun = nil
        timer?.invalidate()
        timer = nil
        stopCapture()
        task?.cancel()
        task = nil
        request = nil
        recognizer?.delegate = nil
        recognizer = nil
    }

    private func requestSpeechPermission(run: UUID) {
        guard isCurrent(run) else { return }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            beginCapture(run: run)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(run) else { return }
                    self.handleSpeechPermission(status, run: run)
                }
            }
        case .denied, .restricted:
            handleSpeechPermission(SFSpeechRecognizer.authorizationStatus(), run: run)
        @unknown default:
            finish(.unavailable("Speech recognition is unavailable on this device right now."))
        }
    }

    private func handleSpeechPermission(_ status: SFSpeechRecognizerAuthorizationStatus, run: UUID) {
        guard isCurrent(run) else { return }
        switch status {
        case .authorized:
            beginCapture(run: run)
        case .denied:
            finish(.permissionDenied("Allow Speech Recognition for ChatPop in iOS Settings to turn your voice into text."))
        case .restricted:
            finish(.permissionDenied("Speech recognition is restricted on this device. Check your iOS privacy or Screen Time settings."))
        case .notDetermined:
            finish(.unavailable("Speech recognition permission was not completed. Please try again."))
        @unknown default:
            finish(.unavailable("Speech recognition is unavailable on this device right now."))
        }
    }

    private func beginCapture(run: UUID) {
        guard isCurrent(run) else { return }
        if UIApplication.shared.applicationState == .inactive {
            // Permission callbacks can arrive before the system alert has finished dismissing.
            pendingStartRun = run
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            finish(.unavailable("Return to ChatPop and try dictation again."))
            return
        }
        pendingStartRun = nil
        guard AVAudioSession.sharedInstance().recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            finish(.permissionDenied("Allow microphone and Speech Recognition access for ChatPop in iOS Settings to dictate a message."))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            finish(.unavailable("Speech recognition is not available for your device language."))
            return
        }
        guard recognizer.isAvailable else {
            finish(.unavailable("Speech recognition is unavailable right now. Check your connection and try again."))
            return
        }

        self.recognizer = recognizer
        recognizer.delegate = self
        let session = AVAudioSession.sharedInstance()
        previousAudioSession = AudioSessionConfiguration(category: session.category, mode: session.mode, options: session.categoryOptions)

        do {
            // No other ChatPop component currently owns an active audio session.
            // Restore its configuration and notify other audio apps on every exit.
            ownsAudioSession = true
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)

            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
                finish(.unavailable("No microphone input is available. Check your microphone and try again."))
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            // Prefer private on-device recognition. For unsupported device/language combinations,
            // Apple's Speech service may process audio under the system speech permission; ChatPop never uploads it.
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            if #available(iOS 16.0, *) { request.addsPunctuation = true }
            self.request = request
            audioEnded = false

            let capture = DictationAudioCapture(request: request) { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(run), !self.isFinishing else { return }
                    if level > 0.3 { self.lastVoiceAt = ProcessInfo.processInfo.systemUptime }
                    self.onLevel?(level)
                }
            }
            self.capture = capture
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                capture.append(buffer)
            }
            tapInstalled = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(run) else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text != self.transcript {
                            self.lastTranscriptAt = ProcessInfo.processInfo.systemUptime
                            self.transcript = text
                        }
                        if result.isFinal {
                            self.finish(text.isEmpty ? .noSpeech : .transcriptAvailable)
                            return
                        }
                        self.publish(text.isEmpty ? .listening : .recognizing)
                    }
                    if error != nil {
                        if self.isFinishing {
                            self.finish(self.transcript.isEmpty ? .noSpeech : .transcriptAvailable)
                        } else {
                            self.finish(.unavailable("Dictation stopped. Check your connection or microphone and try again."))
                        }
                    }
                }
            }

            engine.prepare()
            try engine.start()
            startedAt = ProcessInfo.processInfo.systemUptime
            lastVoiceAt = startedAt
            lastTranscriptAt = startedAt
            publish(.listening)
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(run) else { return }
                    self.checkTimeouts()
                }
            }
        } catch {
            finish(.unavailable("ChatPop could not start the microphone. Check your audio connection and try again."))
        }
    }

    private func checkTimeouts() {
        let now = ProcessInfo.processInfo.systemUptime
        if isFinishing {
            if now - finishingAt >= 3 {
                finish(transcript.isEmpty ? .noSpeech : .transcriptAvailable)
            }
            return
        }
        if transcript.isEmpty, now - startedAt >= 12 {
            finishRecognition()
        } else if now - startedAt >= 55 {
            finishRecognition()
        } else if !transcript.isEmpty, now - max(lastVoiceAt, lastTranscriptAt) >= 5 {
            finishRecognition()
        }
    }

    private func finishRecognition() {
        isFinishing = true
        finishingAt = ProcessInfo.processInfo.systemUptime
        stopCapture()
        publish(.recognizing)
    }

    private func stopCapture() {
        capture?.close()
        capture = nil
        engine?.stop()
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.reset()
        engine = nil
        if !audioEnded {
            request?.endAudio()
            audioEnded = true
        }
        if ownsAudioSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            if let previousAudioSession {
                try? session.setCategory(previousAudioSession.category,
                                         mode: previousAudioSession.mode,
                                         options: previousAudioSession.options)
            }
            ownsAudioSession = false
            previousAudioSession = nil
        }
        onLevel?(0)
    }

    private func finish(_ state: State) {
        stop()
        publish(state)
    }

    private func publish(_ state: State) {
        onChange?(Snapshot(state: state, transcript: transcript))
    }

    private func isCurrent(_ run: UUID) -> Bool { isActive && generation == run }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let run = self.pendingStartRun, self.isCurrent(run) else { return }
                self.beginCapture(run: run)
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.finish(.unavailable("Dictation paused when ChatPop went to the background. Tap Try Again to continue."))
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.finish(.unavailable("Dictation was interrupted. Tap Try Again when you are ready."))
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ||
                    reason == AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.finish(.unavailable("Your microphone connection changed. Tap Try Again to use the available microphone."))
            }
        })
        for name in [AVAudioSession.mediaServicesWereLostNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isActive else { return }
                    self.finish(.unavailable("iOS audio was reset. Tap Try Again to restart dictation."))
                }
            })
        }
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let changedEngine = notification.object as? AVAudioEngine
            Task { @MainActor [weak self] in
                guard let self, self.isActive, let changedEngine, self.engine === changedEngine else { return }
                self.finish(.unavailable("Your microphone configuration changed. Tap Try Again to continue."))
            }
        })
    }
}

extension NativeDictationSession: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isActive, self.recognizer === speechRecognizer else { return }
            self.finish(.unavailable("Speech recognition became unavailable. Check your connection and try again."))
        }
    }
}

private struct AudioSessionConfiguration {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}

// Audio taps run off the main actor. The gate prevents appending after endAudio/cancel,
// and meters at most 20 times per second without ever retaining or writing audio buffers.
private final class DictationAudioCapture {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let onLevel: (Float) -> Void
    private var previousLevel: Float = 0
    private var lastMeterAt: TimeInterval = 0

    init(request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping (Float) -> Void) {
        self.request = request
        self.onLevel = onLevel
    }

    func close() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let request else { lock.unlock(); return }
        request.append(buffer)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMeterAt >= 0.05, let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            lock.unlock()
            return
        }
        lastMeterAt = now
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frames {
                let sample = buffer.format.isInterleaved ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(frames * channelCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = min(1, max(0, (decibels + 60) / 50))
        let coefficient: Float = normalized > previousLevel ? 0.6 : 0.2
        previousLevel += coefficient * (normalized - previousLevel)
        let level = previousLevel
        lock.unlock()
        onLevel(level)
    }
}
