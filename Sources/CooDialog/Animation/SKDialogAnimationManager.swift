/**
 * 文件功能描述：
 * 弹窗动画的「分发层」：按 config.animationType 把入场 / 退场调用转交给对应的动画实现，
 * 并兜住宿主的自定义实现。9 个内置实现已按类型拆分为独立文件（见 Animation/Builtin/），
 * 本文件只保留分发器。
 *
 * 设计原理：分发 + 无状态实现
 * - 分发器本身不写动画，只按 config.animationType 把调用转给对应的实现类型，并兜住 `.custom`。
 *   集中分发的代价是新增内置动画必须改这个 switch，好处是"库支持哪些动画"在编译期穷尽可见。
 * - 每个实现都是**无状态**的 struct：调用前临时 `SlideFromBottomAnimation()` 构造、用完即弃。
 *   动画的参数（时长/阻尼/方向）全部来自 SKDialogConfig，不存在跨次调用的残留，
 *   因此也不会出现"上一次动画的参数污染这一次"的问题。
 *
 * 所有滑动动画共用的实现模板（Builtin/ 下每个实现只描述与模板的差异）：
 * 1. 先 `containerView.superview?.layoutIfNeeded()` 强制求解一次布局，
 *    保证 containerView.bounds 是真实尺寸而不是 0
 * 2. 算出滑动距离（容器在滑动方向上的尺寸，附 100pt 兜底，见下）
 * 3. 把容器摆到屏幕外的起点位置（transform 位移，需要时再把 alpha 置 0）
 * 4. 用弹簧动画把容器送回 identity，遮罩同步淡入
 *
 * 关于 `max(尺寸, 100)` 兜底的原因：AutoLayout 尚未求解时 bounds 可能为 0，
 * 直接使用会得到"零位移"——弹窗原地淡入，滑动动画静默失效。
 * 兜底值保证即便尺寸未知也至少有一段可见位移；正常布局完成后该值不会触发。
 * 注意并非所有动画实现都调用了 layoutIfNeeded（FadeScaleAnimation 就不需要，
 * 它不依赖容器尺寸），因此这个兜底对它是无关项。
 *
 * 与状态管理器的关系：SKDialogAnimationStateManager 会在展示前预置起点状态（防闪现），
 * 而 Builtin/ 下的实现在动画开始时**再次设置起点**。两处同时存在是有意的：
 * 预置状态负责"上屏首帧不能露出错误位置"，动画实现则保证"无论此前处于什么状态，
 * 动画起点都是正确的"（自包含，不依赖外部状态）。
 */

import UIKit

/// 弹窗动画分发器。
///
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

    /// 执行入场动画：按配置分发到 9 种内置实现之一，或直接调用自定义实现。
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
        switch config.animationType {
        case .slideFromBottom:
            SlideFromBottomAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .fadeScale:
            FadeScaleAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromTop:
            SlideFromTopAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromLeft:
            SlideFromLeftAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromRight:
            SlideFromRightAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromBottomWithFade:
            SlideFromBottomWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromTopWithFade:
            SlideFromTopWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromLeftWithFade:
            SlideFromLeftWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromRightWithFade:
            SlideFromRightWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .custom(let animation):
            // 自定义动画完全由宿主控制：起点、终点、时长、是否动遮罩都不受库约束，
            // 库只要求它调用 completion。
            animation.performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
        }
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
    ///   - completion: 动画结束回调；控制器会在其中隐藏 window 或 dismiss 控制器
    public func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        switch config.animationType {
        case .slideFromBottom:
            SlideFromBottomAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .fadeScale:
            FadeScaleAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromTop:
            SlideFromTopAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromLeft:
            SlideFromLeftAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromRight:
            SlideFromRightAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromBottomWithFade:
            SlideFromBottomWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromTopWithFade:
            SlideFromTopWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromLeftWithFade:
            SlideFromLeftWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .slideFromRightWithFade:
            SlideFromRightWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )

        case .custom(let animation):
            animation.performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
        }
    }
}
