//
//  FadeScaleAnimation.swift
//  SiKu
//
//  内置动画实现之一：渐变缩放（默认动画类型）。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 渐变缩放（默认动画类型）：位置不动，容器由小变大并淡入，遮罩同步淡入。
///
/// 为什么不调 layoutIfNeeded：本动画不依赖容器尺寸（缩放比例是比值），
/// 因此不需要为了拿 bounds 而触发布局，也就不会在入场瞬间"顺手"引起一次布局求解。
///
/// 缩放幅度取自 `config.fadeScaleInitialScale`，与布局阶段预置首帧状态用的是同一个值，
/// 因此"预置状态 → 动画起点"之间不会出现缩放跳变。
struct FadeScaleAnimation: SKDialogAnimationProtocol {

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
