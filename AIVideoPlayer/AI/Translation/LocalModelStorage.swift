import Foundation

/// 本地模型文件目录管理（Application Support/Models/<slug>）。
public enum LocalModelStorage {
    public static func directory(for modelID: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let slug = modelID.replacingOccurrences(of: "/", with: "--")
        return base
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
    }

    public static func isDownloaded(_ modelID: String, files: [String]) -> Bool {
        let directory = directory(for: modelID)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        return files.allSatisfy { file in
            let url = directory.appendingPathComponent(file)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return false
            }
            return size > 0
        }
    }

    public static func remove(_ modelID: String) throws {
        let directory = directory(for: modelID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
