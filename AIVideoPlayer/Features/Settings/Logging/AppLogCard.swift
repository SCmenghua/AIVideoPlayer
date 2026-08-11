import SwiftUI

/// 设置页「日志」卡片（Phase 8.13）：
/// - 开关控制日志功能（默认开启）
/// - 导出按钮（分享全部日志文件）
/// - 清空按钮
/// - 显示日志统计信息
struct AppLogCard: View {
    let logger: AppLogger
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false

    var body: some View {
        GlassCard(tint: .indigo) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // 标题栏 + 开关
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日志")
                            .font(.headline)
                        Text("记录应用运行状态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassTogglePill(
                        isOn: logger.isEnabled,
                        onTitle: "关闭",
                        offTitle: "启用",
                        tint: .indigo
                    ) {
                        withAnimation(.snappy) {
                            logger.setEnabled(!logger.isEnabled)
                        }
                    }
                }

                // 统计信息
                HStack(spacing: AppTheme.Spacing.sm) {
                    Label("\(logger.totalEntries) 条", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(logger.isEnabled ? "正在记录" : "已暂停")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(logger.isEnabled ? .green : .secondary)
                }

                // 操作按钮
                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.indigo)
                    .buttonStyle(.bordered)
                    .disabled(logger.totalEntries == 0)

                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label("清空", systemImage: "trash")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    .buttonStyle(.bordered)
                    .disabled(logger.totalEntries == 0)
                }
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
}

/// 系统分享面板
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
