# AI Video Player Project Context

## 产品目标

一个长期维护的个人 iOS 项目：iOS 26 原生视频播放器，目标形态为
「PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器」。

核心能力：App 内网页浏览、WebDAV / SMB / FTP 远程文件访问、自动识别可播放媒体、
自有 AVPlayer 播放、完整播放器 UI、Whisper 本地实时语音识别、AI 双语字幕、
可替换翻译架构、原生 Liquid Glass UI。

质量目标：高质量、可扩展、可维护、性能稳定、符合 Apple 原生设计规范。

## 当前Phase

**Phase 3**（AVPlayer 播放器与 YouTube 风格全屏体验，实现已完成、进入收尾）。
下一阶段：**Phase 4 —— MediaExtractor（HTML5 video / MP4 / HLS / M3U8，不绕过 DRM）**。

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
    提交信息可另加 `[skip ci]` 标记；
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
- **文档**：README / ARCHITECTURE / CHANGELOG / PROJECT_CONTEXT；纯文档改动不触发 CI。

## 禁止事项

- **禁止使用 `AVPlayerViewController`**：播放器必须使用 AVPlayer + SwiftUI 自定义 UI。
- **禁止伪 Liquid Glass**：禁止用 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃；
  必须使用 iOS 26 原生 `glassEffect` / `GlassEffectContainer` / `.glass` / `.glassProminent`。
- **禁止跳 Phase**：严格按 Phase 顺序开发，禁止提前实现后续 Phase。
- **纯文档内容、不涉及程序代码的部分禁止触发 CI**：CI push 触发已配置
  `paths-ignore: *.md, docs/**`，纯文档提交可另加 `[skip ci]` 标记。

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
| 媒体 | AVFoundation / AVPlayer（已接入） |
| 浏览器 | WKWebView（已接入） |
| 远程文件 | URLSession + WebDAV PROPFIND（已接入）；SMB / FTP 后续补充 |
| 安全存储 | Keychain（已接入）、UserDefaults |
| AI | WhisperKit / Core ML（Phase 5 规划，本地运行；超前缓冲识别 2–10s） |
| 翻译 | 可替换 TranslationEngine（Phase 7 规划：Fast NMT / 本地 LLM / 云端 API） |
| 工程 | XcodeGen（project.yml 生成工程） |
| 测试/CI | Swift Testing；GitHub Actions（xcodegen + xcodebuild build/test，macOS runner） |
