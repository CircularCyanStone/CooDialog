//
//  SKDialogConstraintManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的约束管理器，专门负责处理弹窗容器视图的约束设置、更新和管理。
 * 该管理器将约束相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 约束设置：根据弹窗配置设置容器视图的位置、尺寸约束
 * - 约束更新：动态更新约束以适应不同的显示模式和尺寸要求
 * - 位置管理：处理弹窗在不同位置（顶部、居中、底部）的约束配置
 * - 尺寸管理：处理固定尺寸、内容自适应等不同尺寸模式的约束
 * - 安全区域：处理延伸到安全区域的约束配置
 */

import UIKit

/// SKDialog约束管理器
/// 负责管理弹窗容器视图的约束设置和更新
@MainActor
class SKDialogConstraintManager {
    
    // MARK: - Properties
    
    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?
    
    /// 容器视图的约束引用，用于动态更新
    private var containerConstraints: [NSLayoutConstraint] = []
    
    // MARK: - Initialization
    
    /// 初始化约束管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Public Methods
    
    /// 设置容器视图的所有约束
    /// 根据配置的位置、尺寸模式、边距等参数设置约束
    func setupContainerConstraints() {
        guard viewController != nil else { return }
        
        // 清除之前的约束
        clearConstraints()
        
        // 设置背景遮罩约束（填满整个视图）
        setupBackgroundConstraints()
        
        // 设置容器视图约束
        setupContainerViewConstraints()
        
        // 激活所有约束
        NSLayoutConstraint.activate(containerConstraints)
    }
    
    /// 更新约束以适应新的尺寸模式
    /// - Parameter sizeMode: 新的尺寸模式
    func updateConstraintsForSizeMode(_ sizeMode: SKDialogSizeMode) {
        guard let viewController = viewController else { return }
        
        // 移除尺寸相关的约束
        removeSizeConstraints()
        
        // 根据新的尺寸模式添加约束
        addSizeConstraints(for: sizeMode)
        
        // 更新布局
        viewController.view.layoutIfNeeded()
    }
    
    /// 更新位置约束
    /// - Parameter position: 新的位置
    func updateConstraintsForPosition(_ position: SKDialogPosition) {
        guard let viewController = viewController else { return }
        
        // 移除位置相关的约束
        removePositionConstraints()
        
        // 根据新位置添加约束
        addPositionConstraints(for: position)
        
        // 更新布局
        viewController.view.layoutIfNeeded()
    }
    
    // MARK: - Private Methods
    
    /// 清除所有约束
    private func clearConstraints() {
        NSLayoutConstraint.deactivate(containerConstraints)
        containerConstraints.removeAll()
    }
    
    /// 设置背景遮罩约束
    private func setupBackgroundConstraints() {
        guard let viewController = viewController else { return }
        
        viewController.backgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        let backgroundConstraints = [
            viewController.backgroundView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            viewController.backgroundView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            viewController.backgroundView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            viewController.backgroundView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ]
        
        containerConstraints.append(contentsOf: backgroundConstraints)
    }
    
    /// 设置容器视图约束
    private func setupContainerViewConstraints() {
        guard let viewController = viewController else { return }
        
        viewController.containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // 添加位置约束
        addPositionConstraints(for: viewController.config.position)
        
        // 添加尺寸约束
        addSizeConstraints(for: viewController.config.sizeMode)
    }
    
    /// 添加位置约束
    /// - Parameter position: 弹窗位置
    private func addPositionConstraints(for position: SKDialogPosition) {
        guard let viewController = viewController else { return }
        
        let config = viewController.config
        let containerView = viewController.containerView
        let parentView = viewController.view!
        
        var positionConstraints: [NSLayoutConstraint] = []
        
        // 水平居中约束（所有位置都需要）
        positionConstraints.append(
            containerView.centerXAnchor.constraint(equalTo: parentView.centerXAnchor)
        )
        
        // 根据位置设置垂直约束
        switch position {
        case .top:
            if config.extendToSafeArea {
                positionConstraints.append(
                    containerView.topAnchor.constraint(equalTo: parentView.topAnchor, constant: config.margins.top)
                )
            } else {
                positionConstraints.append(
                    containerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: config.margins.top)
                )
            }
            
        case .center:
            positionConstraints.append(
                containerView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor)
            )
            
        case .bottom:
            if config.extendToSafeArea {
                positionConstraints.append(
                    containerView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -config.margins.bottom)
                )
            } else {
                positionConstraints.append(
                    containerView.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor, constant: -config.margins.bottom)
                )
            }
        }
        
        // 添加水平边距约束
        positionConstraints.append(contentsOf: [
            containerView.leadingAnchor.constraint(greaterThanOrEqualTo: parentView.leadingAnchor, constant: config.margins.left),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: parentView.trailingAnchor, constant: -config.margins.right)
        ])
        
        containerConstraints.append(contentsOf: positionConstraints)
    }
    
    /// 添加尺寸约束
    /// - Parameter sizeMode: 尺寸模式
    private func addSizeConstraints(for sizeMode: SKDialogSizeMode) {
        guard let viewController = viewController else { return }
        
        let containerView = viewController.containerView
        var sizeConstraints: [NSLayoutConstraint] = []
        
        switch sizeMode {
        case .fixed(let width, let height):
            if let width = width {
                let widthConstraint = containerView.widthAnchor.constraint(equalToConstant: width)
                sizeConstraints.append(widthConstraint)
                viewController.containerWidthConstraint = widthConstraint
            }
            if let height = height {
                let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: height)
                sizeConstraints.append(heightConstraint)
                viewController.containerHeightConstraint = heightConstraint
            }
            
        case .widthFixed(let width):
            sizeConstraints.append(containerView.widthAnchor.constraint(equalToConstant: width))
            viewController.containerWidthConstraint = sizeConstraints.last
            
        case .heightFixed(let height):
            sizeConstraints.append(containerView.heightAnchor.constraint(equalToConstant: height))
            viewController.containerHeightConstraint = sizeConstraints.last
            
        case .contentAdaptive:
            // 内容自适应模式不需要额外的尺寸约束
            // 容器会根据内容自动调整大小
            break
        }
        
        containerConstraints.append(contentsOf: sizeConstraints)
    }
    
    /// 移除尺寸相关约束
    private func removeSizeConstraints() {
        guard let viewController = viewController else { return }
        
        // 移除并重置约束引用
        if let widthConstraint = viewController.containerWidthConstraint {
            widthConstraint.isActive = false
            containerConstraints.removeAll { $0 === widthConstraint }
            viewController.containerWidthConstraint = nil
        }
        
        if let heightConstraint = viewController.containerHeightConstraint {
            heightConstraint.isActive = false
            containerConstraints.removeAll { $0 === heightConstraint }
            viewController.containerHeightConstraint = nil
        }
    }
    
    /// 移除位置相关约束
    private func removePositionConstraints() {
        // 保留尺寸约束，只移除位置约束
        let sizeConstraints = containerConstraints.filter { constraint in
            return constraint === viewController?.containerWidthConstraint ||
                   constraint === viewController?.containerHeightConstraint
        }
        
        // 停用所有约束
        NSLayoutConstraint.deactivate(containerConstraints)
        
        // 只保留尺寸约束
        containerConstraints = sizeConstraints
        
        // 重新激活尺寸约束
        NSLayoutConstraint.activate(containerConstraints)
    }
}

// MARK: - Internal Access

extension SKDialogConstraintManager {
    
    /// 获取当前活跃的约束列表（用于调试）
    var activeConstraints: [NSLayoutConstraint] {
        return containerConstraints.filter { $0.isActive }
    }
    
    /// 检查约束是否正确设置
    var isConstraintsValid: Bool {
        guard let viewController = viewController else { return false }
        
        // 检查容器视图是否有父视图
        guard viewController.containerView.superview != nil else { return false }
        
        // 检查是否有基本的位置约束
        let hasPositionConstraints = containerConstraints.contains { constraint in
            constraint.firstItem === viewController.containerView &&
            (constraint.firstAttribute == .centerX || 
             constraint.firstAttribute == .centerY ||
             constraint.firstAttribute == .top ||
             constraint.firstAttribute == .bottom)
        }
        
        return hasPositionConstraints
    }
}
