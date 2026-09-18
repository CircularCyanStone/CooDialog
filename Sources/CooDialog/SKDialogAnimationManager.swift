//
//  SKDialogAnimationManager.swift
//  SiKu
//
//  Created by Assistant on 2024
//
//  弹窗动画管理器
//  负责管理弹窗的显示和消失动画，支持多种动画类型包括滑入、渐变缩放等
//  提供统一的动画接口，根据配置选择相应的动画实现

import UIKit

/// 弹窗动画管理器
@MainActor
public class SKDialogAnimationManager {
    
    // MARK: - Properties
    
    private let config: SKDialogConfig
    
    // MARK: - Initialization
    
    public init(config: SKDialogConfig) {
        self.config = config
    }
    
    // MARK: - Public Methods
    
    /// 执行显示动画
    public func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        completion: @escaping () -> Void
    ) {
        switch config.animationType {
        case .slideFromBottom:
            SlideFromBottomAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .fadeScale:
            FadeScaleAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromTop:
            SlideFromTopAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromLeft:
            SlideFromLeftAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromRight:
            SlideFromRightAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromBottomWithFade:
            SlideFromBottomWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromTopWithFade:
            SlideFromTopWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromLeftWithFade:
            SlideFromLeftWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromRightWithFade:
            SlideFromRightWithFadeAnimation().performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .custom(let animation):
            animation.performPresentAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
        }
    }
    
    /// 执行消失动画
    public func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        completion: @escaping () -> Void
    ) {
        switch config.animationType {
        case .slideFromBottom:
            SlideFromBottomAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .fadeScale:
            FadeScaleAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromTop:
            SlideFromTopAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromLeft:
            SlideFromLeftAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromRight:
            SlideFromRightAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromBottomWithFade:
            SlideFromBottomWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromTopWithFade:
            SlideFromTopWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromLeftWithFade:
            SlideFromLeftWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .slideFromRightWithFade:
            SlideFromRightWithFadeAnimation().performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
            
        case .custom(let animation):
            animation.performDismissAnimation(
                backgroundView: backgroundView,
                containerView: containerView,
                config: config,
                completion: completion
            )
        }
    }
}

// MARK: - 带渐变效果的滑动动画类

/// 从底部滑入带渐变动画
class SlideFromBottomWithFadeAnimation: SKDialogAnimationProtocol {
    
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
        // 初始状态：容器在底部且透明
        containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
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

/// 从顶部滑入带渐变动画
class SlideFromTopWithFadeAnimation: SKDialogAnimationProtocol {
    
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
        // 初始状态：容器在顶部且透明
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

/// 从左侧滑入带渐变动画
class SlideFromLeftWithFadeAnimation: SKDialogAnimationProtocol {
    
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

/// 从右侧滑入带渐变动画
class SlideFromRightWithFadeAnimation: SKDialogAnimationProtocol {
    
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
        // 初始状态：容器在右侧且透明
        containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
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
                containerView.transform = CGAffineTransform(translationX: slideDistance, y: 0)
                containerView.alpha = 0
                backgroundView.alpha = 0
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从底部滑入动画

/// 从底部滑入动画
class SlideFromBottomAnimation: SKDialogAnimationProtocol {
    
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
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: 0, y: slideDistance)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 渐变缩放动画

/// 渐变缩放动画
class FadeScaleAnimation: SKDialogAnimationProtocol {
    
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in
                completion()
            }
        )
    }
    
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.alpha = 0
                containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从顶部滑入动画

/// 从顶部滑入动画
class SlideFromTopAnimation: SKDialogAnimationProtocol {
    
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        containerView.superview?.layoutIfNeeded()
        
        let slideDistance = max(containerView.bounds.height, 100)
        containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
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
    
    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        let slideDistance = max(containerView.bounds.height, 100)
        
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = CGAffineTransform(translationX: 0, y: -slideDistance)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从左侧滑入动画

/// 从左侧滑入动画
class SlideFromLeftAnimation: SKDialogAnimationProtocol {
    
    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        containerView.superview?.layoutIfNeeded()
        
        let slideDistance = max(containerView.bounds.width, 100)
        containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
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
                containerView.transform = CGAffineTransform(translationX: -slideDistance, y: 0)
            },
            completion: { _ in
                completion()
            }
        )
    }
}

// MARK: - 从右侧滑入动画

/// 从右侧滑入动画
class SlideFromRightAnimation: SKDialogAnimationProtocol {
    
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
