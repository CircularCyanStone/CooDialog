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
 * 换句话说，本类是动画实现"不必自己处理尺寸未知情况"的前提。
 *
 * 距离公式不在这里：滑动距离取自 `SlideAnimation.slideOffset`（全库唯一一处），
 * 与动画实现共用，因此"预置首帧"与"动画起点"不会出现位置跳变。
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
    /// 分支只有三种，且与动画类型一一对应：
    /// - 滑动类（含 WithFade）：按方向摆到屏幕外，WithFade 系列同时把容器与遮罩置透明
    /// - fadeScale：按配置比例缩小 + 全透明
    /// - 自定义动画：不做任何预置（完全交给宿主的实现）
    func setupInitialAnimationState() {
        guard let viewController = viewController else { return }

        currentAnimationState = .initial

        let animationType = viewController.config.animationType

        if let direction = animationType.slideDirection {
            // 滑动类：方向与是否需要淡入都来自类型元数据，这里不重复判定
            applySlideTransform(direction: direction)
            if animationType.fadesContainerWhileSliding {
                // WithFade 系列：容器与遮罩一起从全透明开始，首帧完全不可见
                viewController.containerView.alpha = 0
                viewController.backgroundView.alpha = 0
            }
        } else if animationType == .fadeScale {
            // 缩放类：起点只与比例有关、与容器尺寸无关，因此不存在"布局后需要修正"的问题
            let initialScale = viewController.config.fadeScaleInitialScale
            viewController.containerView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
            viewController.containerView.alpha = 0
            viewController.backgroundView.alpha = 0
        }
        // .custom：不预置，起点由宿主的实现自行决定
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
    /// 作用：用真实 bounds 重算滑动距离并重新施加——viewDidLoad 阶段 bounds 可能是 0，
    /// 那时算出的起点是退化值（兜底距离），必须跟着实际尺寸更新。
    ///
    /// - Important: guard 把改写限定在"入场完成之前的校正窗口期"内。入场完成后控制器会把状态
    ///   推进为 .final（见 presentDialog），此后布局不再触碰 transform。
    ///   若在入场动画进行中发生布局，这里仍会按最新尺寸重设起点——这是期望行为，
    ///   保证滑动起点与容器实际尺寸一致。
    func updateSlideOffsetAfterLayout() {
        guard let viewController = viewController else { return }
        guard currentAnimationState == .initial else { return }
        // 只有滑动类需要校正：fadeScale 的起点与容器尺寸无关，自定义动画不归库管
        guard let direction = viewController.config.animationType.slideDirection else { return }

        applySlideTransform(direction: direction)
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
}

// MARK: - Private

extension SKDialogAnimationStateManager {

    /// 按滑动方向把容器摆到"屏幕外"的起点。
    ///
    /// 只改 transform，不动 alpha：透明度由预置分支（WithFade）或动画实现自己负责，
    /// 两处职责分开，避免"布局校正"意外把容器改成透明。
    private func applySlideTransform(direction: SlideAnimation.Direction) {
        guard let viewController = viewController else { return }

        let offset = SlideAnimation.slideOffset(
            for: direction,
            containerSize: viewController.containerView.bounds.size,
            margins: viewController.config.margins
        )

        viewController.containerView.transform = direction.translation(offset: offset)
    }
}

// MARK: - Debug & Testing

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
