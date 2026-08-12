import SwiftUI

/// 璁剧疆椤碉細AI 瀛楀箷銆佸瓧骞曡瑷€銆佸瓧骞曟樉绀恒€佺炕璇戞湇鍔°€佽瘖鏂笌鏃ュ織銆侀殣绉佷笌鍏充簬銆?struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                aiSubtitleCard
                subtitleLanguageCard
                subtitleDisplayCard
                diagnosticsCard
                translationCard
                sectionCard(
                    icon: "lock.shield",
                    tint: .green,
                    title: "闅愮",
                    lines: [
                        "杩滅▼璐﹀彿瀵嗙爜浠呬繚瀛樺湪鏈満 Keychain锛圥hase 2锛?,
                        "涓嶆敹闆嗚棰戙€佸瓧骞曘€佹祻瑙堝巻鍙叉垨鏈嶅姟鍣ㄦ枃浠跺垪琛?,
                    ]
                )
                sectionCard(
                    icon: "info.circle",
                    tint: .purple,
                    title: "鍏充簬",
                    lines: [
                        "AI Video Player 路 Phase 8.18锛堥暱瑙嗛鍗￠】淇 + 璇婃柇涓績锛?,
                        "iOS 26 路 Swift 6 路 SwiftUI",
                    ]
                )
            }
            .padding(AppTheme.Spacing.md)
        }
        .navigationTitle("璁剧疆")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleSubtitlePipeline() {
        Task { await environment.subtitlePipeline.toggle() }
    }

    // MARK: - LLM 设置 (本地模型 + API Key)锛圥hase 7锛?
    private var translationCard: some View {
        TranslationSettingsCard()
    }

    // MARK: - 璇婃柇涓庢棩蹇楋紙Phase 8.18 浜岀骇鑿滃崟锛?
    private var diagnosticsCard: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            GlassCard(tint: .indigo) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("璇婃柇涓庢棩蹇?)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("瀛楀箷璁板綍 路 缈昏瘧璁板綍 路 鏃ュ織")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI 瀛楀箷锛圥hase 5锛?
    private var aiSubtitleCard: some View {
        GlassCard(tint: .blue) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "waveform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 瀹炴椂瀛楀箷")
                            .font(.headline)
                        Text("鏈湴 WhisperKit锛屾ā鍨嬪凡鍐呯疆")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassTogglePill(
                        isOn: environment.subtitlePipeline.isActive,
                        onTitle: "鍏抽棴",
                        offTitle: "鍚敤",
                        tint: .blue
                    ) {
                        withAnimation(.snappy) {
                            toggleSubtitlePipeline()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text("璇嗗埆鐘舵€侊細\(environment.subtitlePipeline.status.state.title)")
                        .font(.caption.weight(.medium))
                    Text("妯″瀷锛歕(environment.subtitlePipeline.status.isModelLoaded ? "宸插姞杞? : "鏈姞杞?)"
                        + (environment.subtitlePipeline.status.language.map { " 路 璇嗗埆璇█锛歕($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("宸茶浆鍐?\(environment.subtitlePipeline.transcribedWindowCount) 涓獥鍙?路 宸蹭骇鍑?\(environment.subtitlePipeline.emittedSegmentCount) 鏉″瓧骞?路 宸茬炕璇?\(environment.subtitlePipeline.translatedSegmentCount) 鏉?)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("闊抽姘歌繙涓嶄細绂诲紑璁惧銆?)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 瀛楀箷璇█锛圥hase 8.6锛?
    private var subtitleLanguageCard: some View {
        SubtitleLanguageCard()
    }

    private func sectionCard(icon: String, tint: Color, title: String, lines: [String]) -> some View {
        GlassCard(tint: tint) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(title)
                        .font(.headline)
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 瀛楀箷鏄剧ず锛圥hase 6锛?
    private var subtitleDisplayCard: some View {
        GlassCard(tint: .cyan) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "captions.bubble")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("瀛楀箷鏄剧ず")
                            .font(.headline)
                        Text("鎾斁鍣ㄥ彔鍔犲眰锛氬瓧鍙蜂笌浣嶇疆")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Picker("瀛楀彿", selection: fontSizeBinding) {
                    ForEach(SubtitleFontSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    environment.subtitleDisplaySettings.resetPosition()
                } label: {
                    HStack {
                        Text("閲嶇疆瀛楀箷浣嶇疆")
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .tint(.cyan)
            }
        }
    }

    private var fontSizeBinding: Binding<SubtitleFontSize> {
        Binding(
            get: { environment.subtitleDisplaySettings.fontSize },
            set: { environment.subtitleDisplaySettings.fontSize = $0 }
        )
    }
}
