//
//  SKDialogConfig.swift
//  TAIChat
//
//  Created by Assistant on 2024
//

import Foundation
import UIKit

/// 弹窗位置枚举
public enum SKDialogPosition {
    case center     // 居中显示
    case bottom     // 底部显示
    case top        // 顶部显示
}

/// 弹窗动画类型枚举
public enum SKDialogAnimationType: Equatable {
    case slideFromBottom    // 从底部滑入
    case fadeScale          // 渐变缩放
    case slideFromTop       // 从顶部滑入
    case slideFromLeft      // 从左侧滑入
    case slideFromRight     // 从右侧滑入
    case slideFromBottomWithFade    // 从底部滑入带渐变
    case slideFromTopWithFade       // 从顶部滑入带渐变
    case slideFromLeftWithFade      // 从左侧滑入带渐变
    case slideFromRightWithFade     // 从右侧滑入带渐变
    case custom(SKDialogAnimationProtocol)  // 自定义动画
    
    // 实现Equatable协议
    public static func == (lhs: SKDialogAnimationType, rhs: SKDialogAnimationType) -> Bool {
        switch (lhs, rhs) {
        case (.slideFromBottom, .slideFromBottom),
             (.fadeScale, .fadeScale),
             (.slideFromTop, .slideFromTop),
             (.slideFromLeft, .slideFromLeft),
             (.slideFromRight, .slideFromRight),
             (.slideFromBottomWithFade, .slideFromBottomWithFade),
             (.slideFromTopWithFade, .slideFromTopWithFade),
             (.slideFromLeftWithFade, .slideFromLeftWithFade),
             (.slideFromRightWithFade, .slideFromRightWithFade):
            return true
        case (.custom(_), .custom(_)):
            // 对于自定义动画，由于协议类型无法直接比较，返回false
            // 如果需要比较自定义动画，建议在协议中添加标识符属性
            return false
        default:
            return false
        }
    }
}

/// 弹窗显示模式枚举
public enum SKDialogPresentationMode {
    case viewController(UIViewController)  // 使用指定的ViewController进行模态显示
    case window                           // 使用自定义UIWindow显示
}

/// 弹窗尺寸模式枚举
public enum SKDialogSizeMode {
    case fixed(width: CGFloat?, height: CGFloat?)  // 固定尺寸
    case contentAdaptive                           // 根据内容自适应尺寸
    case widthFixed(CGFloat)                      // 固定宽度，高度自适应
    case heightFixed(CGFloat)                     // 固定高度，宽度自适应
}



/// 弹窗配置类
public class SKDialogConfig {
    
    // MARK: - 显示模式配置
    
    /// 弹窗显示模式（默认使用window模式）
    public var presentationMode: SKDialogPresentationMode = .window
    
    /// 自定义Window的层级（仅在window模式下有效）
    public var windowLevel: UIWindow.Level = UIWindow.Level.alert
    
    // MARK: - 位置和大小配置
    
    /// 弹窗位置
    public var position: SKDialogPosition = .center
    
    /// 弹窗尺寸模式（统一管理宽度和高度设置，避免参数冲突）
    public var sizeMode: SKDialogSizeMode = .contentAdaptive
    
    /// 边距
    public var margins = UIEdgeInsets.zero
    

    
    // MARK: - 外观配置
    
    /// 容器背景色
    public var containerBackgroundColor: UIColor = .systemBackground
    
    /// 圆角半径
    public var cornerRadius: CGFloat = 12
    
    /// 背景遮罩颜色
    public var backgroundMaskColor: UIColor = UIColor.black.withAlphaComponent(0.5)
    
    // MARK: - 阴影配置
    
    /// 是否显示阴影
    public var showShadow: Bool = true
    
    /// 阴影颜色
    public var shadowColor: UIColor = .black
    
    /// 阴影偏移
    public var shadowOffset: CGSize = CGSize(width: 0, height: 2)
    
    /// 阴影半径
    public var shadowRadius: CGFloat = 8
    
    /// 阴影透明度
    public var shadowOpacity: Float = 0.15
    
    // MARK: - 交互配置
    
    /// 点击背景是否消失
    public var dismissOnBackgroundTap: Bool = true
    
    /// 是否支持手势拖拽消失（仅对底部和顶部弹窗有效）
    public var enablePanGestureDismiss: Bool = true
    
    // MARK: - 安全区域配置
    
    /// 是否延伸到安全区域（仅对底部和顶部弹窗有效）
    public var extendToSafeArea: Bool = true
    
    // MARK: - 动画配置
    
    /// 动画类型
    public var animationType: SKDialogAnimationType = .fadeScale
    
    /// 动画持续时间
    public var animationDuration: TimeInterval = 0.3
    
    /// 弹簧动画阻尼
    public var springDamping: CGFloat = 0.8
    
    /// 弹簧动画初始速度
    public var springVelocity: CGFloat = 0.5
    
    /// 渐变缩放动画的初始缩放比例（0.0-1.0，0.0表示完全不可见，0.8表示80%大小）
    public var fadeScaleInitialScale: CGFloat = 0.8
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - 便利构造方法
    
    /// 创建底部弹窗配置
    /// - Parameters:
    ///   - height: 弹窗高度，nil表示根据内容自适应
    ///   - cornerRadius: 圆角半径
    ///   - margins: 边距设置
    ///   - presentationMode: 显示模式
    /// - Returns: 配置好的SKDialogConfig实例
    public static func bottomSheet(
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 16,
        margins: UIEdgeInsets = UIEdgeInsets.zero,
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        let config = SKDialogConfig()
        config.position = .bottom
        config.sizeMode = height != nil ? .heightFixed(height!) : .contentAdaptive
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .slideFromBottom
        config.presentationMode = presentationMode
        return config
    }
    
    /// 创建居中弹窗配置
    /// - Parameters:
    ///   - width: 弹窗宽度，nil表示根据内容自适应
    ///   - height: 弹窗高度，nil表示根据内容自适应
    ///   - cornerRadius: 圆角半径
    ///   - margins: 边距设置
    ///   - presentationMode: 显示模式
    /// - Returns: 配置好的SKDialogConfig实例
    public static func centerDialog(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 12,
        margins: UIEdgeInsets = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        let config = SKDialogConfig()
        config.position = .center
        config.sizeMode = .fixed(width: width, height: height)
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .fadeScale
        config.presentationMode = presentationMode
        return config
    }
    
    /// 创建顶部弹窗配置
    /// - Parameters:
    ///   - height: 弹窗高度，nil表示根据内容自适应
    ///   - cornerRadius: 圆角半径
    ///   - margins: 边距设置
    ///   - presentationMode: 显示模式
    /// - Returns: 配置好的SKDialogConfig实例
    public static func topSheet(
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 16,
        margins: UIEdgeInsets = UIEdgeInsets.zero,
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        let config = SKDialogConfig()
        config.position = .top
        config.sizeMode = height != nil ? .heightFixed(height!) : .contentAdaptive
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .slideFromTop
        config.presentationMode = presentationMode
        return config
    }
}
