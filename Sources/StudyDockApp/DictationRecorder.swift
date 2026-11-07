import AVFoundation
import Speech
import SwiftUI
import StudyDockCore

@MainActor
final class DictationRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Phase { case idle, preparing, recording, transcribing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String?
    @Published private(set) var error: String?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var processing: Task<Void, Never>?
    private var sessionID = UUID()

    private(set) var usesModernSpeech = false
    var hasPendingRecording: Bool { phase == .idle && recordingURL != nil }
    #if os(iOS)
    private var audioSessionActive = false
    #endif
    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }

    func level() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        return max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 55) / 55))
    }

    func start() async {
        guard phase == .idle && recordingURL == nil else { return }
        let sessionID = UUID()
        self.sessionID = sessionID
        error = nil
        transcript = nil
        phase = .preparing
        do {
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            try checkSession(sessionID)
            guard microphone else { throw StudyError.message("Allow microphone access in Settings to dictate.") }

            var modern = false
            if #available(macOS 26, iOS 26, *), SpeechTranscriber.isAvailable {
                modern = await SpeechTranscriber.supportedLocale(equivalentTo: .current) != nil
                try checkSession(sessionID)
            }
            usesModernSpeech = modern
            if !modern {
                let permission = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                }
                try checkSession(sessionID)
                guard permission == .authorized else {
                    throw StudyError.message("Allow speech recognition in Settings to dictate.")
                }
                guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                    throw StudyError.message("On-device speech recognition is unavailable for this language.")
                }
            }

            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionActive = true
            #endif
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("studydock-\(sessionID).caf")
            recordingURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16
            ])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            self.recorder = recorder
            // Keep legacy requests under the older recognizer's one-minute limit.
            let started = modern ? recorder.record() : recorder.record(forDuration: 55)
            guard started else { throw StudyError.message("Could not start recording. Check your microphone and try again.") }
            phase = .recording
        } catch {
            guard self.sessionID == sessionID else { return }
            cancel()
            self.error = error.localizedDescription
        }
    }

    func finish() {
        guard phase == .recording else { return }
        transcribe()
    }

    func retry() {
        guard hasPendingRecording else { return }
        transcribe()
    }

    private func transcribe() {
        guard let url = recordingURL else { return }
        phase = .transcribing
        error = nil
        closeRecorder()
        let sessionID = self.sessionID
        let modern = usesModernSpeech
        processing = Task {
            do {
                let text: String
                if modern, #available(macOS 26, iOS 26, *) {
                    text = try await Self.modernTranscript(url)
                } else {
                    text = try await Self.legacyTranscript(url)
                }
                try checkSession(sessionID)
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
                if text.isEmpty { error = "No speech was detected. Try another recording." }
                else { transcript = text }
            } catch {
                if self.sessionID == sessionID {
                    self.error = "Couldn’t finish dictation. \(error.localizedDescription)"
                }
            }
            if self.sessionID == sessionID {
                phase = .idle
                processing = nil
            }
        }
    }

    func cancel() {
        error = nil
        sessionID = UUID()
        phase = .idle
        processing?.cancel()
        processing = nil
        closeRecorder()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            if flag { finish() }
            else {
                cancel()
                error = "Recording was interrupted. Your draft is still here."
            }
        }
    }

    private func checkSession(_ id: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
    }

    private func closeRecorder() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        #if os(iOS)
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        #endif
    }

    @available(macOS 26, iOS 26, *)
    private static func modernTranscript(_ url: URL) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw StudyError.message("This language is unavailable for on-device transcription.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // The transcription preset produces finalized ranges in audio order.
        async let transcript: String = {
            var text: [String] = []
            for try await result in transcriber.results {
                let phrase = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty { text.append(phrase) }
            }
            return text.joined(separator: " ")
        }()

        do {
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await transcript
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func legacyTranscript(_ url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw StudyError.message("On-device speech recognition is unavailable for this language.")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let results = AsyncThrowingStream<SFSpeechRecognitionResult, Error> { continuation in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result { continuation.yield(result) }
                if let error { continuation.finish(throwing: error) }
                else if result?.isFinal == true { continuation.finish() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        var transcript = DictationTranscript()
        for try await result in results {
            let best = result.bestTranscription
            let formatted = best.formattedString as NSString
            let segments = best.segments.enumerated().compactMap { index, segment -> DictationTranscript.Segment? in
                let start = segment.substringRange.location
                let end = index + 1 < best.segments.count ? best.segments[index + 1].substringRange.location : formatted.length
                guard start >= 0, end >= start, end <= formatted.length else { return nil }
                let text = formatted.substring(with: NSRange(location: start, length: end - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .init(start: segment.timestamp, text: text)
            }
            transcript.update(segments, formattedText: best.formattedString)
        }
        try Task.checkCancellation()
        return transcript.text
    }
}
