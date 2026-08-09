# AI Video Player Project Context

## 产品目标

一个长期维护的个人 iOS 项目：iOS 26 原生视频播放器，目标形态为
「PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器」。

核心能力：App 内网页浏览、WebDAV / SMB / FTP 远程文件访问、自动识别可播放媒体、
自有 AVPlayer 播放、完整播放器 UI、Whisper 本地实时语音识别、AI 双语字幕、
可替换翻译架构、原生 Liquid Glass UI。

质量目标：高质量、可扩展、可维护、性能稳定、符合 Apple 原生设计规范。

## 当前Phase

**Phase 8-10**（规划中）：Liquid Glass 深化（变形过渡）、性能、测试与错误处理。
上一阶段：**Phase 7 —— TranslationEngine（Fast NMT / 本地 LLM / 云端 API 三类可替换 Provider；
识别后立即提前翻译，延迟被超前窗口吸收）**（已完成）。

## 设计提案（AI 先听一步：超前实时字幕）

实时字幕不做「边听边出」的逐词模式，而是让 AI 管线领先播放光标 2–10 秒
（可配置，默认建议 3 秒）：

- 播放器先缓冲 Δ 秒音频，Whisper 提前分析领先窗口内的音频并整句转写；
- 翻译紧随识别提前完成（Phase 7），识别 + 翻译延迟被 Δ 窗口吸收；
- 字幕仍按播放光标对齐，句子开始时整句一次性显示原文 + 译文；
- 设置页提供开关，默认开启；关闭后回到原始实时路径（不预缓冲，Whisper 逐词
  partial → final，识别完成后即时翻译）；
- 仅启用 Fast NMT Provider（本地 / 轻量 NMT）也能按时整句出字幕，不依赖本地 / 云端 LLM；
- 归属 Phase 5（超前音频缓冲 + 领先识别游标）/ Phase 6（整句字幕显示）/ Phase 7（提前翻译），
  详见 docs/ARCHITECTURE.md 8.2.1。

## 工作流程（提交约定）

- **每次任务结束后都要 push**：功能完成或文档修改完成后，及时 commit 并 push 到远端，
  不留未提交的改动。
- **push 前区分是否需要 CI**：
  - 纯文档改动（`*.md` / `docs/**`）：CI 已配置 `paths-ignore`，push 不会触发 CI，
    **无需再加 `[skip ci]` 标记**；
  - **禁止把带 `[skip ci]` 的提交与代码提交合并到同一次 push**：GitHub 会因一次 push 中
    任意提交含跳过标记（`[skip ci]` / `[ci skip]` 等）而跳过整个 push 的工作流；
    若确要使用 `[skip ci]`，文档提交必须单独 push（2026-08-09 曾因此导致 CI 未触发）；
  - 涉及代码的改动：push 会触发 CI，需确保改动通过编译 / 测试后再提交，
    不需要主动关注 CI 结果。
- **CI 结果由用户告知，Codex 不主动关注**：提交后的 CI 运行结果不轮询、不主动跟踪，
  由用户通知；若 CI 失败，用户下载失败日志发送给 Codex 进行排查修复；
  若 CI 成功，则直接进行收尾。

## 已完成

- **Phase 1**：App 骨架、三 Tab（Browser / Player / Settings）、Liquid Glass Design System、
  核心协议与模型、Mock、单元测试、GitHub Actions CI。
- **Phase 2**：WKWebView 浏览器（真实地址栏/历史/收藏）、WebDAV 远程文件浏览
  （PROPFIND + 多级目录导航）、Keychain 凭据、服务器配置与历史/收藏持久化。
- **Phase 3**：`AVPlayerPlaybackEngine`（播放/暂停/进度/倍速/音量/seek，状态流 + 进度流）、
  自定义播放器 UI（**无 AVPlayerViewController**）、玻璃控制栏、画面大小滑块（0.5x-2.0x）、
  YouTube 风格全屏（隐藏 Tab/Nav/状态栏、竖屏锁定时可横屏、手动横屏兜底按钮）、
  远程文件视频 → 播放器交接、播放器空状态调试入口（开发期专用，删除说明见架构文档 8.1.2）。
- **Phase 4**：`WebMediaExtractor`（Services/Media，直链媒体 / HLS / HTML5 video 提取，
  相对地址解析、HTML 实体解码、去重；不绕过 DRM）、浏览器地址栏「提取视频」按钮 +
  结果列表（`MediaExtractionSheet`）→ `AppEnvironment.requestPlayback`、远程文件 `m3u8` / `m3u`
  识别为 video、单元测试（提取器 / 浏览器提取状态 / HLS 映射）。
- **Phase 5**：WhisperKit（`argmax-oss-swift from 1.0.0`，CI 解析 1.1.0）本地实时识别；模型随 App 内置
  （构建脚本打包，运行时不下载、无需用户选择）；`AudioPipeline` 三来源
  （AVAssetReader 预读 / MTAudioProcessingTap 实时 / 麦克风）、`WhisperKitSpeechRecognizer`、
  真实 `SubtitlePipeline`（替换 Mock 注入）；超前识别开关（默认开）+ 2–10s 领先窗口（默认 3s，
  UserDefaults 持久化）；播放器播放前预读 Δ 秒、seek 重建领先窗口、识别游标只进不退；
  状态卡与设置页接入真实管线；单元测试（设置 / 缓冲 / 管线 / 播放器联动）。
- **Phase 6**：`SubtitleTimeline`（SubtitleEngine 真实实现：final 优先于 partial、
  final 到达收敛逐词残留、500 条内存上限）；`SubtitleOverlay` 双语整句字幕叠加
  （按播放光标对齐一次性出现、DragGesture 拖动调整位置、字号样式）；
  `SubtitleDisplaySettings`（字号 + 归一化位置，UserDefaults 持久化，AppEnvironment 共享）；
  播放器普通 / 全屏接入、设置页「字幕显示」卡片；单元测试（时间线 / Overlay VM / 显示设置）。
- **Phase 7**：TranslationEngine 可替换翻译架构——Fast NMT（Apple 原生翻译，完全本地）/
  本地 LLM（MLX Swift + Gemma 4 E2B 4-bit，按需下载 + 进度 / 取消 / 重试 / 删除）/ 云端 API
  （OpenAI 兼容，测试连接 + 隐私提示，API Key 存 Keychain）；剧情理解润色（上下文压缩）；
  final 段提前翻译写入 `SubtitleSegment.translatedText`，翻译期间 `.translating` 状态；
  设置页「翻译服务」卡片；单元测试。
- **文档**：README / ARCHITECTURE / CHANGELOG / PROJECT_CONTEXT；纯文档改动不触发 CI。

## 禁止事项

- **禁止使用 `AVPlayerViewController`**：播放器必须使用 AVPlayer + SwiftUI 自定义 UI。
- **禁止伪 Liquid Glass**：禁止用 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃；
  必须使用 iOS 26 原生 `glassEffect` / `GlassEffectContainer` / `.glass` / `.glassProminent`。
- **Liquid Glass 实现必须遵循 `liquid-glass-design` skill**：所有玻璃组件、交互与变形过渡
  按 `D:\code\CodeX\.agents\skills\liquid-glass-design\SKILL.md` 编写；
  新增或修改玻璃 UI 前先阅读该 skill（多玻璃元素放入 `GlassEffectContainer`、
  仅交互元素加 `.interactive()`、变形过渡用 `@Namespace` + `glassEffectID` 等）。
- **禁止跳 Phase**：严格按 Phase 顺序开发，禁止提前实现后续 Phase。
- **纯文档内容、不涉及程序代码的部分禁止触发 CI**：CI push 触发已配置
  `paths-ignore: *.md, docs/**`，纯文档提交无需 `[skip ci]` 标记；
  **禁止把带 `[skip ci]` 的提交与代码提交合并到同一次 push**（GitHub 会跳过整个 push 的工作流）。

> 附加架构红线（详见 docs/ARCHITECTURE.md）：View 禁止直接处理 AVPlayer / URLSession / WhisperKit
> （渲染句柄绑定 AVPlayerLayer 除外）；单个 View ≤ 300 行；禁止 URL 强制解包；
> 禁止私有 API 旋转（如 `UIDevice.setValue`）；所有 Task 可取消；状态显式表达
> Loading / Ready / Error / Empty / Cancelled。

## 技术栈

| 类别 | 技术 |
|---|---|
| 语言 | Swift 6（严格并发） |
| UI | SwiftUI（iOS 26 Liquid Glass API） |
| 并发 | Swift Concurrency / AsyncStream / Observation |
| 媒体 | AVFoundation / AVPlayer（已接入）；HTML5 video / HLS 提取（Phase 4 已接入） |
| 浏览器 | WKWebView（已接入） |
| 远程文件 | URLSession + WebDAV PROPFIND（已接入）；SMB / FTP 后续补充 |
| 安全存储 | Keychain（已接入）、UserDefaults |
| AI | WhisperKit / Core ML（Phase 5 已接入，本地运行；模型内置；超前缓冲识别 2–10s） |
| 翻译 | 可替换 TranslationEngine（Phase 7 已接入：Apple Translation / MLX Swift 本地 LLM（Gemma 4 E2B，按需下载）/ 云端 OpenAI 兼容 API；API Key 存 Keychain） |
| 工程 | XcodeGen（project.yml 生成工程） |
| 测试/CI | Swift Testing；GitHub Actions（xcodegen + xcodebuild build/test，macOS runner） |
