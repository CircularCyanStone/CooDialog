//
//  SlideFromTopAnimation.swift
//  SiKu
//
//  内置动画实现之一：从顶部滑入（容器不淡入）。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从顶部滑入（容器不淡入），`SKDialog.top()` 预设使用的动画。
struct SlideFromTopAnimation: SKDialogAnimationProtocol {

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
