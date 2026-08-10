import AVFoundation
import Foundation

/// 一段连续的 PCM 音频（单声道 Float32，绝对时间轴）。
/// 注意：与 WhisperKit 内部的 `AudioChunk` 无关，命名避开冲突。
public struct PCMChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let startTime: TimeInterval

    public init(samples: [Float], sampleRate: Double, startTime: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.startTime = startTime
    }

    public var endTime: TimeInterval {
        sampleRate > 0 ? startTime + Double(samples.count) / sampleRate : startTime
    }
}

/// 识别用的 PCM 滚动缓冲（绝对时间轴，只进不退）。
/// 线程安全：音频采集可能在后台线程写入，识别循环在 MainActor 读取。
final class PCMBuffer: @unchecked Sendable {
    private static let maxBufferedDuration: TimeInterval = 120

    private let lock = NSLock()
    private var samples: [Float] = []
    private var baseTime: TimeInterval = 0
    private var sampleRate: Double = 16_000

    var captureStart: TimeInterval {
        lock.withLock { baseTime }
    }

    var sampleRateValue: Double {
        lock.withLock { sampleRate }
    }

    var capturedEnd: TimeInterval {
        lock.withLock { capturedEndLocked() }
    }

    func append(_ chunk: PCMChunk) {
        lock.withLock {
            // 只接受时间轴上向后的数据；旧数据（seek 竞态）直接丢弃。
            // 注意：必须在重置基线之前判定，否则陈旧块会把时间线往回拉。
            guard chunk.endTime > capturedEndLocked() - 0.01 else { return }
            if samples.isEmpty {
                baseTime = chunk.startTime
                sampleRate = chunk.sampleRate
            }
            samples.append(contentsOf: chunk.samples)
            trimFrontLocked()
        }
    }

    /// 提取 [start, end) 区间的采样；数据未完全缓冲时返回 nil。
    func extract(from start: TimeInterval, to end: TimeInterval) -> [Float]? {
        lock.withLock {
            // 范围整体早于捕获起点：数据永远不可能补齐，视为未缓冲。
            guard end > baseTime - 0.01 else { return nil }
            guard end <= capturedEndLocked() + 0.01 else { return nil }
            let rate = sampleRate
            let startIndex = max(0, Int(((start - baseTime) * rate).rounded(.down)))
            let endIndex = min(samples.count, max(startIndex, Int(((end - baseTime) * rate).rounded(.up))))
            guard endIndex > startIndex else { return [] }
            return Array(samples[startIndex..<endIndex])
        }
    }

    /// 重置时间基准并清空缓冲（seek / 模式切换）。
    func reset(to time: TimeInterval) {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            baseTime = time
        }
    }

    /// 丢弃给定时间之前的数据，限制内存占用。
    func discard(before time: TimeInterval) {
        lock.withLock {
            let rate = sampleRate
            let index = Int(((time - baseTime) * rate).rounded(.down))
            guard index > 0 else { return }
            let trimmed = min(index, samples.count)
            if trimmed < samples.count {
                samples.removeFirst(trimmed)
                baseTime += Double(trimmed) / rate
            } else {
                samples.removeAll(keepingCapacity: true)
                baseTime = time
            }
        }
    }

    private func capturedEndLocked() -> TimeInterval {
        sampleRate > 0 ? baseTime + Double(samples.count) / sampleRate : baseTime
    }

    private func trimFrontLocked() {
        let maxSamples = Int(Self.maxBufferedDuration * sampleRate)
        guard samples.count > maxSamples else { return }
        let excess = samples.count - maxSamples
        samples.removeFirst(excess)
        baseTime += Double(excess) / sampleRate
    }
}

/// 音频重采样工具（Whisper 输入固定 16kHz 单声道 Float32）。
enum AudioResampler {
    static let whisperSampleRate: Double = 16_000

    static func resample(
        _ samples: [Float],
        from sourceRate: Double,
        to targetRate: Double
    ) throws -> [Float] {
        guard sourceRate > 0, !samples.isEmpty else { return samples }
        if abs(sourceRate - targetRate) < 0.5 { return samples }

        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw AudioPipelineError.resamplingFailed
        }
        inputBuffer.frameLength = inputBuffer.frameCapacity
        if let channelData = inputBuffer.floatChannelData {
            channelData[0].update(from: samples, count: samples.count)
        }

        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioPipelineError.resamplingFailed
        }

        let outputCapacity = AVAudioFrameCount(Double(samples.count) * targetRate / sourceRate) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AudioPipelineError.resamplingFailed
        }

        var deliveredInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if deliveredInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            deliveredInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status == .haveData || status == .inputRanDry,
              let outputData = outputBuffer.floatChannelData else {
            throw AudioPipelineError.resamplingFailed
        }
        return Array(UnsafeBufferPointer(start: outputData[0], count: Int(outputBuffer.frameLength)))
    }
}
