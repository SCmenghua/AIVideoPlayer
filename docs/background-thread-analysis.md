# 后台线程优化方案分析

> **项目状态：已停止并归档。** 本文件仅保留为旧项目的历史问题分析，不再按本文方案继续修改代码。

## 背景

Phase 8.17 的第三个修复目标：将识别循环移到后台线程，避免主线程阻塞导致 UI 冻结。

## 尝试的修改

从 commit `4571245` 到 `8757ce7`，共 10 次提交尝试将 `runRecognitionLoop` 从 `@MainActor` 移到 `nonisolated`（后台线程）。

### 核心代码变更

**原始代码（a4dc8c4）**：
```swift
@MainActor
@Observable
public class SubtitlePipeline: SubtitleStatusProviding {
    // ...
    private var recognizer: (any SpeechRecognizer)?
    
    private func runRecognitionLoop(generation: Int) async {
        // ...
        while await active && await self.generation == generation && !Task.isCancelled {
            guard let recognizer = await self.recognizer else { return }
            
            // 直接调用识别器
            let outcome = try await recognizer.transcribe(
                samples: samples,
                sampleRate: sampleRate,
                windowStart: windowStart,
                windowDuration: windowSize,
                language: effectiveLang,
                emitPartial: true,
                recognitionSessionID: sessionID
            )
            // ...
        }
    }
}
```

**修改后的代码（8757ce7，编译失败）**：
```swift
@Observable  // 移除了 @MainActor
public class SubtitlePipeline: SubtitleStatusProviding {
    // ...
    private var recognizer: (any SpeechRecognizer)?  // 仍然是 @MainActor 隔离的
    
    nonisolated private func runRecognitionLoop(generation: Int) async {
        // ...
        while !Task.isCancelled {
            // 问题：在 nonisolated 上下文中访问 @MainActor 属性
            let hasRecognizer = await MainActor.run { self.recognizer != nil }
            guard hasRecognizer else { return }
            
            // 问题：MainActor.run 只接受同步闭包，但 transcribe 是 async
            let outcome: RecognitionOutcome = try await MainActor.run {
                guard let recognizer = self.recognizer else {
                    throw CancellationError()
                }
                // ❌ 编译错误：cannot pass function of type '@Sendable () async throws -> RecognitionOutcome' 
                //    to parameter expecting synchronous function type
                return try await recognizer.transcribe(...)
            }
            // ...
        }
    }
}
```

## 遇到的编译错误

### 1. MainActor.run 不支持 async 闭包（第 5 次提交）
```
error: cannot pass function of type '@Sendable () async throws -> RecognitionOutcome' 
       to parameter expecting synchronous function type
```

**原因**：`MainActor.run` 的签名是：
```swift
static func run<T>(body: @Sendable () throws -> T) async rethrows -> T
```
闭包参数是**同步的**，但我们试图在里面 `await recognizer.transcribe()`。

### 2. Sendable 一致性错误（第 6-7 次提交）
```
error: type 'any SpeechRecognizer' does not conform to the 'Sendable' protocol
```

**原因**：在 `nonisolated` 上下文中捕获 `recognizer` 变量，Swift 6 要求它必须是 `Sendable` 的，但 protocol 没有声明 Sendable。

### 3. guard let 与 await 表达式冲突（第 9 次提交）
```
error: guard let cannot use await expressions directly
```

**原因**：`guard let recognizer = await MainActor.run { ... }` 不符合 Swift 语法。

## 为什么会选择这种错误方法？

### 初始假设（看似合理）
1. **问题诊断**：30 分钟视频冻结，怀疑是主线程被识别循环阻塞
2. **解决思路**：将耗时操作移到后台线程，让主线程专注于 UI
3. **实现策略**：标记 `runRecognitionLoop` 为 `nonisolated`，需要访问主线程属性时用 `MainActor.run`

### 忽略的关键事实
**`async/await` 本身就是非阻塞的**：
- 当代码执行到 `await` 时，会**主动让出执行权**
- 线程可以去处理其他任务（包括 UI 事件）
- 即使在主线程上调用 `async` 方法，也不会阻塞主线程

### 陷入的死循环
1. 移到 `nonisolated` → 无法直接访问 `@MainActor` 的 `recognizer`
2. 用 `MainActor.run` 包装 → 闭包必须是同步的
3. 但 `transcribe` 是 `async` → 无法在同步闭包中调用
4. 尝试各种变通（helper 方法、Sendable 标记）→ 都无法解决根本矛盾

## 方案的合理性分析

### ❌ 当前方案不合理

**技术矛盾**：
- `recognizer` 必须在 `@MainActor`（因为它可能操作 ML 模型等主线程资源）
- 调用 `recognizer.transcribe()` 必须回到主线程
- `MainActor.run` 不支持 async 闭包
- **结论**：无法在 `nonisolated` 上下文中正确调用 `transcribe`

**性能悖论**：
- 如果 `transcribe` 已经是 `async` 的，它本来就不会阻塞主线程
- 强行移到后台线程，反而增加了线程切换开销
- 大量 `await MainActor.run { ... }` 调用会导致频繁的上下文切换

### ✅ 什么情况下后台线程优化才有意义？

**适用场景**：
1. **CPU 密集型同步计算**
   ```swift
   // ❌ 这会阻塞主线程
   let result = heavyComputation()  // 同步、耗时
   
   // ✅ 移到后台线程
   let result = await Task.detached {
       heavyComputation()
   }.value
   ```

2. **大量数据处理**
   ```swift
   // ❌ 阻塞主线程
   for segment in allSegments {  // 可能有几千个
       processSegment(segment)
   }
   
   // ✅ 后台处理 + 批量更新
   let processed = await Task.detached {
       allSegments.map { processSegment($0) }
   }.value
   await MainActor.run { self.segments = processed }
   ```

3. **async 方法内部有同步阻塞代码**
   ```swift
   func transcribe(...) async -> Result {
       // 如果内部是这样：
       let prediction = model.predict(audio)  // 同步、耗时几百毫秒
       return Result(prediction)
   }
   // 这种情况才需要考虑后台线程
   ```

**不适用场景**（我们的情况）：
- `transcribe` 已经是 `async` 方法
- 内部很可能是 `await model.prediction(...)`，已经是非阻塞的
- 主循环中有大量 `await`：`await buffer.read()`, `await Task.sleep()` 等
- **这些 await 已经让出了执行权，主线程不会被阻塞**

## 正确的优化方向

如果前两个修复（调试卡片开关 + LazyVStack）不够，应该考虑：

### 1. 减少 @Observable 触发频率
```swift
// 当前：每个属性变化都触发 UI 刷新
@Observable
public class SubtitlePipeline {
    public private(set) var transcribedWindowCount = 0  // 每秒变化多次
    public private(set) var emittedSegmentCount = 0     // 每秒变化多次
}

// 优化：批量更新或节流
private var _transcribedWindowCount = 0
public var transcribedWindowCount: Int {
    _transcribedWindowCount  // 只在需要时更新 UI
}

func updateCounters() {
    // 每 N 次或每 N 秒才触发一次 UI 刷新
    if _transcribedWindowCount % 10 == 0 {
        transcribedWindowCount = _transcribedWindowCount
    }
}
```

### 2. 优化 transcribe 方法本身
如果 `WhisperKitSpeechRecognizer.transcribe` 内部有同步阻塞代码：
```swift
func transcribe(...) async throws -> RecognitionOutcome {
    // 将同步模型推理移到后台
    let prediction = await Task.detached(priority: .userInitiated) {
        self.whisperModel.predict(audio)  // CPU 密集型
    }.value
    
    return RecognitionOutcome(prediction)
}
```

### 3. 使用 Task 优先级
```swift
Task.detached(priority: .medium) {  // 不用 .userInitiated，避免和 UI 竞争
    await runRecognitionLoop(generation: generation)
}
```

### 4. 分析真正的性能瓶颈
- 使用 Instruments 的 Time Profiler 找出主线程卡顿的真实原因
- 可能是 SwiftUI 视图刷新，而不是识别循环
- 可能是某个同步操作（文件 I/O、日志写入等）

## 结论

1. **当前方案（commit 4571245~8757ce7）是错误的**
   - 技术上无法实现（MainActor.run 不支持 async）
   - 概念上不必要（async 方法本身不阻塞）

2. **已回退到 commit a4dc8c4**
   - 保留前两个修复：调试卡片开关 + LazyVStack
   - 等待用户测试是否已解决性能问题

3. **如果问题仍存在，应该**：
   - 用 Instruments 分析真实瓶颈
   - 优化 @Observable 触发频率
   - 检查 `transcribe` 内部实现是否有同步阻塞
   - 考虑 Task 优先级调整

4. **不应该**（针对旧项目后续开发）：
   - 强行将 `async` 方法调用链移到后台线程
   - 在 `nonisolated` 和 `@MainActor` 之间频繁切换

以上结论仅供旧项目复盘；本项目已停止，不再据此安排新的实现工作。
