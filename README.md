# AI Video Player

一个长期维护的个人项目：**iOS 26 原生视频播放器**，目标形态为
「PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器」。

技术栈：Swift 6 / SwiftUI / Swift Concurrency / AVFoundation / WhisperKit（本地）/ Core ML / URLSession / Keychain。

## 当前状态

- **Phase 1 已完成**：工程骨架、Tab + Navigation 架构、Liquid Glass Design System 基础、
  首页（Mock 远程文件列表 + Mock AI 字幕状态）、核心协议与模型、单元测试。
- 播放器、浏览器、远程协议、Whisper、字幕、翻译等属于后续 Phase，尚未实现。

## 构建要求

本项目需要在 **macOS + Xcode 26+（iOS 26 SDK）** 上构建；Windows 无法编译 iOS 应用。

```bash
# 1. 安装 XcodeGen（一次性）
brew install xcodegen

# 2. 生成 Xcode 工程（在仓库根目录执行）
xcodegen generate

# 3. 打开并构建
open AIVideoPlayer.xcodeproj
# 选择 AIVideoPlayer scheme，选 iOS 26 模拟器运行（Cmd+R）

# 4. 运行测试（Cmd+U）
```

> `AIVideoPlayer.xcodeproj` 由 `project.yml` 生成，不提交到版本库。

## CI

[.github/workflows/swift-ci.yml](.github/workflows/swift-ci.yml) 在 macOS runner 上自动执行：
`xcodegen generate` → `xcodebuild build` → `xcodebuild test`（push 到 `main` 或发起 PR 时触发）。

## 目录结构

```text
AIVideoPlayer/
├── project.yml               # XcodeGen 工程定义（唯一事实来源）
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

- View → ViewModel → Service/Engine → Framework；View 禁止直接接触 AVPlayer、URLSession、WhisperKit。
- 单个 View 不超过 300 行；禁止把逻辑堆进 `ContentView.swift`。
- 所有 async Task 支持取消；状态必须显式表达 Loading / Ready / Error / Empty / Cancelled。
- UI 严格使用 iOS 26 原生 Liquid Glass API（`glassEffect`、`GlassEffectContainer`、`.glass` 按钮样式），
  禁止用 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃。

详细说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
