# AI Video Player

> iOS 26 原生视频播放器 —— 浏览器 + AI 实时字幕 + 远程文件浏览

一个长期维护的个人 iOS 项目，提供 App 内网页浏览、WebDAV 远程文件访问、自动识别媒体资源并播放、Whisper 本地实时语音识别与 AI 双语字幕。UI 严格遵循 iOS 26 原生 Liquid Glass 设计规范。

**当前版本**：0.9.3（2026-08-13)

## 核心功能

- **内置浏览器**：WKWebView 网页浏览、历史记录、收藏夹、视频提取
- **远程文件浏览**：WebDAV 目录浏览与文件访问，密码存储于 Keychain
- **自定义播放器**：AVPlayer + 自定义 SwiftUI 控制栏，支持全屏横屏
- **AI 实时字幕**：WhisperKit 本地语音识别，模型内置无需下载
- **可替换翻译**：Apple Translation（本地）/ MLX LLM（按需下载）/ 云端 API
- **双语字幕叠加**：原文 + 译文双行显示，支持拖动调整位置
- **Liquid Glass UI**：iOS 26 原生玻璃效果设计

## 环境要求

- macOS（可安装 Xcode 26）
- Xcode 26+（含 iOS 26 SDK）
- XcodeGen（`brew install xcodegen`）

> Windows 无法编译 iOS 应用，只能用于查看源码。

## 快速开始

```bash
# 1. 安装 XcodeGen
brew install xcodegen

# 2. 生成 Xcode 工程
cd AIVideoPlayer
xcodegen generate

# 3. 打开工程
open AIVideoPlayer.xcodeproj

# 4. 运行：选择 AIVideoPlayer scheme，选 iOS 26 模拟器，Cmd+R
```

## 打包 IPA

仓库提供 GitHub Actions 手动工作流打包未签名 IPA：

1. 访问 [Actions](https://github.com/SCmenghua/AIVideoPlayer/actions)
2. 选择 **Package IPA (unsigned)**
3. 点击 **Run workflow**，填写版本号（默认 0.9.3）
4. 下载生成的 `AIVideoPlayer-<版本>-unsigned.ipa`
5. 使用自签工具（Sideloadly / AltStore / 爱思助手）导入 IPA 并签名安装

> IPA 未签名，必须经自签工具重签；需要 iOS 26+ 设备。

## 技术栈

| 类别 | 技术 |
|---|---|
| 语言 | Swift 6（严格并发） |
| UI | SwiftUI（iOS 26 Liquid Glass API） |
| 并发 | Swift Concurrency / AsyncStream |
| 媒体 | AVFoundation / AVPlayer |
| AI | WhisperKit / Core ML（本地识别） |
| 翻译 | Apple Translation / MLX Swift / OpenAI API |
| 网络 | URLSession、WebDAV |
| 存储 | Keychain、UserDefaults |
| 工程 | XcodeGen |
| 测试 | Swift Testing |
| CI | GitHub Actions |

## 项目文档

- **[PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)**：项目上下文速览（Phase 状态 / 技术栈 / 工作流程）
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**：架构决策与详细设计
- **[docs/CHANGELOG.md](docs/CHANGELOG.md)**：版本变更记录

## 架构原则

- **分层架构**：View → ViewModel → Protocol → Service → Framework
- **依赖注入**：ViewModel 通过 init 获得协议依赖
- **状态显式**：Loading / Ready / Error / Empty / Cancelled
- **协议先行**：先定义契约，实现可替换
- **隐私优先**：视频/音频不上传、Whisper 本地运行、凭据只存 Keychain

## 开发状态

当前 Phase：**8.18**（修复长视频 UI 卡死 + 诊断中心）

下一步：Phase 9 —— Liquid Glass 深化（变形过渡）、性能优化、测试与错误处理

详见 [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) 与 [CHANGELOG.md](docs/CHANGELOG.md)。

## License

本项目采用 **GNU Affero General Public License v3.0 (AGPL-3.0)** 开源协议。

- 你可以自由使用、修改、分发本项目
- 如果你修改并发布（包括网络服务），必须开源你的修改并采用相同协议
- 详见 [LICENSE](LICENSE) 文件
