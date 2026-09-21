//
//  SlideFromTopWithFadeAnimation.swift
//  SiKu
//
//  内置动画实现之一：从顶部滑入 + 容器淡入。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从顶部滑入 + 容器淡入。与上一个类完全对称，只是方向向上（起始位移为负）。
/// 常用于通知条 / 顶部提示。
struct SlideFromTopWithFadeAnimation: SKDialogAnimationProtocol {

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
