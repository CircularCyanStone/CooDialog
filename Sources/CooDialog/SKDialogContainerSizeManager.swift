//
//  SKDialogContainerSizeManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的容器尺寸管理器，专门负责处理弹窗容器视图的尺寸动态更新和管理。
 * 该管理器将容器尺寸相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 尺寸更新：动态更新容器的宽度、高度或整体尺寸
 * - 约束同步：更新尺寸时同步更新相关约束
 * - 配置同步：更新尺寸时同步更新弹窗配置
 * - 动画支持：支持尺寸变化的动画效果
 * - 内容适配：根据内容自动调整容器尺寸
 */

import UIKit

/// SKDialog容器尺寸管理器
/// 负责管理弹窗容器视图的尺寸动态更新
@MainActor
class SKDialogContainerSizeManager {
    
    // MARK: - Properties
    
    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?
    
    /// 尺寸变化动画配置
    private struct SizeAnimationConfig {
        let duration: TimeInterval
        let damping: CGFloat
        let velocity: CGFloat
        let options: UIView.AnimationOptions
        
        static let `default` = SizeAnimationConfig(
            duration: 0.3,
            damping: 0.8,
            velocity: 0,
            options: [.curveEaseInOut]
        )
    }
    
    // MARK: - Initialization
    
    /// 初始化容器尺寸管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Public Methods - Height Management
    
    /// 动态更新容器高度
    /// - Parameters:
    ///   - height: 新的高度值
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func updateContainerHeight(_ height: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 更新约束
        updateHeightConstraint(height)
        
        // 更新配置
        updateConfigForHeightChange(height)
        
        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }
    
    /// 根据内容自动调整高度
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustHeightToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 计算内容所需高度
        let contentHeight = calculateContentHeight()
        
        // 更新高度
        updateContainerHeight(contentHeight, animated: animated, completion: completion)
    }
    
    // MARK: - Public Methods - Width Management
    
    /// 动态更新容器宽度
    /// - Parameters:
    ///   - width: 新的宽度值
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func updateContainerWidth(_ width: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 更新约束
        updateWidthConstraint(width)
        
        // 更新配置
        updateConfigForWidthChange(width)
        
        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }
    
    /// 根据内容自动调整宽度
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustWidthToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 计算内容所需宽度
        let contentWidth = calculateContentWidth()
        
        // 更新宽度
        updateContainerWidth(contentWidth, animated: animated, completion: completion)
    }
    
    // MARK: - Public Methods - Size Management
    
    /// 动态更新容器尺寸
    /// - Parameters:
    ///   - size: 新的尺寸
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func updateContainerSize(_ size: CGSize, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 更新约束
        updateSizeConstraints(size)
        
        // 更新配置
        updateConfigForSizeChange(size)
        
        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }
    
    /// 根据内容自动调整尺寸
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustSizeToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }
        
        // 计算内容所需尺寸
        let contentSize = calculateContentSize()
        
        // 更新尺寸
        updateContainerSize(contentSize, animated: animated, completion: completion)
    }
    
    // MARK: - Private Methods - Constraint Updates
    
    /// 更新高度约束
    /// - Parameter height: 新的高度值
    private func updateHeightConstraint(_ height: CGFloat) {
        guard let viewController = viewController else { return }
        
        if let heightConstraint = viewController.containerHeightConstraint {
            heightConstraint.constant = height
        } else {
            // 如果没有高度约束，创建一个新的
            let newConstraint = viewController.containerView.heightAnchor.constraint(equalToConstant: height)
            newConstraint.isActive = true
            viewController.containerHeightConstraint = newConstraint
        }
    }
    
    /// 更新宽度约束
    /// - Parameter width: 新的宽度值
    private func updateWidthConstraint(_ width: CGFloat) {
        guard let viewController = viewController else { return }
        
        if let widthConstraint = viewController.containerWidthConstraint {
            widthConstraint.constant = width
        } else {
            // 如果没有宽度约束，创建一个新的
            let newConstraint = viewController.containerView.widthAnchor.constraint(equalToConstant: width)
            newConstraint.isActive = true
            viewController.containerWidthConstraint = newConstraint
        }
    }
    
    /// 更新尺寸约束
    /// - Parameter size: 新的尺寸
    private func updateSizeConstraints(_ size: CGSize) {
        updateWidthConstraint(size.width)
        updateHeightConstraint(size.height)
    }
    
    // MARK: - Private Methods - Config Updates
    
    /// 更新配置以反映高度变化
    /// - Parameter height: 新的高度值
    private func updateConfigForHeightChange(_ height: CGFloat) {
        guard let viewController = viewController else { return }
        
        // 根据当前尺寸模式更新配置
        switch viewController.config.sizeMode {
        case .fixed(let width, _):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .heightFixed(_):
            viewController.config.sizeMode = .heightFixed(height)
        case .widthFixed(let width):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .contentAdaptive:
            // 内容自适应模式不需要更新配置
            break
        }
    }
    
    /// 更新配置以反映宽度变化
    /// - Parameter width: 新的宽度值
    private func updateConfigForWidthChange(_ width: CGFloat) {
        guard let viewController = viewController else { return }
        
        // 根据当前尺寸模式更新配置
        switch viewController.config.sizeMode {
        case .fixed(_, let height):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .widthFixed(_):
            viewController.config.sizeMode = .widthFixed(width)
        case .heightFixed(let height):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .contentAdaptive:
            // 内容自适应模式不需要更新配置
            break
        }
    }
    
    /// 更新配置以反映尺寸变化
    /// - Parameter size: 新的尺寸
    private func updateConfigForSizeChange(_ size: CGSize) {
        guard let viewController = viewController else { return }
        
        viewController.config.sizeMode = .fixed(width: size.width, height: size.height)
    }
    
    // MARK: - Private Methods - Content Size Calculation
    
    /// 计算内容所需高度
    /// - Returns: 内容高度
    private func calculateContentHeight() -> CGFloat {
        guard let viewController = viewController else { return 0 }
        
        // 获取容器视图的当前宽度
        let containerWidth = viewController.containerView.bounds.width
        
        // 如果容器宽度为0，使用屏幕宽度减去边距
        let availableWidth = containerWidth > 0 ? containerWidth : 
            UIScreen.main.bounds.width - viewController.config.margins.left - viewController.config.margins.right
        
        // 计算内容视图所需的高度
        let targetSize = CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height)
        let contentHeight = viewController.containerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        
        return max(contentHeight, 44) // 最小高度44
    }
    
    /// 计算内容所需宽度
    /// - Returns: 内容宽度
    private func calculateContentWidth() -> CGFloat {
        guard let viewController = viewController else { return 0 }
        
        // 获取容器视图的当前高度
        let containerHeight = viewController.containerView.bounds.height
        
        // 如果容器高度为0，使用一个合理的默认值
        let availableHeight = containerHeight > 0 ? containerHeight : 200
        
        // 计算内容视图所需的宽度
        let targetSize = CGSize(width: UIView.layoutFittingCompressedSize.width, height: availableHeight)
        let contentWidth = viewController.containerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .required
        ).width
        
        // 限制最大宽度为屏幕宽度减去边距
        let maxWidth = UIScreen.main.bounds.width - viewController.config.margins.left - viewController.config.margins.right
        
        return min(max(contentWidth, 100), maxWidth) // 最小宽度100，最大宽度为屏幕宽度减去边距
    }
    
    /// 计算内容所需尺寸
    /// - Returns: 内容尺寸
    private func calculateContentSize() -> CGSize {
        guard let viewController = viewController else { return .zero }
        
        // 使用系统布局计算合适的尺寸
        let fittingSize = viewController.containerView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        
        // 限制尺寸范围
        let maxWidth = UIScreen.main.bounds.width - viewController.config.margins.left - viewController.config.margins.right
        let maxHeight = UIScreen.main.bounds.height - viewController.config.margins.top - viewController.config.margins.bottom
        
        let width = min(max(fittingSize.width, 100), maxWidth)
        let height = min(max(fittingSize.height, 44), maxHeight)
        
        return CGSize(width: width, height: height)
    }
    
    // MARK: - Private Methods - Layout Updates
    
    /// 执行布局更新
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 完成回调
    private func performLayoutUpdate(animated: Bool, completion: (() -> Void)?) {
        guard let viewController = viewController else {
            completion?()
            return
        }
        
        if animated {
            let config = SizeAnimationConfig.default
            
            UIView.animate(
                withDuration: config.duration,
                delay: 0,
                usingSpringWithDamping: config.damping,
                initialSpringVelocity: config.velocity,
                options: config.options,
                animations: {
                    viewController.view.layoutIfNeeded()
                },
                completion: { _ in
                    completion?()
                }
            )
        } else {
            viewController.view.layoutIfNeeded()
            completion?()
        }
    }
}

// MARK: - Internal Access

extension SKDialogContainerSizeManager {
    
    /// 获取当前容器尺寸
    var currentContainerSize: CGSize {
        guard let viewController = viewController else { return .zero }
        return viewController.containerView.bounds.size
    }
    
    /// 获取当前约束值
    var currentConstraintValues: (width: CGFloat?, height: CGFloat?) {
        guard let viewController = viewController else { return (nil, nil) }
        
        let width = viewController.containerWidthConstraint?.constant
        let height = viewController.containerHeightConstraint?.constant
        
        return (width, height)
    }
    
    /// 检查尺寸约束是否有效
    var isSizeConstraintsValid: Bool {
        guard let viewController = viewController else { return false }
        
        switch viewController.config.sizeMode {
        case .fixed(_, _):
            return viewController.containerWidthConstraint != nil && viewController.containerHeightConstraint != nil
        case .widthFixed(_):
            return viewController.containerWidthConstraint != nil
        case .heightFixed(_):
            return viewController.containerHeightConstraint != nil
        case .contentAdaptive:
            return true // 内容自适应模式不需要固定约束
        }
    }
    
    /// 强制刷新尺寸计算
    func forceRefreshSize() {
        guard let viewController = viewController else { return }
        
        // 强制重新计算布局
        viewController.containerView.setNeedsLayout()
        viewController.containerView.layoutIfNeeded()
        
        // 如果是内容自适应模式，重新调整尺寸
        if case .contentAdaptive = viewController.config.sizeMode {
            adjustSizeToContent(animated: false)
        }
    }
}
