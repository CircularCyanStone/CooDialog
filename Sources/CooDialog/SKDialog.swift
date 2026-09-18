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
 * 类型功能描述：
 * - SKDialog：主要的弹窗构建器类，提供链式配置API
 * - 静态便利方法：提供快速创建常用弹窗的方法
 * - 扩展方法：提供预设配置的构建器
 *
 * 设计原理（为什么用构建器而不是让宿主直接配置控制器）：
 * 1. 意图集中：位置、尺寸、动画、交互等参数往往需要在不同分支里分别决定，
 *    链式 API 让这些决定可以写成一条表达式，读代码时一眼看清"这个弹窗长什么样"
 * 2. 延迟展示：配置阶段不创建任何视图，真正落地发生在 `show()`——
 *    因此可以先构造再决定展示方式，也可以把它当参数在方法间传递
 * 3. 分层清晰：本类只负责收集意图（写入 SKDialogConfig），
 *    执行全部交给 SKDialogViewController 及其管理器，两者互不越界
 *
 * 三个类型的关系与生命周期：
 * `SKDialog`（意图收集）→ 持有 `SKDialogConfig`（参数）→ `show()` 创建 `SKDialogViewController`（执行）
 * 注意 config 是引用类型：同一个构建器实例被展示两次时，两个弹窗共享同一份配置，
 * 后续对构建器的修改会同时影响已存在的两个弹窗。需要多个独立弹窗时应各自新建构建器。
 */

import UIKit

/// 弹窗便捷入口类 - 提供链式配置API和快速创建方法
/// 全部 API 在主 actor 上；每个配置方法都返回 self（并用 @discardableResult 允许忽略返回值），
/// 因此既可以 `dialog.position(.bottom).show()` 连写，也可以逐行配置。
@MainActor
public class SKDialog {

    // MARK: - Properties

    /// 配置累积器：所有链式方法最终都写进这里，`show()` 时整体交给控制器。
    /// 只在构建器内部使用，宿主看到的是各个语义化的配置方法。
    private var config = SKDialogConfig()

    /// 待装载的内容视图。
    /// 延迟到 `show()` 才加入容器：此时控制器与容器已存在，能立刻建立四边贴合约束；
    /// 若提前持有，则无法确定容器实例，还得额外维护"稍后补装"的状态。
    private var contentView: UIView?

    // 动画回调（四个时机各一个）。
    // 之所以先存在构建器上、到 show() 再转移给控制器：配置阶段控制器还不存在，
    // 而链式调用期望这些方法和其它配置方法一样"即调即生效"，故先寄存。

    /// 入场动画开始前触发（业务上常用于准备数据、埋点起点）
    private var presentAnimationWillStartHandler: (() -> Void)?

    /// 入场动画结束时触发（此时容器已就位，适合自动聚焦输入框、启动计时）
    private var presentAnimationDidFinishHandler: (() -> Void)?

    /// 退场动画开始前触发（适合打断轮询、保存草稿）
    private var dismissAnimationWillStartHandler: (() -> Void)?

    /// 退场动画结束时触发（此时视图尚未从层级中移除，仍可读取尺寸）
    private var dismissAnimationDidFinishHandler: (() -> Void)?

    // MARK: - Initialization

    /// 无参初始化，得到一份默认配置（居中 / 内容自适应 / window 载体 / fadeScale 动画）。
    /// 需要特定形态时优先用下方静态工厂（`bottom()` / `center()` / `top()`）。
    public init() {}

    // MARK: - Core Configuration Methods

    /// 设置弹窗位置（等价于写 config.position）。
    /// 影响面较广：约束锚点、拖拽方向、滑动动画的进出方向都由它决定，
    /// 因此建议在链式调用的前段设置，避免与后续的尺寸/动画方法语义互相打架。
    @discardableResult
    public func position(_ position: SKDialogPosition) -> SKDialog {
        config.position = position
        return self
    }

    /// 设置显示模式（等价于写 config.presentationMode）。
    /// - Note: 传 `.viewController(self)` 时配置会强引用该控制器（见 SKDialogPresentationMode 的内存提示）。
    @discardableResult
    public func presentationMode(_ mode: SKDialogPresentationMode) -> SKDialog {
        config.presentationMode = mode
        return self
    }

    /// 设置尺寸模式（等价于写 config.sizeMode）。
    /// - Important: 与 `size(width:height:)` / `contentAdaptive()` / `fixedWidth(_:)` /
    ///   `fixedHeight(_:)` 是同一份数据的不同入口，**后调用的会覆盖先调用的**
    ///   （它们都直接改写 sizeMode，而不是叠加）。
    @discardableResult
    public func sizeMode(_ mode: SKDialogSizeMode) -> SKDialog {
        config.sizeMode = mode
        return self
    }

    /// 设置边距（等价于写 config.margins）。
    /// 语义随位置而异：底部/顶部弹窗用 top/bottom 控制贴边留白、left/right 作为最小横向留白；
    /// 居中弹窗只用 left/right 限制最大宽度。
    @discardableResult
    public func margins(_ margins: UIEdgeInsets) -> SKDialog {
        config.margins = margins
        return self
    }

    /// 设置容器背景色。仅影响容器本身，内容视图的内部背景需自行设置
    /// （内容四边贴合容器，自带不透明直角背景会盖住圆角）。
    @discardableResult
    public func backgroundColor(_ color: UIColor) -> SKDialog {
        config.containerBackgroundColor = color
        return self
    }

    /// 设置容器圆角半径。
    /// - Note: 圆角作用于容器 layer，而开启阴影时图层不裁剪，因此子视图不会被自动裁进圆角。
    @discardableResult
    public func cornerRadius(_ radius: CGFloat) -> SKDialog {
        config.cornerRadius = radius
        return self
    }

    /// 仅设置动画类型，时长与弹簧参数保持 config 默认值（0.3s / damping 0.8 / velocity 0.5）。
    /// 需要同时定制手感时用下面带参数的重载。
    @discardableResult
    public func animation(_ type: SKDialogAnimationType) -> SKDialog {
        config.animationType = type
        return self
    }

    /// 设置点击遮罩是否关闭弹窗。
    /// 手势在 `show()` 之前安装时读取此值，因此必须在展示前设置；
    /// 展示后再改配置不会同步到已安装的手势。
    @discardableResult
    public func dismissOnBackgroundTap(_ dismiss: Bool = true) -> SKDialog {
        config.dismissOnBackgroundTap = dismiss
        return self
    }

    /// 设置是否支持拖拽关闭（仅对底部/顶部弹窗有意义）。
    /// - Note: 手势在展示时按此值安装；展示后修改需调用
    ///   SKDialogGestureHandler.updateGestureStates() 才会同步到已安装的手势。
    @discardableResult
    public func enablePanGestureDismiss(_ enable: Bool = true) -> SKDialog {
        config.enablePanGestureDismiss = enable
        return self
    }

    /// 设置Window层级（仅在window模式下有效）。
    /// 默认 `.alert + 1`；调低可能让弹窗被更高层级的 window（键盘、系统弹窗）遮挡。
    @discardableResult
    public func windowLevel(_ level: UIWindow.Level) -> SKDialog {
        config.windowLevel = level
        return self
    }

    /// 设置固定尺寸（nil 的维度表示该方向不限制）。
    /// - Important: 会覆盖之前的尺寸设置——内部直接改写 `config.sizeMode` 为 `.fixed`，
    ///   调用顺序靠后的尺寸方法生效。
    @discardableResult
    public func size(width: CGFloat? = nil, height: CGFloat? = nil) -> SKDialog {
        config.sizeMode = .fixed(width: width, height: height)
        return self
    }

    /// 设置为内容自适应：不施加任何尺寸约束，容器由内容的内在尺寸撑开。
    /// 内容必须自带内在尺寸或自身约束，否则容器会塌缩到 0 尺寸。
    @discardableResult
    public func contentAdaptive() -> SKDialog {
        config.sizeMode = .contentAdaptive
        return self
    }

    /// 设置固定宽度，高度仍随内容变化。
    @discardableResult
    public func fixedWidth(_ width: CGFloat) -> SKDialog {
        config.sizeMode = .widthFixed(width)
        return self
    }

    /// 设置固定高度，宽度仍随内容变化。
    @discardableResult
    public func fixedHeight(_ height: CGFloat) -> SKDialog {
        config.sizeMode = .heightFixed(height)
        return self
    }

    /// 设置遮罩颜色（含 alpha 的完整颜色）。
    /// - Note: 拖拽时会以该颜色的 alpha 为基准淡出（最多 50%），
    ///   因此建议使用半透明色，详见 SKDialogConfig.backgroundMaskColor。
    @discardableResult
    public func maskColor(_ color: UIColor) -> SKDialog {
        config.backgroundMaskColor = color
        return self
    }

    /// 一次性设置阴影的开关与全部参数（参数的默认值即 config 的默认外观）。
    /// 相比逐个属性赋值，这里更适合"要么全默认、要么整体换一套"的用法。
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

    /// 设置动画类型并同时定制手感。
    ///
    /// 这是 `animation(_:)` 的重载版本，区别在于它把时长与弹簧参数一并写入：
    /// - duration: 动画时长（秒），也影响退场
    /// - damping: 阻尼（1.0 无回弹）
    /// - velocity: 初始速度
    /// - Note: 尺寸变化的过渡动画不受这些参数影响（它使用独立的固定参数）。
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
    /// 为 true 时容器贴屏幕物理边缘，内容需自行处理刘海/Home Indicator 的间距。
    @discardableResult
    public func extendToSafeArea(_ extend: Bool) -> SKDialog {
        config.extendToSafeArea = extend
        return self
    }

    /// 设置动画显示开始回调（在入场动画发起前触发，适合做数据准备或埋点起点）。
    /// 回调在 `show()` 之后由控制器持有并在入场完成时清理，不会长期驻留。
    @discardableResult
    public func onPresentAnimationWillStart(_ handler: @escaping () -> Void) -> SKDialog {
        self.presentAnimationWillStartHandler = handler
        return self
    }

    /// 设置动画显示完成回调（入场动画结束时触发，适合做自动聚焦、开始计时等）。
    @discardableResult
    public func onPresentAnimationDidFinish(_ handler: @escaping () -> Void) -> SKDialog {
        self.presentAnimationDidFinishHandler = handler
        return self
    }

    /// 设置动画消失开始回调（退场动画发起前触发）。
    @discardableResult
    public func onDismissAnimationWillStart(_ handler: @escaping () -> Void) -> SKDialog {
        self.dismissAnimationWillStartHandler = handler
        return self
    }

    /// 设置动画消失完成回调（退场动画结束时触发，此时视图尚未从层级中移除）。
    /// 若需要在窗口/控制器彻底收尾后执行逻辑，用 `show()` 返回值的
    /// `addCompletionHandler(_:)`，或 `dismissDialog(completion:)`。
    @discardableResult
    public func onDismissAnimationDidFinish(_ handler: @escaping () -> Void) -> SKDialog {
        self.dismissAnimationDidFinishHandler = handler
        return self
    }

    /// 设置内容视图。
    /// 内容会在 `show()` 时被装载并四边贴合容器（容器的自适应尺寸正来源于此）。
    /// - Note: 多次调用只有最后一次生效（这里保存的是引用，不是数组）。
    @discardableResult
    public func contentView(_ view: UIView) -> SKDialog {
        self.contentView = view
        return self
    }
}

// MARK: - Show Methods

extension SKDialog {

    /// 显示弹窗（根据配置自动选择显示方式），返回承载它的控制器。
    ///
    /// 返回值不是可忽略的错误值，而是**操控已展示弹窗的唯一入口**：
    /// 通过它可以动态改尺寸（`updateContainerHeight` 等）、追加完成回调或主动关闭。
    /// 标 `@discardableResult` 是因为"配好就展开展示、不关心后续"是最常见的用法。
    ///
    /// 执行流程：创建控制器 → 装载内容 → 转移动画回调 → 按显示模式发起展示。
    /// - Note: 两种模式的"发起方式"不同——window 模式由管理器自建窗口并上屏，
    ///   控制器模式交给指定控制器 present（`animated: false`，视觉动画全部由库自绘）。
    ///   无论哪条路径，真正的入场动画都由控制器统一发起（viewDidAppear 或 showInWindow），
    ///   本方法不直接播放动画。
    @discardableResult
    public func show() -> SKDialogViewController {
        let dialog = SKDialogViewController(config: config)

        if let contentView = contentView {
            dialog.addContentView(contentView)
        }

        // 设置动画回调
        // 把构建器上寄存的回调交给控制器：控制器会在对应时机调用，并在调用后清空引用
        dialog.presentAnimationWillStartHandler = presentAnimationWillStartHandler
        dialog.presentAnimationDidFinishHandler = presentAnimationDidFinishHandler
        dialog.dismissAnimationWillStartHandler = dismissAnimationWillStartHandler
        dialog.dismissAnimationDidFinishHandler = dismissAnimationDidFinishHandler

        switch config.presentationMode {
        case .window:
            dialog.showInWindow()
        case .viewController(let viewController):
            // 用 animated: false 交由系统建立模态层级，入场动画随后由控制器的
            // viewDidAppear → presentDialog 播放，避免系统转场与自绘动画叠加
            viewController.present(dialog, animated: false)
        }

        return dialog
    }
}

// MARK: - Preset Configuration Builders

extension SKDialog {

    /// 创建底部弹窗（预设：从底部滑入 / 内容自适应 / 可拖拽 / 延伸到安全区）。
    ///
    /// 之所以提供预设而不是让宿主每次手写一串配置：这三套参数是经过验证的常见组合
    /// （底部面板、居中提示、顶部通知条），预设能让普通用法保持一行代码，
    /// 需要偏离时再用链式方法覆盖其中的某一项。
    public static func bottom() -> SKDialog {
        return SKDialog()
            .position(.bottom)
            .animation(.slideFromBottom)
            .margins(UIEdgeInsets.zero)
            .contentAdaptive()
            .enablePanGestureDismiss()
            .extendToSafeArea(true)
    }

    /// 创建居中弹窗（预设：缩放淡入 / 四周 40 边距 / 圆角 12）。
    /// 边距在这里同时扮演"最大宽度限制"的角色，避免内容撑满屏幕宽度。
    public static func center() -> SKDialog {
        return SKDialog()
            .position(.center)
            .animation(.fadeScale)
            .margins(UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40))
            .cornerRadius(12)
    }

    /// 创建顶部弹窗（预设：从顶部滑入 / 圆角 16 / 可拖拽）。
    /// - Note: 与 `bottom()` 不同，这里没有设置 `extendToSafeArea`，
    ///   沿用配置默认值（当前默认为 true，即贴屏幕物理上边缘）。
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

    /// 一行完成"创建底部弹窗并展示"，返回控制器以便后续操作。
    /// 等价于 `SKDialog.bottom().contentView(view).show()`。
    @discardableResult
    public static func showBottom(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.bottom()
            .contentView(contentView)
            .show()
    }

    /// 一行完成"创建居中弹窗并展示"，等价于 `SKDialog.center().contentView(view).show()`。
    @discardableResult
    public static func showCenter(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.center()
            .contentView(contentView)
            .show()
    }

    /// 一行完成"创建顶部弹窗并展示"，等价于 `SKDialog.top().contentView(view).show()`。
    @discardableResult
    public static func showTop(with contentView: UIView) -> SKDialogViewController {
        return SKDialog.top()
            .contentView(contentView)
            .show()
    }
}
