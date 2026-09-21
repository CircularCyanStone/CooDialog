//
//  SlideFromLeftWithFadeAnimation.swift
//  SiKu
//
//  内置动画实现之一：从左侧滑入 + 容器淡入。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从左侧滑入 + 容器淡入。
///
/// 与前两个类的关键差异：滑动距离取**宽度**（bounds.width），位移作用在 x 轴上。
/// 横向动画通常用于侧边栏式面板，因此这里必须等布局完成才能算准距离。
struct SlideFromLeftWithFadeAnimation: SKDialogAnimationProtocol {

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
