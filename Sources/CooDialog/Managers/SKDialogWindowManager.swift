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
 *
 * 设计原理（为什么用独立 window 而不是把视图 addSubview 到某个控制器上）：
 * 1. 层级最高：UIWindow 位于所有视图控制器之上，弹窗不会被导航栏、TabBar 或已 present
 *    的其它控制器遮挡，也不需要宿主提供"合适的"目标控制器
 * 2. 时机自由：启动早期、网络回调、后台回到前台的瞬间都能展示，不依赖任何 VC 的可见性
 * 代价是 window 的 key 状态与生命周期都得自己管——这正是本类存在的理由
 *
 * 引用关系（其中一环需要在关闭时显式打破）：
 * 控制器 →(强) windowManager →(强) customWindow →(强) rootViewController = 控制器
 * 这个环由 hideCustomWindow() 打破（先清 rootViewController，再释放 customWindow）。
 * 因此**必须保证关闭流程会走到 hideCustomWindow()**：控制器的 dismissDialog() 在 window
 * 模式下会调用它；若绕过关闭流程直接丢弃控制器，环不会被打破，window 与控制器都将泄漏。
 */

import UIKit

/// SKDialog Window模式管理器
/// 负责处理弹窗的Window模式显示逻辑，包括自定义Window的创建、显示、隐藏等功能
@MainActor
class SKDialogWindowManager {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?

    /// 自定义Window实例（强引用：由本类负责它的存活与释放）
    private var customWindow: UIWindow?

    /// Window是否当前可见。
    /// 用独立布尔状态而不是"customWindow 是否非空"来判断：创建成功与显示成功是两件事，
    /// 且本类以"是否可见"作为幂等依据（重复 show 直接返回、未显示时的 hide 直接返回）。
    private var isWindowVisible: Bool = false

    /// 原始的key window（用于恢复）
    /// 用 weak：它只是"记住是谁，稍后还给它"，不需要也不应该延长原 window 的生命周期。
    private weak var originalKeyWindow: UIWindow?

    // MARK: - Initialization

    /// 初始化Window管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods

    /// 在自定义Window中显示弹窗。
    ///
    /// 执行顺序很重要：
    /// 1. 幂等检查（已在显示则直接返回）
    /// 2. 创建并配置 window，失败则返回且不改状态
    /// 3. **先**记录当前 key window，再把自己变成 key（顺序反了就只会记到自己）
    /// 4. 设置 rootViewController —— 这一步会触发控制器的 viewDidLoad，
    ///    从而搭建 backgroundView / containerView / 约束 / 手势
    /// 5. makeKeyAndVisible 上屏，并把状态置为可见
    /// - Parameter completion: 显示完成回调
    func showInWindow(completion: (() -> Void)? = nil) {
        guard let viewController = viewController else {
            completion?()
            return
        }

        // 如果已经在Window中显示，直接返回
        // 幂等：重复调用不会创建第二个 window，也不会重复挂载控制器
        if isWindowVisible {
            completion?()
            return
        }

        // 创建自定义Window；失败时直接返回，不置位 isWindowVisible，
        // 避免出现「状态为已显示但实际没有 Window」的错乱。
        // 失败的具体情形：应用没有任何可用的 UIWindowScene（例如场景尚未连接完成）。
        guard createCustomWindow(), let window = customWindow else {
            completion?()
            return
        }

        // 保存当前的key window（须在 makeKeyAndVisible 之前保存，否则保存的是自己）
        originalKeyWindow = currentKeyWindow()

        // 设置Window的根控制器
        window.rootViewController = viewController

        // 显示Window
        window.makeKeyAndVisible()
        isWindowVisible = true

        // 调用完成回调
        completion?()
    }

    /// 隐藏自定义Window，并把 key 状态归还给原来的 window。
    ///
    /// 清理顺序的原因：先 isHidden + 清空 rootViewController，断开
    /// "window ↔ 控制器"这段强引用；再把 key 状态还给原 window（顺序颠倒的话，
    /// 中间会出现短暂的"无 key window"状态）；最后清空自身引用与可见标记。
    ///
    /// - Parameter completion: 隐藏完成回调
    func hideCustomWindow(completion: (() -> Void)? = nil) {

        // 未显示时直接回调：保持"调用必回调"的约定，简化调用方的流程判断
        guard isWindowVisible else {
            completion?()
            return
        }

        // 隐藏Window
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil

        // 恢复原始的key window
        // 用可选链：原 window 可能已被系统回收（weak），此时不恢复也不影响正确性
        originalKeyWindow?.makeKeyAndVisible()

        // 清理Window引用（打破 控制器 → 管理器 → window → 控制器 的环）
        customWindow = nil
        isWindowVisible = false
        originalKeyWindow = nil

        // 调用完成回调
        completion?()
    }
}

// MARK: - Private

extension SKDialogWindowManager {

    /// 创建自定义Window
    /// - Returns: 是否创建成功；无可用 window scene 时返回 false。
    @discardableResult
    private func createCustomWindow() -> Bool {
        guard let windowScene = activeWindowScene else { return false }

        // 用 windowScene 初始化而不是 UIWindow(frame:)：iOS 13 起是多场景模型，
        // 未绑定 scene 的 window 拿不到正确的场景上下文（尺寸、层级、旋转行为都会异常）
        customWindow = UIWindow(windowScene: windowScene)

        // 配置Window属性
        configureWindow()
        return true
    }

    /// 配置Window属性
    private func configureWindow() {
        guard let window = customWindow else { return }

        // 设置Window层级，确保弹窗在所有内容之上
        // 取值来自 config.windowLevel，默认 `.alert + 1`：既高于普通 window，也高于系统 alert 层。
        // 取不到控制器时（理论上不会发生）退回同一个默认值，避免层级意外下降。
        window.windowLevel = viewController?.config.windowLevel ?? (UIWindow.Level.alert + 1)

        // 设置背景色为透明
        // window 自身不画任何东西，视觉全部来自控制器的 view（半透明遮罩 + 容器）；
        // 若用不透明色，会把下层界面整个挡住
        window.backgroundColor = UIColor.clear

        // 尺寸跟随所属 windowScene，而非全局的 UIScreen.main
        // （后者在 iPad 分屏 / 多窗口场景下会取到错误尺寸）。
        if let scene = window.windowScene {
            window.frame = scene.coordinateSpace.bounds
        }

        // 确保Window不会自动调整大小
        // 清空 autoresizingMask：避免父级尺寸变化时系统按 autoresizing 规则拉伸 window，
        // window 的尺寸应完全由所属 scene 决定
        window.autoresizingMask = []
    }

    /// 当前活跃的 window scene（优先 foregroundActive，其次首个可用的）
    /// - Note: 优先取前台活跃场景，是为了在分屏 / 多窗口下把弹窗放到用户正在操作的那个场景；
    ///   没有前台场景时退化为任意可用场景，保证"能显示"优先于"显示在正确场景"。
    private var activeWindowScene: UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
    }

    /// 当前活跃场景的 key window
    /// - Note: 不使用已弃用的 `UIApplication.keyWindow`，也不使用 iOS 15+ 才有的
    ///   `UIWindowScene.keyWindow`。`scene.windows` 与 `UIWindow.isKeyWindow` 均自
    ///   iOS 13 起可用，因此无需版本分支。
    private func currentKeyWindow() -> UIWindow? {
        // 按 isKeyWindow 筛选而不是取 windows.first：同一场景可能同时存在多个 window
        // （键盘 window、状态栏 window 等），只有 key 的那个才是需要恢复的目标
        return activeWindowScene?.windows.first { $0.isKeyWindow }
    }
}

// MARK: - Debug & Testing

/// 调试 / 测试用的状态查询与强制清理入口，不参与生产路径。
extension SKDialogWindowManager {

    /// Window 当前是否可见（即"本管理器认为弹窗正在显示"）
    var isVisible: Bool {
        return isWindowVisible
    }

    /// 当前持有的自定义 Window
    var window: UIWindow? {
        return customWindow
    }

    /// 强制清理：不做 key window 恢复，也不校验可见状态。
    /// 用于异常路径的兜底释放（例如控制器已被销毁、window 状态不明确时），
    /// 目的只是消除残留引用，避免泄漏。
    func forceCleanup() {
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil
        customWindow = nil
        isWindowVisible = false
        originalKeyWindow = nil
    }

}
