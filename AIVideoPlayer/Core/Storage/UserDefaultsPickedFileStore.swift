import Foundation

/// 基于 UserDefaults 的已选取视频文件存储（书签 JSON 编码）。
public struct UserDefaultsPickedFileStore: PickedFileStoring {
    private static let key = "media.pickedFiles.v1"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func loadFiles() -> [PickedVideoFile] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PickedVideoFile].self, from: data)) ?? []
    }

    public func addFile(_ file: PickedVideoFile) throws {
        var files = loadFiles()
        files.removeAll { $0.id == file.id }
        files.insert(file, at: 0)
        let data = try JSONEncoder().encode(files)
        defaults.set(data, forKey: Self.key)
    }

    public func removeFile(id: UUID) throws {
        var files = loadFiles()
        files.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(files)
        defaults.set(data, forKey: Self.key)
    }
}
