import Foundation
import Testing
@testable import AIVideoPlayer

struct SpeechWindowPlannerTests {
    private let planner = SpeechWindowPlanner()
    private let sampleRate = 1_000.0

    @Test func speechFollowedByPauseProducesVariableRecognitionWindow() {
        let samples = speech(seconds: 1.2) + silence(seconds: 0.5)

        let decision = planner.nextWindow(samples: samples, sampleRate: sampleRate, startTime: 0)
        guard case .transcribe(let window) = decision else {
            Issue.record("Expected a speech window, received \(decision)")
            return
        }
        #expect(abs(window.startTime - 0) < 0.001)
        #expect(abs(window.endTime - 1.2) < 0.001)
    }

    @Test func leadingSilenceIsSkippedBeforeRecognition() {
        let samples = silence(seconds: 0.7) + speech(seconds: 0.4)

        let decision = planner.nextWindow(samples: samples, sampleRate: sampleRate, startTime: 12)
        guard case .skipSilence(let nextTime) = decision else {
            Issue.record("Expected leading silence to be skipped, received \(decision)")
            return
        }
        #expect(abs(nextTime - 12.7) < 0.001)
    }

    @Test func pureSilenceIsSkippedWithoutRecognition() {
        let decision = planner.nextWindow(
            samples: silence(seconds: 2),
            sampleRate: sampleRate,
            startTime: 4
        )
        guard case .skipSilence(let nextTime) = decision else {
            Issue.record("Expected silence to be skipped, received \(decision)")
            return
        }
        #expect(abs(nextTime - 6) < 0.001)
    }

    @Test func uninterruptedSpeechUsesMaximumDurationFallback() {
        let decision = planner.nextWindow(
            samples: speech(seconds: 8),
            sampleRate: sampleRate,
            startTime: 3
        )
        guard case .transcribe(let window) = decision else {
            Issue.record("Expected maximum-length speech window, received \(decision)")
            return
        }
        #expect(abs(window.startTime - 3) < 0.001)
        #expect(abs(window.endTime - 11) < 0.001)
    }

    @Test func unfinishedSpeechWaitsForPauseOrMaximumDuration() {
        #expect(
            planner.nextWindow(
                samples: speech(seconds: 1),
                sampleRate: sampleRate,
                startTime: 0
            ) == .waitForMoreAudio
        )
    }

    @Test func steadyBackgroundToneIsSkippedInsteadOfSentToWhisper() {
        let decision = planner.nextWindow(
            samples: steadyTone(seconds: 8),
            sampleRate: sampleRate,
            startTime: 3
        )

        #expect(decision == .skipSilence(to: 11))
    }

    private func speech(seconds: Double) -> [Float] {
        let frameSize = Int(sampleRate * 0.1)
        return (0..<Int(seconds * sampleRate)).map { index in
            (index / frameSize).isMultiple(of: 2) ? 0.05 : 0.025
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    private func steadyTone(seconds: Double) -> [Float] {
        [Float](repeating: 0.02, count: Int(seconds * sampleRate))
    }
}
