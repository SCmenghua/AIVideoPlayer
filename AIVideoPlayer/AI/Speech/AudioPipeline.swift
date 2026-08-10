import AVFoundation
import CoreMedia
import Foundation
import WhisperKit

/// 音频来源类型。
public enum AudioSourceKind: Sendable, Equatable {
    case player
    case microphone
}

/// 音频管线错误。
public enum AudioPipelineError: LocalizedError, Sendable {
    case captureUnavailable(String)
    case microphonePermissionDenied
    case resamplingFailed
    case noAudioTrack
    case readerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .captureUnavailable(let message):
            "无法采集音频：\(message)"
        case .microphonePermissionDenied:
            "未获得麦克风权限"
        case .resamplingFailed:
            "音频重采样失败"
        case .noAudioTrack:
            "媒体没有音频轨道"
        case .readerFailed(let message):
            "音频读取失败：\(message)"
        }
    }
}

/// 音频管线：向识别器提供连续的 PCM 音频块。
/// 实现：AssetReaderAudioPipeline（AVAssetReader 预读）、
/// PlayerAudioPipeline（AVPlayer 实时 Tap）、MicrophoneAudioPipeline（麦克风）。
@MainActor
public protocol AudioPipeline: AnyObject {
    var sourceKind: AudioSourceKind { get }
    var chunks: AsyncStream<PCMChunk> { get }

    func start(at playbackTime: TimeInterval) async throws
    func stop() async
    /// 重置时间基准并停止当前读取 / 采集；调用方随后调用 `start(at:)` 重新开始。
    func reset(to playbackTime: TimeInterval) async
}

/// 基于 AVAssetReader 的音频管线：以高于实时的速度解码 PCM，向识别器供料。
/// 本地 / 渐进式媒体适用；
/// HLS 等 AVAssetReader 无法读取的来源在 `start` 时抛错，由上层回退到 PlayerAudioPipeline。
@MainActor
public final class AssetReaderAudioPipeline: AudioPipeline {
    public let sourceKind: AudioSourceKind = .player
    public let chunks: AsyncStream<PCMChunk>

    private let item: MediaItem
    private let continuation: AsyncStream<PCMChunk>.Continuation
    private var reader: AVAssetReader?
    private var audioOutput: AVAssetReaderTrackOutput?
    private var consumeTask: Task<Void, Never>?
    private var isRunning = false
    private var baseTime: TimeInterval = 0
    private var accumulatedFrames: Int = 0

    private let sampleRate = AudioResampler.whisperSampleRate

    public init(item: MediaItem) {
        self.item = item
        let pair = AsyncStream<PCMChunk>.makeStream()
        self.chunks = pair.stream
        self.continuation = pair.continuation
    }

    public func start(at playbackTime: TimeInterval) async throws {
        guard !isRunning else { return }
        try await prepareReader(at: playbackTime)
        isRunning = true
        consumeTask = Task { [weak self] in
            await self?.consume()
        }
    }

    public func stop() async {
        isRunning = false
        consumeTask?.cancel()
        consumeTask = nil
        reader?.cancelReading()
        reader = nil
        audioOutput = nil
    }

    public func reset(to playbackTime: TimeInterval) async {
        await stop()
        baseTime = playbackTime
        accumulatedFrames = 0
    }

    // MARK: - Private

    private func prepareReader(at time: TimeInterval) async throws {
        let asset = AVURLAsset(url: item.url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioPipelineError.noAudioTrack
        }

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        output.alwaysCopiesSampleData = true

        let reader = try AVAssetReader(asset: asset)
        guard reader.canAdd(output) else {
            throw AudioPipelineError.readerFailed("无法添加音频输出")
        }
        reader.add(output)

        if time > 0 {
            let start = CMTime(seconds: time, preferredTimescale: 600)
            let duration = try await asset.load(.duration)
            reader.timeRange = CMTimeRange(start: start, duration: duration - start)
        }

        guard reader.startReading() else {
            throw AudioPipelineError.readerFailed(reader.error?.localizedDescription ?? "读取器启动失败")
        }

        self.reader = reader
        self.audioOutput = output
        self.baseTime = time
        self.accumulatedFrames = 0
    }

    private func consume() async {
        while !Task.isCancelled {
            guard let reader, let audioOutput else { return }
            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                switch reader.status {
                case .completed, .cancelled, .failed:
                    return
                case .unknown, .reading:
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                @unknown default:
                    return
                }
            }

            if let floats = Self.convertToFloat(sampleBuffer) {
                let start = baseTime + Double(accumulatedFrames) / sampleRate
                accumulatedFrames += floats.count
                continuation.yield(
                    PCMChunk(samples: floats, sampleRate: sampleRate, startTime: start)
                )
            }
        }
    }

    private static func convertToFloat(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer else { return nil }
        let sampleCount = length / MemoryLayout<Int16>.size
        return dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Pointer in
            UnsafeBufferPointer(start: int16Pointer, count: sampleCount)
                .map { Float($0) / 32_768.0 }
        }
    }
}

/// 基于 AVPlayer 实时渲染的音频管线：用 MTAudioProcessingTap 捕获 PCM。
/// 只能实时取到「正在播放」的音频。
@MainActor
public final class PlayerAudioPipeline: AudioPipeline {
    public let sourceKind: AudioSourceKind = .player
    public let chunks: AsyncStream<PCMChunk>

    private let engine: any PlaybackEngine
    private let continuation: AsyncStream<PCMChunk>.Continuation
    private let tapBox: TapBox
    private var captureTap: MTAudioProcessingTap?
    private var isRunning = false
    private var baseTime: TimeInterval = 0

    public init(engine: any PlaybackEngine) {
        self.engine = engine
        let pair = AsyncStream<PCMChunk>.makeStream()
        self.chunks = pair.stream
        self.continuation = pair.continuation
        self.tapBox = TapBox(continuation: pair.continuation)
    }

    public func start(at playbackTime: TimeInterval) async throws {
        guard !isRunning else { return }
        guard let player = engine.player, let item = player.currentItem else {
            throw AudioPipelineError.captureUnavailable("播放器未加载媒体")
        }
        baseTime = playbackTime
        tapBox.resetTime(base: playbackTime)
        try installTap(on: item)
        isRunning = true
    }

    public func stop() async {
        isRunning = false
        removeTap()
    }

    public func reset(to playbackTime: TimeInterval) async {
        await stop()
        baseTime = playbackTime
    }

    // MARK: - Tap

    private func installTap(on item: AVPlayerItem) throws {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(tapBox).toOpaque(),
            init: Self.tapInit,
            finalize: Self.tapFinalize,
            prepare: Self.tapPrepare,
            unprepare: Self.tapUnprepare,
            process: Self.tapProcess
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapRef
        )
        guard status == noErr, let tap = tapRef else {
            throw AudioPipelineError.captureUnavailable("无法创建音频采集 Tap")
        }

        captureTap = tap
        let inputParams = AVMutableAudioMixInputParameters()
        inputParams.trackID = kCMPersistentTrackID_Invalid
        inputParams.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [inputParams]
        item.audioMix = mix
    }

    private func removeTap() {
        if let player = engine.player, let item = player.currentItem {
            item.audioMix = nil
        }
        captureTap = nil
    }

    // MARK: - C callbacks（音频线程）

    private static let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    private static let tapFinalize: MTAudioProcessingTapFinalizeCallback = { _ in }

    /// iOS 26 SDK：prepare 不再传 clientInfo，上下文通过 MTAudioProcessingTapGetStorage 取回。
    private static let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, formatOut in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<TapBox>.fromOpaque(storage).takeUnretainedValue()
            .updateFormat(formatOut.pointee)
    }

    private static let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

    /// iOS 26 SDK：process 回调签名为
    /// (tap, numberOfFrames, flags, bufferListInOut, numberFramesOut, flagsOut)。
    private static let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberOfFrames, _, bufferListInOut, numberFramesOut, flagsOut in
        var timeRange = CMTimeRange()
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberOfFrames,
            bufferListInOut,
            flagsOut,
            &timeRange,
            numberFramesOut
        )
        guard status == noErr else { return }
        // 只处理实际取到的帧数，避免轨道末尾读到无效数据。
        let framesToProcess = min(numberOfFrames, numberFramesOut.pointee)
        guard framesToProcess > 0 else { return }
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<TapBox>.fromOpaque(storage).takeUnretainedValue()
            .process(bufferListInOut, frameCount: framesToProcess)
    }
}

/// Tap 回调上下文：音频线程写入，锁保护格式信息；AsyncStream continuation 线程安全。
private final class TapBox: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<PCMChunk>.Continuation
    private var sampleRate: Double = 44_100
    private var channelsPerFrame: UInt32 = 1
    private var isInterleaved = false
    private var isFloatFormat = true
    private var baseTime: TimeInterval = 0
    private var accumulatedFrames: Double = 0

    init(continuation: AsyncStream<PCMChunk>.Continuation) {
        self.continuation = continuation
    }

    func updateFormat(_ format: AudioStreamBasicDescription) {
        lock.withLock {
            sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
            channelsPerFrame = max(format.mChannelsPerFrame, 1)
            isInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            // Tap 可能交付 Float32 或 Int16 PCM；按格式位判断，避免按 Float 强读越界。
            isFloatFormat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        }
    }

    func resetTime(base: TimeInterval) {
        lock.withLock {
            baseTime = base
            accumulatedFrames = 0
        }
    }

    func process(_ bufferListPointer: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let (rate, base, accumulated, channels, interleaved, isFloat) = lock.withLock {
            (sampleRate, baseTime, accumulatedFrames, Int(channelsPerFrame), isInterleaved, isFloatFormat)
        }
        guard rate > 0 else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        guard !buffers.isEmpty else { return }

        var floats = [Float](repeating: 0, count: frameCount)
        if interleaved {
            guard let firstData = buffers[0].mData else { return }
            let stride = max(channels, 1)
            if isFloat {
                let pointer = firstData.assumingMemoryBound(to: Float.self)
                let count = min(frameCount, Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size / stride)
                for index in 0..<count {
                    floats[index] = pointer[index * stride]
                }
            } else {
                let pointer = firstData.assumingMemoryBound(to: Int16.self)
                let count = min(frameCount, Int(buffers[0].mDataByteSize) / MemoryLayout<Int16>.size / stride)
                for index in 0..<count {
                    floats[index] = Float(pointer[index * stride]) / 32_768.0
                }
            }
        } else {
            var mixed = [Float](repeating: 0, count: frameCount)
            var activeChannels = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                if isFloat {
                    let pointer = data.assumingMemoryBound(to: Float.self)
                    let count = min(frameCount, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                    for index in 0..<count {
                        mixed[index] += pointer[index]
                    }
                } else {
                    let pointer = data.assumingMemoryBound(to: Int16.self)
                    let count = min(frameCount, Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size)
                    for index in 0..<count {
                        mixed[index] += Float(pointer[index]) / 32_768.0
                    }
                }
                activeChannels += 1
            }
            let scale = 1 / Float(max(activeChannels, 1))
            floats = mixed.map { $0 * scale }
        }

        let startTime = base + accumulated / rate
        lock.withLock { accumulatedFrames += Double(frameCount) }
        continuation.yield(
            PCMChunk(samples: floats, sampleRate: rate, startTime: startTime)
        )
    }
}

/// 麦克风音频管线：WhisperKit AudioProcessor 实时采集（partial → final）。
@MainActor
public final class MicrophoneAudioPipeline: AudioPipeline {
    public let sourceKind: AudioSourceKind = .microphone
    public let chunks: AsyncStream<PCMChunk>

    private let continuation: AsyncStream<PCMChunk>.Continuation
    private let processor: any AudioProcessing
    private var consumeTask: Task<Void, Never>?
    private var isRunning = false
    private var baseTime: TimeInterval = 0
    private var accumulatedFrames: Double = 0

    private let sampleRate = AudioResampler.whisperSampleRate

    public init(processor: any AudioProcessing = AudioProcessor()) {
        self.processor = processor
        let pair = AsyncStream<PCMChunk>.makeStream()
        self.chunks = pair.stream
        self.continuation = pair.continuation
    }

    public func start(at playbackTime: TimeInterval) async throws {
        guard !isRunning else { return }
        guard await AudioProcessor.requestRecordPermission() else {
            throw AudioPipelineError.microphonePermissionDenied
        }

        baseTime = playbackTime
        accumulatedFrames = 0
        let (stream, _) = processor.startStreamingRecordingLive(inputDeviceID: nil)
        consumeTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await samples in stream {
                    guard !samples.isEmpty else { continue }
                    let start = self.baseTime + self.accumulatedFrames / self.sampleRate
                    self.accumulatedFrames += Double(samples.count)
                    self.continuation.yield(
                        PCMChunk(samples: samples, sampleRate: self.sampleRate, startTime: start)
                    )
                }
            } catch {
                // 采集结束 / 失败：静默退出，状态由上层管理。
            }
        }
        isRunning = true
    }

    public func stop() async {
        isRunning = false
        consumeTask?.cancel()
        consumeTask = nil
        processor.stopRecording()
    }

    public func reset(to playbackTime: TimeInterval) async {
        await stop()
        baseTime = playbackTime
        accumulatedFrames = 0
    }
}
