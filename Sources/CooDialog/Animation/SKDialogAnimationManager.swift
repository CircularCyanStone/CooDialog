/**
 * 文件功能描述：
 * 弹窗动画的「分发层」：按 config.animationType 把入场 / 退场调用转交给对应的动画实现，
 * 并兜住宿主的自定义实现。映射表就是本文件末尾的 `SKDialogAnimationType.makeAnimation()`。
 *
 * 设计原理：分发 + 无状态实现
 * - 分发器本身不写动画，只把类型映射成实现对象再调用；映射关系全库只有一份，
 *   新增内置动画只需要改那一处。
 * - 每个实现都是**无状态**的 struct：调用前临时构造、用完即弃。
 *   动画参数（时长/阻尼/方向/边距）全部来自 SKDialogConfig，
 *   因此不存在跨次调用的残留，也不会出现"上一次动画的参数污染这一次"。
 *
 * 实现分工（见 Animation/Builtin/）：
 * - `SlideAnimation`：8 种滑动类型共用一个实现，差异由"方向 + 是否淡入"表达
 * - `FadeScaleAnimation`：原地缩放淡入
 * - 宿主的实现：经 `SKDialogAnimationType.custom` 注入，库不做任何包装
 *
 * 与状态管理器的关系：SKDialogAnimationStateManager 会在展示前预置起点状态（防闪现），
 * 而各动画实现在动画开始时**再次设置起点**。两处同时存在是有意的：
 * 预置状态负责"上屏首帧不能露出错误位置"，动画实现则保证"无论此前处于什么状态，
 * 动画起点都是正确的"（自包含，不依赖外部状态）。
 * 前提是两处用同一个距离公式——滑动类统一走 `SlideAnimation.slideOffset`。
 */

import UIKit

/// 弹窗动画分发器。
///
/// 对外可见（public）是为了让宿主在需要时可以单独构造使用；库内由
/// SKDialogViewController 强引用并委托调用，宿主一般不需要直接接触它。
///
/// 无状态：不持有配置也不缓存动画实现，配置由每次调用传入，
/// 因此同一实例可安全复用于多次入场/退场。
@MainActor
public class SKDialogAnimationManager {

    // MARK: - Initialization

    /// 无参初始化：本类不持有任何状态——配置由调用方在每次执行动画时传入，
    /// 因此值类型的 SKDialogConfig 也能反映调用时刻的最新取值。
    public init() {}

    // MARK: - Public Methods

    /// 执行入场动画：按配置取到对应实现并委托给它。
    ///
    /// - Parameters:
    ///   - backgroundView: 遮罩视图（与容器同步淡入）
    ///   - containerView: 容器视图（位移/缩放/透明度的作用对象）
    ///   - config: 执行时刻的配置（由调用方传入，本类不保存，因此值类型也不会读到旧快照）
    ///   - completion: 动画结束回调；由分发目标负责调用，调用方据此更新内部状态与触发宿主回调
    public func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        config.animationType.makeAnimation().performPresentAnimation(
            backgroundView: backgroundView,
            containerView: containerView,
            config: config,
            completion: completion
        )
    }

    /// 执行退场动画：分发逻辑与入场完全对称。
    ///
    /// 之所以退场也走同一套分发而不是"复用入场再取反"：位移动画与淡入动画的退场行为并不总是
    /// 入场行为的简单镜像（例如带淡入的版本退场时要同时回退位移与透明度），
    /// 让每个实现单独描述退场，语义更清晰。
    /// - Parameters:
    ///   - backgroundView: 遮罩视图
    ///   - containerView: 容器视图
    ///   - config: 执行时刻的配置（同上，由调用方传入）
    ///   - completion: 动画结束回调；控制器会在其中隐藏 window 或把控制器交还给系统 dismiss
    public func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        config.animationType.makeAnimation().performDismissAnimation(
            backgroundView: backgroundView,
            containerView: containerView,
            config: config,
            completion: completion
        )
    }
}

// MARK: - 类型 → 实现（库内唯一的分发表）

extension SKDialogAnimationType {

    /// 把动画类型映射成具体实现。
    ///
    /// 分支只有三档：
    /// - `.custom`：宿主提供的实现，原样使用
    /// - 8 种滑动类型：共用 `SlideAnimation`，方向与是否淡入由元数据决定
    /// - 其余内置动画：逐个映射（目前只有 fadeScale）
    ///
    /// 扩展指引：新增内置**滑动**类型时，只需在 `slideDirection` 里补一个 case，这里不用动；
    /// 新增**非滑动**类型时，编译器会因为 switch 不再穷尽而报错——这正是我们要的提醒。
    func makeAnimation() -> SKDialogAnimationProtocol {
        switch self {
        case .custom(let animation):
            // 自定义动画完全由宿主控制：起点、终点、时长、是否动遮罩都不受库约束，
            // 库只要求它调用 completion
            return animation

        case .fadeScale:
            return FadeScaleAnimation()

        case .slideFromBottom, .slideFromTop, .slideFromLeft, .slideFromRight,
             .slideFromBottomWithFade, .slideFromTopWithFade, .slideFromLeftWithFade, .slideFromRightWithFade:
            // 这 8 个 case 与 slideDirection 的非 nil 集合严格对应（由同一文件的元数据保证）。
            // 万一元数据被改坏，退化为"从下方滑入"这一无害默认，而不是崩溃
            return SlideAnimation(
                direction: slideDirection ?? .bottom,
                fadesContainer: fadesContainerWhileSliding
            )
        }
    }
}
