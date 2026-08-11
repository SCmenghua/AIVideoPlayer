# Phase 8.11 Summary

## 目标
修复 UI 卡顿问题——视频能播放，但字幕和翻译不显示，所有 UI（包括播放器控制栏和底部 Tab 栏）卡住点不动

## 问题分析

### 根本原因
Phase 8.10 的问题不在于 `forwardSegment` 的同步/异步，而在于 `translateAndYield` 在主线程同步执行系统翻译操作。

系统翻译（NLTranslator）调用可能耗时数百毫秒，在主线程执行会：
- 阻塞主线程渲染
- 导致 UI 完全无响应
- 播放器控制栏卡死
- 底部 Tab 栏无法切换

### Phase 8.10 的错误尝试
将 `forwardSegment` 改为 `nonisolated` 并用 `Task { @MainActor in }` 包裹，导致：
- 字幕写入变成异步操作
- UI 更加卡顿
- 字幕和翻译完全不显示

## 解决方案

### 核心思路
1. **保持 `forwardSegment` 为同步 `@MainActor` 方法**，确保字幕写入链路清晰
2. **将翻译操作移至后台线程**，避免阻塞主线程
3. **翻译完成后回到主线程写入结果**

### 具体实现

在 `SubtitlePipeline.swift` 中修改 `translateAndYield(_:)` 方法：

```swift
private nonisolated func translateAndYield(_ segment: SubtitleSegment) {
    Task.detached { [weak self] in
        guard let self else { return }

        // 在后台线程执行翻译（可能耗时数百毫秒）
        var translated = segment
        if self.translationEnabled, !segment.text.isEmpty {
            do {
                let result = try await self.translator.translate(segment.text)
                translated.translatedText = result
                await self.updateTranslationRecord(/* ... */)
            } catch {
                await self.recordTranslationFailure(/* ... */)
            }
        }

        // 翻译完成后回到主线程写入结果
        await MainActor.run {
            self.transcriptStore.append(translated)
        }
    }
}
```

**关键点**：
- `nonisolated` 标记方法本身不绑定到主线程
- `Task.detached` 在后台线程执行翻译
- `await MainActor.run` 确保最终写入在主线程

## 修改文件

### SubtitlePipeline.swift
- 保持 `forwardSegment` 为同步 `@MainActor` 方法
- 修改 `translateAndYield` 为 `nonisolated` 并用 `Task.detached` 包裹翻译逻辑
- 翻译完成后用 `await MainActor.run` 回到主线程写入

## 验证结果

✅ **完全修复**：
- 视频播放流畅
- 字幕实时显示
- 翻译正常工作
- 播放器控制栏响应正常
- 底部 Tab 栏切换流畅
- UI 完全不卡顿

## 版本信息
- **Phase**: 8.11
- **Version**: 0.8.11
- **Date**: 2026-08-11
- **Status**: ✅ 已完成

## 经验教训

1. **性能问题定位要准确**：UI 卡顿不一定是同步/异步问题，可能是主线程执行了耗时操作
2. **系统 API 调用要小心**：NLTranslator 等系统翻译 API 可能耗时较长，不应在主线程调用
3. **保持架构清晰**：不要为了修复而破坏原有的清晰架构（如 Phase 8.10 错误地改变了 `forwardSegment`）
4. **后台线程 + 主线程结合**：耗时操作在后台线程，UI 更新回到主线程
