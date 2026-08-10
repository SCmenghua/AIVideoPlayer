import Foundation

/// 文件来源中已选取视频文件的存取。
public protocol PickedFileStoring: Sendable {
    func loadFiles() -> [PickedVideoFile]
    func addFile(_ file: PickedVideoFile) throws
    func removeFile(id: UUID) throws
}
