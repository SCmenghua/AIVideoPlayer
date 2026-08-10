# AI Video Player Project Context

## 产品目标

一个长期维护的个人 iOS 项目：iOS 26 原生视频播放器，目标形态为
「PotPlayer + 浏览器 + AI 实时字幕 + 远程文件浏览器」。

核心能力：App 内网页浏览、WebDAV / SMB / FTP 远程文件访问、自动识别可播放媒体、
自有 AVPlayer 播放、完整播放器 UI、Whisper 本地实时语音识别、AI 双语字幕、
可替换翻译架构、原生 Liquid Glass UI。

质量目标：高质量、可扩展、可维护、性能稳定、符合 Apple 原生设计规范。

## 当前Phase

**Phase 8.0**（已完成，2026-08-10 打包 0.8.0）：修复语音识别功能——先解决
「开启后播放视频没有任何字幕输出」的核心链路问题（播放器开关未联动管线激活、
播放中途激活从陈旧时间重建游标、模型加载期识别循环永久退出），并预留双语字幕空间。
**Phase 8.1**（已完成，2026-08-10 打包 0.8.1）：修复「开关已生效但看不到字幕」——确认字幕开关链路
（设置页 / 播放器联动）真实生效；修正识别参数（标准 prefill + 语言传递）、
识别游标跟随播放位置并跳过落后窗口；设置页新增识别状态统计，便于确认
模型是否真的被调用并产出字幕。
**Phase 8.2**（已完成，2026-08-10 打包 0.8.2）：翻译功能增强——确认默认使用
系统内置翻译（Fast NMT，Apple Translation，完全本地）；本地大模型
（Gemma 4 E2B 4-bit，约 3.55 GB）按需从 Hugging Face 下载、不随 App 内置，
设置页可选择系统翻译 / 本地大模型 / 云端 API；新增「原语言 / 目标语言」选择；
多语言池 12 种，设置页可勾选呈现与排序；播放器字幕开启后出现「字幕语言」按钮。
**Phase 8.3**（已完结，2026-08-10 打包 0.8.3；仍有实测 bug 待后续修复）：实测反馈修复——播放器字幕开关
随识别管线激活自动同步、实时字幕显示修复（partial 不再被过期判定丢弃）、
设置页语言与 Provider 选择器交互修复（玻璃卡片 interactive）、
播放器语言菜单分栏标注原 / 目标语言；识别统计按会话重置。
**Phase 8.4**（已完结，2026-08-10 打包 0.8.4）：代码基线回退至 Phase 8.1 / 0.8.1
（commit `4449b16`）后重建多语言与源/目标语言——全语言池 12 种（含日文等），
设置页「语言列表」可勾选呈现并排序；设置页与播放器均可调整「原语言 / 目标语言」；
播放器「字幕语言」按钮紧邻字幕开关、开启字幕后才出现，菜单分栏明确标注
原语言 / 目标语言；仍有实测 bug 待后续修复（具体清单待用户提供）。
**Phase 8.5+**（规划中）：根据实测继续完善识别 / 翻译（含本地模型下载镜像等）。
**Phase 9 & Phase 9+**（规划中）：完成 Liquid Glass 深化（变形过渡）、性能、
测试与错误处理。
上一阶段：**Phase 7.13 —— 移除文件来源导入**（已完成；Phase 7.5–7.13
已整体收尾）。

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
    **无需再加 `[skip ci]` 标记**；
  - **禁止把带 `[skip ci]` 的提交与代码提交合并到同一次 push**：GitHub 会因一次 push 中
    任意提交含跳过标记（`[skip ci]` / `[ci skip]` 等）而跳过整个 push 的工作流；
    若确要使用 `[skip ci]`，文档提交必须单独 push（2026-08-09 曾因此导致 CI 未触发）；
  - 涉及代码的改动：push 会触发 CI，需确保改动通过编译 / 测试后再提交，
    不需要主动关注 CI 结果。
- **CI 结果由用户告知，Codex 不主动关注**：提交后的 CI 运行结果不轮询、不主动跟踪，
  由用户通知；若 CI 失败，用户下载失败日志发送给 Codex 进行排查修复；
  若 CI 成功，则直接进行收尾。
- **版本号与打包约定**：同一 Phase 内按小版本迭代时（如 Phase 7.x 系列），
  每打包一次 IPA，下一次打包版本递增一个小版本——上一次 `0.7.x` → 下一次
  `0.7.(x+1)`；文档中的 Phase 编号同步变更（`Phase 7.x` → `Phase 7.(x+1)`）。
  打包时同步提升 `MARKETING_VERSION`（project.yml）与两个 IPA 工作流
  （`package-ipa.yml` / `release-ipa.yml`）的默认版本号。
  当前代码基线：0.8.4（Phase 8.4，2026-08-10 打包），
  下一次打包应为 0.8.5（Phase 8.5）。

## 已完成

- **Phase 8.4 基线回退**（2026-08-10）：代码基线回退至 Phase 8.1 / 0.8.1
  （commit `4449b16`），移除 0.8.2 / 0.8.3 的翻译与字幕相关改动；
  保留 4 份说明文档（README / CHANGELOG / PROJECT_CONTEXT / ARCHITECTURE）
  并记录本次操作；后续字幕 bug 修复将在 0.8.1 基线上进行。
- **Phase 8.4 功能实现**（2026-08-10，打包 0.8.4）：多语言与源/目标语言——
  全语言池 12 种（含日文等），设置页「语言列表」可勾选呈现并排序；
  设置页与播放器均可调整「原语言 / 目标语言」；播放器「字幕语言」按钮
  紧邻字幕开关、开启字幕后才出现，菜单分栏明确标注原语言 / 目标语言；
  设置页翻译卡片启用 Liquid Glass interactive（修复选择器无法操作）。
- **Phase 8.3**：实测反馈修复——播放器字幕开关随识别管线激活 / 关闭自动同步
  （设置页开启识别后切回播放器自动点亮字幕）；原始实时路径 partial 不再被
  「早于播放位置」丢弃，修复「识别已产出但播放器无字幕」；识别统计在管线
  激活时重置；设置页交互卡片启用 Liquid Glass interactive（修复语言与
  Provider 选择器无法操作）；播放器「字幕语言」菜单分栏标注原语言 / 目标语言；
  `MARKETING_VERSION` 提升至 0.8.3。

- **Phase 8.2**：翻译功能增强——确认默认使用系统内置翻译（Apple Translation）；
  本地大模型（Gemma 4 E2B 4-bit）按需下载（Hugging Face 官方仓库
  `mlx-community/gemma-4-e2b-it-4bit`，约 3.55 GB，文件清单核对匹配），
  设置页可选择系统翻译 / 本地大模型 / 云端 API；翻译设置新增「原语言」
  （自动检测 + 已启用语言）与「目标语言」选择，手动源语言优先于识别语言，
  LLM Prompt 携带源语言提示；多语言池扩展至 12 种，设置页可勾选呈现并排序
  （语言列表持久化精确保持用户选择）；播放器字幕开关开启后控制栏出现
  「字幕语言」按钮（原 / 目标语言快捷选择）；`MARKETING_VERSION` 提升至 0.8.2。

- **Phase 8.1**：修复「开关已生效但看不到字幕」——确认字幕开关链路真实生效；
  识别参数修正（标准 prefill + 语言传递，中文 / 短音频识别更稳）；
  识别游标跟随播放位置、落后窗口跳过（避免识别速度跟不上时字幕持续错过）；
  设置页新增识别状态统计（模型加载 / 转写窗口 / 字幕产出）与 OSLog 日志；
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

- **Phase 7.5**：对 Phase 1–7 成品做整体 Debug + 实测反馈完善——
  修复浏览器后退/前进/刷新命令未送达、换片字幕沿用旧视频音频源、seek 后过期识别结果
  透出、WebDAV 连接失败凭据残留、本地模型下载取消竞态、播放器加载无超时、
  音频 Tap 格式强读越界风险、云端翻译绕过隐私校验、CI 编译失败（deinit 并发）等；
  完善地址栏「清空当前网址」按钮、浏览器内视频接入内置播放器
  （内联播放 + 直链拦截 + HTML5 video 桥接）、构建时内置示例视频
  （原 googleapis 示例 URL 403 导致测试视频无法播放）；同步补充单元测试；
  `MARKETING_VERSION` 提升至 0.7.5，新增 `package-ipa.yml`（未签名 IPA →
  Actions 工件 + GitHub Release，供自签测试）。
- **Phase 7.6**：播放器换片复位——`PlayerViewModel.load` 先复位（进度/状态/
  字幕循环）再加载，旧加载任务取消 + generation 守卫，防止换片后旧任务
  覆盖新状态（转圈/旧进度残留）；引擎换片复位进度/倍速、`waitUntilReady`
  检测到当前条目被替换即视为本加载失效；播放器控制栏新增「手动初始化」
  按钮、失败态新增「重试」；补充单测；`MARKETING_VERSION` 提升至 0.7.6。
- **Phase 7.7**：播放器状态与进度修复——换片加载先 `avPlayer.pause()`
  避免新条目因 rate 保持 1 自动播放；引擎状态机禁止 `.playing` 被 `.ready`
  回退、VM 仅在仍处于 loading 态时置 ready；HLS / 时长未就绪时
  `currentItemDuration` 用可 seek 范围末端兜底，修复进度条不显示与
  拖动从 0 重播；修 `CMTime.seconds` 误用 `if let` 的 CI 编译失败；
  `MARKETING_VERSION` 提升至 0.7.7。
- **Phase 1**：App 骨架、三 Tab（Browser / Player / Settings）、Liquid Glass Design System、
  核心协议与模型、Mock、单元测试、GitHub Actions CI。
- **Phase 2**：WKWebView 浏览器（真实地址栏/历史/收藏）、WebDAV 远程文件浏览
  （PROPFIND + 多级目录导航）、Keychain 凭据、服务器配置与历史/收藏持久化。
- **Phase 3**：`AVPlayerPlaybackEngine`（播放/暂停/进度/倍速/音量/seek，状态流 + 进度流）、
  自定义播放器 UI（**无 AVPlayerViewController**）、玻璃控制栏、画面大小滑块（0.5x-2.0x）、
  YouTube 风格全屏（隐藏 Tab/Nav/状态栏、竖屏锁定时可横屏、手动横屏兜底按钮）、
  远程文件视频 → 播放器交接、播放器空状态调试入口（开发期专用，删除说明见架构文档 8.1.2）。
- **Phase 4**：`WebMediaExtractor`（Services/Media，直链媒体 / HLS / HTML5 video 提取，
  相对地址解析、HTML 实体解码、去重；不绕过 DRM）、浏览器地址栏「提取视频」按钮 +
  结果列表（`MediaExtractionSheet`）→ `AppEnvironment.requestPlayback`、远程文件 `m3u8` / `m3u`
  识别为 video、单元测试（提取器 / 浏览器提取状态 / HLS 映射）。
- **Phase 5**：WhisperKit（`argmax-oss-swift from 1.0.0`，CI 解析 1.1.0）本地实时识别；模型随 App 内置
  （构建脚本打包，运行时不下载、无需用户选择）；`AudioPipeline` 三来源
  （AVAssetReader 预读 / MTAudioProcessingTap 实时 / 麦克风）、`WhisperKitSpeechRecognizer`、
  真实 `SubtitlePipeline`（替换 Mock 注入）；超前识别开关（默认开）+ 2–10s 领先窗口（默认 3s，
  UserDefaults 持久化）；播放器播放前预读 Δ 秒、seek 重建领先窗口、识别游标只进不退；
  状态卡与设置页接入真实管线；单元测试（设置 / 缓冲 / 管线 / 播放器联动）。
- **Phase 6**：`SubtitleTimeline`（SubtitleEngine 真实实现：final 优先于 partial、
  final 到达收敛逐词残留、500 条内存上限）；`SubtitleOverlay` 双语整句字幕叠加
  （按播放光标对齐一次性出现、DragGesture 拖动调整位置、字号样式）；
  `SubtitleDisplaySettings`（字号 + 归一化位置，UserDefaults 持久化，AppEnvironment 共享）；
  播放器普通 / 全屏接入、设置页「字幕显示」卡片；单元测试（时间线 / Overlay VM / 显示设置）。
- **Phase 7**：TranslationEngine 可替换翻译架构——Fast NMT（Apple 原生翻译，完全本地）/
  本地 LLM（MLX Swift + Gemma 4 E2B 4-bit，按需下载 + 进度 / 取消 / 重试 / 删除）/ 云端 API
  （OpenAI 兼容，测试连接 + 隐私提示，API Key 存 Keychain）；剧情理解润色（上下文压缩）；
  final 段提前翻译写入 `SubtitleSegment.translatedText`，翻译期间 `.translating` 状态；
  设置页「翻译服务」卡片；单元测试；`release-ipa.yml` 打包未签名 IPA 发布到 GitHub Release
  （自签安装，首次产出 `AIVideoPlayer-0.7.0-unsigned.ipa`）。
- **文档**：README / ARCHITECTURE / CHANGELOG / PROJECT_CONTEXT；纯文档改动不触发 CI。

## 禁止事项

- **禁止使用 `AVPlayerViewController`**：播放器必须使用 AVPlayer + SwiftUI 自定义 UI。
- **禁止伪 Liquid Glass**：禁止用 `.blur()` / `.opacity()` / `.ultraThinMaterial` 模拟玻璃；
  必须使用 iOS 26 原生 `glassEffect` / `GlassEffectContainer` / `.glass` / `.glassProminent`。
- **Liquid Glass 实现必须遵循 `liquid-glass-design` skill**：所有玻璃组件、交互与变形过渡
  按 `D:\code\CodeX\.agents\skills\liquid-glass-design\SKILL.md` 编写；
  新增或修改玻璃 UI 前先阅读该 skill（多玻璃元素放入 `GlassEffectContainer`、
  仅交互元素加 `.interactive()`、变形过渡用 `@Namespace` + `glassEffectID` 等）。
- **禁止跳 Phase**：严格按 Phase 顺序开发，禁止提前实现后续 Phase。
- **纯文档内容、不涉及程序代码的部分禁止触发 CI**：CI push 触发已配置
  `paths-ignore: *.md, docs/**`，纯文档提交无需 `[skip ci]` 标记；
  **禁止把带 `[skip ci]` 的提交与代码提交合并到同一次 push**（GitHub 会跳过整个 push 的工作流）。

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
| 媒体 | AVFoundation / AVPlayer（已接入）；HTML5 video / HLS 提取（Phase 4 已接入） |
| 浏览器 | WKWebView（已接入） |
| 远程文件 | URLSession + WebDAV PROPFIND（已接入）；SMB / FTP 后续补充 |
| 安全存储 | Keychain（已接入）、UserDefaults |
| AI | WhisperKit / Core ML（Phase 5 已接入，本地运行；模型内置；超前缓冲识别 2–10s） |
| 翻译 | 可替换 TranslationEngine（Phase 7 已接入：Apple Translation / MLX Swift 本地 LLM（Gemma 4 E2B，按需下载）/ 云端 OpenAI 兼容 API；API Key 存 Keychain） |
| 工程 | XcodeGen（project.yml 生成工程）；GitHub Actions：主 CI（build/test）+ release-ipa（unsigned IPA → GitHub Release） |
| 测试/CI | Swift Testing；GitHub Actions（xcodegen + xcodebuild build/test，macOS runner） |
