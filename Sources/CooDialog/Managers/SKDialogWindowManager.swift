//
//  SKDialogWindowManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的Window模式管理器：负责自建 UIWindow 的创建、配置、上屏与回收。
 *
 * 类型功能描述：
 * - Window创建：创建并配置自定义Window（层级、透明背景、跟随场景尺寸）
 * - 宿主提供：为弹窗准备一个可被 present 的宿主控制器
 * - Window管理：上屏与回收，以及 key window 的保存与归还
 *
 * 设计原理（为什么用独立 window 而不是把视图 addSubview 到某个控制器上）：
 * 1. 层级最高：UIWindow 位于所有视图控制器之上，弹窗不会被导航栏、TabBar 或已 present
 *    的其它控制器遮挡，也不需要宿主提供"合适的"目标控制器
 * 2. 时机自由：启动早期、网络回调、后台回到前台的瞬间都能展示，不依赖任何 VC 的可见性
 * 代价是 window 的 key 状态与生命周期都得自己管——这正是本类存在的理由
 *
 * 与展示流程的边界（本类不管动画，也不管弹窗的呈现关系）：
 * 弹窗由 window 里的宿主控制器 present（见 makeHostForPresentation()），
 * present / dismiss 与入场退场动画全部归 SKDialogViewController 编排。
 * 本类只负责两件事：**准备一个落在最上层的宿主**、**用完把它收干净**。
 * 这样 `.window` 与 `.viewController` 两种模式共享同一条展示链路，
 * 差异只剩"那个宿主是谁"——不再需要各自一套上屏与收尾。
 *
 * 引用关系（这条环必须在关闭时显式打破）：
 * 控制器 →(强) windowManager →(强) customWindow →(强) rootViewController(宿主)
 *        →(强) presentedViewController(控制器)
 * 本类刻意**不**反向持有控制器：它需要的唯一配置（窗口层级）由调用方按参数传入，
 * 因此这里没有弱引用、也不需要自定义 init——环只经由 window 这一条路成立。
 * 打断顺序固定为：控制器先 dismiss 自己（摘掉 present 关系）→ 本类再清 rootViewController、
 * 释放 customWindow。因此**必须保证关闭流程会走到 removeCustomWindow()**：
 * 控制器的 dismissDialog() 在 window 模式下会调用它；若绕过关闭流程直接丢弃控制器，
 * 环不会被打破，window 与控制器都将泄漏。
 */

import UIKit

/// SKDialog Window模式管理器
/// 负责处理弹窗的Window模式显示逻辑，包括自定义Window的创建、显示、隐藏等功能
@MainActor
class SKDialogWindowManager {

    // MARK: - Properties

    /// 自定义Window实例（强引用：由本类负责它的存活与释放）
    private var customWindow: UIWindow?

    /// 自建 window 的根控制器，也就是"由谁来 present 弹窗"。
    /// 它同时是本类唯一的展示状态：非 nil ⟺ 自建 window 已上屏、随时可以承载弹窗。
    /// 之所以不把弹窗直接设成 rootViewController：那样 window 模式会变成另一套展示机制，
    /// 与 `.viewController` 模式的入场时序、关闭收尾都要各写一遍（见文件头说明）。
    private(set) var hostViewController: UIViewController?

    /// 原始的key window（用于恢复）
    /// 用 weak：它只是"记住是谁，稍后还给它"，不需要也不应该延长原 window 的生命周期。
    private weak var originalKeyWindow: UIWindow?

    // MARK: - Public Methods

    /// 准备一个承载弹窗的自建 window，并返回其中的宿主控制器。
    ///
    /// 执行顺序很重要：
    /// 1. 幂等检查（已经建过则复用同一个宿主，重复 show 不会建出第二个 window）
    /// 2. 创建并配置 window；没有可用场景时返回 nil，且不留下任何状态
    /// 3. **先**记录当前 key window，再把自己变成 key（顺序反了就只会记到自己）
    /// 4. 设置 rootViewController —— 这一步会触发宿主的 viewDidLoad
    /// 5. makeKeyAndVisible 上屏，并把宿主记为"已就位"
    ///
    /// - Parameter windowLevel: 自建 window 的层级（由调用方按配置传入；
    ///   本类不读取配置，也不认识弹窗控制器，只负责把 window 摆到指定层级）
    /// - Returns: 承载弹窗的宿主控制器；`nil` 表示当前没有可用的 UIWindowScene。
    func makeHostForPresentation(windowLevel: UIWindow.Level) -> UIViewController? {
        // 幂等：window 已在，直接复用它的宿主
        if let host = hostViewController {
            return host
        }

        guard createCustomWindow(windowLevel: windowLevel), let window = customWindow else {
            return nil
        }

        // 保存当前的key window（须在 makeKeyAndVisible 之前保存，否则保存的是自己）
        originalKeyWindow = currentKeyWindow()

        // 宿主只提供"被 present 的落点"：它自己不画任何东西，
        // 视觉全部来自弹窗（半透明遮罩 + 容器），因此背景必须是透明的
        let host = UIViewController()
        host.view.backgroundColor = .clear
        window.rootViewController = host

        // 显示Window
        window.makeKeyAndVisible()
        hostViewController = host

        return host
    }

    /// 回收自建 window，并把 key 状态归还给原来的 window。
    ///
    /// 调用时机：`.window` 模式的关闭收尾。此时弹窗已由控制器自己 `dismiss` 掉，
    /// 这里只负责 window 本身。
    ///
    /// 清理顺序的原因：先 isHidden + 清空 rootViewController，断开
    /// "window → 宿主 → 弹窗"这段强引用；再把 key 状态还给原 window（顺序颠倒的话，
    /// 中间会出现短暂的"无 key window"状态）；最后清空自身引用与状态。
    func removeCustomWindow() {

        // 未建过直接返回：调用方不需要判断当前是不是 window 模式
        guard hostViewController != nil else { return }

        // 先记下所属场景：key 的恢复需要它，而下面的清理会把 customWindow 置空
        let scene = customWindow?.windowScene ?? activeWindowScene

        // 拆除 window 的整棵视图树（连同宿主与它呈现的弹窗）
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil

        // 恢复原始的key window（取不到原窗口时退化为同场景的其它窗口，见 restoreKeyWindow）
        restoreKeyWindow(in: scene)

        // 清理Window引用（打破 控制器 → 管理器 → window → 宿主 → 弹窗 的环）
        customWindow = nil
        hostViewController = nil
        originalKeyWindow = nil
    }
}

// MARK: - Private

extension SKDialogWindowManager {

    /// 创建自定义Window
    /// - Parameter windowLevel: 自建 window 的层级
    /// - Returns: 是否创建成功；无可用 window scene 时返回 false。
    @discardableResult
    private func createCustomWindow(windowLevel: UIWindow.Level) -> Bool {
        guard let windowScene = activeWindowScene else { return false }

        // 用 windowScene 初始化而不是 UIWindow(frame:)：iOS 13 起是多场景模型，
        // 未绑定 scene 的 window 拿不到正确的场景上下文（尺寸、层级、旋转行为都会异常）
        customWindow = UIWindow(windowScene: windowScene)

        // 配置Window属性
        configureWindow(windowLevel: windowLevel)
        return true
    }

    /// 配置Window属性
    private func configureWindow(windowLevel: UIWindow.Level) {
        guard let window = customWindow else { return }

        // 设置Window层级，确保弹窗在所有内容之上
        // 取值由调用方按 config.windowLevel 传入，构造时已给默认值 `.alert + 1`：
        // 既高于普通 window，也高于系统 alert 层
        window.windowLevel = windowLevel

        // 设置背景色为透明
        // window 自身不画任何东西，视觉全部来自弹窗的 view（半透明遮罩 + 容器）；
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

    /// 把 key 状态还给原窗口；原窗口已不可用时退化为同场景的其它可见窗口。
    ///
    /// 为什么需要兜底：`originalKeyWindow` 是 weak（它只负责"记住是谁、稍后还给它"，
    /// 不应延长原窗口的生命周期），而弹窗展示期间原窗口可能已被系统回收、或被宿主隐藏。
    /// 此时若只做 `originalKeyWindow?.makeKeyAndVisible()`，场景里会没有任何 key window——
    /// 键盘弹出、输入框聚焦、状态栏等依赖 key window 的行为会一起异常。
    /// - Parameter scene: 自建 window 所属的场景（removeCustomWindow 在清理前记下的）
    private func restoreKeyWindow(in scene: UIWindowScene?) {
        if let originalKeyWindow = originalKeyWindow, !originalKeyWindow.isHidden {
            originalKeyWindow.makeKeyAndVisible()
            return
        }

        // 兜底：同场景里任取一个可见窗口（排除即将失效的自建 window 自己）
        scene?.windows
            .first { $0 !== customWindow && !$0.isHidden }?
            .makeKeyAndVisible()
    }
}

// MARK: - Debug & Testing

/// 调试 / 测试用的状态查询与强制清理入口，不参与生产路径。
extension SKDialogWindowManager {

    /// 自建 window 当前是否已就位（即"本管理器认为弹窗可以显示"）
    var isVisible: Bool {
        return hostViewController != nil
    }

    /// 当前持有的自定义 Window
    var window: UIWindow? {
        return customWindow
    }

    /// 强制清理：不做 key window 恢复，也不校验当前状态。
    /// 用于异常路径的兜底释放（例如控制器已被销毁、window 状态不明确时），
    /// 目的只是消除残留引用，避免泄漏。
    func forceCleanup() {
        customWindow?.isHidden = true
        customWindow?.rootViewController = nil
        customWindow = nil
        hostViewController = nil
        originalKeyWindow = nil
    }

}
