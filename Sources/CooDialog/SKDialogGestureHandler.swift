//
//  SKDialogGestureHandler.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的手势处理器，专门负责处理弹窗的各种手势交互，包括背景点击关闭、拖拽手势等。
 * 该处理器将手势相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 背景点击：处理点击背景区域关闭弹窗的手势
 * - 拖拽手势：处理拖拽容器视图进行交互式关闭的手势
 * - 手势状态：管理手势的开始、变化、结束等状态
 * - 拖拽进度：计算拖拽进度并提供视觉反馈
 * - 自动关闭：根据拖拽距离和速度判断是否自动关闭弹窗
 */

import UIKit

/// SKDialog手势处理器
/// 负责管理弹窗的所有手势交互逻辑
@MainActor
class SKDialogGestureHandler {
    
    // MARK: - Properties
    
    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?
    
    /// 背景点击手势识别器
    private var backgroundTapGesture: UITapGestureRecognizer?
    
    /// 拖拽手势识别器
    private var panGesture: UIPanGestureRecognizer?
    
    /// 拖拽开始时的容器位置
    private var initialContainerCenter: CGPoint = .zero
    
    /// 拖拽开始时的触摸位置
    private var initialTouchPoint: CGPoint = .zero
    
    // MARK: - Initialization
    
    /// 初始化手势处理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Public Methods
    
    /// 设置所有手势识别器
    func setupGestures() {
        setupBackgroundTapGesture()
        setupPanGesture()
    }
    
    /// 移除所有手势识别器
    func removeGestures() {
        removeBackgroundTapGesture()
        removePanGesture()
    }
    
    /// 更新手势状态（根据配置启用或禁用）
    func updateGestureStates() {
        guard let viewController = viewController else { return }
        
        // 更新背景点击手势状态
        backgroundTapGesture?.isEnabled = viewController.config.dismissOnBackgroundTap
        
        // 更新拖拽手势状态（只有底部和顶部弹窗支持拖拽）
        let supportsPanGesture = viewController.config.position == .bottom || viewController.config.position == .top
        panGesture?.isEnabled = supportsPanGesture
    }
    
    // MARK: - Private Methods - Background Tap
    
    /// 设置背景点击手势
    private func setupBackgroundTapGesture() {
        guard let viewController = viewController else { return }
        
        // 移除旧的手势
        removeBackgroundTapGesture()
        
        // 创建新的背景点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tapGesture.isEnabled = viewController.config.dismissOnBackgroundTap
        
        viewController.backgroundView.addGestureRecognizer(tapGesture)
        backgroundTapGesture = tapGesture
    }
    
    /// 移除背景点击手势
    private func removeBackgroundTapGesture() {
        if let gesture = backgroundTapGesture {
            gesture.view?.removeGestureRecognizer(gesture)
            backgroundTapGesture = nil
        }
    }
    
    /// 处理背景点击事件
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard let viewController = viewController else { return }
        
        // 确保点击的是背景视图而不是容器视图
        let location = gesture.location(in: viewController.view)
        let containerFrame = viewController.containerView.frame
        
        if !containerFrame.contains(location) {
            viewController.dismiss()
        }
    }
    
    // MARK: - Private Methods - Pan Gesture
    
    /// 设置拖拽手势
    private func setupPanGesture() {
        guard let viewController = viewController else { return }
        
        // 移除旧的手势
        removePanGesture()
        
        // 创建新的拖拽手势
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        
        // 只有底部和顶部弹窗支持拖拽
        let supportsPanGesture = viewController.config.position == .bottom || viewController.config.position == .top
        panGestureRecognizer.isEnabled = supportsPanGesture
        
        viewController.containerView.addGestureRecognizer(panGestureRecognizer)
        panGesture = panGestureRecognizer
    }
    
    /// 移除拖拽手势
    private func removePanGesture() {
        if let gesture = panGesture {
            gesture.view?.removeGestureRecognizer(gesture)
            panGesture = nil
        }
    }
    
    /// 处理拖拽手势事件
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard viewController != nil else { return }
        
        switch gesture.state {
        case .began:
            handlePanBegan(gesture)
        case .changed:
            handlePanChanged(gesture)
        case .ended, .cancelled:
            handlePanEnded(gesture)
        default:
            break
        }
    }
    
    /// 处理拖拽开始
    private func handlePanBegan(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }
        
        // 记录初始位置
        initialContainerCenter = viewController.containerView.center
        initialTouchPoint = gesture.location(in: viewController.view)
    }
    
    /// 处理拖拽变化
    private func handlePanChanged(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }
        
        let translation = gesture.translation(in: viewController.view)
        let position = viewController.config.position
        
        // 根据弹窗位置限制拖拽方向
        var allowedTranslation = translation
        
        switch position {
        case .bottom:
            // 底部弹窗只允许向下拖拽
            allowedTranslation.y = max(0, translation.y)
        case .top:
            // 顶部弹窗只允许向上拖拽
            allowedTranslation.y = min(0, translation.y)
        case .center:
            // 居中弹窗不支持拖拽
            return
        }
        
        // 更新容器位置
        let newCenter = CGPoint(
            x: initialContainerCenter.x,
            y: initialContainerCenter.y + allowedTranslation.y
        )
        viewController.containerView.center = newCenter
        
        // 计算拖拽进度并更新背景透明度
        let progress = calculateDragProgress(translation: allowedTranslation)
        updateBackgroundAlpha(progress: progress)
    }
    
    /// 处理拖拽结束
    private func handlePanEnded(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }
        
        let translation = gesture.translation(in: viewController.view)
        let velocity = gesture.velocity(in: viewController.view)
        
        // 判断是否应该关闭弹窗
        if shouldDismissOnPanEnd(translation: translation, velocity: velocity) {
            viewController.dismiss()
        } else {
            // 恢复到原始位置
            restoreContainerPosition()
        }
    }
    
    /// 计算拖拽进度
    /// - Parameter translation: 拖拽偏移量
    /// - Returns: 拖拽进度（0.0 - 1.0）
    private func calculateDragProgress(translation: CGPoint) -> CGFloat {
        guard let viewController = viewController else { return 0 }
        
        let containerHeight = viewController.containerView.bounds.height
        let dragDistance = abs(translation.y)
        
        // 拖拽距离超过容器高度的一半时进度为1
        let maxDragDistance = containerHeight * 0.5
        let progress = min(dragDistance / maxDragDistance, 1.0)
        
        return progress
    }
    
    /// 更新背景透明度
    /// - Parameter progress: 拖拽进度
    private func updateBackgroundAlpha(progress: CGFloat) {
        guard let viewController = viewController else { return }
        
        // 根据拖拽进度调整背景透明度
        let originalAlpha = viewController.config.backgroundMaskColor.cgColor.alpha
        let newAlpha = originalAlpha * (1.0 - progress * 0.5) // 最多减少50%透明度
        
        viewController.backgroundView.backgroundColor = viewController.config.backgroundMaskColor.withAlphaComponent(newAlpha)
    }
    
    /// 判断是否应该在拖拽结束时关闭弹窗
    /// - Parameters:
    ///   - translation: 拖拽偏移量
    ///   - velocity: 拖拽速度
    /// - Returns: 是否应该关闭
    private func shouldDismissOnPanEnd(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard let viewController = viewController else { return false }
        
        let containerHeight = viewController.containerView.bounds.height
        let dragDistance = abs(translation.y)
        let dragVelocity = abs(velocity.y)
        
        // 拖拽距离超过容器高度的1/3或者拖拽速度超过阈值
        let distanceThreshold = containerHeight / 3.0
        let velocityThreshold: CGFloat = 1000.0
        
        return dragDistance > distanceThreshold || dragVelocity > velocityThreshold
    }
    
    /// 恢复容器到原始位置
    private func restoreContainerPosition() {
        guard let viewController = viewController else { return }
        
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.curveEaseOut],
            animations: {
                viewController.containerView.center = self.initialContainerCenter
                viewController.backgroundView.backgroundColor = viewController.config.backgroundMaskColor
            },
            completion: nil
        )
    }
}

// MARK: - Internal Access

extension SKDialogGestureHandler {
    
    /// 获取当前是否正在拖拽
    var isDragging: Bool {
        return panGesture?.state == .changed
    }
    
    /// 获取背景点击手势是否启用
    var isBackgroundTapEnabled: Bool {
        return backgroundTapGesture?.isEnabled ?? false
    }
    
    /// 获取拖拽手势是否启用
    var isPanGestureEnabled: Bool {
        return panGesture?.isEnabled ?? false
    }
    
    /// 强制结束当前手势
    func cancelCurrentGestures() {
        panGesture?.isEnabled = false
        panGesture?.isEnabled = true
        
        backgroundTapGesture?.isEnabled = false
        backgroundTapGesture?.isEnabled = true
    }
}
