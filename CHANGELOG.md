# Changelog

本项目的所有重要变更都会记录在此文件中。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 待规划

- Phase 3 播放器全屏/方向需求已记录至架构文档（2026-08-09）。

## [0.7.0] - 2026-08-09

### Added（Phase 7 TranslationEngine 可替换翻译）

- `TranslationEngine` 协议演进：Provider 元数据（ID / 显示名 / 本地性 / 润色支持 / 就绪状态）+
  上下文参数 `TranslationContext`；云端能力协议 `TranslationConnectionTesting`
- Fast NMT Provider：Apple 原生 Translation 框架（iOS 26 `TranslationSession(installedSource:target:)`），
  完全本地、零新依赖；`LanguageAvailability` 语言包可用性检查，未安装 / 不支持给出可读提示
- Cloud LLM Provider：OpenAI 兼容 ChatCompletions（Base URL / API Key / Model 自定义），
  「测试连接」成功 + 隐私提示确认后才允许启用；apiKey 存 Keychain（`KeychainAPIKeyStore`）
- Local LLM Provider：MLX Swift（`mlx-swift-lm` 3.x + `swift-transformers` Tokenizer）本地推理，
  默认模型 Gemma 4 E2B 4-bit（`mlx-community/gemma-4-e2b-it-4bit`，约 3.5 GB）；
  `LocalModelDownloadManager` 从 Hugging Face 按需下载（逐文件进度 / 取消 / 重试 / 删除 / 校验），
  下载完成后才能启用
- `TranslationContextProvider`：剧情理解润色上下文（滑动窗口 + 逐条截断 + 总预算压缩），
  仅本地 / 云端 LLM 使用，Fast NMT 不参与
- `SubtitlePipeline` 接入：final 段翻译后写入 `translatedText`（超前窗口内提前就绪），
  partial 原样透出；翻译期间状态 `.translating`；翻译禁用 / 失败时原样透出原文；
  设置变更重建引擎缓存
- 设置页「翻译服务」卡片：Provider 选择、目标语言（简体中文 / English，留多语言扩展）、
  云端配置 + 测试连接 + 隐私提示、本地模型下载管理、剧情润色开关、启用校验
- SPM 依赖：`ml-explore/mlx-swift-lm`（3.31.3+）、`huggingface/swift-transformers`（1.3.0+）
- 单元测试：翻译设置持久化 / API Key 存储 / 云端 Provider（URLProtocol 桩：翻译、上下文、
  测试连接、HTTP 错误、空内容）/ Fast NMT（元数据、可用性门控、空结果）/ 上下文压缩 /
  下载管理器（完成、失败重试、取消、删除）/ 管线翻译集成（final 翻译、partial 透传、
  禁用透传、失败透传、润色上下文、`.translating` 状态）

### Changed

- `TranslationEngine` 协议签名扩展（元数据 + `context` 参数），协议测试替身同步更新
- 设置页「翻译服务」占位卡片替换为真实卡片；「关于」版本说明更新为 Phase 7
- `SubtitlePipeline` 构造增加翻译设置 / Provider 工厂 / 上下文提供者注入
- `AppEnvironment` 新增 `translationSettings` 与 `localModelDownloadManager` 全局共享

### Fixed

- `FastNMTTranslator` 默认参数引用 `private` 静态方法导致编译失败：
  默认参数值在调用点求值；public init 的默认参数必须引用 public 符号，
  静态方法最终改为 public（2026-08-09）
- `TranslationSettingsViewModel.statusMessage` setter 对设置卡片不可见导致编译失败：
  `private(set)` 改为 internal（ViewModel 为 internal，仅 UI 使用）（2026-08-09）
- `LoadState<Void>` 不满足 Equatable，设置页改用 `if case .loading` 模式匹配判断测试状态（2026-08-09）
- `URLSession.bytes(for:)` 逐字节产出（UInt8）而非 Data 块：
  下载管理器改为 64KB 缓冲后写盘，避免逐字节 IO（2026-08-09）
- `mlx-swift-lm` 的 `ChatSession` 非 Sendable 且未标注隔离，严格并发下调用
  `respond` 报数据竞争：`LocalLLMTranslator` 改用 `@preconcurrency import MLXLMCommon`
  （该模块 API 未适配并发，按迁移惯例放宽检查）（2026-08-09）
- 测试桩 `StubURLProtocol.handler` 声明中 `?` 误绑定到返回元组，导致静态存储属性
  无初始值编译失败：函数类型整体加括号后再标可选（2026-08-09）
- 下载管理器测试中 `phase == .failed` 无法比较带关联值的枚举：
  改为 `if case .failed` 模式匹配（2026-08-09）

## [0.6.0] - 2026-08-09

### Added（Phase 6 SubtitleOverlay 双语整句字幕叠加）

- `SubtitleTimeline`：`SubtitleEngine` 真实实现——按 `startTime` 排序的时间线；
  `segment(at:)` 按播放光标返回当前整句（final 优先于重叠 partial，区间左闭右开）；
  append final 时清理被其覆盖的旧 partial（原始实时路径 partial → final 收敛）；
  500 条内存上限，超出丢弃最旧
- `SubtitleOverlayViewModel`：消费共享 `SubtitlePipeline.segments` 流写入时间线；
  播放光标驱动当前句子（整句一次性出现）；拖动位移换算归一化位置（边界 0.08...0.92）；
  换片 / 管线关闭时清空时间线与当前字幕
- `SubtitleDisplaySettings`：字号（小 / 中 / 大）+ 字幕中心点归一化位置，
  UserDefaults 持久化，提供重置位置；`AppEnvironment` 全局共享（播放器与设置页同一实例）
- `SubtitleOverlay`：双语整句玻璃字幕条（原文 + 译文，译文缺失只显示原文；
  原生 Liquid Glass，无模拟玻璃 API）；整句出现 / 消失动画；`DragGesture` 拖动调整位置
- 播放器接入：`PlayerView` 与 `FullscreenPlayerView` 在「字幕开关开启且管线激活」时
  渲染叠加层，普通与全屏共享同一 ViewModel；换片清空时间线、管线关闭清空当前字幕
- 设置页：新增「字幕显示」卡片（字号选择、重置字幕位置）
- 单元测试：时间线语义（边界 / final 优先 / partial 清理 / update / removeAll /
  内存上限 / 排序）、Overlay ViewModel（流消费 / 光标对齐 / partial→final 收敛 /
  reset / 拖动收敛与持久化 / 字号代理）、显示设置（默认值 / 持久化 / 越界收敛 / 重置）

### Changed

- 播放器叠加字幕层接入普通与全屏两个播放场景；设置页「关于」版本说明更新为 Phase 6

### Fixed

- `SubtitleOverlayViewModelTests` 补 `uniqueSuiteName()` 辅助函数（此前遗漏导致
  CI 测试目标编译失败，并级联产生 `.large` 类型推断错误）（2026-08-09）

## [0.5.0] - 2026-08-09

### Added（Phase 5 WhisperKit 实时识别 + 超前缓冲）

- WhisperKit 接入：SPM 依赖 `argmaxinc/argmax-oss-swift from 1.0.0`（产品 `WhisperKit`，CI 解析 1.1.0）；
  模型随 App 内置（`scripts/fetch-whisper-model.sh` 构建时从 HuggingFace 打包到
  `Resources/Models/whisperkit-coreml`，git 忽略），运行时不下载，无需用户选择；
  音频始终不离开设备
- `AudioPipeline`（AI/Speech）：`AssetReaderAudioPipeline`（AVAssetReader 预读解码，可领先播放光标）、
  `PlayerAudioPipeline`（MTAudioProcessingTap 实时 PCM 捕获，HLS/实时流降级）、
  `MicrophoneAudioPipeline`（WhisperKit AudioProcessor，不可预读，自动走原始实时路径）
- `WhisperKitSpeechRecognizer`：实现 `SpeechRecognizer`，partial / final → `SubtitleSegment` 流；
  窗口转写（重采样 16kHz、special token 清理、置信度近似映射、语言检测）
- `SubtitlePipeline`：真实 `SubtitleStatusProviding`（替换 Mock 注入），七态语义
  LISTENING / TRANSCRIBING / READY / ERROR；领先识别游标只进不退；seek / 设置变更重建窗口并
  丢弃过期 partial / final
- 超前识别设置：开关（默认开启）+ 领先窗口 2–10s（默认 3s），UserDefaults 持久化；
  设置页提供开关与滑块；开启时播放前先预读 Δ 秒音频，Whisper 提前整句转写
- 播放器联动：`PlayerViewModel` 注入共享管线，播放前预读等待、暂停停止识别、seek 重建、
  播放结束停止识别
- 全局共享：`AppEnvironment` 持有 `SubtitleSettings` + `SubtitlePipeline`；
  浏览器首页状态卡与播放器共用同一管线
- 单元测试：设置持久化与边界、PCM 缓冲游标语义、管线状态流转（超前 / 原始 / seek /
  设置变更 / 关闭 / 麦克风降级）、播放器-管线联动探针

### Changed

- `SpeechRecognizer` 协议演进：新增 `discardPendingResults()` 与窗口转写
  `transcribe(samples:sampleRate:windowStart:windowDuration:emitPartial:)`
- `SubtitleStatusCard` 文案更新为「本地内置」；CI 增加 Whisper 模型缓存（避免每次重新下载）

### Fixed

- 模型内置脚本不再调用 HuggingFace API 列表接口（CI 环境返回 401），改为提交固化文件清单
  （`scripts/whisperkit-tiny.manifest`）逐个直链下载；修正 tokenizer 仓库名推导
  （`openai/tiny` → `openai/whisper-tiny`）
- 适配 iOS 26 SDK：`MTAudioProcessingTap` 回调签名更新（prepare/process 参数变化、
  上下文改经 `MTAudioProcessingTapGetStorage` 取回、`MTAudioProcessingTapCreate` 返回
  ARC 托管对象、`MTAudioProcessingTapGetSourceAudio` 新增 `numberFramesOut` 并按实际帧数处理）；
  音频 tap 改经 `AVMutableAudioMixInputParameters.audioTapProcessor` 挂载
- 规避 Swift 6.2 类型推断缺陷：`withAnimation` 泛型闭包内的 `Task` 提取为实例方法；
  三元运算符分支内的闭包字面量改为 if/else 显式赋值
- 修复 `@Observable` + `didSet` 自我赋值导致的无限递归（栈溢出）：`leadAheadWindow`
  边界收敛改为先判等、越界值只回写一次
- 修复 `PCMBuffer` seek 竞态：陈旧音频块不再把时间线往回拉（先判陈旧再重置基线）；
  完全早于捕获起点的区间 `extract` 返回 nil 而非空数组

## [0.2.0] - 2026-08-09

### Added（Phase 2 浏览器 + 远程文件）

- WKWebView 浏览器：真实地址栏、前进/后退/刷新、历史、收藏
- 远程文件：WebDAV 目录浏览（PROPFIND + XML 解析，多级目录导航、面包屑）
- 凭据：Keychain 存储（`KeychainCredentialStore`）；服务器配置持久化（UserDefaults）
- 协议新增：CredentialStoring / RemoteServerProfileStoring / BrowserHistoryStoring / BookmarkStoring；
  RemoteFileBrowsing 演进为 connect / listDirectory / disconnect
- 浏览器与远程文件 ViewModel 独立（BrowserViewModel / RemoteFilesViewModel），依赖注入
- 网络权限声明：ATS Web 内容例外、本地网络访问、局域网使用说明
- 单元测试：WebDAV 解析、历史/收藏/配置存储、凭据存储、浏览器 VM、远程文件 VM

### Changed

- Browser Tab 根视图由 HomeView 改为 BrowserView；HomeView 重构为未打开网页时的首页内容

### Security

- 密码只写入 Keychain；WebDAV 会话凭据在 disconnect 时从内存清除

### Fixed

- WebDAV Multi-Status 解析器：`didEndElement` 修改的是结构体副本导致所有资源被丢弃，
  改为就地修改 `currentResource`（CI 测试失败修复）

## [0.3.0] - 2026-08-09

### Added（Phase 3 播放器）

- `AVPlayerPlaybackEngine`：加载（可取消等待 ready）、播放/暂停/seek/倍速/音量，
  状态流与进度流双观察通道（`stateStream` / `progressStream`）
- `PlaybackEngine` 协议演进：新增 `PlaybackProgress`、只读渲染句柄 `player`；
  `PlaybackState` 去重（当前条目由 `currentItem` 单独跟踪）
- 自定义播放器 UI（**无 AVPlayerViewController**）：玻璃控制栏（播放/暂停、进度条 + 拖动、
  倍速菜单、音量、比例 fit/fill、字幕开关、全屏）
- 画面大小滑块（0.5x-2.0x）实时缩放视频画面
- YouTube 风格全屏：fullScreenCover 隐藏 Tab Bar / 导航栏 / 状态栏；竖屏锁定时可全屏横屏；
  全屏控制栏手动「横屏/竖屏」兜底按钮；iPad 保持多任务支持
- 远程文件视频 → 播放器一键交接（`AppEnvironment.requestPlayback`）
- 播放器空状态调试入口「播放示例媒体」（开发期专用，删除方法见架构文档 8.1.2）
- 单元测试：共享 `MockPlaybackEngine` + `PlayerViewModelTests`

### Changed

- Player Tab 由占位页升级为完整播放器；`PlayerViewModel` 注入 `PlaybackEngine` 并消费双流

### Fixed

- Swift 6 数据竞争：播放结束通知闭包不再跨隔离域传递 `Notification`（改用 `ObjectIdentifier`）
- 倍速菜单数组类型 `[Double]` → `[Float]`，匹配 `setRate(Float)`
- 移除 iOS 16+ 弃用的 `attemptRotationToDeviceOrientation`

### Security

- 播放器渲染只读绑定 AVPlayerLayer，不做任何播放控制（架构红线唯一例外）

## [0.1.0] - 2026-08-09

### Added（Phase 1 基础架构）

- SwiftUI App 初始化与三 Tab（Browser / Player / Settings）导航架构，每个 Tab 独立 NavigationStack
- Liquid Glass Design System：GlassCard / GlassBadge / GlassIconButton / GlassProminentButton /
  GlassTogglePill，基于 iOS 26 原生 `glassEffect` / `GlassEffectContainer` / `.glassProminent`
- 首页：Mock 地址栏、Mock 远程文件列表、AI 字幕状态卡（OFF → LOADING → LISTENING → READY 状态流转演示）
- 核心协议（7 个）：MediaExtractor / PlaybackEngine / SpeechRecognizer / TranslationEngine /
  SubtitleEngine / RemoteFileBrowsing / SubtitleStatusProviding
- 数据模型（7 个）：MediaItem / RemoteFile / SubtitleSegment / AIState / AISubtitleStatus /
  PlaybackState / LoadState
- Mock 实现（4 个）：MockRemoteFiles / MockSubtitleStatus / MockRemoteFileBrowser /
  MockSubtitleStatusProvider
- ViewModel 依赖注入（`browser:` / `provider:`）与可取消 Task（generation 令牌、AsyncStream）
- 单元测试（Swift Testing）：ModelsTests / MockDataTests / ProtocolConformanceTests
- GitHub Actions CI：`xcodegen generate` → `xcodebuild build` → `xcodebuild test`（macOS runner）
- Git 仓库初始化、工程文档（README / ARCHITECTURE / CHANGELOG）

### Fixed

- Mock 远程文件 URL 中非 ASCII 字符强制解包导致的运行时崩溃风险（改为百分号编码 + 安全构造 +
  `preconditionFailure` 断言，移除全部 URL 强制解包）
- iOS 26 `glassEffect` 的 tint 参数为 `Color?`，`.accent` 简写无法编译
  （改为 `Color.accentColor`）
- `#expect` 宏内 `allSatisfy(\.keyPath)` 触发 rethrows 编译错误（改为显式非抛错闭包）
- 测试辅助函数引入 `try #require` 后变为多语句函数，缺失隐式返回（补充显式 `return`）

### Security

- 移除全部 URL 强制解包；新增 Mock 数据 URL 有效性测试（https / host / 全 ASCII）

## [0.4.0] - 2026-08-09

### Added（Phase 4 MediaExtractor）

- `WebMediaExtractor`（Services/Media）：直链媒体（MP4 / MOV / WebM / MP3 / M4A 等）→ 单个
  `MediaItem`（不发起网络请求）；HLS（`.m3u8` / `.m3u`）→ 视频项（AVPlayer 原生处理播放列表）；
  HTML 页面 → 提取 `<video>` / `<source src>` / `data-src`，支持相对地址解析、HTML 实体解码与去重
- 浏览器入口：地址栏“提取视频”按钮 + 结果列表（`MediaExtractionSheet`），点击条目经
  `AppEnvironment.requestPlayback` 一键播放
- 远程文件：`m3u8` / `m3u` 识别为 video，WebDAV 目录中的 HLS 可直接进入播放链路
- 单元测试：`WebMediaExtractorTests`（直链 / HLS / HTML 提取（含 data-src）/ 相对地址 / 去重 /
  DRM 跳过 / 错误与取消）、`BrowserViewModelTests` 提取状态与防过期、`ModelsTests` HLS 映射

### Security

- 不绕过 DRM：只提取普通 HTTP(S) 媒体地址；带 `encrypted` 等加密标记或非 HTTP(S) 协议的
  资源一律跳过，不做任何解密或绕过
