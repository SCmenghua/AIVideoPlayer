import Foundation

/// Plans variable-length Whisper input windows from PCM energy rather than a fixed clock interval.
/// The planner is independent from AVFoundation and WhisperKit so its boundary rules are testable.
struct SpeechWindowPlanner: Sendable {
    struct Configuration: Sendable {
        let analysisFrameDuration: TimeInterval
        let minimumSpeechDuration: TimeInterval
        let trailingSilenceDuration: TimeInterval
        let maximumWindowDuration: TimeInterval
        let speechEnergyThreshold: Float
        let minimumSpeechEnergyRange: Float

        init(
            analysisFrameDuration: TimeInterval = 0.1,
            minimumSpeechDuration: TimeInterval = 0.4,
            trailingSilenceDuration: TimeInterval = 0.5,
            maximumWindowDuration: TimeInterval = 8,
            speechEnergyThreshold: Float = 0.008,
            minimumSpeechEnergyRange: Float = 0.004
        ) {
            self.analysisFrameDuration = analysisFrameDuration
            self.minimumSpeechDuration = minimumSpeechDuration
            self.trailingSilenceDuration = trailingSilenceDuration
            self.maximumWindowDuration = maximumWindowDuration
            self.speechEnergyThreshold = speechEnergyThreshold
            self.minimumSpeechEnergyRange = minimumSpeechEnergyRange
        }
    }

    struct Window: Equatable, Sendable {
        let startTime: TimeInterval
        let endTime: TimeInterval

        var duration: TimeInterval {
            endTime - startTime
        }
    }

    enum Decision: Equatable, Sendable {
        case waitForMoreAudio
        case skipSilence(to: TimeInterval)
        case transcribe(Window)
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func nextWindow(
        samples: [Float],
        sampleRate: Double,
        startTime: TimeInterval
    ) -> Decision {
        guard sampleRate > 0,
              configuration.analysisFrameDuration > 0,
              configuration.maximumWindowDuration > 0
        else {
            return .waitForMoreAudio
        }

        let samplesPerFrame = max(1, Int((sampleRate * configuration.analysisFrameDuration).rounded()))
        let frameCount = samples.count / samplesPerFrame
        guard frameCount > 0 else { return .waitForMoreAudio }

        let maximumFrameCount = max(
            1,
            Int((configuration.maximumWindowDuration / configuration.analysisFrameDuration).rounded(.down))
        )
        let usableFrameCount = min(frameCount, maximumFrameCount)
        let frameDuration = Double(samplesPerFrame) / sampleRate
        let speechFrame = firstSpeechFrame(
            in: samples,
            frameCount: usableFrameCount,
            samplesPerFrame: samplesPerFrame
        )

        guard let speechFrame else {
            return .skipSilence(to: startTime + Double(usableFrameCount) * frameDuration)
        }

        // Skip leading quiet audio before asking Whisper to decode an utterance.
        guard speechFrame == 0 else {
            return .skipSilence(to: startTime + Double(speechFrame) * frameDuration)
        }

        let requiredSpeechFrames = max(
            1,
            Int((configuration.minimumSpeechDuration / frameDuration).rounded(.up))
        )
        let requiredSilenceFrames = max(
            1,
            Int((configuration.trailingSilenceDuration / frameDuration).rounded(.up))
        )

        var silenceRun = 0
        for frameIndex in 0..<usableFrameCount {
            if isSpeechFrame(samples, frameIndex: frameIndex, samplesPerFrame: samplesPerFrame) {
                silenceRun = 0
                continue
            }

            silenceRun += 1
            guard silenceRun >= requiredSilenceFrames else { continue }

            let speechFrameCount = frameIndex - silenceRun + 1
            if speechFrameCount >= requiredSpeechFrames {
                let window = Window(
                    startTime: startTime,
                    endTime: startTime + Double(speechFrameCount) * frameDuration
                )
                return hasEnoughSpeechVariation(
                    samples,
                    frameCount: speechFrameCount,
                    samplesPerFrame: samplesPerFrame
                ) ? .transcribe(window) : .skipSilence(to: window.endTime)
            }

            // Ignore isolated clicks and other short non-speech sounds.
            return .skipSilence(to: startTime + Double(frameIndex + 1) * frameDuration)
        }

        if usableFrameCount == maximumFrameCount {
            let window = Window(
                startTime: startTime,
                endTime: startTime + Double(usableFrameCount) * frameDuration
            )
            return hasEnoughSpeechVariation(
                samples,
                frameCount: usableFrameCount,
                samplesPerFrame: samplesPerFrame
            ) ? .transcribe(window) : .skipSilence(to: window.endTime)
        }

        return .waitForMoreAudio
    }

    private func firstSpeechFrame(
        in samples: [Float],
        frameCount: Int,
        samplesPerFrame: Int
    ) -> Int? {
        for frameIndex in 0..<frameCount {
            if isSpeechFrame(samples, frameIndex: frameIndex, samplesPerFrame: samplesPerFrame) {
                return frameIndex
            }
        }
        return nil
    }

    private func isSpeechFrame(
        _ samples: [Float],
        frameIndex: Int,
        samplesPerFrame: Int
    ) -> Bool {
        let lowerBound = frameIndex * samplesPerFrame
        let upperBound = lowerBound + samplesPerFrame
        let thresholdSquared = configuration.speechEnergyThreshold * configuration.speechEnergyThreshold
        var energy: Float = 0

        for sample in samples[lowerBound..<upperBound] {
            energy += sample * sample
        }
        return energy / Float(samplesPerFrame) >= thresholdSquared
    }

    /// A steady tone or amplified room noise can pass an RMS threshold while containing no speech.
    /// Require some frame-to-frame energy movement before it is sent to Whisper.
    private func hasEnoughSpeechVariation(
        _ samples: [Float],
        frameCount: Int,
        samplesPerFrame: Int
    ) -> Bool {
        guard configuration.minimumSpeechEnergyRange > 0 else { return true }

        var lowestEnergy = Float.greatestFiniteMagnitude
        var highestEnergy: Float = 0
        for frameIndex in 0..<frameCount {
            let energy = rootMeanSquare(
                samples,
                frameIndex: frameIndex,
                samplesPerFrame: samplesPerFrame
            )
            guard energy >= configuration.speechEnergyThreshold else { continue }
            lowestEnergy = min(lowestEnergy, energy)
            highestEnergy = max(highestEnergy, energy)
        }
        return highestEnergy - lowestEnergy >= configuration.minimumSpeechEnergyRange
    }

    private func rootMeanSquare(
        _ samples: [Float],
        frameIndex: Int,
        samplesPerFrame: Int
    ) -> Float {
        let lowerBound = frameIndex * samplesPerFrame
        let upperBound = lowerBound + samplesPerFrame
        var energy: Float = 0
        for sample in samples[lowerBound..<upperBound] {
            energy += sample * sample
        }
        return (energy / Float(samplesPerFrame)).squareRoot()
    }
}
