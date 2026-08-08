import Foundation

/// 异步加载值的显式生命周期状态。
/// View 必须分别渲染 loading / ready / empty / error / cancelled。
public enum LoadState<Value: Sendable>: Sendable {
    case loading
    case ready(Value)
    case empty
    case error(String)
    case cancelled
}

extension LoadState: Equatable where Value: Equatable {}
