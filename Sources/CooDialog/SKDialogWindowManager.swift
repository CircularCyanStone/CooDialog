//
//  SKDialogWindowManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的Window模式管理器，专门负责处理弹窗在独立Window中的显示和管理。
 * 该管理器将Window模式相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - Window创建：创建和配置自定义Window用于弹窗显示
 * - Window管理：管理Window的显示、隐藏和生命周期
 * - 层级管理：处理Window的层级关系，确保弹窗在最顶层显示
 * - 状态跟踪：跟踪Window的显示状态和相关属性
 * - 内存管理：确保Window的正确释放，避免内存泄漏
 */

import UIKit

/// SKDialog Window模式管理器
/// 负责处理弹窗的Window模式显示逻辑，包括自定义Window的创建、显示、隐藏等功能
@MainActor
class SKDialogWindowManager {
    
    // MARK: - Properties
    
    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?
    
    /// 自定义Window实例
    private var customWindow: UIWindow?
    
    /// Window是否当前可见
    private var isWindowVisible: Bool = false
    
    /// 原始的key window（用于恢复）
    private weak var originalKeyWindow: UIWindow?
    
    // MARK: - Initialization
    
    /// 初始化Window管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }
    
    // MARK: - Public Methods
    
    /// 在自定义Window中显示弹窗
    /// - Parameter completion: 显示完成回调
    func showInWindow(completion: (() -> Void)? = nil) {
        guard let viewController = viewController else {
            completion?()
            return
        }
        
        // 如果已经在Window中显示，直接返回
        if isWindowVisible {
            completion?()
            return
        }
        
        // 保存当前的key window
        if #available(iOS 15.0, *) {
            originalKeyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow
        } else {
            originalKeyWindow = UIApplication.shared.keyWindow
        }
        
        // 创建自定义Window
        createCustomWindow()
        
        // 设置Window的根控制器
        customWindow?.rootViewController = viewController
        
        // 显示Window
        customWindow?.makeKeyAndVisible()
        isWindowVisible = true
        
        // 调用完成回调
        completion?()
    }
    
    /// 隐藏自定义Window
    /// - Parameter completion: 隐藏完成回调
    func hideCustomWindow(completion: (() -> Void)? = nil) {
    

        guard isWindowVisible else {
            completion?()
            return
        }
        
        // 隐藏Window
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil
        
        // 恢复原始的key window
        originalKeyWindow?.makeKeyAndVisible()
        
        // 清理Window引用
        customWindow = nil
        isWindowVisible = false
        originalKeyWindow = nil
        
        // 调用完成回调
        completion?()
    }
    

    
    // MARK: - Private Methods
    
    /// 创建自定义Window
    private func createCustomWindow() {
        // iOS 15+ 使用scene-based window
        if let windowScene = getAppropriateWindowScene() {
            customWindow = UIWindow(windowScene: windowScene)
        }
        
        // 配置Window属性
        configureWindow()
    }
    
    /// 配置Window属性
    private func configureWindow() {
        guard let window = customWindow else { return }
        
        // 设置Window层级为最高层级，确保弹窗在所有内容之上
        window.windowLevel = UIWindow.Level.alert + 1
        
        // 设置背景色为透明
        window.backgroundColor = UIColor.clear
        
        // 设置Window frame
        window.frame = UIScreen.main.bounds
        
        // 确保Window不会自动调整大小
        window.autoresizingMask = []
    }
    

    
    /// 获取合适的Window Scene
    private func getAppropriateWindowScene() -> UIWindowScene? {
        // 优先获取当前活跃的window scene
        if let activeScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            return activeScene
        }
        
        // 如果没有活跃的，获取第一个可用的
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
    }
    

}

// MARK: - Internal Access

extension SKDialogWindowManager {
    
    /// 获取当前Window是否可见
    var isVisible: Bool {
        return isWindowVisible
    }
    
    /// 获取自定义Window实例
    var window: UIWindow? {
        return customWindow
    }
    

    
    /// 强制清理Window
    func forceCleanup() {
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil
        customWindow = nil
        isWindowVisible = false
        originalKeyWindow = nil
    }
    

}
