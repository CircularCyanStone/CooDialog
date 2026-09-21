//
//  SKDialogAnimationUtils.swift
//  SiKu
//
//  动画工具：内置动画与宿主自定义动画共用的 UIKit 动画封装。
//  从 SKDialogAnimationProtocol.swift 拆出，原文件只保留协议定义。
//

import UIKit

/// 动画工具：把 UIKit 的三类常用动画封装成统一样式的静态方法。
///
/// 存在的意义是"统一"而非"省字"：9 个内置动画都走同一套 UIView.animate 参数组合
/// （同样的 options、同样的 envelope 写法），因此调整全局动画风格时只需改这里一处。
/// 同时它也是 public 的，宿主的自定义动画可以复用，保证自定义动画与内置动画的手感一致。
///
/// - Note: 用**空枚举**（uninhabited）而非 class/struct 承载：这里只有静态方法、
///   没有任何实例语义，空枚举恰好表达"它不该也不能被实例化"。
@MainActor
public enum SKDialogAnimationUtils {

    /// 执行弹簧动画（内置动画统一使用的方式）。
    ///
    /// 参数落点：`duration` / `damping` / `velocity` 均来自 SKDialogConfig，
    /// 因此宿主调 `animation(_:duration:damping:velocity:)` 就能统一改掉所有内置动画的手感。
    ///
    /// options 的选择理由：
    /// - `.curveEaseInOut`：弹簧动画的时间曲线实际由 damping 决定，此项主要是与
    ///   `basicAnimation` 保持一致的调用形态
    /// - `.allowUserInteraction`：动画进行中仍允许用户点击容器内按钮。
    ///   若去掉它，入场/退场的 0.3 秒里界面会短暂"不响应"，用户快速连点时会丢事件
    ///
    /// - Parameters:
    ///   - duration: 动画时长（秒）
    ///   - damping: 阻尼，1.0 无回弹，越小回弹越明显
    ///   - velocity: 初始速度
    ///   - animations: 属性变化闭包
    ///   - completion: 结束回调（`finished` 表示是正常结束还是被中途打断）
    public static func springAnimation(
        duration: TimeInterval,
        damping: CGFloat,
        velocity: CGFloat,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: velocity,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    /// 执行普通（非弹簧）动画：时间曲线固定为 easeInOut，起止都平缓。
    /// - Note: 库内当前没有调用者，保留给宿主的自定义动画使用（与内置动画共用同一套 options 约定）。
    public static func basicAnimation(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    /// 执行关键帧动画：`animations` 内部用 addKeyframe 描述分段轨迹。
    /// - Note: 库内当前没有调用者，保留给宿主的自定义动画使用。
    ///
    /// 关于 `completion` 的标注：`completion` 在主线程回调，故标注为 `@MainActor @Sendable`。
    /// `UIView.animateKeyframes` 的 completion 参数在 SDK 中被标注为 `@Sendable`
    /// （而 `UIView.animate` 的不是），直接透传非 Sendable 闭包会产生并发告警。
    public static func keyframeAnimation(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0,
            options: [.calculationModeLinear],
            animations: animations
        ) { finished in
            // UIKit 保证动画完成回调在主线程，此处据实断言主 actor 隔离。
            MainActor.assumeIsolated { completion?(finished) }
        }
    }
}
