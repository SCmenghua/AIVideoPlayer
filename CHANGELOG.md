# Changelog

本项目的所有重要变更都会记录在此文件中。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 待规划

- 当前主线为 Phase 6（SubtitleOverlay：双语、整句按播放光标对齐一次性出现、拖动、样式）。
- Phase 3 播放器全屏/方向需求已记录至架构文档（2026-08-09）。
- Phase 7 翻译引擎需求扩充已记录至架构文档：Fast NMT / 本地 LLM / 云端 API 三类 Provider +
  剧情理解润色（自动压缩文本；Fast NMT 直接翻译、不参与上下文润色）（2026-08-09）。
- 设计提案「AI 先听一步」已记录至架构文档（8.2.1）：播放器缓存 2–10s，Whisper 提前转写，
  翻译紧随其后提前完成，字幕按整句对齐播放光标一次性出现（归属 Phase 5/6/7）（2026-08-09）。
- 超前识别补充：新增开关（默认开启，关闭走原始 partial → final 实时路径）；
  仅启用 Fast NMT Provider 时也能提前翻译、按时整句显示字幕，不依赖本地 / 云端 LLM（2026-08-09）。
- Phase 7 翻译引擎需求补充：本地 LLM 模型不随 App 预置，由用户选择并从 Hugging Face 按需下载，
  下载完成后可用；云端 API 填入 key 后提供「测试连接」按钮（2026-08-09）。

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
