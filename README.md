# AI Video Player

> iOS 26 原生视频播放器 —— PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器

一个长期维护的个人 iOS 项目：在 iOS 26+ 上提供 App 内网页浏览、WebDAV / SMB / FTP 远程文件访问、
自动识别媒体资源并用自有播放器播放、Whisper 本地实时语音识别与双语 AI 字幕。UI 严格遵循
iOS 26 原生 Liquid Glass 设计规范，架构面向可扩展与长期维护。

## 当前功能（Phase 2）

- 三 Tab 入口：Browser / Player / Settings，各自独立 NavigationStack，系统 Liquid Glass Tab Bar
- Liquid Glass Design System：玻璃卡片、状态胶囊、图标按钮、强调按钮、开关（原生 `glassEffect` /
  `GlassEffectContainer` / `.glassProminent`，无任何 `.blur()` / `.opacity()` 模拟玻璃）
- 浏览器：真实玻璃地址栏（前进/后退/刷新）、WKWebView 网页浏览、历史（去重 + 上限）、收藏
- 远程文件：WebDAV 目录浏览（PROPFIND，多级目录导航 + 面包屑），连接表单与已保存服务器一键重连
- 凭据安全：密码只存 Keychain；服务器配置 / 历史 / 收藏持久化（UserDefaults）
- 首页（未打开网页时）：AI 字幕状态卡（OFF → LOADING → LISTENING → READY 状态流转演示）+ 远程文件区
- 播放器占位页（玻璃播放按钮与控制组）、设置页（隐私承诺与后续功能占位）
- 核心协议层（11 个协议）与数据模型（11 个模型）；ViewModel 依赖注入；所有 Task 可取消
- 单元测试（Swift Testing）：模型、Mock 数据、WebDAV 解析、存储、浏览器与远程文件 ViewModel、协议测试替身
- GitHub Actions CI：`xcodegen generate` → `xcodebuild build` → `xcodebuild test`

## 技术栈

| 类别 | 技术 |
|---|---|
| 语言 | Swift 6（严格并发） |
| UI | SwiftUI（iOS 26 Liquid Glass API） |
| 并发 | Swift Concurrency / AsyncStream / Observation |
| 媒体 | AVFoundation / AVPlayer（Phase 3 接入） |
| 浏览器 | WKWebView（已接入） |
| AI | WhisperKit / Core ML（本地运行，Phase 5 接入） |
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

## 当前阶段状态

- ✅ Phase 1 完成：App 骨架、Liquid Glass Design System、首页（Mock）、核心协议与模型、单元测试、CI 通过
- ✅ Phase 2 完成：WKWebView 浏览器（地址栏/历史/收藏）+ WebDAV 远程文件 + Keychain 凭据，CI 通过
- ⬜ Phase 3 尚未开始：AVPlayer 播放器

## 后续开发路线

| Phase | 内容 | 状态 |
|---|---|---|
| 1 | 基础架构 / Liquid Glass / 首页 / 协议 / 测试 / CI | ✅ 完成 |
| 2 | WKWebView 浏览器、WebDAV（SMB / FTP 后续补充）、Keychain 凭据 | ✅ 完成 |
| 3 | AVPlayer 播放器 + YouTube 风格全屏横屏体验（不依赖 AVPlayerViewController，系统竖屏锁定时仍可全屏横屏） | ⬜ 未开始 |
| 4 | MediaExtractor（HTML5 video / MP4 / HLS / M3U8，不绕过 DRM） | ⬜ 未开始 |
| 5 | WhisperKit 本地实时识别（AudioPipeline + SpeechRecognizer） | ⬜ 未开始 |
| 6 | SubtitleOverlay（双语、时间同步、拖动、样式） | ⬜ 未开始 |
| 7 | TranslationEngine：Fast NMT / 本地 LLM / 云端 API 三类 Provider + 剧情理解润色（仅 LLM Provider，自动压缩文本）+ 隐私提示 | ⬜ 未开始 |
| 8-10 | Liquid Glass 深化、性能优化、测试与错误处理 | ⬜ 未开始 |

> 严格执行 Phase 顺序，禁止提前实现后续 Phase。详细规划见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，
> 变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 目录结构

```text
AIVideoPlayer/
├── project.yml               # XcodeGen 工程定义（唯一事实来源）
├── .github/workflows/        # GitHub Actions CI
├── docs/ARCHITECTURE.md      # 架构决策与 Phase 规划
├── AIVideoPlayer/            # App 源码
│   ├── App/                  # 入口、Tab、路由、全局状态
│   ├── DesignSystem/         # Liquid Glass 组件与设计令牌
│   ├── Features/             # Browser / Player / Subtitle / Settings
│   ├── Core/                 # Protocols、Models、Mock
│   ├── AI/                   # Speech / Translation（Phase 5/7）
│   ├── Services/             # 业务服务（后续 Phase）
│   └── Utilities/
└── Tests/AIVideoPlayerTests  # 单元测试（Swift Testing）
```

## 架构红线（摘要）

- View → ViewModel → Protocol → Service/Framework；View 禁止直接接触 AVPlayer、URLSession、WhisperKit。
- 单个 View 不超过 300 行；禁止把逻辑堆进 `ContentView.swift`。
- 所有 async Task 支持取消；状态显式表达 Loading / Ready / Error / Empty / Cancelled。
- UI 严格使用 iOS 26 原生 Liquid Glass API，禁止 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃。
- 隐私优先：视频/音频不上传、Whisper 本地运行、凭据只存本机 Keychain。

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
