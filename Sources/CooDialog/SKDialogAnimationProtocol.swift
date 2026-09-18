//
//  SKDialogAnimationProtocol.swift
//  SiKu
//
//  Created by Assistant on 2024
//
//  弹窗动画协议
//  定义弹窗动画的标准接口，包括显示和消失动画的执行方法
//  提供动画工具类，封装常用的动画方法如弹簧动画、基础动画等

import UIKit

/// 弹窗动画协议
@MainActor
public protocol SKDialogAnimationProtocol {

    /// 执行显示动画
    /// - Parameters:
    ///   - backgroundView: 背景遮罩视图
    ///   - containerView: 容器视图
    ///   - config: 弹窗配置
    ///   - completion: 动画完成回调
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    )

    /// 执行消失动画
    /// - Parameters:
    ///   - backgroundView: 背景遮罩视图
    ///   - containerView: 容器视图
    ///   - config: 弹窗配置
    ///   - completion: 动画完成回调
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    )
}

/// 动画工具类
@MainActor
public class SKDialogAnimationUtils {

    /// 执行弹簧动画
    public static func springAnimation(
        duration: TimeInterval,
        damping: CGFloat,
        velocity: CGFloat,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: velocity,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    /// 执行普通动画
    public static func basicAnimation(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: animations,
            completion: completion
        )
    }

    /// 执行关键帧动画
    public static func keyframeAnimation(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0,
            options: [.calculationModeLinear],
            animations: animations,
            completion: completion
        )
    }
}
