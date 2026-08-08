import Foundation
import SwiftUI

/// 远程文件玻璃行。响应点击，因此使用 `.interactive()`。
struct RemoteFileRow: View {
    let file: RemoteFile
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: file.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(file.kind.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(file.metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(file.kind.tint).interactive(), in: .rect(cornerRadius: AppTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - UI 映射

extension RemoteFile.Kind {
    var systemImage: String {
        switch self {
        case .folder: "folder.fill"
        case .video: "film.fill"
        case .audio: "music.note"
        case .image: "photo.fill"
        case .document: "doc.fill"
        case .other: "questionmark.folder"
        }
    }

    var tint: Color {
        switch self {
        case .folder: .blue
        case .video: .purple
        case .audio: .orange
        case .image: .green
        case .document, .other: .gray
        }
    }
}

extension RemoteFile.Connection {
    var displayName: String {
        switch self {
        case .webdav: "WebDAV"
        case .smb: "SMB"
        case .ftp: "FTP"
        case .local: "本机"
        }
    }
}

extension RemoteFile {
    var metadataText: String {
        let connectionLabel = connection.displayName
        if let size, size > 0 {
            return "\(connectionLabel) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
        return connectionLabel
    }
}
