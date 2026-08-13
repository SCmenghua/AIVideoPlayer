# Changelog

本项目的所有重要变更都会记录在此文件中。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 待规划

- **Phase 9.3**：LLM 功能深化——模型集成、提示词优化、推理加速
- **后续**：新浏览器功能、Liquid Glass 深化、性能优化与测试（编号后续规划）

## [0.9.2] - 2026-08-13

### Added（Phase 9.2 翻译引擎卡片 + 本地大模型 + API Key）

- 设置页新增与「字幕语言 / 字幕显示」同级的「翻译引擎」卡片，提供系统内置翻译 / 本地大模型 / API Key 三选一
- 确认 `TranslationEngine` 三 Provider（Fast NMT / Local LLM / Cloud LLM）与设置卡片已接通字幕管线
- 修复卡片不显示：`TranslationSettingsViewModel` 改由 `AppEnvironment` 持有，卡片直接读取环境、始终渲染

### Changed（Phase 9.2）

- 「翻译服务」卡片更名为「翻译引擎」，副标题改为「系统内置翻译 · 本地大模型 · API Key」
- Fast NMT Provider 展示名由「本地轻量翻译（Apple）」改为「系统内置翻译（Apple）」
- 修正 `project.yml` 编码；恢复 `package-ipa.yml` / `swift-ci.yml`
- `MARKETING_VERSION` 定为 0.9.2

## [0.8.18] - 2026-08-13

### Fixed（Phase 8.18 修复长视频 UI 卡死）

- **长视频开启字幕 + 翻译后 UI 卡死**：根因是本地文件的音频采集链路把整条音轨在 MainActor 上以
  高于实时速度解码，并反复触发 `PCMBuffer` 的 `Array.removeFirst`（O(n)）整体搬移，长视频下
  主线程被近平方级的 memmove 拖垮。修复：
  - `PCMBuffer` 改为「存储数组 + 头下标」环形窗口，裁剪 O(1)、周期性压实均摊 O(1)；
  - `AudioPipeline` 新增 `setReadTarget`，`AssetReaderAudioPipeline` 只预读播放位置前方 30 秒，
    由字幕管线随播放进度推进，不再整轨解码；
  - `updatePlaybackPosition` / `preparePlayback` / `handleSeek` 同步推进预读目标。

### Added（Phase 8.18 诊断与日志）

- 设置页新增「诊断与日志」二级菜单，集中展示字幕记录 / 翻译记录 / 日志，三者独立开关
  （字幕记录与翻译记录默认关闭，避免高频数据造成 UI 开销）。
- `AppLogger` 重构：内存环形缓冲（500 条）+ 后台异步落盘、去掉逐行 fsync；
  日志列表支持级别着色、导出、清空。

### Changed（Phase 8.18 日志重做）

- 识别日志：窗口完成日志包含耗时 / 采样数 / 语言 / 段数；
- 翻译日志：包含 provider / 源目标语言 / 耗时 / 原文摘要；
- 跳过落后窗口日志：包含累计跳过次数与秒数，并去掉重复的逐窗口完成日志。

### Changed

- `MARKETING_VERSION` 提升至 0.8.18；两个 IPA 工作流默认版本同步为 0.8.18；swift-ci 构建 + 单元测试全绿。

## [0.8.17] - 2026-08-12

### Fixed（Phase 8.17 性能优化：修复字幕相关 UI 卡顿）

- **长视频字幕导致 UI 卡顿甚至卡死**：30 分钟视频识别后 UI 完全卡死，3 分钟视频出现明显卡顿，
  根本原因是设置页的「字幕记录」和「翻译记录」调试卡片观察 `@Observable` 的 `SubtitleTranscriptStore`，
  每 150ms 字幕更新时触发全量重新渲染（VStack 遍历数百条记录），阻塞主线程；
  修复分三管齐下：
  1. **调试卡片默认隐藏**：在 `SubtitleDisplaySettings` 中新增 `showTranscriptCard` 和 
     `showTranslationCard` 两个 Bool 属性（默认 `false`），并在设置页添加 Toggle 开关，
     只有主动开启时才渲染调试卡片，避免默认情况下的性能损耗
  2. **优化卡片渲染算法**：将 `VStack` 替换为 `LazyVStack + ScrollView`，只渲染可见行；
     使用 `.suffix(20).reversed()` 算法只显示最近 20 条记录（`SubtitleTranscriptStore` 新增 
     `recentSegments` 计算属性），避免遍历全量数据
  3. **识别循环后台线程化（尝试后撤回）**：曾将 `SubtitlePipeline.runRecognitionLoop` 和相关方法
     标记为 `nonisolated` 移入后台线程，但该方案无法编译（`MainActor.run` 不支持 async 闭包、
     非隔离上下文无法访问主线程属性），且 async 方法本身不阻塞主线程、后台化并无必要；
     已撤回该改动，`SubtitlePipeline.swift` 恢复至 Phase 8.16 基线（保留 maxLookahead 与游标逻辑），
     仅保留前两个修复
- **CI 测试修复（构建恢复后）**：`recognitionLoopSurvivesEngineNotReadyAndRecovers` 断言对齐
  8.16「识别失败重试当前窗口」语义（首窗 windowStart=0）；`detectedLanguageIsPassedToNextWindow`
  越界崩溃（`transcriptionCalls[1]` Index out of range）改为安全访问（5s 超时 + 显式计数断言）；
  全部字幕管线测试结束调用 `shutdown(pipeline)` 停止泄漏的后台识别循环；
  swift-ci 构建 + 单元测试全绿

### Changed

- `MARKETING_VERSION` 提升至 0.8.17

## [0.8.16] - 2026-08-12

### Fixed（Phase 8.16 修复识别循环逻辑 + 音频路由问题）

- **长视频识别仍然无限推进**：Phase 8.15 的 `lastSuccessfulCursor` 逻辑错误，
  识别成功后 `lastSuccessfulCursor` 更新为当前窗口起点，导致 `cursor > lastSuccessfulCursor + maxLookahead` 
  限制失效，识别可以无限向前推进；修复为恢复基于播放位置的限制 `cursor > playbackTime + maxLookahead`，
  并改为识别失败时不推进 cursor 而是重试当前窗口，这样既能限制识别范围（当前播放位置前后 10 秒），
  又不会因失败而被阻塞
- **音频输出路由不随系统更新**：使用蓝牙耳机安装应用后，取消蓝牙配对无法自动切换到扬声器播放；
  修复为在 `AppDelegate.didFinishLaunchingWithOptions` 中配置 `AVAudioSession`（使用 `.playback` 
  类别和 `.moviePlayback` 模式），使音频输出随系统自动切换（蓝牙 ↔ 扬声器）

### Changed

- `MARKETING_VERSION` 提升至 0.8.16

## [0.8.15] - 2026-08-12

### Fixed（Phase 8.15 修复识别循环逻辑缺陷）

- **识别失败无限重试导致测试失败**：`SubtitlePipeline.runRecognitionLoop` 中 
  `lastSuccessfulCursor` 为 optional 且初始值 nil，识别失败时 cursor 不推进，
  导致同一窗口无限重试；修复为 `lastSuccessfulCursor` 改为 non-optional，
  初始值设为 `buffer.captureStart`，失败时 cursor 正常推进跳过失败窗口，
  maxLookahead 检查基于最后成功位置而非当前 cursor
- **追赶播放位置被 maxLookahead 误判为超前**：识别落后于播放时，cursor 跳跃到播放位置后，
  `lastSuccessfulCursor` 仍是初始值导致 `cursor > lastSuccessfulCursor + maxLookahead` 
  触发等待分支，游标永远卡住；修复为追赶跳跃时同步更新 `lastSuccessfulCursor = cursor`，
  避免合法跳跃被当作超前

### Changed

- `MARKETING_VERSION` 提升至 0.8.15

## [0.8.14] - 2026-08-12

### Fixed（Phase 8.14 修复无限识别导致 UI 卡死 + 在线视频播放失败 + IPA 版本号）

- **本地视频无限识别导致 UI 卡死**：`SubtitlePipeline.runRecognitionLoop` 会无限向后识别，
  尝试将整个视频的所有音频全部识别完并翻译，导致超过 1-2 分钟的长视频无法正确显示字幕、
  超过 10 分钟以上的视频会一直卡住（后台疯狂识别）；修复为新增识别前瞻窗口限制
  `maxLookahead`（10 秒），只识别当前播放位置前后各 10 秒的内容，识别进度超前播放位置
  10 秒时等待播放追上，避免无限识别整个视频文件
- **在线视频点击播放按钮后无反应**：`AVPlayerPlaybackEngine.handleTimeControlStatus` 
  的复杂缓冲监听逻辑（`isWaitingForBuffer` 状态标记 + `observeBufferStatus` 异步监听）
  导致播放状态混乱，在线视频点击播放按钮后没有反应（拖动进度条仍能加载对应帧画面但无法播放）；
  简化状态处理逻辑，移除缓冲监听与自动恢复播放代码，让 AVPlayer 自动处理网络缓冲，
  `.waitingToPlayAtSpecifiedRate` 状态不干预播放流程
- **IPA 版本号识别错误**：Phase 8.13 打包时 `project.yml` 的 `MARKETING_VERSION` 
  仍为 0.8.12（忘记更新），导致 IPA 虽然写的是 0.8.13 但安装时识别为 0.8.12；
  修正为 0.8.14

### Changed

- `MARKETING_VERSION` 提升至 0.8.14

## [0.8.13] - 2026-08-11

### Fixed（Phase 8.13 日志功能 + CI 修复）

- **SubtitleTranscriptStore 时间计算错误**：`flush()` 方法中节流判断的时间计算方向错误
  （`now.duration(to: lastFlushTime)` 应为 `lastFlushTime.duration(to: now)`），
  导致 `elapsed` 总是负值、节流逻辑失效、`pendingSegments` 无法正确提交到 `segments`，
  引发 `SubtitleTranscriptStoreTests` 中三个测试失败（批量更新、自动刷新、清空后刷新）；
  修复后所有测试通过
- **测试异步时序问题**：`SubtitlePipelineTests.recognitionLoopSurvivesEngineNotReadyAndRecovers()` 
  在检查 `transcript.segments` 前添加 100ms 等待，确保异步 `continuation.yield()` 
  完成并且 segments 已处理到 transcript store；修复 CI 间歇性失败

### Added（Phase 8.13 持久化日志）

- **应用级日志服务**：新增 `AppLogger`（`@MainActor` 单例）支持四级日志（debug / info / warning / error），
  内存循环缓冲 500 条 + 持久化到 Documents/Logs（按日期分文件、自动清理 7 天前旧日志）；
  统一日志格式（时间戳 + 级别 + 消息）；`SubtitlePipeline` 关键路径接入日志
- **日志卡片 UI**：设置页新增「应用日志」卡片（最近 50 条日志倒序显示、四级颜色区分、
  一键清空、导出全部日志到系统分享面板）；实时订阅日志更新

### Changed

- `MARKETING_VERSION` 提升至 0.8.13

## [0.8.12] - 2026-08-11

### Fixed（Phase 8.12 UI 卡顿问题根本修复）

- **批量更新 + 节流机制**：`SubtitleTranscriptStore` 作为 `@MainActor @Observable` 类，
  每次 `append()` 都立即触发 SwiftUI UI 刷新；高频识别结果（partial 段每秒数次、
  音频块更频繁）会完全卡死主线程；根本原因是 `@Observable` 的属性变更机制——
  每次写入 `segments` 都会通知所有观察者（播放器 Overlay、设置页等）立即重新渲染
- **解决方案**：引入批量更新 + 节流——`append()` 不再立即写入 `segments`，
  而是累积到 `pendingSegments` 缓冲区，最快每 150ms 批量提交一次（`scheduleFlush()`），
  大幅减少 UI 刷新频率；`segment(at:)` 查询时自动刷新缓冲区，确保最新字幕立即可见
  （不等待定时器）；`clear()` 和 `SubtitlePipeline.shutdown()` 调用 `flush()` 
  确保所有字幕都已写入；补充单元测试（批量更新行为 + 自动刷新）

### Changed

- `MARKETING_VERSION` 提升至 0.8.12

## [0.8.11] - 2026-08-11

### Fixed（Phase 8.11 修复 Phase 8.10 引入的问题）

- **还原字幕写入为同步方法**：`SubtitlePipeline.forwardSegment` 移除 
  `nonisolated` 标记与 `Task { @MainActor in }` 包裹，恢复为同步执行；
  修复 Phase 8.10 引入的 UI 卡住、字幕和翻译不显示的问题
- **根因分析**：Phase 8.10 将 `forwardSegment` 改为 `nonisolated` 并用异步 Task 包裹，
  导致字幕写入变成异步操作，引发执行顺序混乱和 UI 状态不一致；
  由于 `SubtitlePipeline` 整个类已标记 `@MainActor`，该方法无需额外隔离

### Changed

- `MARKETING_VERSION` 提升至 0.8.11

## [0.8.10] - 2026-08-11（❌ 失败弃用）

**Phase 8.10 标记失败**：尝试修复字幕开启后 UI 卡住问题，将 `forwardSegment` 
改为 `nonisolated` 并用 `Task { @MainActor in }` 包裹，导致字幕写入变成异步操作，
引发更严重的问题——视频能动但字幕和翻译完全不显示、所有 UI（包括播放器控制栏
和底部 Tab 栏）卡住点不动。代码已回退至 0.8.9，后续 Phase 忽略本次代码。

### 变更（Phase 8.10 基线回退，2026-08-11）

- 代码基线回退至 Phase 8.9 / 0.8.9（commit `a86c1b0`）：
  移除 0.8.10 的 `forwardSegment` 异步化改动，回到字幕功能正常的版本
- 保留说明文档（README / CHANGELOG / PROJECT_CONTEXT / ARCHITECTURE）
  并记录本次回退
- 后续修复将在 0.8.9 基线上进行（下一次 Phase 编号为 8.11）

## [0.8.9] - 2026-08-11

### Fixed（Phase 8.9 播放器 bug 修复）

- **大视频 UI 冻结修复**：`AssetReaderAudioPipeline.consume()` 解码循环
  从主线程 `Task` 改为后台线程 `Task.detached(priority: .userInitiated)`，
  避免大视频（1h 以上）解码时阻塞主线程导致 UI 冻结（视频声音继续但界面无响应）
- **网络资源播放停摆修复**：`SubtitlePipeline.makeSource` 按 URL 类型判断
  音频来源选路——本地文件（`url.isFileURL` 且非 HLS）优先用 AssetReader 预读，
  网络资源 / HLS 直接用 PlayerAudioPipeline 实时 Tap，避免 AVAssetReader 
  不支持 HLS 导致卡住（表现为播放器加载封面后点击开始 2 秒恢复暂停、
  拖动进度条可显示画面但暂停键失效）

### Changed

- `MARKETING_VERSION` 提升至 0.8.9

## [0.8.8] - 2026-08-11（❌ 失败弃用）

**Phase 8.8 标记失败**：实测修好了大视频播放 bug，但网页视频仍无法播放，
且字幕功能回归不可用（字幕卡片显示错误或停在「正在聆听」无法执行字幕显示
与语音识别，字幕记录与翻译记录均为空）。代码已回退至 0.8.7，后续 Phase 
忽略本次代码。

### 变更（Phase 8.8 基线回退，2026-08-11）

- 代码基线回退至 Phase 8.7 / 0.8.7（commit `b6ae7aa`）：
  移除 0.8.8 的播放器 / 音频来源选路改动，回到可正常识别字幕的版本
- 保留说明文档（README / CHANGELOG / PROJECT_CONTEXT / ARCHITECTURE）
  并记录本次回退
- 后续修复将在 0.8.7 基线上进行（下一次 Phase 编号为 8.9）

### 变更（工作流约定，2026-08-10）

- push 后 Codex 主动监控 CI：CI 通过则直接按版本约定打包 IPA，打包结束后
  通过 Bark 推送通知用户；CI 失败则尝试拉取日志修复，多次尝试仍无法拉取时
  通过 Bark 通知用户帮忙下载日志
- 记录 Bark 推送链接：`https://api.day.app/e9Ag3rveUM3ZGJqGQDb2oU/<推送内容>`
- 术语约定：「设置页」= 底部 Setting 选项卡，「播放器页」= 底部 Player 选项卡

## [0.8.7] - 2026-08-10

### Fixed（Phase 8.7 翻译不显示的根因修复）

- **翻译默认开启**：此前「启用翻译」默认关闭，final 段识别后从不调用翻译引擎、
  直接放行原文，是「只显示原语言、不显示翻译后语言」的最主要原因；
  现在默认开启（默认 Provider 为完全本地的 Fast NMT，无需隐私确认），
  已手动关闭过的用户设置保持不变
- **翻译可观测**：`SubtitlePipeline` 新增 `translatedSegmentCount`
  （成功翻译条数）与 `lastTranslationError`（最近一次失败原因）；
  设置页 AI 字幕卡片的识别状态行增加「已翻译 N 条」；翻译开始 / 成功 / 失败
  均有 OSLog 日志，失败原因不再静默吞掉
- **零时长 final 防御**：Whisper 时间戳异常（end <= start）的 final 片段
  按最小可显示时长（0.5s）收敛，字幕存储查询同样兜底，
  避免「翻译已产出但字幕永远不显示」的时间轴空洞

### Added（Phase 8.7）

- 设置页新增独立「翻译记录」卡片：展示最近 20 条已成功翻译的字幕
  （原文小字 + 译文大字 + 时间），头部显示已翻译总数；
  翻译失败时在卡片内直接提示失败原因，便于确认系统翻译是否真的被调用

### Changed（Phase 8.7 打包）

- 版本号提升至 0.8.7（Phase 8.7），两个 IPA 工作流默认版本同步为 0.8.7
- 0.8.7 IPA 已打包（GitHub Actions `package-ipa.yml`，2026-08-10）并可自签安装测试

## [0.8.6] - 2026-08-10

### Added（Phase 8.6 字幕语言与双语显示）

- 设置页新增独立「字幕语言」卡片（与「字幕记录」同层级）：
  - 「原语言」：视频语音 / 识别与翻译源语言，提供「自动检测」+ 12 种语言
    （简体中文 / English / 日本語 / 한국어 / Bahasa Melayu / Filipino / ไทย /
    Tiếng Việt / Bahasa Indonesia / Français / Deutsch / Español）；
  - 「翻译语言」：字幕译文输出语言（同样 12 种）；
  - 「双语显示」开关：开启时字幕上行原文（小字）、下行译文（大字）；
    关闭时只显示译文一行（译文缺失时显示原文）
- 语言选择真实生效：手动指定源语言后，Whisper 识别直接使用该语言
  （不再等待自动检测），翻译源语言同步切换；自动检测时翻译源语言跟随识别结果；
  切换源 / 目标语言会重建翻译引擎，Fast NMT 按新语言对初始化
- 原语言 / 翻译语言选择持久化（UserDefaults，新增 `translation.sourceLanguage.v1`），
  双语显示开关持久化（`subtitle.display.bilingual.v1`，默认开启）
- 翻译目标语言选择从「翻译服务」卡片移入「字幕语言」卡片，
  「翻译服务」卡片聚焦 Provider 与启用配置

### Changed（Phase 8.6 打包）

- 版本号提升至 0.8.6（Phase 8.6），两个 IPA 工作流默认版本同步为 0.8.6

## [0.8.5] - 2026-08-10

### Removed（Phase 8.5 删除超前识别）

- 删除超前识别（Lead-Ahead）功能：设置开关 / Δ 领先窗口（2–10s）滑杆 /
  播放前预读等待全部移除；`SubtitleSettings` 类与相关存储键删除，
  字幕管线统一走实时路径（固定 5 秒窗口，partial → final）
- 删除 `SubtitleEngine` 协议与 `SubtitleTimeline` 时间线实现，
  由共享 `SubtitleTranscriptStore` 取代

### Changed（Phase 8.5 字幕显示链路重构）

- 新增共享 `SubtitleTranscriptStore`（@MainActor @Observable，有界保留最近 200 条）：
  字幕管线每条识别 / 翻译结果（原文 + 译文）写入该存储；
  播放器 Overlay 直接按播放光标查询，不再消费单次迭代的 AsyncStream——
  修复播放器 Tab 反复进出 / 全屏切换后「识别已产出但播放器无字幕」的显示 bug
- 实时路径 partial 不再按播放位置丢弃（此前起点早于播放光标 1s 即被丢，
  识别稍慢时字幕整句缺失）；final 只在整句已播完时才丢弃
- 设置页新增「字幕记录」调试卡片：展示已识别字幕的原文 + 译文 + 时间
  （最多最近 20 条可见 / 存储 200 条），支持一键清空，便于排查字幕问题
- 音频管线协议移除 `canReadAhead`（仅超前识别使用）
- 播放器 / 设置页代码同步精简：移除 `prepareAIForPlayback` 中的预读等待、
  设置页移除超前开关与领先窗口控件

### Changed（Phase 8.5 打包）

- 版本号提升至 0.8.5（Phase 8.5），两个 IPA 工作流默认版本同步为 0.8.5

## [0.8.4] - 2026-08-10

> ⚠️ **失败版本（已弃用）**：Phase 8.4 实测无法使用，2026-08-10 结束并二次回退至
> 0.8.1 基线；本次实现已弃用，后续所有 Phase 忽略。

### 基线回退（Phase 8.4 开启）

- 代码基线回退至 Phase 8.1 / 0.8.1（commit `4449b16`）：
  移除 0.8.2 / 0.8.3 的翻译与字幕相关改动，回到可成功识别字幕 / 字母的版本；
  保留说明文档并记录本次回退（2026-08-10）

### Added（Phase 8.4 多语言与源/目标语言）

- 全语言池扩展至 12 种（简体中文 / English / 日本語 / 한국어 / Bahasa Melayu /
  Filipino / ไทย / Tiếng Việt / Bahasa Indonesia / Français / Deutsch / Español）
- 设置页「翻译服务」新增「语言列表」：可勾选语言是否在「原语言 / 目标语言」中呈现，
  并支持上移 / 下移排序（精确持久化用户勾选与排序）
- 设置页新增「原语言」选择（自动检测 + 已呈现语言）；手动指定时优先于识别语言，
  本地 / 云端 LLM 的 Prompt 会带上源语言提示
- 目标语言选项跟随语言列表（仅显示已呈现的语言）
- 播放器控制栏新增「字幕语言」按钮，紧邻字幕开关、开启字幕后才出现；
  菜单分栏明确标注「原语言 / 目标语言」，可在播放器页直接调整
- 设置页翻译卡片启用 Liquid Glass interactive，修复语言 / Provider 选择器无法操作

### Changed（Phase 8.4 打包）

- 版本号提升至 0.8.4（Phase 8.4），两个 IPA 工作流默认版本同步为 0.8.4

## [0.8.3] - 2026-08-10

> ⚠️ **失败版本（已弃用）**：Phase 8.3 实测仍有字幕 bug，代码已回退弃用，
> 后续所有 Phase 忽略本次实现。

### Fixed（Phase 8.3 实测反馈修复）

- 播放器字幕开关随识别管线激活 / 关闭自动同步：
  在设置页（或首页）开启识别后切回播放器，字幕开关自动点亮并显示字幕
- 原始实时路径 partial 不再被「早于播放位置」的过期判定丢弃
  （final 仍只在整句播完后丢弃），修复「识别已产出但播放器无字幕」
- 识别统计在管线激活时重置，设置页「已转写窗口 / 已产出字幕」反映当前会话
- 设置页翻译 / AI 字幕 / 字幕显示卡片启用 Liquid Glass 交互
  （`GlassCard.isInteractive`），修复语言与 Provider 选择器无法操作
- 播放器「字幕语言」菜单按 Section 分栏，明确标注「原语言 / 目标语言」

### Changed（Phase 8.3 打包）

- 版本号提升至 0.8.3（Phase 8.3），两个 IPA 工作流默认版本同步为 0.8.3

## [0.8.2] - 2026-08-10

> ⚠️ **失败版本（已弃用）**：Phase 8.2 实测无法正常使用，代码已回退弃用，
> 后续所有 Phase 忽略本次实现。

### Added（Phase 8.2 翻译功能增强）

- 翻译设置新增「原语言」选择（自动检测 + 已启用语言）：
  手动指定源语言时优先于识别语言；本地 / 云端 LLM 的 Prompt 会带上源语言提示
- 确认 Gemma 4 E2B 官方下载仓库 `mlx-community/gemma-4-e2b-it-4bit`
  （Hugging Face，主文件约 3.55 GB，文件清单与下载器匹配）；
  本地大模型按需下载、不随 App 内置，设置页可选择系统翻译 / 本地大模型 / 云端 API
- 多语言支持：语言池扩展至 12 种（简体中文 / English / 日本語 / 한국어 /
  Bahasa Melayu / Filipino / ไทย / Tiếng Việt / Bahasa Indonesia / Français /
  Deutsch / Español）；设置页可勾选语言是否呈现并排序
  （系统翻译仅支持 Apple 提供的语言对，马来文 / 菲律宾文等需用本地大模型）
- 播放器字幕开关打开后，控制栏出现「字幕语言」按钮（原语言 / 目标语言选择）

### Fixed（Phase 8.2）

- 语言列表持久化精确保持用户勾选与排序（此前重新加载会自动加回已关闭的语言）

### Changed（Phase 8.2 打包）

- 版本号提升至 0.8.2（Phase 8.2），两个 IPA 工作流默认版本同步为 0.8.2

## [0.8.1] - 2026-08-10

### Fixed（Phase 8.1 语音识别可用性）

- 识别参数修正：转写开启标准 prefill（SOT + 语言 + 任务 + 时间戳 token），
  并支持把已检测语言传给后续窗口（此前逐窗口重复自动检测，中文 / 短音频
  检测失败时用英文解码，结果为空或乱码）
- 识别游标跟随播放位置：播放器进度实时推送给字幕管线；识别速度跟不上播放时
  跳过已落后的窗口、从当前播放位置继续，避免字幕持续错过（「开了字幕却什么都没有」）
- 可观测性：设置页「AI 实时字幕」卡片新增识别状态行（引擎状态 / 模型加载 /
  识别语言 / 已转写窗口数 / 已产出字幕数）；关键链路加入 OSLog 日志
  （模型加载、音频来源、窗口转写开始 / 完成、缓冲等待），便于确认识别是否真的在跑

### Changed（Phase 8.1 打包）

- 版本号提升至 0.8.1（Phase 8.1），两个 IPA 工作流默认版本同步为 0.8.1

## [0.8.0] - 2026-08-10

### Fixed（Phase 8.0 语音识别字幕修复）

- 修复「播放视频没有字幕」的核心链路问题：
  - 播放器字幕开关此前只切换叠加层显示位，不会启动 AI 识别管线，
    在设置页/首页未开启时按了开关也没反应；现在打开播放器字幕开关会自动激活
    共享管线（设置页 / 首页开关保持不变）
  - 管线激活发生在播放中途时，识别游标改用引擎当前真实播放时间重建，
    不再从陈旧记录值（通常为 0）开始，避免识别永远追不上播放光标导致零字幕
  - 模型仍在加载时收到转写请求：识别器改为抛出「引擎未就绪」普通错误而非
    CancellationError，识别循环重试而不是永久退出（此前一旦抢先触发就再也不会恢复）
  - 识别循环对临时失败增加重试间隔，避免模型加载期空转打满 CPU
- 播放器内新增 AI 字幕状态提示：字幕开关开启但引擎加载中 / 出错 / 已关闭时，
  画面顶部显示状态胶囊（加载中 / 错误 / 已关闭），明确识别引擎状态

### Added（Phase 8.0 测试素材与双语预留）

- 内置普通话测试视频 `test.mp4` + 正确转写文本 `test.txt`：
  放入 `Resources/Samples/`（随 App 打包，调试入口优先加载；
  `test.txt` 入库，`test.mp4` 体积约 9 MB 保持 git 忽略、本地放置）
  注：GitHub Actions 打包的 IPA 不含 git 忽略的 `test.mp4`，
  设备上调试入口回退到 `sample.mp4` / 远程示例；本地 macOS 构建放入该文件即可随包
- 双语字幕结构保持就位：`SubtitleSegment.translatedText` + Overlay 第二行渲染
  已存在，译文可用时自动显示，Phase 8 后续只补翻译质量与开关

### Changed（Phase 8.0 打包）

- 版本号提升至 0.8.0（Phase 8.0），两个 IPA 工作流默认版本同步为 0.8.0

## [0.7.13] - 2026-08-10

### Removed（Phase 7.13 移除文件来源导入）

- 版本号提升至 0.7.13（Phase 7.13 移除文件来源导入）
- 移除「文件 App 导入视频」功能：该功能经多次修复（书签授权 → 复制到沙盒）
  仍不稳定，按用户要求整体下线；相册与 WebDAV 来源不受影响
- 删除文件导入相关代码与存储：`FilesMediaSourceView`、`PickedVideoFile`、
  `PickedFileStoring`、`UserDefaultsPickedFileStore` 及对应单测

### Changed（Phase 7.13）

- 保留 `MediaSourceKind.files` 枚举值与来源占位入口：兼容旧数据解码，并为
  后期恢复文件导入预留扩展点（模型 / VM / 视图均留有注释说明恢复步骤）

## [0.7.12] - 2026-08-10

### Fixed（Phase 7.12 实测反馈修复）

- 版本号提升至 0.7.12（Phase 7.12 实测反馈修复）

- 文件来源仍无法导入：iOS 文档选择器的临时授权不能靠普通书签跨会话保持，
  改为导入时把文件复制到 App Documents/MediaFiles 目录并登记本地 URL，
  跨启动始终可播放；删除来源文件时同步删除沙盒副本

## [0.7.11] - 2026-08-10

### Fixed（Phase 7.11 实测反馈修复）

- 版本号提升至 0.7.11（Phase 7.11 实测反馈修复）

- 相册来源点击视频崩溃：不再把 Photos 内部 URL 直接交给新的 AVPlayerItem，
  统一导出到 App 沙盒临时目录后按普通文件播放（iCloud 资源自动下载）
- 文件来源选择器「打开」无反应：改用系统 `fileImporter` 呈现文档选择器，
  避免在 sheet 内嵌 UIDocumentPickerViewController 的交互失效问题
- 媒体来源删除：来源区新增「编辑」模式显示删除按钮，长按卡片删除保留
- 全屏自动横屏仍失效：横竖屏检测改用播放器已加载的 asset（远程/HLS 也能
  识别）；旋转请求后校验实际方向，未生效则自动重试

## [0.7.10] - 2026-08-10

### Added（Phase 7.10 横屏识别/方向切换修复 + 媒体来源）

- 版本号提升至 0.7.10（Phase 7.10 横屏识别/方向切换修复 + 媒体来源）

- 修复横屏视频识别：分辨率检测改用 `preferredTransform` 修正旋转元数据，
  全屏入口检测未完成时重新检测并等待结论
- 修复全屏内横/竖屏切换：请求旋转前刷新 supportedInterfaceOrientations，
  横屏同时请求左右两个方向，失败自动重试一次；按钮状态按真实界面方向判断
- 主页「媒体来源」替代原「添加服务器」：支持网络（WebDAV）/ 相册 / 文件三类来源，
  多个来源均展示在主页并可分别打开
- 相册来源：列出系统相册视频（缩略图 + 时长），点击交给内置播放器；
  新增相册权限声明
- 文件来源：从文件 App 选取视频（安全作用域书签持久化，跨启动可用），点击播放
- 新增 `MediaSource` / `PickedVideoFile` 模型与存储，及对应单元测试

### Fixed（Phase 7.10）

- 全屏内横/竖屏切换失效：请求旋转前先刷新 supportedInterfaceOrientations，
  横屏同时请求左右两个方向，失败延迟重试一次；按钮状态按真实界面方向判断
- iOS 编译修复：`.withSecurityScope` 仅 macOS 可用改普通书签、
  `writeData(toFile:)` 参数标签、`UIInterfaceOrientation` 无 `.landscape`
  改 Bool 参数

## [0.7.9] - 2026-08-10

### Added（Phase 7.9 播放器细节优化 + 主页标签页）

- 版本号提升至 0.7.9（Phase 7.9 播放器细节优化 + 主页标签页）
- 播放器控制栏新增「设置」二级菜单，收纳重新播放 / 画面比例 / 重新初始化；
  删除音量按钮与音量相关代码（引擎协议、VM、测试替身同步清理）
- 视频横竖屏检测：加载时异步读取视频轨自然尺寸（宽 > 高为横屏）；
  横屏视频进入全屏时默认横屏
- 全屏内横屏/竖屏合并为单个切换按钮：当前横屏则切回竖屏，当前竖屏则切为横屏
- 浏览器地址栏新增「返回主页」按钮，一键回到刚进入 App 的首页
- 主页新增「标签页」区域：可手动添加常用网页快捷入口（名称 + 网址），
  点击直接打开，长按可删除；独立于收藏（收藏保持原状）
- WKWebView 启用 iOS 默认边缘滑动手势：从屏幕左侧右滑返回（有历史时）

### Changed（Phase 7.9）

- 新增 `HomeTab` / `HomeTabStoring` / `UserDefaultsHomeTabStore`，
  与历史、收藏存储相互独立

### Added（Phase 7.9 回归测试）

- 新增主页标签页存储测试（增删、按网址去重）与浏览器 VM 测试
  （返回主页复位、标签页添加/打开/删除、非法网址忽略），清理音量测试桩

## [0.7.8] - 2026-08-10

### Added（Phase 7.8 播放器状态与进度兜底）

- 版本号提升至 0.7.8（Phase 7.8 播放器状态与进度兜底）

### Fixed（Phase 7.8）

- 播放按钮状态不随播放切换（视频在播但按钮仍为「播放」、无法暂停）：
  引擎 `play()` / `pause()` 直接维护权威状态，不再只依赖 `timeControlStatus`
  KVO 回调；`seek()` 与加载完成路径同步状态，VM 在每次播放控制后立即从引擎
  同步 `playbackState`，即使状态流未送达 UI 也能即时切换；加载失败时引擎状态
  同步标记为 failed（不再停留在 loading 让 UI 无法恢复），failed 态禁止直接
  play（只能重试）（2026-08-10）
- 时间栏不显示当前时间 / 进度条不动：引擎新增 0.5s 兜底节拍器，周期读取
  AVPlayer 当前时间 / 时长 / 状态并推送（与周期观察者双通道并存）；VM 新增
  轮询兜底，周期直接同步引擎属性，流未送达时 UI 仍能更新（2026-08-10）
- 拖动进度条从 0 重播：时长未知时进度条禁用拖动（避免 0...1 退化范围把任意
  拖动视为 seek 到开头）；加载完成即推送一次进度让时长尽快就绪；`seek` 目标
  收敛到已知时长范围；时长未知时显示 `--:--`（2026-08-10）
- `emitProgress` 对非有限时间回退 0，避免 NaN 污染时间标签与进度条（2026-08-10）

### Added（Phase 7.8 回归测试）

- 新增静默播放引擎（不 yield 状态/进度流）：验证 VM 不依赖流也能同步
  播放状态、时间与时长；补 seek 后时间/时长同步断言（2026-08-10）

### Changed（2026-08-10）

- 阶段规划调整：Phase 8 改为修好语音识别功能与翻译功能（当前为半成品状态）；
  Phase 9 & Phase 9+ 为 Liquid Glass 深化（变形过渡）、性能、测试与错误处理。
- 新增版本与打包约定：同一 Phase 内每打包一次 IPA，版本号递增一个小版本
  （`0.7.x` → `0.7.(x+1)`），Phase 编号同步变更（`7.x` → `7.(x+1)`）；
  当前基线 0.7.7，下一次打包应为 0.7.8。

## [0.7.5] - 2026-08-09

### Added（Phase 7.5 完善）

- 版本号提升至 0.7.5（Phase 7.5 修复与完善）
- 新增 `package-ipa.yml` 工作流：构建未签名 IPA，上传为 Actions 工件并发布
  GitHub Release（默认版本 0.7.5；`release-ipa.yml` 默认版本同步更新）
- 浏览器地址栏右侧新增「清空当前网址」按钮（×），一键清空输入
- 浏览器内视频接入内置播放器：
  - WKWebView 开启内联播放（blob: 等不可直连流在页面内播放，不再跳转系统全屏播放器）；
  - 点击 .mp4 / .m3u8 / 音频等直链时拦截导航，转交内置播放器；
  - 注入桥接脚本：页面内 HTML5 `<video>` 播放可直连媒体时上报 App，
    由内置播放器接管（标题取 video title / aria-label / 页面标题）
- 示例视频内置：`scripts/fetch-sample-video.sh` 构建时从 CDN 下载约 1 MB MP4
  （test-videos.co.uk Big Buck Bunny 10 秒，可用 `SAMPLE_VIDEO_URL` 更换），
  运行时优先加载内置文件（离线可播）；修复原 googleapis 示例 URL 返回 403
  导致「测试视频无法播放」的问题

### Fixed（Phase 7.5 续）

- `AVPlayerPlaybackEngine.deinit` 在 Swift 6 严格并发下无法访问非 Sendable
  观察者属性，导致 CI 编译失败：观察者属性标记 `nonisolated(unsafe)`
  （仅 MainActor 与 deinit 访问，deinit 时对象不再被并发访问）
- `decidePolicyFor` 的 `decisionHandler` 闭包补 `@MainActor` 注解
  （iOS 26 SDK 协议要求），否则 WKWebView 不会调用该方法，直链视频拦截失效
- 新增的 `staleSegmentsBeforePlaybackTimeAreDropped` 测试误用了另一测试文件
  的 Mock 方法：为 `SubtitlePipelineTests` 的 `MockSpeechRecognizer` 补 `emit`
- `SubtitlePipeline.activate()` 未使用的 `engine` 绑定改为布尔判断（清警告）

### Fixed（Phase 7.5 成品 Debug）

- 浏览器后退 / 前进 / 刷新按钮命令未送达 WKWebView：`pendingCommand` 变化未被
  任何 View 观察，`WebViewRepresentable.updateUIView` 不会触发。新增
  `commandVersion` 作为代表视图输入参数，命令变化时强制刷新驱动（2026-08-09）
- 换片后字幕管线沿用上一部视频的音频来源（旧视频字幕串到新视频时间线）：
  `preparePlayback` 按引擎当前媒体 ID 检测换片并重建音频来源（2026-08-09）
- seek / 停止后仍在途的 Whisper 转写结果（partial / final）仍被透出到字幕流：
  识别器增加 generation 门控（锁保护世代计数，兼容音频线程回调）+
  管线转发按播放位置丢弃过期片段（2026-08-09）
- WebDAV 连接失败后内存会话残留凭据：`connect` 失败时清除 profile / credentials，
  避免残留凭据被后续 `listDirectory` 使用（2026-08-09）
- 本地大模型下载「取消后立即重试」会并发重复下载：`cancel` 不再立即置空任务引用，
  保留至任务自然结束；`deleteModel` 等待任务结束后再删除目录（2026-08-09）
- AVPlayer 媒体加载无超时（坏 URL 永久 loading）：增加 60 秒加载超时；
  引擎 deinit 清理周期观察者与结束通知（2026-08-09）
- `PlayerAudioPipeline` 音频 Tap 按 Float32 强读（未校验格式，存在越界读风险）：
  按 `kAudioFormatFlagIsFloat` 区分 Float / Int16，并按 `mDataByteSize` 限制读取（2026-08-09）
- 云端翻译可在未「测试连接 + 隐私确认」时直接启用（违反隐私红线）：
  启用校验增加「测试连接成功」与「隐私确认」两个前置条件（2026-08-09）

## [0.7.6] - 2026-08-09

### Added（Phase 7.6 播放器换片复位）

- 版本号提升至 0.7.6（Phase 7.6 播放器换片复位 + 手动初始化）
- 播放器控制栏新增「手动初始化」按钮（重新加载当前媒体），
  播放失败状态新增「重试」按钮

### Fixed（Phase 7.6）

- 换片播放失败 / 转圈残留：`PlayerViewModel.load` 改为「先复位再加载」——
  换片立即清空进度与状态、取消旧加载任务，并用 generation 守卫保证
  旧加载（超时/失败）不会覆盖新媒体的状态；引擎换片同步复位进度与倍速，
  `waitUntilReady` 检测到当前条目被替换即视为本加载已失效（2026-08-09）

## [0.7.7] - 2026-08-09

### Added（Phase 7.7 播放器状态与进度修复）

- 版本号提升至 0.7.7（Phase 7.7 播放器状态与进度修复）

### Fixed（Phase 7.7）

- 播放按钮状态错乱（视频在播放却显示暂停）：换片加载先 `avPlayer.pause()`
  避免新条目因 rate 保持 1 自动播放；引擎状态机禁止 `.playing` 被 `.ready`
  回退；VM 仅在仍处于 loading 态时置 ready（2026-08-09）
- 进度条不显示当前视频数据 / 拖动进度条从 0 重新播放：HLS 或时长未就绪时
  `currentItemDuration` 用可 seek 范围末端近似时长（否则 slider 范围退化为
  0...1，拖动即视为 seek 到开头）（2026-08-09）
- `CMTime.seconds` 是非可选 `Double`，`currentItemDuration` 误用 `if let`
  导致 CI 编译失败：改为直接取值后判等（2026-08-09）

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
- GitHub Actions：新增手动触发工作流 `release-ipa.yml`——构建未签名 iphoneos Release IPA
  并自动创建 GitHub Release（供 Sideloadly / AltStore / 爱思助手 等自签工具使用）；
  `MARKETING_VERSION` 提升至 0.7.0
- 首次通过 `release-ipa.yml` 产出未签名 IPA（`AIVideoPlayer-0.7.0-unsigned.ipa`）
  并发布到 GitHub Release（2026-08-09）
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
- CI 测试运行期修复：Keychain 单测在模拟器无签名 entitlement（-34018）时标记 disabled；
  URLProtocol 桩补充 httpBodyStream 读取（URLSession 会把 httpBody 转为流）；
  管线润色上下文测试首句断言改为 nil；设置缓存键测试修正切回 Provider 后的断言（2026-08-09）

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
