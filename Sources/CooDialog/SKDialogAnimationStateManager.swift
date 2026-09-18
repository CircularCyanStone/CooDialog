//
//  SKDialogAnimationStateManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的动画状态管理器，专门负责处理弹窗的动画初始状态设置和动画过程中的状态管理。
 * 该管理器将动画状态相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 初始状态：根据动画类型设置弹窗显示前的初始状态
 * - 状态计算：计算不同动画类型所需的偏移量、缩放比例等
 * - 状态管理：管理动画过程中的各种状态变化
 * - 偏移计算：计算滑动动画的偏移量
 * - 变换设置：设置容器视图的transform变换
 */

import UIKit

/// SKDialog动画状态管理器
/// 负责管理弹窗动画的初始状态和状态变化
@MainActor
class SKDialogAnimationStateManager {
    
    // MARK: - Properties
    
    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?
    
    /// 当前动画状态
    private var currentAnimationState: AnimationState = .initial
    
    /// 动画状态枚举
    private enum AnimationState {
        case initial    // 初始状态
        case animating  // 动画中
        case final      // 最终状态
    }
    
    // MARK: - Initialization
    
    /// 初始化动画状态管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Public Methods
    
    /// 设置动画初始状态
    /// 根据配置的动画类型设置容器视图的初始状态
    func setupInitialAnimationState() {
        guard let viewController = viewController else { return }
        
        currentAnimationState = .initial
        
        let animationType = viewController.config.animationType
        
        switch animationType {
        case .slideFromBottom, .slideFromTop:
            setupSlideInitialState()
        case .slideFromLeft, .slideFromRight:
            setupSlideInitialState()
        case .slideFromBottomWithFade, .slideFromTopWithFade:
            setupSlideWithFadeInitialState()
        case .slideFromLeftWithFade, .slideFromRightWithFade:
            setupSlideWithFadeInitialState()
        case .fadeScale:
            setupFadeScaleInitialState()
        case .custom(_):
            // 自定义动画由外部处理
            break
        }
    }
    
    /// 重置到最终状态
    /// 将容器视图重置到正常显示状态
    func resetToFinalState() {
        guard let viewController = viewController else { return }
        
        currentAnimationState = .final
        
        // 重置所有变换
        viewController.containerView.transform = .identity
        viewController.containerView.alpha = 1.0
        viewController.backgroundView.alpha = 1.0
    }
    
    /// 更新滑动偏移量（布局更新后调用）
    func updateSlideOffsetAfterLayout() {
        guard let viewController = viewController else { return }
        guard currentAnimationState == .initial else { return }
        
        let animationType = viewController.config.animationType
        
        // 只有包含滑动的动画类型需要更新偏移量
        switch animationType {
        case .slideFromBottom, .slideFromTop, .slideFromLeft, .slideFromRight:
            let offset = calculateSlideOffset()
            let transform: CGAffineTransform
            
            switch animationType {
            case .slideFromLeft, .slideFromRight:
                transform = CGAffineTransform(translationX: offset, y: 0)
            default:
                transform = CGAffineTransform(translationX: 0, y: offset)
            }
            
            viewController.containerView.transform = transform
        case .slideFromBottomWithFade, .slideFromTopWithFade, .slideFromLeftWithFade, .slideFromRightWithFade:
            let offset = calculateSlideOffset()
            let transform: CGAffineTransform
            
            switch animationType {
            case .slideFromLeftWithFade, .slideFromRightWithFade:
                transform = CGAffineTransform(translationX: offset, y: 0)
            default:
                transform = CGAffineTransform(translationX: 0, y: offset)
            }
            
            viewController.containerView.transform = transform
        default:
            break
        }
    }
    
    /// 标记动画开始
    func markAnimationStarted() {
        currentAnimationState = .animating
    }
    
    /// 标记动画完成
    func markAnimationCompleted() {
        currentAnimationState = .final
    }
    
    // MARK: - Private Methods - Slide Animation
    
    /// 设置滑动动画初始状态
    private func setupSlideInitialState() {
        guard let viewController = viewController else { return }
        
        let offset = calculateSlideOffset()
        viewController.containerView.transform = CGAffineTransform(translationX: 0, y: offset)
    }
    
    /// 计算滑动偏移量
    /// - Returns: 偏移量（根据动画类型确定方向）
    private func calculateSlideOffset() -> CGFloat {
        guard let viewController = viewController else { return 0 }
        
        let animationType = viewController.config.animationType
        let containerSize = viewController.containerView.bounds.size
        _ = viewController.view.bounds.size
        
        switch animationType {
        case .slideFromTop, .slideFromTopWithFade:
            // 从顶部滑入，初始位置在视图上方
            return -(containerSize.height + viewController.config.margins.top)
        case .slideFromBottom, .slideFromBottomWithFade:
            // 从底部滑入，初始位置在视图下方
            return containerSize.height + viewController.config.margins.bottom
        case .slideFromLeft, .slideFromLeftWithFade:
            // 从左侧滑入，初始位置在视图左侧
            return -(containerSize.width + viewController.config.margins.left)
        case .slideFromRight, .slideFromRightWithFade:
            // 从右侧滑入，初始位置在视图右侧
            return containerSize.width + viewController.config.margins.right
        default:
            return 0
        }
    }
    
    /// 设置带渐变的滑动动画初始状态
    private func setupSlideWithFadeInitialState() {
        guard let viewController = viewController else { return }
        
        let offset = calculateSlideOffset()
        let animationType = viewController.config.animationType
        
        // 设置滑动偏移
        let transform: CGAffineTransform
        switch animationType {
        case .slideFromLeftWithFade, .slideFromRightWithFade:
            transform = CGAffineTransform(translationX: offset, y: 0)
        default:
            transform = CGAffineTransform(translationX: 0, y: offset)
        }
        
        viewController.containerView.transform = transform
        // 设置初始透明度为0（渐变效果）
        viewController.containerView.alpha = 0.0
        viewController.backgroundView.alpha = 0.0
    }
    
    // MARK: - Private Methods - FadeScale Animation
    
    /// 设置渐变缩放动画初始状态
    private func setupFadeScaleInitialState() {
        guard let viewController = viewController else { return }
        
        // 设置初始缩放和透明度
        let initialScale = viewController.config.fadeScaleInitialScale
        viewController.containerView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
        viewController.containerView.alpha = 0.0
        viewController.backgroundView.alpha = 0.0
    }
}

// MARK: - Internal Access

extension SKDialogAnimationStateManager {
    
    /// 获取当前动画状态
    var isInInitialState: Bool {
        return currentAnimationState == .initial
    }
    
    /// 获取是否正在动画中
    var isAnimating: Bool {
        return currentAnimationState == .animating
    }
    
    /// 获取是否在最终状态
    var isInFinalState: Bool {
        return currentAnimationState == .final
    }
    
    /// 获取当前容器视图的变换信息（用于调试）
    var currentTransformInfo: (translation: CGPoint, scale: CGPoint, rotation: CGFloat) {
        guard let viewController = viewController else {
            return (translation: .zero, scale: CGPoint(x: 1, y: 1), rotation: 0)
        }
        
        let transform = viewController.containerView.transform
        
        // 提取变换信息
        let translation = CGPoint(x: transform.tx, y: transform.ty)
        let scaleX = sqrt(transform.a * transform.a + transform.c * transform.c)
        let scaleY = sqrt(transform.b * transform.b + transform.d * transform.d)
        let scale = CGPoint(x: scaleX, y: scaleY)
        let rotation = atan2(transform.b, transform.a)
        
        return (translation: translation, scale: scale, rotation: rotation)
    }
    
    /// 强制重置状态
    func forceResetState() {
        currentAnimationState = .initial
        setupInitialAnimationState()
    }
}
