//
//  SKDialog.swift
//  SiKu
//
//  Created by Assistant on 2024
//

/**
 * SKDialog - 弹窗组件的便捷入口类
 * 
 * 功能描述：
 * - 提供链式配置API，简化弹窗创建和配置过程
 * - 支持多种弹窗位置：底部、居中、顶部
 * - 支持多种显示模式：Window模式、ViewController模式
 * - 提供丰富的配置选项：动画、样式、交互等
 * - 内置常用弹窗类型的快速创建方法
 * 
 * 类型功能：
 * - SKDialog：主要的弹窗构建器类，提供链式配置API
 * - 静态便利方法：提供快速创建常用弹窗的方法
 * - 扩展方法：提供预设配置的构建器
 */

import UIKit

/// 弹窗便捷入口类 - 提供链式配置API和快速创建方法
@MainActor
public class SKDialog {
    
    // MARK: - Properties
    
    private var config = SKDialogConfig()
    private var contentView: UIView?
    
    // 动画回调
    private var presentAnimationWillStartHandler: (() -> Void)?
    private var presentAnimationDidFinishHandler: (() -> Void)?
    private var dismissAnimationWillStartHandler: (() -> Void)?
    private var dismissAnimationDidFinishHandler: (() -> Void)?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Core Configuration Methods
    
    /// 设置弹窗位置
    @discardableResult
    public func position(_ position: SKDialogPosition) -> SKDialog {
        config.position = position
        return self
    }
    
    /// 设置显示模式
    @discardableResult
    public func presentationMode(_ mode: SKDialogPresentationMode) -> SKDialog {
        config.presentationMode = mode
        return self
    }
    
    /// 设置尺寸模式
    @discardableResult
    public func sizeMode(_ mode: SKDialogSizeMode) -> SKDialog {
        config.sizeMode = mode
        return self
    }
    
    /// 设置边距
    @discardableResult
    public func margins(_ margins: UIEdgeInsets) -> SKDialog {
        config.margins = margins
        return self
    }
    
    /// 设置背景色
    @discardableResult
    public func backgroundColor(_ color: UIColor) -> SKDialog {
        config.containerBackgroundColor = color
        return self
    }
    
    /// 设置圆角
    @discardableResult
    public func cornerRadius(_ radius: CGFloat) -> SKDialog {
        config.cornerRadius = radius
        return self
    }
    
    /// 设置动画类型
    @discardableResult
    public func animation(_ type: SKDialogAnimationType) -> SKDialog {
        config.animationType = type
        return self
    }
    
    /// 设置点击背景是否消失
    @discardableResult
    public func dismissOnBackgroundTap(_ dismiss: Bool = true) -> SKDialog {
        config.dismissOnBackgroundTap = dismiss
        return self
    }
    
    /// 设置是否支持拖拽消失
    @discardableResult
    public func enablePanGestureDismiss(_ enable: Bool = true) -> SKDialog {
        config.enablePanGestureDismiss = enable
        return self
    }
    
    /// 设置Window层级（仅在window模式下有效）
    @discardableResult
    public func windowLevel(_ level: UIWindow.Level) -> SKDialog {
        config.windowLevel = level
        return self
    }
    
    /// 设置弹窗大小
    @discardableResult
    public func size(width: CGFloat? = nil, height: CGFloat? = nil) -> SKDialog {
        config.sizeMode = .fixed(width: width, height: height)
        return self
    }
    
    /// 设置为内容自适应
    @discardableResult
    public func contentAdaptive() -> SKDialog {
        config.sizeMode = .contentAdaptive
        return self
    }
    
    /// 设置固定宽度
    @discardableResult
    public func fixedWidth(_ width: CGFloat) -> SKDialog {
        config.sizeMode = .widthFixed(width)
        return self
    }
    
    /// 设置固定高度
    @discardableResult
    public func fixedHeight(_ height: CGFloat) -> SKDialog {
        config.sizeMode = .heightFixed(height)
        return self
    }
    
    /// 设置遮罩颜色
    @discardableResult
    public func maskColor(_ color: UIColor) -> SKDialog {
        config.backgroundMaskColor = color
        return self
    }
    
    /// 设置阴影
    @discardableResult
    public func shadow(
        show: Bool = true,
        color: UIColor = .black,
        offset: CGSize = CGSize(width: 0, height: 2),
        radius: CGFloat = 8,
        opacity: Float = 0.15
    ) -> SKDialog {
        config.showShadow = show
        config.shadowColor = color
        config.shadowOffset = offset
        config.shadowRadius = radius
        config.shadowOpacity = opacity
        return self
    }
    
    /// 设置动画（带参数）
    @discardableResult
    public func animation(
        _ type: SKDialogAnimationType,
        duration: TimeInterval = 0.3,
        damping: CGFloat = 0.8,
        velocity: CGFloat = 0.5
    ) -> SKDialog {
        config.animationType = type
        config.animationDuration = duration
        config.springDamping = damping
        config.springVelocity = velocity
        return self
    }
    
    /// 设置是否延伸到安全区域（仅对底部和顶部弹窗有效）
    @discardableResult
    public func extendToSafeArea(_ extend: Bool) -> SKDialog {
        config.extendToSafeArea = extend
        return self
    }
    
    /// 设置动画显示开始回调
    @discardableResult
    public func onPresentAnimationWillStart(_ handler: @escaping () -> Void) -> SKDialog {
        self.presentAnimationWillStartHandler = handler
        return self
    }
    
    /// 设置动画显示完成回调
    @discardableResult
    public func onPresentAnimationDidFinish(_ handler: @escaping () -> Void) -> SKDialog {
        self.presentAnimationDidFinishHandler = handler
        return self
    }
    
    /// 设置动画消失开始回调
    @discardableResult
    public func onDismissAnimationWillStart(_ handler: @escaping () -> Void) -> SKDialog {
        self.dismissAnimationWillStartHandler = handler
        return self
    }
    
    /// 设置动画消失完成回调
    @discardableResult
    public func onDismissAnimationDidFinish(_ handler: @escaping () -> Void) -> SKDialog {
        self.dismissAnimationDidFinishHandler = handler
        return self
    }
    
    /// 设置内容视图
    @discardableResult
    public func contentView(_ view: UIView) -> SKDialog {
        self.contentView = view
        return self
    }
}

// MARK: - Show Methods

extension SKDialog {
    
    /// 显示弹窗（根据配置自动选择显示方式）
    @discardableResult
    public func show() -> SKDialogViewController {
        let dialog = SKDialogViewController(config: config)
        
        if let contentView = contentView {
            dialog.addContentView(contentView)
        }
        
        // 设置动画回调
        dialog.presentAnimationWillStartHandler = presentAnimationWillStartHandler
        dialog.presentAnimationDidFinishHandler = presentAnimationDidFinishHandler
        dialog.dismissAnimationWillStartHandler = dismissAnimationWillStartHandler
        dialog.dismissAnimationDidFinishHandler = dismissAnimationDidFinishHandler
        
        switch config.presentationMode {
        case .window:
            dialog.showInWindow()
        case .viewController(let viewController):
            viewController.present(dialog, animated: false)
        }
        
        return dialog
    }
}

// MARK: - Preset Configuration Builders

extension SKDialog {
    
    /// 创建底部弹窗
    public static func bottom() -> SKDialog {
        return SKDialog()
            .position(.bottom)
            .animation(.slideFromBottom)
            .margins(UIEdgeInsets.zero)
            .contentAdaptive()
            .enablePanGestureDismiss()
            .extendToSafeArea(true)
    }
    
    /// 创建居中弹窗
    public static func center() -> SKDialog {
        return SKDialog()
            .position(.center)
            .animation(.fadeScale)
            .margins(UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40))
            .cornerRadius(12)
    }
    
    /// 创建顶部弹窗
    public static func top() -> SKDialog {
        return SKDialog()
            .position(.top)
            .animation(.slideFromTop)
            .margins(UIEdgeInsets.zero)
            .cornerRadius(16)
            .enablePanGestureDismiss()
    }
}

// MARK: - Quick Creation Methods

extension SKDialog {
    
    /// 快速创建并显示底部弹窗
    @discardableResult
    public static func showBottom(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.bottom()
            .contentView(contentView)
            .show()
    }
    
    /// 快速创建并显示居中弹窗
    @discardableResult
    public static func showCenter(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.center()
            .contentView(contentView)
            .show()
    }
    
    /// 快速创建并显示顶部弹窗
    @discardableResult
    public static func showTop(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.top()
            .contentView(contentView)
            .show()
    }
}
