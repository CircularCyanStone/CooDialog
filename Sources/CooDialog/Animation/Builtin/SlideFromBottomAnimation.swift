//
//  SlideFromBottomAnimation.swift
//  SiKu
//
//  内置动画实现之一：从底部滑入（容器不淡入）。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从底部滑入（容器**不**淡入）。
///
/// 与 `SlideFromBottomWithFadeAnimation` 的唯一区别在透明度通道：
/// 这里入场时显式把 containerView.alpha 置为 1，只让遮罩淡入。
/// 效果是容器轮廓从第一帧起就清晰可见，速度感更强，适合底部操作面板。
///
/// 为什么显式置 1 而不是"不管它"：容器可能残留在透明状态（例如展示前把动画类型
/// 从带 WithFade 的类型改成这个类型，而预置的首帧状态已经写了 alpha = 0）。
/// 显式置 1 让本动画不依赖外部状态，任何情况下入场终点都一定是完全可见。
struct SlideFromBottomAnimation: SKDialogAnimationProtocol {

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
