# Changelog

本项目的所有重要变更都会记录在此文件中。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 待规划

- 暂无。当前主线为 Phase 2。
- Phase 3 播放器全屏/方向需求已记录至架构文档（2026-08-09）。

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

## [0.3.0] - Phase 3（规划中）

_尚未开发。_

- AVPlayer 封装：播放、暂停、进度、倍速、音量、全屏、比例调整、字幕控制

## [0.4.0] - Phase 4（规划中）

_尚未开发。_

- MediaExtractor：HTML5 video / MP4 / HLS / M3U8（不绕过 DRM）
