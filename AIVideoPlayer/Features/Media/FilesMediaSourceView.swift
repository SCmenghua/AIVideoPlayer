import SwiftUI
import UniformTypeIdentifiers

/// 文件媒体来源：从文件 App 选取视频（安全作用域书签持久化），点击播放。
struct FilesMediaSourceView: View {
    let viewModel: MediaSourcesViewModel
    let onPlayMedia: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.pickedFiles.isEmpty {
                    ContentUnavailableView {
                        Label("还没有视频文件", systemImage: "folder")
                    } description: {
                        Text("从文件 App 添加视频后即可播放。")
                    } actions: {
                        Button("添加视频文件") { showsPicker = true }
                    }
                } else {
                    List {
                        ForEach(viewModel.pickedFiles) { file in
                            Button {
                                play(file)
                            } label: {
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: "film")
                                        .foregroundStyle(.tint)
                                    Text(file.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.removePickedFile(file)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("文件视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加视频文件")
                }
            }
        }
        .sheet(isPresented: $showsPicker) {
            VideoDocumentPicker { urls in
                viewModel.addPickedFiles(urls: urls)
            }
        }
    }

    private func play(_ file: PickedVideoFile) {
        guard let url = viewModel.resolvePickedFileURL(file) else { return }
        onPlayMedia(
            MediaItem(
                title: file.name,
                url: url,
                kind: .video,
                source: .local
            )
        )
    }
}

/// 文件 App 视频选择器（支持多选，返回安全作用域 URL）。
private struct VideoDocumentPicker: UIViewControllerRepresentable {
    let onPicked: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        )
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: dismiss)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPicked: ([URL]) -> Void
        private let dismiss: DismissAction

        init(onPicked: @escaping ([URL]) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPicked(urls)
            dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }
    }
}
