//
//  SKDialogAnimationProtocol.swift
//  SiKu
//
//  Created by Assistant on 2024
//

/**
 * 文件功能描述：
 * 动画能力的「协议层 + 工具层」。协议定义一次弹窗动画需要实现什么，工具类提供实现时
 * 最常用的 UIKit 动画封装。库内 9 种内置动画与宿主的自定义动画都实现在这套约定之上。
 *
 * 为什么把动画设计成协议而不是让控制器直接写动画代码：
 * 1. 一对新动画 = 一个独立类型。入场与退场是必然成对出现的操作，把它们收在同一个类型里，
 *    实现者不会出现"只改了入场、忘了退场"的半成品状态。
 * 2. 扩展不需要改库：宿主实现本协议后通过 `SKDialogAnimationType.custom(_)` 注入即可。
 *    内置动画则集中由 SKDialogAnimationManager 分发（新增内置动画需要同时修改那个 switch）。
 *
 * 与其它文件的协作：
 * - SKDialogAnimationType.custom 携带本协议的实现，是唯一的库外扩展入口
 * - SKDialogAnimationManager 为 9 种内置类型各提供一个实现类
 * - SKDialogAnimationStateManager 负责在动画开始前把容器预置到"起点状态"
 *   （这两个职责必须一致：状态管理器设定的初始 transform 应与动画实现的起点吻合，
 *   否则会出现闪跳）
 */

import UIKit

/// 弹窗动画协议：描述"入场"与"退场"两个动作。
///
/// - Important: 实现方的两条硬性约定：
///   1. 必须以某种方式**恰好调用一次** `completion`。控制器的 `presentAnimationDidFinishHandler`
///      与内部显示状态都挂在它上面，漏调会导致回调不触发、`dismissDialog` 的语义错乱。
///   2. 起点状态既可以在实现内部设置（内置动画就是这么做的，因此动画是自包含的），
///      也可以依赖 SKDialogAnimationStateManager 预置的状态。内置动画选择"自己设起点"，
///      这样即便配置在展示前被改过，动画也总能从正确位置开始。
@MainActor
public protocol SKDialogAnimationProtocol {

    /// 执行入场动画。
    /// - Parameters:
    ///   - backgroundView: 遮罩视图。通常与容器同步变化（例如遮罩淡入），避免两者各自动画
    ///     造成一先一后的撕裂感。
    ///   - containerView: 承载内容的容器视图，位移/缩放/透明度都作用在它身上。
    ///   - config: 弹窗配置。动画实现从这里读取时长与弹簧参数，因此动画实例本身可以是无状态的
    ///     （每次执行前新建即可），配置变化无需通知动画对象。
    ///   - completion: 动画结束回调，实现方必须调用它。
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    )

    /// 执行退场动画。约定与入场相同。
    ///
    /// 注意实现上的镜像关系：退场通常把容器送回入场起点（同样的位移方向、同样的透明度），
    /// 这样"出现"和"消失"在空间上首尾一致，观感才自然。
    /// - Parameters:
    ///   - backgroundView: 遮罩视图
    ///   - containerView: 容器视图
    ///   - config: 弹窗配置
    ///   - completion: 动画结束回调，实现方必须调用它
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    )
}

/// 动画工具类：把 UIKit 的三类常用动画封装成统一样式的静态方法。
///
/// 存在的意义是"统一"而非"省字"：9 个内置动画都走同一套 UIView.animate 参数组合
/// （同样的 options、同样的 envelope 写法），因此调整全局动画风格时只需改这里一处。
/// 同时它也是 public 的，宿主的自定义动画可以复用，保证自定义动画与内置动画的手感一致。
@MainActor
public class SKDialogAnimationUtils {

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
