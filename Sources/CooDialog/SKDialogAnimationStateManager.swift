//
//  SKDialogAnimationStateManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * 弹窗的「动画状态管理器」。负责两件事：
 * 1. 展示前把容器预置到该动画的**起点状态**（避免视图以正确位置先闪现一帧再开始动画）
 * 2. 在布局完成后，按真实尺寸**重算并重新施加**滑动偏移量
 *
 * 为什么需要它（设计原理）：
 * 弹窗容器使用 AutoLayout，尺寸在 viewDidLoad 阶段尚未求解（bounds 常常是 0）。
 * 而滑动动画的起点取决于容器尺寸（"从下方滑入"= 向下偏移一个容器高度），
 * 于是出现时序矛盾：预置状态的那一刻拿不到正确尺寸。
 * 解决办法就是把"预置"和"校正"分开：先给一个粗略的起点保证首帧不露馅，
 * 等 viewDidLayoutSubviews 拿到真实 bounds 后再精修一次。
 * 换句话说，本类是动画实现类"不必自己处理尺寸未知情况"的前提。
 *
 * 包含类型：
 * - SKDialogAnimationStateManager：状态持有者 + 初始状态与偏移量计算
 * - AnimationState（私有）：initial / animating / final 三态
 *
 * 状态推进（谁改状态、何时改）：
 * - `setupInitialAnimationState()`（由控制器 viewDidLoad 调用）：置为 .initial
 * - `SKDialogViewController.presentDialog()` 的入场动画完成回调：调用 markAnimationCompleted() 置为 .final
 * 这一次推进是必要的：updateSlideOffsetAfterLayout() 只在 .initial 时改写 transform，
 * 若入场完成后仍停留在 .initial，任何一次布局（宿主改尺寸、屏幕旋转、安全区变化）
 * 都会把滑动类容器重新推回屏幕外的起点，且不会再自己回来。
 */

import UIKit

/// 弹窗动画状态管理器。
///
/// 由 SKDialogViewController 持有（lazy 创建），是动画链路上"唯一记得当前处于什么阶段"的对象。
@MainActor
class SKDialogAnimationStateManager {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?

    /// 当前动画状态
    private var currentAnimationState: AnimationState = .initial

    /// 动画状态枚举
    private enum AnimationState {
        case initial    // 初始状态：等待布局校正，允许重设起点
        case animating  // 动画中：不应再被外部改写 transform
        case final      // 最终状态：已就位（identity）
    }

    // MARK: - Initialization

    /// 初始化动画状态管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods

    /// 设置动画初始状态。
    ///
    /// 调用时机：SKDialogViewController.setupUI() 内，即视图层级刚建好、约束尚未求解时。
    /// 目的：让容器上屏的第一帧就位于"该动画的起点"（例如屏幕下方、或缩放 80% 且透明），
    /// 而不是先出现在最终位置再被动画拉走（那会表现为闪一下）。
    ///
    /// 分组说明：对称的动画类型共用同一套起点设置——
    /// 垂直与水平滑动共用 setupSlideInitialState（按轴校正留给布局完成后的
    /// updateSlideOffsetAfterLayout），带淡入的四种共用 setupSlideWithFadeInitialState，
    /// fadeScale 单独处理，自定义动画不做任何预置（完全交给宿主的实现）。
    func setupInitialAnimationState() {
        guard let viewController = viewController else { return }

        currentAnimationState = .initial

        let animationType = viewController.config.animationType

        switch animationType {
        case .slideFromBottom, .slideFromTop:
            setupSlideInitialState()
        case .slideFromLeft, .slideFromRight:
            setupSlideInitialState()
        case .slideFromBottomWithFade, .slideFromTopWithFade:
            setupSlideWithFadeInitialState()
        case .slideFromLeftWithFade, .slideFromRightWithFade:
            setupSlideWithFadeInitialState()
        case .fadeScale:
            setupFadeScaleInitialState()
        case .custom(_):
            // 自定义动画由外部处理
            break
        }
    }

    /// 重置到最终状态（把容器恢复到"已就位、完全可见"）。
    ///
    /// - Note: 库内当前没有调用者，保留给测试与调试（配合 forceResetState 使用，
    ///   可把因中断而停在半途的容器恢复到可交互状态）。
    func resetToFinalState() {
        guard let viewController = viewController else { return }

        currentAnimationState = .final

        // 重置所有变换
        viewController.containerView.transform = .identity
        viewController.containerView.alpha = 1.0
        viewController.backgroundView.alpha = 1.0
    }

    /// 布局完成后校正滑动偏移量。
    ///
    /// 调用时机：SKDialogViewController.viewDidLayoutSubviews()，每次布局都会走到。
    /// 作用有两层：
    /// 1. 用真实的 bounds 重新计算偏移量（viewDidLoad 阶段 bounds 可能为 0，
    ///    那时算出的起点是错的或退化的）
    /// 2. **按轴纠正**：setupSlideInitialState()/setupSlideWithFadeInitialState() 统一把偏移
    ///    写进了 y 分量，而左右滑动的偏移量本应作用在 x 轴上；这里按动画类型选择正确的轴重写
    ///
    /// - Important: guard 把改写限定在"入场完成之前的校正窗口期"内。入场完成后控制器会把状态
    ///   推进为 .final（见 presentDialog），此后布局不再触碰 transform；
    ///   若在入场动画进行中发生布局，这里仍会按最新尺寸重设起点——这是期望行为，
    ///   保证滑动起点与容器实际尺寸一致。
    func updateSlideOffsetAfterLayout() {
        guard let viewController = viewController else { return }
        guard currentAnimationState == .initial else { return }

        let animationType = viewController.config.animationType

        // 只有包含滑动的动画类型需要更新偏移量
        switch animationType {
        case .slideFromBottom, .slideFromTop, .slideFromLeft, .slideFromRight:
            let offset = calculateSlideOffset()
            let transform: CGAffineTransform

            switch animationType {
            case .slideFromLeft, .slideFromRight:
                transform = CGAffineTransform(translationX: offset, y: 0)
            default:
                transform = CGAffineTransform(translationX: 0, y: offset)
            }

            viewController.containerView.transform = transform
        case .slideFromBottomWithFade, .slideFromTopWithFade, .slideFromLeftWithFade, .slideFromRightWithFade:
            // 与上一个分支逻辑相同（都只改 transform，不动 alpha）：
            // 淡入动画的透明度由预置状态或动画实现负责，这里不应插手
            let offset = calculateSlideOffset()
            let transform: CGAffineTransform

            switch animationType {
            case .slideFromLeftWithFade, .slideFromRightWithFade:
                transform = CGAffineTransform(translationX: offset, y: 0)
            default:
                transform = CGAffineTransform(translationX: 0, y: offset)
            }

            viewController.containerView.transform = transform
        default:
            // fadeScale / custom：不需要偏移量校正
            // fadeScale 的起点只与缩放比例有关，与容器尺寸无关，
            // 因此不存在"布局后需要修正"的问题（这也是它不需要 layoutIfNeeded 的原因）
            break
        }
    }

    /// 标记动画进行中。
    /// - Note: 库内当前没有调用者——入场动画期间需要保留"布局后校正起点"的能力，
    ///   因此控制器只在动画完成时推进状态（markAnimationCompleted）。
    ///   若将来需要在动画期间冻结容器的 transform，可在 presentDialog 发起动画前调用本方法。
    func markAnimationStarted() {
        currentAnimationState = .animating
    }

    /// 标记入场动画完成：状态推进到 .final，此后 updateSlideOffsetAfterLayout() 不再改写容器。
    /// 调用方：SKDialogViewController.presentDialog() 的动画完成回调。
    func markAnimationCompleted() {
        currentAnimationState = .final
    }

    // MARK: - Private Methods - Slide Animation

    /// 设置滑动动画初始状态。
    ///
    /// - Note: 这里**统一使用 y 轴**（即使当前动画是左右滑动），因为此刻布局未完成、
    ///   宽度还不可靠；真实的方向与距离交给 updateSlideOffsetAfterLayout() 在布局后按轴重写。
    ///   中间这一小段时间里水平滑动动画的起点是"竖直偏移"，实际观感不可见（尚未上屏）。
    private func setupSlideInitialState() {
        guard let viewController = viewController else { return }

        let offset = calculateSlideOffset()
        viewController.containerView.transform = CGAffineTransform(translationX: 0, y: offset)
    }

    /// 计算滑动偏移量。
    ///
    /// 返回值的符号即方向：负值表示"从上方/左方进入"，正值表示"从下方/右方进入"。
    /// 距离取"容器在滑动轴上的尺寸 + 对应方向的 margins"，
    /// 保证起点完全在屏幕外（即使是贴边面板也不会露出一个边角）。
    /// - Returns: 偏移量（根据动画类型确定方向）
    private func calculateSlideOffset() -> CGFloat {
        guard let viewController = viewController else { return 0 }

        let animationType = viewController.config.animationType
        let containerSize = viewController.containerView.bounds.size
        // 下面这行的取值结果被丢弃（仅做一次 view 访问）。它不参与计算，
        // 保留原样以免改变行为；如需清理可直接删除。
        _ = viewController.view.bounds.size

        switch animationType {
        case .slideFromTop, .slideFromTopWithFade:
            // 从顶部滑入，初始位置在视图上方
            return -(containerSize.height + viewController.config.margins.top)
        case .slideFromBottom, .slideFromBottomWithFade:
            // 从底部滑入，初始位置在视图下方
            return containerSize.height + viewController.config.margins.bottom
        case .slideFromLeft, .slideFromLeftWithFade:
            // 从左侧滑入，初始位置在视图左侧
            return -(containerSize.width + viewController.config.margins.left)
        case .slideFromRight, .slideFromRightWithFade:
            // 从右侧滑入，初始位置在视图右侧
            return containerSize.width + viewController.config.margins.right
        default:
            // fadeScale / custom 无位移
            return 0
        }
    }

    /// 设置"滑动 + 淡入"类动画的初始状态：
    /// 偏移量作用在 y 轴（轴校正同上），并把容器与遮罩一并置为全透明，
    /// 使首帧完全不可见——这是 WithFade 系列与纯滑动系列在预置阶段的关键区别。
    private func setupSlideWithFadeInitialState() {
        guard let viewController = viewController else { return }

        let offset = calculateSlideOffset()
        let animationType = viewController.config.animationType

        // 设置滑动偏移
        let transform: CGAffineTransform
        switch animationType {
        case .slideFromLeftWithFade, .slideFromRightWithFade:
            transform = CGAffineTransform(translationX: offset, y: 0)
        default:
            transform = CGAffineTransform(translationX: 0, y: offset)
        }

        viewController.containerView.transform = transform
        // 设置初始透明度为0（渐变效果）
        viewController.containerView.alpha = 0.0
        viewController.backgroundView.alpha = 0.0
    }

    // MARK: - Private Methods - FadeScale Animation

    /// 设置 fadeScale 动画的初始状态：按配置比例缩小 + 全透明。
    ///
    /// - Note: 这里的缩放值取自 `config.fadeScaleInitialScale`，但 FadeScaleAnimation
    ///   在动画开始时会用固定的 0.8 覆盖它，所以自定义该值对最终观感的改变有限（详见配置类注释）。
    private func setupFadeScaleInitialState() {
        guard let viewController = viewController else { return }

        // 设置初始缩放和透明度
        let initialScale = viewController.config.fadeScaleInitialScale
        viewController.containerView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
        viewController.containerView.alpha = 0.0
        viewController.backgroundView.alpha = 0.0
    }
}

// MARK: - Internal Access

/// 调试 / 测试用的只读快照与强制重置入口，均不参与生产路径。
extension SKDialogAnimationStateManager {

    /// 是否处于初始状态
    var isInInitialState: Bool {
        return currentAnimationState == .initial
    }

    /// 是否正在动画中
    var isAnimating: Bool {
        return currentAnimationState == .animating
    }

    /// 是否已到最终状态
    var isInFinalState: Bool {
        return currentAnimationState == .final
    }

    /// 提取容器当前 transform 的位移 / 缩放 / 旋转分量（调试用）。
    ///
    /// 原理：CGAffineTransform 的 a/b/c/d 组成 2×2 线性部分，
    /// 对纯缩放 + 平移的变换，x 轴缩放 = √(a²+c²)，y 轴缩放 = √(b²+d²)，旋转 = atan2(b, a)。
    /// 若变换中混入了斜切，这里的分解结果会不准确——本库只使用平移与等比缩放，因此成立。
    var currentTransformInfo: (translation: CGPoint, scale: CGPoint, rotation: CGFloat) {
        guard let viewController = viewController else {
            return (translation: .zero, scale: CGPoint(x: 1, y: 1), rotation: 0)
        }

        let transform = viewController.containerView.transform

        // 提取变换信息
        let translation = CGPoint(x: transform.tx, y: transform.ty)
        let scaleX = sqrt(transform.a * transform.a + transform.c * transform.c)
        let scaleY = sqrt(transform.b * transform.b + transform.d * transform.d)
        let scale = CGPoint(x: scaleX, y: scaleY)
        let rotation = atan2(transform.b, transform.a)

        return (translation: translation, scale: scale, rotation: rotation)
    }

    /// 强制重置：状态回到 .initial 并重新应用初始状态。
    /// 用于测试或异常恢复（例如动画被打断后需要重新走一遍入场）。
    func forceResetState() {
        currentAnimationState = .initial
        setupInitialAnimationState()
    }
}
