//
//  DialogLogging.swift
//  SPMExample
//
//  示例专用的接线辅助（库本身不提供、也不需要提供这类 API）：
//  把四个动画回调统一接到页面的轨迹面板上，避免几十个案例各抄一遍四段闭包。
//

import UIKit
import CooDialog

// MARK: - 构建器路径

extension SKDialog {

    /// 把四个动画回调接到轨迹面板上（返回 self，便于继续链式书写）。
    /// - Note: 入场回调会在入场完成后被库清空（用完即弃），退场回调保留到关闭收尾时清空，
    ///   所以同一个弹窗"展示 → 关闭"各触发一次，轨迹里正好四行。
    @discardableResult
    func logging(_ name: String, into log: DialogEventLog) -> SKDialog {
        onPresentAnimationWillStart { log.record(name, "present.willStart") }
            .onPresentAnimationDidFinish { log.record(name, "present.didFinish") }
            .onDismissAnimationWillStart { log.record(name, "dismiss.willStart") }
            .onDismissAnimationDidFinish { log.record(name, "dismiss.didFinish") }
    }
}

// MARK: - 控制器路径

extension SKDialogViewController {

    /// 直接构造控制器的案例用它接线。
    /// 这些案例走控制器路径的原因：`SKDialog.show()` 不接受 completion，
    /// 而"未能展示时也回调"的约定只有 `show(completion:)` 能观察到。
    func logging(_ name: String, into log: DialogEventLog) {
        presentAnimationWillStartHandler = { log.record(name, "present.willStart") }
        presentAnimationDidFinishHandler = { log.record(name, "present.didFinish") }
        dismissAnimationWillStartHandler = { log.record(name, "dismiss.willStart") }
        dismissAnimationDidFinishHandler = { log.record(name, "dismiss.didFinish") }
    }
}

// MARK: - 日志可读性

extension SKDialogSizeMode {

    /// 轨迹面板里用的短形式：`fixed 300×360` / `fixedWidth 300` / `contentAdaptive`。
    /// 目的是让"动态改尺寸后配置被回写成什么"一眼可读（完整 case 名的打印太长，一行放不下）。
    var shortDescription: String {
        switch self {
        case let .fixed(width, height):
            return "fixed \(Int(width))×\(Int(height))"
        case let .fixedWidth(width):
            return "fixedWidth \(Int(width))"
        case let .fixedHeight(height):
            return "fixedHeight \(Int(height))"
        case .contentAdaptive:
            return "contentAdaptive"
        }
    }
}
