//
//  SKDialogAnimationManager.swift
//  SiKu
//
//  Created by Assistant on 2024
//

/**
 * 文件功能描述：
 * 弹窗动画的「实现层」。上半部分是分发器 SKDialogAnimationManager，下半部分是 9 个内置
 * 动画类（4 个纯滑动、4 个滑动+淡入、1 个缩放淡入）。
 *
 * 设计原理：分发 + 无状态实例
 * - 分发器本身不写动画，只按 config.animationType 把调用转给对应的实现类，并兜住 `.custom`。
 *   集中分发的代价是新增内置动画必须改这个 switch，好处是"库支持哪些动画"在编译期穷尽可见。
 * - 每个动画实例都是**无状态**的：调用前临时 `SlideFromBottomAnimation()` 构造、用完即弃。
 *   动画的状态（时长/阻尼/方向）全部来自 SKDialogConfig，不存在跨次调用的残留，
 *   因此也不会出现"上一次动画的参数污染这一次"的问题。
 *
 * 所有滑动动画共用的实现模板（后文每个类只描述与模板的差异）：
 * 1. 先 `containerView.superview?.layoutIfNeeded()` 强制求解一次布局，
 *    保证 containerView.bounds 是真实尺寸而不是 0
 * 2. 算出滑动距离（容器在滑动方向上的尺寸，附 100pt 兜底，见下）
 * 3. 把容器摆到屏幕外的起点位置（transform 位移，需要时再把 alpha 置 0）
 * 4. 用弹簧动画把容器送回 identity，遮罩同步淡入
 *
 * 关于 `max(尺寸, 100)` 兜底的原因：AutoLayout 尚未求解时 bounds 可能为 0，
 * 直接使用会得到"零位移"——弹窗原地淡入，滑动动画静默失效。
 * 兜底值保证即便尺寸未知也至少有一段可见位移；正常布局完成后该值不会触发。
 * 注意并非所有动画类都调用了 layoutIfNeeded（FadeScaleAnimation 就不需要，
 * 它不依赖容器尺寸），因此这个兜底对它是无关项。
 *
 * 与状态管理器的关系：SKDialogAnimationStateManager 会在展示前预置起点状态（防闪现），
 * 而下面的实现类在动画开始时**再次设置起点**。两处同时存在是有意的：
 * 预置状态负责"上屏首帧不能露出错误位置"，动画实现则保证"无论此前处于什么状态，
 * 动画起点都是正确的"（自包含，不依赖外部状态）。
 */

import UIKit

/// 弹窗动画分发器。
///
/// 对外可见（public）是为了让宿主在需要时可以单独构造使用；库内由
/// SKDialogViewController 强引用并委托调用，宿主一般不需要直接接触它。
///
/// 无状态：只持有 config（引用），不缓存动画实现，因此同一实例可安全复用于多次入场/退场。
@MainActor
public class SKDialogAnimationManager {

    // MARK: - Properties

    /// 配置来源：动画类型决定分发目标，时长/弹簧参数由各实现类读取。
    private let config: SKDialogConfig

    // MARK: - Initialization

    /// 持有配置即可，构造阶段不做任何 UIKit 操作。
    public init(config: SKDialogConfig) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 执行入场动画：按配置分发到 9 种内置实现之一，或直接调用自定义实现。
    ///
    /// - Parameters:
    ///   - backgroundView: 遮罩视图（与容器同步淡入）
    ///   - containerView: 容器视图（位移/缩放/透明度的作用对象）
    ///   - completion: 动画结束回调；由分发目标负责调用，调用方据此更新内部状态与触发宿主回调
    public func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
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
    /// 让每个实现类自己描述退场，语义更清晰。
    /// - Parameters:
    ///   - backgroundView: 遮罩视图
    ///   - containerView: 容器视图
    ///   - completion: 动画结束回调；控制器会在其中隐藏 window 或 dismiss 控制器
    public func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
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

// MARK: - 带渐变效果的滑动动画类

/// 从底部滑入 + 容器淡入。
///
/// 视觉轨迹：容器从屏幕下方（自身高度之外）一边上移一边由透明变清晰，遮罩同时淡入。
/// 相比 `SlideFromBottomAnimation`（容器全程不透明）多了一个透明度通道，
/// 观感更柔和，适合较高的面板。
///
/// 所有动画类都是 internal：宿主需要自定义动画时应实现 public 的 SKDialogAnimationProtocol
/// 并通过 `.custom` 注入，而不是直接引用这些内置实现。
class SlideFromBottomWithFadeAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕下方滑入并同时淡入（起点 y = +容器高度）
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保AutoLayout布局计算完成
        // 目的：让下面的 bounds.height 取到真实高度（否则起点距离可能退化成兜底值）
        containerView.superview?.layoutIfNeeded()

        // 获取准确的容器高度，添加安全检查
        // 兜底 100pt 的用途见文件头说明：布局未完成时避免"零位移"
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt
        // 初始状态：容器在底部且透明
        containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
        containerView.alpha = 0
        backgroundView.alpha = 0

        // 终点为 identity（归位）+ 完全不透明；时长/弹簧参数来自 config，
        // 因此宿主通过 animation(_:duration:damping:velocity:) 就能整体调节手感
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = .identity
                containerView.alpha = 1
                backgroundView.alpha = 1
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑回屏幕下方并淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {

        // 确保获取当前准确的容器高度
        // 退场时不再调用 layoutIfNeeded：此刻布局已经稳定，且拖拽可能改变了 center，
        // 再次求解布局会把用户拖拽的位移抹掉（视图被约束拉回原位），造成"回弹"错觉
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt

        // 与入场起点镜像：滑回屏幕外并淡出，视觉上"从哪来回哪去"
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
                containerView.alpha = 0
                backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
}

/// 从顶部滑入 + 容器淡入。与上一个类完全对称，只是方向向上（起始位移为负）。
/// 常用于通知条 / 顶部提示。
class SlideFromTopWithFadeAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕上方滑入并同时淡入（起点 y = -容器高度）
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保AutoLayout布局计算完成
        containerView.superview?.layoutIfNeeded()

        // 获取准确的容器高度，添加安全检查
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt
        // 初始状态：容器在顶部且透明（y 取负值表示位于自身位置上方的屏幕外）
        containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
        containerView.alpha = 0
        backgroundView.alpha = 0

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = .identity
                containerView.alpha = 1
                backgroundView.alpha = 1
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑回屏幕上方并淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {

        // 确保获取当前准确的容器高度
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
                containerView.alpha = 0
                backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
}

/// 从左侧滑入 + 容器淡入。
///
/// 与前两个类的关键差异：滑动距离取**宽度**（bounds.width），位移作用在 x 轴上。
/// 横向动画通常用于侧边栏式面板，因此这里必须等布局完成才能算准距离。
class SlideFromLeftWithFadeAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕左侧滑入并同时淡入（起点 x = -容器宽度）
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保AutoLayout布局计算完成
        containerView.superview?.layoutIfNeeded()

        // 获取准确的容器宽度，添加安全检查
        let slideDistance = max(containerView.bounds.width, 100) // 最小滑动距离100pt
        // 初始状态：容器在左侧且透明
        containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
        containerView.alpha = 0
        backgroundView.alpha = 0

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = .identity
                containerView.alpha = 1
                backgroundView.alpha = 1
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑回屏幕左侧并淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {

        // 确保获取当前准确的容器宽度
        let slideDistance = max(containerView.bounds.width, 100) // 最小滑动距离100pt

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
                containerView.alpha = 0
                backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
}

/// 从右侧滑入 + 容器淡入。与左侧版对称（x 轴正方向）。
class SlideFromRightWithFadeAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕右侧滑入并同时淡入（起点 x = +容器宽度）
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保AutoLayout布局计算完成
        containerView.superview?.layoutIfNeeded()

        // 获取准确的容器宽度，添加安全检查
        let slideDistance = max(containerView.bounds.width, 100) // 最小滑动距离100pt
        // 初始状态：容器在右侧且透明
        containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
        containerView.alpha = 0
        backgroundView.alpha = 0

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = .identity
                containerView.alpha = 1
                backgroundView.alpha = 1
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑回屏幕右侧并淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {

        // 确保获取当前准确的容器宽度
        let slideDistance = max(containerView.bounds.width, 100) // 最小滑动距离100pt

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
                containerView.alpha = 0
                backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从底部滑入动画

/// 从底部滑入（容器**不**淡入）。
///
/// 与 `SlideFromBottomWithFadeAnimation` 的唯一区别在透明度通道：
/// 这里入场时显式把 containerView.alpha 置为 1，只让遮罩淡入。
/// 效果是容器轮廓从第一帧起就清晰可见，速度感更强，适合底部操作面板。
///
/// 为什么显式置 1 而不是"不管它"：容器可能残留在透明状态（例如展示前把动画类型
/// 从带 WithFade 的类型改成这个类型，而预置的首帧状态已经写了 alpha = 0）。
/// 显式置 1 让本动画不依赖外部状态，任何情况下入场终点都一定是完全可见。
class SlideFromBottomAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕下方滑入；容器保持不透明，只有遮罩淡入
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保AutoLayout布局计算完成
        containerView.superview?.layoutIfNeeded()

        // 获取准确的容器高度，添加安全检查
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt
        // 起点：屏幕下方（容器不透明，只有遮罩从 0 淡入）
        containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
        containerView.alpha = 1

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑出屏幕下方；容器保持可见，只有遮罩淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保获取当前准确的容器高度
        // 注意这里也不动 containerView.alpha：入场时它是 1，退场只需位移 + 遮罩淡出，
        // 保证"滑出去"的过程始终看得见容器本身
        let slideDistance = max(containerView.bounds.height, 100) // 最小滑动距离100pt

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 渐变缩放动画

/// 渐变缩放（默认动画类型）：位置不动，容器由小变大并淡入，遮罩同步淡入。
///
/// 为什么不调 layoutIfNeeded：本动画不依赖容器尺寸（缩放比例是比值），
/// 因此不需要为了拿 bounds 而触发布局，也就不会在入场瞬间"顺手"引起一次布局求解。
///
/// 缩放幅度取自 `config.fadeScaleInitialScale`，与布局阶段预置首帧状态用的是同一个值，
/// 因此"预置状态 → 动画起点"之间不会出现缩放跳变。
class FadeScaleAnimation: SKDialogAnimationProtocol {

    /// 入场：原地由 80% 放大到 100% 并淡入，遮罩同步淡入
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 起点：透明 + 按配置比例缩小（与 state manager 的预置状态读同一个配置值）
        let initialScale = config.fadeScaleInitialScale
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：原地缩回 80% 并淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 退场即入场起点的镜像：缩回 0.8 并淡出，视觉上"塌缩消失"
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.alpha = 0
                // 退场同样回到配置的起始比例，保证入场/退场首尾一致
                let initialScale = config.fadeScaleInitialScale
                containerView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从顶部滑入动画

/// 从顶部滑入（容器不淡入），`SKDialog.top()` 预设使用的动画。
class SlideFromTopAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕上方滑入；容器保持不透明，只有遮罩淡入
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 先求解布局：顶部面板的高度依赖内容，未求解时 bounds.height 会取到兜底值
        containerView.superview?.layoutIfNeeded()

        let slideDistance = max(containerView.bounds.height, 100)
        containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
        containerView.alpha = 1

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑出屏幕上方；容器保持可见，只有遮罩淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        let slideDistance = max(containerView.bounds.height, 100)

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从左侧滑入动画

/// 从左侧滑入（容器不淡入），横向滑动距离取容器宽度。
class SlideFromLeftAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕左侧滑入；容器保持不透明，只有遮罩淡入
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        containerView.superview?.layoutIfNeeded()

        let slideDistance = max(containerView.bounds.width, 100)
        containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
        containerView.alpha = 1

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑出屏幕左侧；容器保持可见，只有遮罩淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        let slideDistance = max(containerView.bounds.width, 100)

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从右侧滑入动画

/// 从右侧滑入（容器不淡入），与左侧版对称。
class SlideFromRightAnimation: SKDialogAnimationProtocol {

    /// 入场：由屏幕右侧滑入；容器保持不透明，只有遮罩淡入
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        containerView.superview?.layoutIfNeeded()

        let slideDistance = max(containerView.bounds.width, 100)
        containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
        containerView.alpha = 1

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }

    /// 退场：滑出屏幕右侧；容器保持可见，只有遮罩淡出
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        let slideDistance = max(containerView.bounds.width, 100)

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
            },
            completion: { _ in
                completion()
            }
        )
    }
}
