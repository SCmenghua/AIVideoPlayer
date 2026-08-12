# AI Video Player - 项目上下文速览

> iOS 26 原生视频播放器 —— 浏览器 + AI 实时字幕 + 远程文件浏览

**当前版本**：0.8.17（2026-08-12）  
**当前 Phase**：8.17（性能优化：修复字幕相关 UI 卡顿）

## 核心功能

- **内置浏览器**：WKWebView 网页浏览、历史记录、收藏夹、视频提取
- **远程文件浏览**：WebDAV 目录浏览与文件访问，密码存储于 Keychain
- **自定义播放器**：AVPlayer + 自定义 SwiftUI 控制栏，支持全屏横屏
- **AI 实时字幕**：WhisperKit 本地语音识别，模型内置无需下载
- **可替换翻译**：Apple Translation（本地）/ MLX LLM（按需下载）/ 云端 API
- **双语字幕叠加**：原文 + 译文双行显示，支持拖动调整位置
- **Liquid Glass UI**：iOS 26 原生玻璃效果设计

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

## 开发环境

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

## 打包与部署

仓库提供 GitHub Actions 手动工作流打包未签名 IPA：

1. 访问 [Actions](https://github.com/SCmenghua/AIVideoPlayer/actions)
2. 选择 **Package IPA (unsigned)**
3. 点击 **Run workflow**，填写版本号（默认 0.8.17）
4. 下载生成的 `AIVideoPlayer-<版本>-unsigned.ipa`
5. 使用自签工具（Sideloadly / AltStore / 爱思助手）导入 IPA 并签名安装

> IPA 未签名，必须经自签工具重签；需要 iOS 26+ 设备。

## 架构原则

- **分层架构**：View → ViewModel → Protocol → Service → Framework
- **依赖注入**：ViewModel 通过 init 获得协议依赖
- **状态显式**：Loading / Ready / Error / Empty / Cancelled
- **协议先行**：先定义契约，实现可替换
- **隐私优先**：视频/音频不上传、Whisper 本地运行、凭据只存 Keychain

## 项目文档

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**：架构决策与详细设计
- **[docs/CHANGELOG.md](docs/CHANGELOG.md)**：版本变更记录
- **[README.md](README.md)**：项目介绍与快速开始

## 已完成

- **Phase 8.17（2026-08-12 打包 0.8.17）**：性能优化：修复字幕相关 UI 卡顿——
  修复长视频字幕导致 UI 卡顿甚至卡死问题（30 分钟视频完全卡死、3 分钟视频明显卡顿），
  根本原因是设置页的「字幕记录」和「翻译记录」调试卡片观察 `@Observable` 的 
  `SubtitleTranscriptStore`，每 150ms 字幕更新时触发全量重新渲染（VStack 遍历数百条记录），
  阻塞主线程；修复分三管齐下：(1) 调试卡片默认隐藏：在 `SubtitleDisplaySettings` 中新增 
  `showTranscriptCard` 和 `showTranslationCard` 两个 Bool 属性（默认 `false`），
  并在设置页添加 Toggle 开关，只有主动开启时才渲染调试卡片；(2) 优化卡片渲染算法：
  将 `VStack` 替换为 `LazyVStack + ScrollView`，只渲染可见行；使用 `.suffix(20).reversed()` 
  算法只显示最近 20 条记录（`SubtitleTranscriptStore` 新增 `recentSegments` 计算属性），
  避免遍历全量数据；(3) 识别循环后台线程化（尝试后撤回）：曾将 `SubtitlePipeline.runRecognitionLoop` 
  和相关方法（`setStatus`、`logBufferWaitIfNeeded`、`translateAndYield`、`forwardSegment`、
  `startForwarding`）标记为 `nonisolated` 移入后台线程，但该方案无法编译
  （`MainActor.run` 不支持 async 闭包、非隔离上下文无法访问主线程属性），且 async 方法
  本身不阻塞主线程、后台化并无必要；已撤回该改动，`SubtitlePipeline.swift` 恢复至
  Phase 8.16 基线（保留 maxLookahead 与游标逻辑），仅保留前两个修复；同步修复字幕管线
  测试（对齐 8.16「识别失败重试当前窗口」语义、修复 `detectedLanguageIsPassedToNextWindow`
  越界崩溃、测试结束关闭管线停止泄漏的后台循环）；swift-ci 构建 + 单元测试全绿；
  `MARKETING_VERSION` 提升至 0.8.17。
- **Phase 8.16（2026-08-12 打包 0.8.16）**：修复识别循环逻辑 + 音频路由问题——
  修复长视频识别仍然无限推进：Phase 8.15 的 `lastSuccessfulCursor` 逻辑错误，
  识别成功后更新为当前窗口起点导致限制失效，改为恢复基于播放位置的限制 
  `cursor > playbackTime + maxLookahead`，并改为识别失败时不推进 cursor 而是重试当前窗口；
  修复音频输出路由不随系统更新：使用蓝牙耳机安装应用后取消蓝牙配对无法自动切换到扬声器播放，
  改为在 `AppDelegate.didFinishLaunchingWithOptions` 中配置 `AVAudioSession`（使用 `.playback` 
  类别和 `.moviePlayback` 模式），使音频输出随系统自动切换；`MARKETING_VERSION` 提升至 0.8.16。
- **Phase 8.15（2026-08-12 打包 0.8.15）**：修复识别循环逻辑缺陷——修复识别失败无限重试：
  `SubtitlePipeline.runRecognitionLoop` 中 `lastSuccessfulCursor` 为 optional 且初始值 nil，
  识别失败时 cursor 不推进导致同一窗口无限重试；改为 non-optional 初始值 `buffer.captureStart`，
  失败时 cursor 正常推进跳过失败窗口，maxLookahead 检查基于最后成功位置而非当前 cursor；
  修复追赶播放位置被 maxLookahead 误判：cursor 跳跃到播放位置后 `lastSuccessfulCursor` 
  仍是初始值导致触发等待分支卡住，改为追赶跳跃时同步更新 `lastSuccessfulCursor = cursor`；
  `MARKETING_VERSION` 提升至 0.8.15。
- **Phase 8.14（2026-08-12 打包 0.8.14）**：修复无限识别导致 UI 卡死 + 在线视频播放失败 + IPA 版本号——
  修复本地视频无限向后识别导致长视频 UI 卡死：`SubtitlePipeline.runRecognitionLoop` 
  新增 `maxLookahead` 参数（10 秒），限制识别进度只能超前播放位置 10 秒，
  避免本地视频一次性识别整个文件（超过 1-2 分钟的长视频会导致 UI 完全卡住、
  超过 10 分钟的视频会因后台疯狂识别而无法播放）；修复在线视频点击播放按钮后
  无反应的问题：简化 `AVPlayerPlaybackEngine.handleTimeControlStatus` 逻辑，
  移除复杂的缓冲监听与自动恢复播放代码（`isWaitingForBuffer` / `observeBufferStatus`），
  让 AVPlayer 自动处理网络缓冲，避免状态混乱导致播放失败（拖动进度条能显示画面但
  播放按钮无响应）；修复 IPA 版本号错误：`project.yml` 的 `MARKETING_VERSION` 
  从 0.8.12 更新为 0.8.14（Phase 8.13 忘记更新导致安装时识别为 0.8.12）；
  `MARKETING_VERSION` 提升至 0.8.14。
- **Phase 8.13（2026-08-11 打包 0.8.13）**：日志功能 + CI 修复——
  新增应用级日志服务 `AppLogger`（四级日志 debug/info/warning/error，内存循环缓冲 500 条 + 
  持久化到 Documents/Logs 按日期分文件、自动清理 7 天前旧日志），`SubtitlePipeline` 
  关键路径接入日志；设置页新增「应用日志」卡片（最近 50 条日志倒序显示、四级颜色区分、
  一键清空、导出全部日志）；修复 `SubtitleTranscriptStore` 时间计算错误
  （`flush()` 中 `now.duration(to: lastFlushTime)` 应为 `lastFlushTime.duration(to: now)`，
  错误的计算方向导致 `elapsed` 总是负值、节流失效、`pendingSegments` 无法提交到 `segments`，
  引发测试失败）；CI 通过；`MARKETING_VERSION` 提升至 0.8.13。
- **Phase 8.12（2026-08-11 打包 0.8.12）**：UI 卡顿问题根本修复——
  真正原因是 `SubtitleTranscriptStore` 作为 `@MainActor @Observable` 类，
  每次 `append()` 都立即触发 SwiftUI 的 UI 刷新；高频识别结果（partial 段
  每秒数次、音频块更频繁）会完全卡死主线程；解决方案：引入**批量更新 + 节流机制**——
  `append()` 不再立即写入 `segments`，而是累积到 `pendingSegments` 缓冲区，
  最快每 150ms 批量提交一次（`scheduleFlush()`），大幅减少 UI 刷新频率；
  `segment(at:)` 查询时自动刷新缓冲区，确保最新字幕立即可见（不等待定时器）；
  `clear()` 和 `shutdown()` 调用 `flush()` 确保所有字幕都已写入；
  补充单元测试（批量更新行为 + 自动刷新）；`MARKETING_VERSION` 提升至 0.8.12。
- **Phase 8.11（2026-08-11 打包 0.8.11）**：修复 UI 卡顿问题——
  真正原因是 `translateAndYield` 在主线程同步执行系统翻译（可能耗时数百毫秒），
  阻塞主线程导致 UI 卡住；将翻译操作用 `Task.detached` 移至后台线程执行，
  翻译完成后再回到主线程写入结果；保持 `forwardSegment` 为同步方法；
  修复了 UI 卡顿、字幕和翻译不显示、播放器控制栏和底部 Tab 栏无响应等问题；
  `MARKETING_VERSION` 提升至 0.8.11。
- **Phase 8.10 终止与回退**（2026-08-11）：尝试修复字幕开启后 UI 卡住问题，
  将 `forwardSegment` 改为 `nonisolated` 并用 `Task { @MainActor in }` 包裹，
  导致字幕写入变成异步操作，引发更严重的 UI 卡住、字幕和翻译不显示等问题；
  代码已回退至 Phase 8.9，后续所有 Phase 忽略本次代码，下一次 Phase 为 8.11。
- **Phase 8.10（失败，2026-08-11 打包 0.8.10）**：尝试修复 UI 卡住问题，
  但实测导致视频能动、字幕和翻译完全不显示、所有 UI（包括播放器控制栏和底部
  Tab 栏）卡住点不动；代码已回退弃用。
- **Phase 8.9（2026-08-11 打包 0.8.9）**：修复两个播放器 bug——大视频 UI 冻结
  （`AssetReaderAudioPipeline.consume()` 解码循环用 `Task.detached` 移到后台线程，
  避免阻塞主线程 UI）；网络资源播放停摆（`SubtitlePipeline.makeSource` 按 URL 类型
  判断：本地文件优先用 AssetReader 预读、网络资源 / HLS 直接用 PlayerAudioPipeline
  实时 Tap，避免 AVAssetReader 不支持 HLS 导致卡住）；`MARKETING_VERSION` 提升至 0.8.9。
- **Phase 8.8 终止与回退**（2026-08-11）：实测网页视频仍无法播放，且字幕功能
  回归不可用（卡片显示错误 / 停在「正在聆听」无法识别、字幕记录与翻译记录为空），
  结束 Phase 8.8；代码基线回退至 Phase 8.7 / 0.8.7（commit `b6ae7aa`），
  保留 4 份说明文档并记录本次操作；后续所有 Phase 忽略本次代码，未来从
  0.8.7 代码开始重构，下一次 Phase 为 8.9。
- **Phase 8.8（失败，2026-08-11 打包 0.8.8）**：修复两个播放器 bug——大视频
  UI 冻结（读取器解码移出主线程）；网络资源播放停摆（本地才用读取器、网络走
  Tap、HLS 跳过采集）；实测修好大视频 bug，但网页视频仍无法播放，且字幕功能
  回归不可用（卡片错误 / 停在「正在聆听」、字幕记录与翻译记录无内容），
  代码已回退弃用。
- **Phase 8.7（2026-08-10 打包 0.8.7）**：修复「只显示原语言、不显示译文」——
  根因：翻译默认关闭导致 final 段从不调用翻译引擎；修复为默认开启（本地
  Fast NMT）；管线新增翻译计数与失败原因（设置页显示 + OSLog）；
  零 / 负时长 final 按 0.5s 最小窗口兜底；新增设置页独立「翻译记录」卡片
  （原文 + 译文 + 时间 + 已翻译总数 + 失败提示）；`MARKETING_VERSION` 提升至 0.8.7。
- **Phase 8.6（2026-08-10 打包 0.8.6）**：新增字幕语言与双语显示——设置页新增
  独立「字幕语言」卡片（原语言 / 翻译语言 / 双语显示开关，与「字幕记录」同层级）；
  原语言支持自动检测 + 12 种语言，手动指定后 Whisper 识别与翻译源语言立即生效，
  自动检测时翻译源语言跟随识别结果；翻译语言 12 种，切换语言重建翻译引擎；
  双语显示开启时上行原文（约译文一半字号）、下行译文（主行大字），关闭时只显示
  译文；设置持久化（源 / 目标语言 + 双语开关）；`MARKETING_VERSION` 提升至 0.8.6。
- **Phase 8.5（2026-08-10 打包 0.8.5）**：删除超前识别功能；重构字幕显示链路——
  新增共享 `SubtitleTranscriptStore`（播放器 Overlay 与设置页「字幕记录」直接读取，
  不再依赖单次消费的流，修复 Tab 反复进出后字幕丢失）；实时路径 partial 不再按
  播放位置丢弃；设置页新增「字幕记录」卡片（原文 + 译文 + 时间 + 清空）；
  `MARKETING_VERSION` 提升至 0.8.5。
- **Phase 8.4 终止与二次回退**（2026-08-10）：实测仍无法使用，结束 Phase 8.4；
  代码基线再次回退至 Phase 8.1 / 0.8.1（commit `4449b16`），保留说明文档并记录；
  **Phase 8.2 – Phase 8.4 全部失败**，实现已弃用；后续所有 Phase 忽略这几次代码，
  未来从 0.8.1 代码开始重构，下一次 Phase 为 8.5。
- **Phase 8.4 基线回退**（2026-08-10）：代码基线回退至 Phase 8.1 / 0.8.1
  （commit `4449b16`），保留 Phase 8.2 + Phase 8.3 说明文档并记录本次操作；
  后续所有 Phase 忽略此前 Phase 8.2–8.3 代码，未来从 0.8.1 代码开始重构，
  下一次 Phase 为 8.4（重新开始）。
- **Phase 8.4（失败，2026-08-10 打包 0.8.4）**：多语言与源/目标语言——
  在 0.8.1 基线上重建多语言；全语言池 12 种（含日文等），设置页「语言列表」
  可勾选呈现并排序；设置页与播放器均可调整「原语言 / 目标语言」；播放器
  「字幕语言」按钮紧邻字幕开关、开启字幕后才出现，菜单分栏明确标注；
  实测仍无法使用，代码已回退弃用。
- **Phase 8.3（失败，2026-08-10 打包 0.8.3）**：实测反馈修复——播放器字幕开关随识别管线激活 / 关闭自动同步
  （开关「On」代表「我想看字幕」、开关「Off」代表「不看字幕并关闭识别」；
  与识别管线「活跃 / 非活跃」实时双向联动）；原始实时路径 partial 不再被
  「早于播放位置」丢弃（避免「识别已产出但播放器无字幕」）；识别统计在
  管线激活时重置（确保开关切换时计数与日志从 0 开始）；设置页交互卡片启用
  Liquid Glass interactive（播放器保持非交互）；播放器「字幕语言」菜单分栏
  标注原语言 / 目标语言（原语言列表含「自动检测」+6 种、目标语言 6 种）；
  实测仍无法使用，代码已回退弃用。
- **Phase 8.2（失败，2026-08-10 打包 0.8.2）**：翻译功能增强——确认默认使用系统内置翻译（Apple Translation）；
  支持本地大模型（Gemma 4 E2B、按需下载）与云端 API（OpenAI / Azure）；
  设置页新增「翻译引擎」卡片（Apple Translation / 本地模型 / API）；云端
  API 需配置 Key（保存 Keychain）、本地模型需手动下载（下载进度卡片）；
  设置页与播放器均可调整「原语言」与「目标语言」（共 6 种：简体中文 /
  English / 日本語 / 한국어 / Bahasa Melayu / Filipino，设置页可排序）；
  播放器「字幕语言」按钮（紧邻字幕开关、开启字幕后才出现）打开菜单
  （原语言 + 目标语言分栏列出可选语言，「确认」后生效）；设置页补充
  「原语言 / 目标语言」展示；持久化引擎选择 / API Key / 下载完成的模型 /
  语言池 / 排序后语言；实测无法正常使用，代码已回退弃用。
- **Phase 8.1**：修复「开关已生效但看不到字幕」——确认字幕开关链路真实生效；
  根因：（1）识别参数没有传递 prefill（应使用标准 SOT+语言+任务+时间戳）；
  （2）首窗自动检测语言后未把语言代码传给后续窗口（每窗都检测一遍，中文/短
  音频容易失败）；（3）识别速度跟不上时会一直尝试落后窗口、越来越慢，应跳过
  已落后的窗口从当前播放位置继续；修复为使用标准 prefill，首窗检测后把语言
  传给后续，识别游标跟随播放位置；新增识别状态统计（设置页显示 + OSLog）；
  补充单元测试（语言传递 / 落后窗口跳过）；`MARKETING_VERSION` 提升至 0.8.1。
- **Phase 8.0**：修复「播放视频没有字幕」的核心链路——播放器字幕开关自动激活
  识别管线（管线已在别处启用时播放器默认显示字幕）；播放中途激活 / 设置变更
  改用引擎当前真实时间重建识别游标；模型加载期识别循环改为「引擎未就绪」重试
  而非永久退出；播放器内新增字幕状态胶囊（加载中 / 错误 / 已关闭）；
  内置普通话测试素材 `test.mp4` + 正确转写 `test.txt`（`test.txt` 入库并随包，
  `test.mp4` 体积约 9 MB 保持 git 忽略——GitHub Actions 打包的 IPA 不含
  `test.mp4`，仅在本地构建时随包，调试入口优先加载、缺失时回退内置 `sample.mp4`）；
  补充单元测试（识别未就绪恢复 / 播放中途激活时间基准 / 播放器开关联动）；
  `MARKETING_VERSION` 提升至 0.8.0。
- **Phase 7.13**：移除文件来源导入功能——「文件 App 导入视频」经多次修复
  （书签授权 → 复制到沙盒）仍不稳定，按用户要求整体下线；删除
  `FilesMediaSourceView` / `PickedVideoFile` / `PickedFileStoring` /
  `UserDefaultsPickedFileStore` 及相关单测；保留 `MediaSourceKind.files`
  枚举值与来源占位入口（兼容旧数据解码），模型 / VM / 视图均留有恢复步骤
  注释；媒体来源保留网络（WebDAV）与相册两类；
  `MARKETING_VERSION` 提升至 0.7.13。
- **Phase 7.12**：文件来源导入修复——iOS 文档选择器临时授权无法靠普通书签
  跨会话保持，导入时改为把文件复制到 App Documents/MediaFiles 并登记本地
  URL，跨启动始终可播放；删除导入文件时同步清理沙盒副本；
  `MARKETING_VERSION` 提升至 0.7.12。
- **Phase 7.11**：实测反馈修复——相册来源点击视频崩溃（Photos 内部 URL 改为
  导出到 App 临时目录后按普通文件播放，iCloud 自动下载）；文件来源选择器
  改用系统 `fileImporter`（修复「打开」无反应）；媒体来源新增「编辑」模式
  删除按钮（长按删除保留）；全屏自动横屏优化（检测改用播放器已加载的 asset，
  旋转请求后校验实际方向、未生效自动重试）；`MARKETING_VERSION` 提升至 0.7.11。
- **Phase 7.10**：横屏识别/方向切换修复 + 媒体来源——分辨率检测改用
  `preferredTransform` 修正旋转元数据，全屏入口检测未完成时重新检测并等待结论；
  请求旋转前先刷新 supportedInterfaceOrientations、横屏同时请求左右方向、
  失败自动重试，切换按钮按真实界面方向判断；主页「添加服务器」升级为
  「添加媒体来源」（网络 WebDAV / 相册，多个来源均展示在主页），
  相册来源列出系统视频、文件来源用安全作用域书签持久化；新增
  `MediaSource` / `PickedVideoFile` 模型与单测；`MARKETING_VERSION` 提升至 0.7.10。
- **Phase 7.9**：播放器细节优化与主页标签页——控制栏新增「设置」二级菜单
  （收纳重新播放 / 画面比例 / 重新初始化），删除音量按钮与音量相关代码；
  加载时异步检测视频横竖屏（宽 > 高为横屏），横屏视频进入全屏默认横屏；
  全屏内横屏/竖屏合并为单个切换按钮；浏览器地址栏新增「返回主页」按钮；
  主页新增「标签页」区域（手动添加快捷入口，独立于收藏）；WKWebView 启用
  iOS 默认左缘右滑返回手势；新增 `HomeTab` 存储与单测；
  `MARKETING_VERSION` 提升至 0.7.9。
- **Phase 7.8**：播放器状态与进度兜底——引擎 `play()` / `pause()` / `seek()`
  直接维护权威状态（不再只依赖 `timeControlStatus` KVO 回调），加载完成即推送
  一次进度；引擎新增 0.5s 兜底节拍器（周期读取 AVPlayer 当前时间 / 时长 / 状态，
  与周期观察者双通道并存）；VM 播放控制后立即从引擎同步 `playbackState`，并新增
  轮询兜底（周期同步引擎属性，流未送达时 UI 仍更新）；时长未知时进度条禁用拖动
  （避免 0...1 退化范围把任意拖动变成从头重播）、时长显示 `--:--`、seek 目标
  收敛到已知时长；加载失败时引擎状态同步标记为 failed（不再停留在 loading）；
  `emitProgress` 对非有限时间回退 0；补充静默引擎回归测试；
  `MARKETING_VERSION` 提升至 0.7.8。
- **Phase 7.7**：播放器状态与进度修复——换片加载先 `avPlayer.pause()`
  避免新条目因 rate 保持 1 自动播放；引擎状态机禁止 `.playing` 被 `.ready`
  回退、VM 仅在仍处于 loading 态时置 ready；HLS / 时长未就绪时
  `currentItemDuration` 用可 seek 范围末端兜底，修复进度条不显示与
  拖动从 0 重播；修 `CMTime.seconds` 误用 `if let` 的 CI 编译失败；
  `MARKETING_VERSION` 提升至 0.7.7。
- **Phase 7.6**：播放器换片复位——`PlayerViewModel.load` 先复位（进度/状态/
  字幕循环）再加载，旧加载任务取消 + generation 守卫，防止换片后旧任务
  覆盖新状态（转圈/旧进度残留）；引擎换片复位进度/倍速、`waitUntilReady`
  检测到当前条目被替换即视为本加载失效；播放器控制栏新增「手动初始化」
  按钮、失败态新增「重试」；补充单测；`MARKETING_VERSION` 提升至 0.7.6。
- **Phase 7.5**：对 Phase 1–7 成品做整体 Debug + 实测反馈完善——
  修复浏览器后退/前进/刷新命令未送达、换片字幕沿用旧视频音频源、seek 后过期识别结果
  透出、WebDAV 连接失败凭据残留、本地模型下载取消竞态、播放器加载无超时、
  音频 Tap 格式强读越界风险、云端翻译绕过隐私校验、CI 编译失败（deinit 并发）等；
  完善地址栏「清空当前网址」按钮、浏览器内视频接入内置播放器
  （内联播放 + 直链拦截 + HTML5 video 桥接）、构建时内置示例视频
  （原 googleapis 示例 URL 403 导致测试视频无法播放）；同步补充单元测试；
  `MARKETING_VERSION` 提升至 0.7.5，新增 `package-ipa.yml`（未签名 IPA →
  Actions 工件 + GitHub Release，供自签测试）。
- **Phase 1–4**：App 骨架（Browser / Player / Settings 三 Tab）、Liquid Glass Design System、
  核心协议与模型、Mock、单元测试、GitHub Actions CI；WKWebView 浏览器（地址栏/历史/收藏）、
  WebDAV 远程文件浏览（PROPFIND + 多级目录）、Keychain 凭据、服务器配置持久化；
  `AVPlayerPlaybackEngine`（播放/暂停/进度/倍速/seek）、自定义播放器 UI（无 AVPlayerViewController）、
  玻璃控制栏、YouTube 风格全屏（隐藏 Tab/Nav/状态栏、竖屏锁定时可横屏）；
  `WebMediaExtractor`（直链媒体 / HLS / HTML5 video 提取）、浏览器「提取视频」按钮 + 结果列表。
- **Phase 5–6**：WhisperKit 本地实时识别（模型随 App 内置）、`AudioPipeline` 三来源
  （AVAssetReader 预读 / MTAudioProcessingTap 实时 / 麦克风）、`WhisperKitSpeechRecognizer`、
  `SubtitlePipeline`（音频采集 → Whisper 转写 → 字幕段聚合）、播放器字幕 Overlay
  （双语显示 / 拖动调整位置 / 播放器控制栏字幕开关）、设置页字幕配置
  （识别模型 / 翻译引擎 / 字幕位置）；Apple Translation 本地翻译、MLX LLM 按需下载、
  云端 API（OpenAI / Azure）可选；单元测试覆盖识别器 / 管线 / 翻译引擎；
  `MARKETING_VERSION` 提升至 0.6.0。


## 禁止事项

**禁止在没有 Phase 标记的情况下直接修改代码**。每次代码变更都必须：

1. **明确 Phase 编号**：下一个 Phase 编号由用户指定或按顺序递增
2. **记录变更内容**：在本文档「已完成」部分新增一条记录，描述本次 Phase 的目标、实现与影响
3. **更新版本号**：修改 `project.yml` 中的 `MARKETING_VERSION`，与 Phase 版本一致（如 Phase 8.15 → 0.8.15）
4. **提交与推送**：`git add` → `git commit -m "Phase X.Y: <描述>"` → `git push`
5. **触发 CI**：推送后自动触发 GitHub Actions 打包 IPA

**所有代码变更都必须经过 Phase 流程**，即使是一行修改也要：

- 明确 Phase 编号
- 更新本文档
- 更新版本号
- 提交推送

**例外**：仅文档修改（README / ARCHITECTURE / 本文件）可以不创建新 Phase，但仍需提交推送。

## 工作流程

### 标准开发流程

1. **用户指定下一个 Phase**：「现在进入 Phase X.Y，目标是...」
2. **Claude 执行开发**：
   - 修改代码
   - 更新 `project.yml` 的 `MARKETING_VERSION`
   - 更新本文档「已完成」部分
   - 更新 `docs/CHANGELOG.md`（如有必要）
3. **提交与推送**：
   ```bash
   git add .
   git commit -m "Phase X.Y: <描述>"
   git push
   ```
4. **触发 CI**：GitHub Actions 自动打包 IPA

### 失败回退流程

如果某个 Phase 实测失败：

1. **用户指定回退目标**：「Phase X.Y 失败，回退到 Phase X.Z」
2. **Claude 执行回退**：
   ```bash
   git reset --hard <commit-hash>  # 回退到指定 commit
   git push --force
   ```
3. **记录失败 Phase**：在本文档「已完成」部分标注失败的 Phase 与原因
4. **下一个 Phase 从回退基线继续**

## 当前状态

- **Phase**：8.17
- **版本**：0.8.17
- **状态**：✅ 修复字幕相关 UI 卡顿；swift-ci 构建 + 单元测试全绿
- **下一步**：Phase 9 —— Liquid Glass 深化（变形过渡）、性能优化、测试与错误处理

## 注意事项

1. **Windows 环境限制**：无法编译 iOS 应用，只能查看源码和修改文档
2. **模型文件**：WhisperKit 模型已内置于 `AIVideoPlayer/Resources/Models/`，约 50 MB
3. **测试素材**：`test.mp4` 约 9 MB，git 忽略，仅本地构建时随包
4. **IPA 打包**：GitHub Actions 生成的 IPA 未签名，需自签工具重签后安装
5. **版本同步**：`project.yml` 的 `MARKETING_VERSION` 必须与 Phase 版本一致
6. **Phase 流程**：所有代码变更都必须经过 Phase 流程（编号 → 文档 → 版本 → 提交 → 推送 → CI）

