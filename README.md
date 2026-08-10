# AI Video Player

> iOS 26 原生视频播放器 —— PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器

一个长期维护的个人 iOS 项目：在 iOS 26+ 上提供 App 内网页浏览、WebDAV / SMB / FTP 远程文件访问、
自动识别媒体资源并用自有播放器播放、Whisper 本地实时语音识别与双语 AI 字幕。UI 严格遵循
iOS 26 原生 Liquid Glass 设计规范，架构面向可扩展与长期维护。
字幕采用「AI 先听一步」的超前识别设计：播放器先缓存 2–10 秒音频，Whisper 提前转写并翻译，
字幕按整句一次出现，并支持拖动与样式调整（详见下文「AI 实时字幕：超前识别」）。

## 当前功能（Phase 7）

- 三 Tab 入口：Browser / Player / Settings，各自独立 NavigationStack，系统 Liquid Glass Tab Bar
- Liquid Glass Design System：玻璃卡片、状态胶囊、图标按钮、强调按钮、开关（原生 `glassEffect` /
  `GlassEffectContainer` / `.glassProminent`，无任何 `.blur()` / `.opacity()` 模拟玻璃）
- 浏览器：真实玻璃地址栏（前进/后退/刷新）、WKWebView 网页浏览、历史（去重 + 上限）、收藏
- 浏览器地址栏：右侧「清空当前网址」按钮，一键清空输入
- 浏览器视频接管：视频默认内联播放（不跳转系统全屏播放器）；点击直链媒体
  （mp4 / m3u8 / 音频）或播放页面内 HTML5 视频时，由内置播放器接管
- 远程文件：WebDAV 目录浏览（PROPFIND，多级目录导航 + 面包屑），连接表单与已保存服务器一键重连
- 凭据安全：密码只存 Keychain；服务器配置 / 历史 / 收藏持久化（UserDefaults）
- 首页（未打开网页时）：AI 字幕状态卡（OFF → LOADING → LISTENING → READY 状态流转演示）+ 远程文件区
- 播放器：AVPlayer 引擎（播放/暂停/进度/倍速/音量/seek）+ 自定义 SwiftUI 播放器（无 AVPlayerViewController）
- 玻璃控制栏：进度条、倍速菜单、音量、画面比例（fit/fill）、画面大小滑块（0.5x-2.0x）、字幕开关、全屏
- YouTube 风格全屏：隐藏 Tab Bar / 导航栏 / 状态栏；竖屏锁定时可横屏；全屏控制栏手动横屏/竖屏兜底；iPad 多任务
- 远程文件视频 → 播放器一键交接；播放器空状态含开发期调试入口（删除方法见架构文档 8.1.2）
- 设置页（隐私承诺与后续功能占位）
- 核心协议层（12 个协议）与数据模型（12 个模型）；ViewModel 依赖注入；所有 Task 可取消
- 单元测试（Swift Testing）：模型、Mock 数据、WebDAV 解析、存储、浏览器与远程文件 ViewModel、
  AI 字幕管线（PCM 缓冲游标 / 设置持久化与边界 / 超前与实时路径 / seek 重建 / 播放器联动）、协议测试替身
- GitHub Actions CI：`xcodegen generate` → `xcodebuild build` → `xcodebuild test`
- 媒体提取（Phase 4）：`WebMediaExtractor` 从网页提取 HTML5 video / MP4 / HLS / M3U8，不绕过 DRM；
  浏览器地址栏「提取视频」按钮一键列出可播放媒体并交给自有播放器
- 远程 HLS：WebDAV 目录中的 `.m3u8` / `.m3u` 识别为视频，可直接播放
- AI 实时字幕（Phase 5）：WhisperKit 本地实时识别，模型随 App 内置（构建时打包，运行时不下载、
  无需用户选择——只有 Phase 7 翻译用的大模型才由用户选择下载）；音频永不离开设备
- 超前识别（Lead-Ahead）：设置页开关（默认开启）+ 领先窗口 2–10s（默认 3s）；
  播放前先预读 Δ 秒音频，Whisper 提前整句转写；关闭后回到 partial → final 逐词实时路径；
  HLS / 麦克风等不可预读来源自动降级为实时路径
- 播放器联动：播放前预读等待、暂停停止识别、seek 重建领先窗口、识别游标只进不退；
  浏览器首页 AI 状态卡与播放器共用同一管线
- 字幕叠加层（Phase 6）：双语整句字幕（原文 + 译文，译文缺失只显示原文），
  按播放光标对齐一次性出现；原生 Liquid Glass 玻璃条；DragGesture 拖动调整位置
  （归一化坐标持久化）；字号小 / 中 / 大三档；设置页「字幕显示」卡片可调字号与重置位置
- 字幕时间线（Phase 6）：`SubtitleTimeline` 实现 `SubtitleEngine`——final 优先于
  partial、final 到达自动收敛逐词残留、500 条内存上限；普通播放与全屏播放共享同一叠加层
- 可替换翻译引擎（Phase 7）：`TranslationEngine` 单一协议 + 三类 Provider——
  Fast NMT（Apple 原生翻译，完全本地）/ 本地大模型（MLX Swift + Gemma 4 E2B 4-bit，
  按需从 Hugging Face 下载约 3.5 GB，进度 / 取消 / 重试 / 删除）/ 云端 API
  （OpenAI 兼容，Base URL / API Key / Model 自定义，测试连接 + 隐私提示，API Key 存 Keychain）
- 剧情理解润色（Phase 7）：本地 / 云端 LLM 可选开关，`TranslationContextProvider`
  结合最近字幕上下文翻译并自动压缩（滑动窗口 + 截断 + 预算），Fast NMT 不参与
- 字幕翻译接入（Phase 7）：final 段识别后立即翻译并写入译文，超前窗口内提前就绪；
  翻译禁用 / 失败时只显示原文；翻译期间状态卡显示 TRANSLATING
- 设置页「翻译服务」卡片（Phase 7）：Provider 选择、目标语言（简体中文 / English，
  留多语言扩展）、云端配置与测试连接、本地模型下载管理、启用校验

## 技术栈

| 类别 | 技术 |
|---|---|
| 语言 | Swift 6（严格并发） |
| UI | SwiftUI（iOS 26 Liquid Glass API） |
| 并发 | Swift Concurrency / AsyncStream / Observation |
| 媒体 | AVFoundation / AVPlayer（已接入）；HTML5 video / HLS 提取（Phase 4 已接入） |
| 浏览器 | WKWebView（已接入） |
| AI | WhisperKit / Core ML（本地识别，模型内置）；MLX Swift（mlx-swift-lm，本地 LLM 推理） |
| 翻译 | 可替换 TranslationEngine（Phase 7 已接入）：Apple Translation / 本地 LLM（Gemma 4 E2B，按需下载）/ 云端 OpenAI 兼容 API |
| 网络 | URLSession、WebDAV（已接入）；SMB / FTP 后续补充 |
| 存储 | Keychain 凭据（已接入）、UserDefaults 配置/历史/收藏；SwiftData（仅必要时） |
| 工程 | XcodeGen（`project.yml` 生成 `.xcodeproj`） |
| 测试 | Swift Testing |
| CI | GitHub Actions（macOS runner） |

## 环境要求

- macOS（可安装 Xcode 26 的版本）
- Xcode 26+（含 iOS 26 SDK）
- XcodeGen（`brew install xcodegen`）
- 可选：GitHub 账号（用于 CI）

> Windows 无法编译 iOS 应用，只能用于编辑与查看源码。

## 在 macOS + Xcode 运行

```bash
# 1. 安装 XcodeGen（一次性）
brew install xcodegen

# 2. 生成 Xcode 工程（在仓库根目录执行）
xcodegen generate

# 3. 打开工程
open AIVideoPlayer.xcodeproj

# 4. 运行：选择 AIVideoPlayer scheme，选 iOS 26 模拟器，Cmd+R
# 5. 测试：Cmd+U
```

命令行构建与测试：

```bash
# 构建（模拟器，免签名）
xcodebuild build -project AIVideoPlayer.xcodeproj -scheme AIVideoPlayer \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

# 测试
xcodebuild test -project AIVideoPlayer.xcodeproj -scheme AIVideoPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```

> `AIVideoPlayer.xcodeproj` 由 `project.yml` 生成，不提交到版本库。

## 打包 IPA（自签安装）

仓库提供两个 GitHub Actions 手动工作流：

1. **Package IPA (unsigned)**（推荐日常测试）：构建未签名 IPA，同时上传为
   Actions 工件并发布到 GitHub Release（可填版本号，默认 0.8.0）；
2. **Build & Release IPA**：构建未签名 IPA 并创建 GitHub Release
   （`AIVideoPlayer-<版本>-unsigned.ipa`，可填版本号，默认 0.8.0）。

两者均构建**未签名的 iphoneos Release 版**，打包成标准 `Payload/` 结构的 IPA；
用自签工具（Sideloadly / AltStore / 爱思助手 等）导入 IPA，用自己的 Apple ID 签名安装。

**版本约定**：同一 Phase 内每打包一次 IPA，下一次打包版本递增一个小版本
（上一次 `0.x.y` → 下一次 `0.x.(y+1)`），文档中的 Phase 编号同步递增。
当前基线 0.8.0（Phase 8.0），下一次打包应为 0.8.1（Phase 8.1）。

> IPA 未签名，必须经自签工具重签；需要 iOS 26 及以上设备。

## 当前阶段状态

- ✅ Phase 1 完成：App 骨架、Liquid Glass Design System、首页（Mock）、核心协议与模型、单元测试、CI 通过
- ✅ Phase 2 完成：WKWebView 浏览器（地址栏/历史/收藏）+ WebDAV 远程文件 + Keychain 凭据，CI 通过
- ✅ Phase 3 完成：AVPlayer 播放器 + YouTube 风格全屏横屏（画面大小滑块、手动横屏兜底），CI 通过
- ✅ Phase 4 完成：MediaExtractor（HTML5 video / MP4 / HLS / M3U8，不绕过 DRM），CI 通过
- ✅ Phase 5 完成：WhisperKit 实时识别 + 超前缓冲（AudioPipeline / SpeechRecognizer / 真实状态管线；
  模型内置；超前开关与 Δ 配置），CI 通过
- ✅ Phase 6 完成：SubtitleOverlay 双语整句字幕叠加（按播放光标对齐、拖动、样式；
  SubtitleTimeline / SubtitleDisplaySettings / 单元测试），CI 通过
- ✅ Phase 7 完成：TranslationEngine 可替换翻译（Fast NMT（Apple 原生翻译）/ 本地 LLM
  （MLX Swift + Gemma 4 E2B 4-bit，按需下载）/ 云端 API（OpenAI 兼容，测试连接 + 隐私提示）；
  剧情理解润色；final 段提前翻译；设置页「翻译服务」卡片；单元测试），CI 通过
- ✅ Phase 7.5 完成：整体 Debug（浏览器命令修复、换片字幕串台修复、过期字幕丢弃、
  WebDAV 凭据清理、下载取消竞态、播放器加载超时、音频 Tap 格式加固、云端隐私校验、
  CI 编译失败修复）+ 实测完善（地址栏清空按钮、浏览器视频接入内置播放器、内置示例视频）
- ✅ Phase 7.6 完成：播放器换片复位（先初始化再加载、旧加载取消 + 世代守卫、
  进度/状态复位）+ 手动初始化按钮与失败重试，CI 通过
- ✅ Phase 7.7 完成：播放器状态与进度修复（换片先暂停避免自动播放、
  状态机禁止 playing 被 ready 回退、HLS/时长未就绪时进度条兜底），CI 通过
- ✅ Phase 7.8 完成：播放器状态与进度兜底（引擎 play/pause/seek 直接维护权威状态、
  引擎节拍器周期推送进度、VM 双通道同步（流 + 轮询）、时长未知时进度条禁用），CI 通过
- ✅ Phase 7.9 完成：播放器细节优化（设置二级菜单、删除音量、视频横竖屏检测与
  全屏默认方向、横/竖屏单按钮切换）+ 浏览器主页标签页、返回主页与左缘右滑返回，CI 通过
- ✅ Phase 7.10 完成：横屏识别修复（preferredTransform + 全屏入口重新检测）、
  横/竖屏切换修复（刷新方向掩码 + 失败重试）+ 主页媒体来源
  （网络 WebDAV / 相册，多来源展示），CI 通过
- ✅ Phase 7.11 完成：实测反馈修复——相册视频导出后播放（修复崩溃）、
  文件来源改用系统 fileImporter、媒体来源编辑模式删除、全屏自动横屏
  检测与旋转重试优化，CI 通过
- ✅ Phase 7.12 完成：文件来源导入改为复制到 App 沙盒
  （Documents/MediaFiles），修复书签授权跨启动失效导致的导入失败，CI 通过
- ✅ Phase 7.13 完成：移除文件来源导入功能（多次修复未稳定，保留枚举值与
  占位入口便于后期恢复），媒体来源保留 WebDAV 与相册，CI 通过
- 🔄 Phase 8.0 进行中：修复语音识别字幕链路——播放器字幕开关自动激活识别管线、
  播放中途激活用真实播放时间重建游标、模型加载期识别循环自动重试；
  内置普通话测试视频 test.mp4 + 正确转写 test.txt 供回归验证
  （当前基线 0.8.0 / Phase 8.0，2026-08-10 打包）

## 后续开发路线

| Phase | 内容 | 状态 |
|---|---|---|
| 1 | 基础架构 / Liquid Glass / 首页 / 协议 / 测试 / CI | ✅ 完成 |
| 2 | WKWebView 浏览器、WebDAV（SMB / FTP 后续补充）、Keychain 凭据 | ✅ 完成 |
| 3 | AVPlayer 播放器 + YouTube 风格全屏横屏体验（不依赖 AVPlayerViewController，系统竖屏锁定时仍可全屏横屏） | ✅ 完成 |
| 4 | MediaExtractor（HTML5 video / MP4 / HLS / M3U8，不绕过 DRM） | ✅ 完成 |
| 5 | WhisperKit 本地实时识别（AudioPipeline + SpeechRecognizer；播放器缓存 2–10s，AI 领先转写，整句输出；模型内置） | ✅ 完成 |
| 6 | SubtitleOverlay（双语、整句按播放光标对齐一次性出现、拖动、样式） | ✅ 完成 |
| 7 | TranslationEngine：Fast NMT（Apple 原生翻译）/ 本地 LLM（MLX Swift + Gemma 4 E2B，按需下载）/ 云端 API（OpenAI 兼容，测试连接 + 隐私提示）+ 剧情理解润色（自动压缩文本）；识别后立即提前翻译，延迟被超前窗口吸收 | ✅ 完成 |
| 7.5 | 成品 Debug + 实测反馈完善（浏览器命令修复、视频接管、内置示例视频、地址栏清空按钮、打包 action） | ✅ 完成 |
| 7.6 | 播放器换片复位（先初始化再加载、旧加载取消 + 世代守卫）+ 手动初始化按钮 | ✅ 完成 |
| 7.7 | 播放器状态与进度修复（播放按钮状态错乱、进度条兜底、版本 0.7.7） | ✅ 完成 |
| 7.8 | 播放器状态与进度兜底（权威状态 + 节拍器 + VM 双通道 + 时长未知禁拖，版本 0.7.8） | ✅ 完成 |
| 7.9 | 播放器细节优化（设置二级菜单、删除音量、横竖屏检测与默认方向、横/竖屏单按钮）+ 主页标签页（版本 0.7.9） | ✅ 完成 |
| 7.10 | 横屏识别与方向切换修复 + 主页媒体来源（WebDAV / 相册）（版本 0.7.10） | ✅ 完成 |
| 7.11 | 实测反馈修复（相册崩溃 / 文件选择器 / 来源删除 / 自动横屏）（版本 0.7.11） | ✅ 完成 |
| 7.12 | 文件来源导入复制到 App 沙盒（修复跨启动访问失效）（版本 0.7.12） | ✅ 完成 |
| 7.13 | 移除文件来源导入（保留扩展点与占位入口），媒体来源保留 WebDAV / 相册（版本 0.7.13） | ✅ 完成 |
| 7.14+ | 播放器功能收尾（每次打包版本递增 0.7.x → 0.7.(x+1)，Phase 编号同步） | ⬜ 未开始 |
| 8 | 修好语音识别功能与翻译功能（当前为半成品状态）；8.0 已修复字幕输出链路 | 🔄 进行中 |
| 9 & 9+ | Liquid Glass 深化（变形过渡）、性能、测试与错误处理 | ⬜ 未开始 |

#### AI 实时字幕：超前识别（设计提案）

实时字幕默认不做「边听边出」的逐词模式，而是让 AI 管线领先播放光标 2–10 秒
（可配置，默认建议 3 秒）：播放器先缓冲 Δ 秒音频，Whisper 提前分析领先窗口并整句转写，
翻译紧随其后提前完成；字幕仍按播放光标对齐，句子开始时整句一次性显示原文 + 译文。
识别与翻译延迟被吸收在超前窗口内，不叠加到用户可见延迟上。
归属 Phase 5/6/7，详细设计见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 8.2.1。

- 该功能是设置页开关，**默认开启**；关闭后回到原始实时路径：不预缓冲，
  Whisper 输出 partial → final 逐词字幕，识别完成后即时翻译。
- 仅启用 Fast NMT（本地 / 轻量 NMT）时也能正常工作：本地翻译耗远小于 Δ 秒窗口，
  不依赖本地 / 云端 LLM，字幕同样按时整句出现。
- Whisper 模型随 App 内置（构建脚本从 HuggingFace 打包，git 忽略，CI 有缓存）；
  应用内没有任何模型下载 / 选择步骤。

> 严格执行 Phase 顺序，禁止提前实现后续 Phase。详细规划见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，
> 变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 目录结构

```text
AIVideoPlayer/
├── project.yml               # XcodeGen 工程定义（唯一事实来源）
├── PROJECT_CONTEXT.md        # 项目上下文速览（Phase 状态 / 禁止事项 / 技术栈）
├── .github/workflows/        # GitHub Actions CI
├── docs/ARCHITECTURE.md      # 架构决策与 Phase 规划
├── AIVideoPlayer/            # App 源码
│   ├── App/                  # 入口、Tab、路由、全局状态
│   ├── DesignSystem/         # Liquid Glass 组件与设计令牌
│   ├── Features/             # Browser / Player / Subtitle / Settings
│   ├── Core/                 # Protocols、Models、Mock
│   ├── AI/                   # Speech / Translation（Phase 5/7）
│   ├── Services/             # 业务服务（Playback / MediaExtractor）
│   └── Utilities/
└── Tests/AIVideoPlayerTests  # 单元测试（Swift Testing）
```

## 架构红线（摘要）

- View → ViewModel → Protocol → Service/Framework；View 禁止直接接触 AVPlayer、URLSession、WhisperKit。
- 单个 View 不超过 300 行；禁止把逻辑堆进 `ContentView.swift`。
- 所有 async Task 支持取消；状态显式表达 Loading / Ready / Error / Empty / Cancelled。
- UI 严格使用 iOS 26 原生 Liquid Glass API，禁止 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃；
  Liquid Glass 实现遵循 `liquid-glass-design` skill
  （`.agents/skills/liquid-glass-design/SKILL.md`：GlassEffectContainer / 交互 / 变形过渡等）。
- 隐私优先：视频/音频不上传、Whisper 本地运行、凭据只存本机 Keychain。

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
