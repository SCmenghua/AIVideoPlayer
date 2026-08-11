# AI Video Player - Changelog

> 所有重要变更的记录，按时间倒序排列（最新在上）

## [0.8.11] - 2026-08-11

### 修复
- **UI 卡顿问题**：将 `translateAndYield` 中的系统翻译操作移至后台线程（`Task.detached`），翻译完成后回到主线程写入结果，解决主线程阻塞导致的 UI 完全无响应问题
- 保持 `forwardSegment` 为同步 `@MainActor` 方法，确保字幕写入链路清晰
- 修复视频能播放但字幕和翻译不显示、播放器控制栏和底部 Tab 栏卡住无法操作的问题

### 技术细节
- `SubtitlePipeline.translateAndYield` 改为 `nonisolated`，用 `Task.detached` 在后台执行翻译
- 翻译完成后用 `await MainActor.run` 回到主线程写入字幕记录
- 根本原因：系统翻译（NLTranslator）可能耗时数百毫秒，不应在主线程同步调用

### 版本信息
- `MARKETING_VERSION`: 0.8.11
- IPA: `AIVideoPlayer-0.8.11-unsigned.ipa`

## [0.8.10] - 2026-08-11 ❌ 已弃用

### 状态
**失败并回退**：尝试修复 UI 卡顿，但导致更严重的问题（字幕和翻译完全不显示、所有 UI 卡住点不动）

### 尝试的修复（错误）
- 将 `forwardSegment` 改为 `nonisolated` 并用 `Task { @MainActor in }` 包裹
- 导致字幕写入变成异步操作，引发 UI 更加卡顿

### 回退
- 代码已回退至 Phase 8.9 / 0.8.9（commit `a86c1b0`）
- 后续 Phase 忽略本次代码

## [0.8.9] - 2026-08-11

### 修复
- **大视频 UI 冻结**：`AssetReaderAudioPipeline.consume()` 解码循环用 `Task.detached` 移到后台线程，避免阻塞主线程 UI
- **网络资源播放停摆**：`SubtitlePipeline.makeSource` 按 URL 类型判断——本地文件优先用 AssetReader 预读、网络资源/HLS 直接用 PlayerAudioPipeline 实时 Tap，避免 AVAssetReader 不支持 HLS 导致卡住

### 版本信息
- `MARKETING_VERSION`: 0.8.9
- IPA: `AIVideoPlayer-0.8.9-unsigned.ipa`

---

*更多版本记录请查看 Git 提交历史和文档*
