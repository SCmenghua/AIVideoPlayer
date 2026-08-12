import SwiftUI

/// 诊断页「日志」内容列表（Phase 8.18）：
/// - 展示内存中最近日志（最新在上）；
/// - 按级别着色，支持导出与清空。
struct AppLogList: View {
    let logger: AppLogger
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Label("\(logger.totalEntries) 条", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showShareSheet = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                }
                .tint(.indigo)
                .buttonStyle(.bordered)
                .disabled(logger.totalEntries == 0)

                Button {
                    showClearConfirmation = true
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .tint(.red)
                .buttonStyle(.bordered)
                .disabled(logger.totalEntries == 0)
            }

            if logger.entries.isEmpty {
                Text("暂无日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppTheme.Spacing.xs)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(logger.entries.reversed())) { entry in
                            logRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [logger.exportLogs()])
        }
        .confirmationDialog(
            "确认清空日志",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空所有日志", role: .destructive) {
                logger.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有已记录的日志（\(logger.totalEntries) 条），此操作不可撤销。")
        }
    }

    private func logRow(_ entry: AppLogger.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.level.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Self.tint(for: entry.level))
                Text(entry.category)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func tint(for level: AppLogger.Level) -> Color {
        switch level {
        case .debug: .gray
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

/// 系统分享面板
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}