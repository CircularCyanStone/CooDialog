//
//  SlideFromRightAnimation.swift
//  SiKu
//
//  内置动画实现之一：从右侧滑入（容器不淡入）。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从右侧滑入（容器不淡入），与左侧版对称。
struct SlideFromRightAnimation: SKDialogAnimationProtocol {

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
