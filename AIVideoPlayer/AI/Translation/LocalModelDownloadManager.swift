import Foundation
import Observation

/// 本地 LLM 模型下载管理（Hugging Face 直链，进度 / 失败重试 / 取消 / 删除）。
@MainActor
@Observable
public final class LocalModelDownloadManager {
    public enum Phase: Equatable {
        case idle
        case downloading(file: String, fraction: Double)
        case verifying
        case completed
        case failed(String)
        case cancelled

        public var isBusy: Bool {
            switch self {
            case .downloading, .verifying: true
            case .idle, .completed, .failed, .cancelled: false
            }
        }
    }

    public let descriptor: LocalModelDescriptor
    public private(set) var phase: Phase = .idle

    private let fileManager: FileManager
    private let session: URLSession
    private let directoryProvider: (String) -> URL
    private var currentTask: Task<Void, Never>?

    public init(
        descriptor: LocalModelDescriptor,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        directoryProvider: @escaping (String) -> URL = LocalModelStorage.directory(for:)
    ) {
        self.descriptor = descriptor
        self.fileManager = fileManager
        self.session = session
        self.directoryProvider = directoryProvider
    }

    public var isModelDownloaded: Bool {
        let directory = directoryProvider(descriptor.id)
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        return descriptor.requiredFiles.allSatisfy { file in
            let url = directory.appendingPathComponent(file)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return false
            }
            return size > 0
        }
    }

    public var modelSizeLabel: String { descriptor.sizeLabel }

    /// 开始下载（幂等：进行中再次调用忽略）。
    public func start() {
        guard currentTask == nil else { return }
        phase = .idle
        currentTask = Task { [weak self] in
            await self?.runDownload()
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// 删除已下载模型（含临时文件）。
    public func deleteModel() async throws {
        cancel()
        let directory = directoryProvider(descriptor.id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        phase = .idle
    }

    // MARK: - 下载

    private func runDownload() async {
        defer { currentTask = nil }
        let directory = directoryProvider(descriptor.id)
        do {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            for file in descriptor.requiredFiles {
                try Task.checkCancellation()
                let url = try Self.resolveURL(repoID: descriptor.id, file: file)
                var request = URLRequest(url: url)
                request.timeoutInterval = 120
                phase = .downloading(file: file, fraction: 0)
                let (bytes, response) = try await session.bytes(for: request)
                try Task.checkCancellation()
                let expected = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
                let destination = directory.appendingPathComponent(file)
                let temp = directory.appendingPathComponent(file + ".part")
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                fileManager.createFile(atPath: temp.path, contents: nil)
                let handle = try FileHandle(forWritingTo: temp)
                var received: Int64 = 0
                do {
                    for try await chunk in bytes {
                        try Task.checkCancellation()
                        try handle.write(contentsOf: chunk)
                        received += Int64(chunk.count)
                        if expected > 0 {
                            phase = .downloading(
                                file: file,
                                fraction: min(max(Double(received) / Double(expected), 0), 1)
                            )
                        }
                    }
                } catch {
                    try? handle.close()
                    throw error
                }
                try handle.close()
                try Task.checkCancellation()
                // 校验非空后原子替换临时文件。
                let attributes = try fileManager.attributesOfItem(atPath: temp.path)
                guard (attributes[.size] as? Int ?? 0) > 0 else {
                    throw LocalModelDownloadError.emptyFile(file)
                }
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: temp, to: destination)
            }
            phase = .verifying
            guard isModelDownloaded else {
                throw LocalModelDownloadError.verificationFailed
            }
            phase = .completed
        } catch is CancellationError {
            phase = .cancelled
        } catch let error as URLError where error.code == .cancelled {
            phase = .cancelled
        } catch {
            phase = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private static func resolveURL(repoID: String, file: String) throws -> URL {
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        guard let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)") else {
            throw LocalModelDownloadError.invalidURL(file)
        }
        return url
    }
}

/// 本地模型下载错误。
public enum LocalModelDownloadError: LocalizedError, Sendable {
    case invalidURL(String)
    case emptyFile(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let file):
            "无法构造下载地址（\(file)）。"
        case .emptyFile(let file):
            "下载文件为空（\(file)）。"
        case .verificationFailed:
            "模型文件校验失败，请重试。"
        }
    }
}
