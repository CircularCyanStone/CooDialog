/**
 * 文件功能描述：
 * 动画能力的「协议层」：定义一次弹窗动画需要实现什么。库内内置动画与宿主的自定义
 * 动画都实现在这套约定之上；协议配套的 UIKit 动画封装见 SKDialogAnimationUtils.swift。
 *
 * 为什么把动画设计成协议而不是让控制器直接写动画代码：
 * 1. 一对新动画 = 一个独立类型。入场与退场是必然成对出现的操作，把它们收在同一个类型里，
 *    实现者不会出现"只改了入场、忘了退场"的半成品状态。
 * 2. 扩展不需要改库：宿主实现本协议后通过 `SKDialogAnimationType.custom(_)` 注入即可。
 *    内置动画则集中由 SKDialogAnimationManager 分发（新增内置动画需要同时修改那个 switch）。
 *
 * 与其它文件的协作：
 * - SKDialogAnimationType.custom 携带本协议的实现，是唯一的库外扩展入口
 * - SKDialogAnimationManager 负责"类型 → 实现"的映射与分发（映射表在它的文件末尾）
 * - 内置实现见 Animation/Builtin/：SlideAnimation（8 种滑动类型共用）、FadeScaleAnimation
 * - SKDialogAnimationUtils 提供统一的 UIKit 动画封装（spring / basic / keyframe）
 * - SKDialogAnimationStateManager 负责在动画开始前把容器预置到"起点状态"
 *   （这两个职责必须一致：状态管理器设定的初始 transform 应与动画实现的起点吻合，
 *   否则会出现闪跳。滑动类的距离公式统一在 SlideAnimation.slideOffset）
 */

import UIKit

/// 弹窗动画协议：描述"入场"与"退场"两个动作。
///
/// - Important: 实现方的两条硬性约定：
///   1. 必须以某种方式**恰好调用一次** `completion`。控制器的 `presentAnimationDidFinishHandler`
///      与内部显示状态都挂在它上面，漏调会导致回调不触发、`dismiss` 的语义错乱。
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
