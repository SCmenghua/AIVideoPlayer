import AVFoundation
import Photos
import SwiftUI

/// 相册媒体来源：列出系统相册中的视频，点击交给内置播放器。
struct PhotoLibraryVideosView: View {
    let onPlayMedia: (MediaItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var authorization: PHAuthorizationStatus = .notDetermined
    @State private var assets: [PHAsset] = []

    var body: some View {
        NavigationStack {
            Group {
                switch authorization {
                case .authorized, .limited:
                    content
                case .denied, .restricted:
                    ContentUnavailableView(
                        "没有相册权限",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("请在系统设置中允许访问照片后再试。")
                    )
                case .notDetermined:
                    ProgressView("正在请求相册权限…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    ContentUnavailableView(
                        "无法访问相册",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .navigationTitle("相册视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await requestAuthorizationAndLoad()
        }
    }

    private var content: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView("相册中没有视频", systemImage: "video.slash")
            } else {
                List(assets, id: \.localIdentifier) { asset in
                    Button {
                        play(asset)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            PhotoThumbnailView(
                                asset: asset,
                                targetSize: CGSize(width: 72, height: 72)
                            )
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: asset))
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(formatDuration(asset.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func requestAuthorizationAndLoad() async {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        authorization = status
        guard status == .authorized || status == .limited else { return }

        let fetchResult = PHAsset.fetchAssets(with: .video, options: nil)
        assets = (0..<fetchResult.count).compactMap { fetchResult.object(at: $0) }
    }

    private func play(_ asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let title = title(for: asset)

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            // 在回调线程上解析可播放 URL（导出另有回调），只把 Sendable 的 URL 交给主线程。
            Self.resolvePlayableURL(avAsset: avAsset, asset: asset) { url in
                Task { @MainActor in
                    guard let url else { return }
                    onPlayMedia(
                        MediaItem(
                            title: title,
                            url: url,
                            kind: .video,
                            source: .local
                        )
                    )
                }
            }
        }
    }

    private static func resolvePlayableURL(
        avAsset: AVAsset?,
        asset: PHAsset,
        completion: @escaping (URL?) -> Void
    ) {
        if let urlAsset = avAsset as? AVURLAsset, let url = urlAsset.url {
            completion(url)
            return
        }
        // 无法直接取得 URL（如 iCloud 资源）时导出到临时目录。
        guard let resource = PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .video }) else {
            completion(nil)
            return
        }
        let ext = (resource.originalFilename as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "mov" : ext)
        PHAssetResourceManager.default().writeData(for: resource, toFileURL: url, options: nil) { error in
            completion(error == nil ? url : nil)
        }
    }

    private func title(for asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset)
            .first?.originalFilename ?? "视频 \(asset.localIdentifier)"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 相册视频缩略图（按需请求，避免一次性加载全部）。
private struct PhotoThumbnailView: View {
    let asset: PHAsset
    let targetSize: CGSize
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                guard let result else { return }
                // 回调可能在线程池：只把可 Sendable 的编码数据交给主线程。
                let data = result.jpegData(compressionQuality: 0.8)
                Task { @MainActor in
                    guard let data, let uiImage = UIImage(data: data) else { return }
                    image = uiImage
                }
            }
        }
    }
}
