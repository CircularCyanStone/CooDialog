//
//  SlideFromBottomWithFadeAnimation.swift
//  SiKu
//
//  内置动画实现之一：从底部滑入 + 容器淡入。由 SKDialogAnimationManager 按
//  `config.animationType` 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 从底部滑入 + 容器淡入。
///
/// 视觉轨迹：容器从屏幕下方（自身高度之外）一边上移一边由透明变清晰，遮罩同时淡入。
/// 相比 `SlideFromBottomAnimation`（容器全程不透明）多了一个透明度通道，
/// 观感更柔和，适合较高的面板。
///
/// 这些内置实现都是 internal 的无状态 struct：宿主需要自定义动画时应实现 public 的
/// SKDialogAnimationProtocol 并通过 `.custom` 注入，而不是直接引用这些内置实现。
struct SlideFromBottomWithFadeAnimation: SKDialogAnimationProtocol {

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
