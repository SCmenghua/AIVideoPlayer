# AI Video Player — 架构文档

## 目标

高质量、可扩展、可维护、性能稳定、符合 Apple 原生设计规范的长期 iOS 项目。

## 分层架构

```text
View ──► ViewModel ──► Service / Engine ──► Framework（AVFoundation / WhisperKit / URLSession ...）
```

- **View**：纯展示与用户手势；不持有业务逻辑。
- **ViewModel**：`@MainActor @Observable`；持有页面状态与协议依赖；发起可取消的 Task。
- **Service / Engine**：实现核心协议；例如 `PlaybackEngine`（封装 AVPlayer）。
- **Framework**：Apple / 第三方框架，业务层只通过协议接触。

## 模块划分

| 目录 | 职责 | 当前 Phase |
|---|---|---|
| `App/` | App 入口、Tab 路由、全局状态 | 1 |
| `DesignSystem/` | Liquid Glass 组件、Theme、通用 UI | 1 |
| `Features/Browser/` | 首页、地址栏、远程文件浏览 | 1（Mock）→ 2 |
| `Features/Player/` | 播放器 UI 与状态 | 1（占位）→ 3 |
| `Features/Subtitle/` | AI 字幕状态卡 | 1（Mock）→ 5/6 |
| `Features/Settings/` | 设置页 | 1（占位）→ 7 |
| `Core/Protocols/` | `MediaExtractor`、`PlaybackEngine`、`SpeechRecognizer`、`TranslationEngine`、`SubtitleEngine` | 1 |
| `Core/Models/` | `MediaItem`、`RemoteFile`、`SubtitleSegment`、`AIState`、`LoadState`、`PlaybackState` | 1 |
| `Core/Mock/` | Phase 1 Mock 数据 | 1 |
| `Core/Networking/` | 远程协议（WebDAV / SMB / FTP） | 2 |
| `Core/Storage/` | Keychain / SwiftData | 2+ |
| `AI/Speech/` | WhisperKit 语音识别 | 5 |
| `AI/Translation/` | 可替换翻译引擎 | 7 |
| `Services/` | 业务编排服务 | 2+ |
| `Utilities/` | 日志等通用设施 | 1 |

## 核心协议

- `MediaExtractor`：网页 / 远程目录 → `[MediaItem]`（不绕过 DRM）。
- `PlaybackEngine`：封装 AVPlayer 生命周期（加载、播放、暂停、seek、倍速、音量）。
- `SpeechRecognizer`：本地实时语音识别，输出 `AsyncStream<SubtitleSegment>`（partial / final）。
- `TranslationEngine`：可替换翻译（API / 本地模型 / Mock）。
- `SubtitleEngine`：字幕时间线管理（双语、同步、样式由 UI 层负责）。
- `RemoteFileBrowsing`：远程文件列表（Phase 1 Mock，Phase 2 接入 WebDAV / SMB / FTP）。
- `SubtitleStatusProviding`：AI 字幕状态来源（Phase 1 Mock，Phase 5 由 WhisperKit 管线实现）。

业务层只依赖协议；具体实现（WhisperKit、AVPlayer、API 翻译）在各自 Phase 注入。

## AI 字幕 Pipeline（规划）

```text
AVPlayer → AudioPipeline → SpeechRecognizer → SubtitleSegment → SubtitleEngine → SwiftUI Overlay
```

`AIState`：`OFF / LOADING / LISTENING / TRANSCRIBING / TRANSLATING / READY / ERROR`。

## 隐私承诺

- 视频、音频默认不上传；Whisper 完全本地运行。
- 远程凭据只存本机 Keychain。
- 翻译服务启用前必须明确提示：「字幕文本将发送到你配置的翻译服务」。
- 不收集视频、字幕、浏览历史、服务器文件列表。

## Phase 规划

1. **Phase 1（当前）**：App 初始化、目录、Tab/Navigation、Liquid Glass Design System 基础、首页、Mock、核心协议。
2. **Phase 2**：WKWebView 浏览器（地址栏/历史/收藏）+ WebDAV / SMB / FTP + Keychain 凭据。
3. **Phase 3**：AVPlayer 封装（播放/暂停/进度/倍速/音量/全屏/比例/字幕控制）。
4. **Phase 4**：MediaExtractor（HTML5 video / MP4 / HLS / M3U8；不绕过 DRM）。
5. **Phase 5**：WhisperKit AudioPipeline + SpeechRecognizer 实时识别。
6. **Phase 6**：SubtitleOverlay（双语、时间同步、拖动、样式）。
7. **Phase 7**：TranslationEngine（Base URL / API Key / Model / Language；明确隐私提示）。
8. **Phase 8-10**：Liquid Glass 深化（变形过渡）、性能、测试与错误处理。

> 禁止提前实现后续 Phase。
