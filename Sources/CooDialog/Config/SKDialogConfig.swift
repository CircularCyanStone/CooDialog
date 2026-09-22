/**
 * 文件功能描述：
 * 弹窗的「配置容器」类型：把"弹窗长什么样、从哪出现、怎么交互"的全部可选项收在一个值类型里，
 * 全部以纯数据（属性 + 便捷构造方法）表达，不涉及任何视图创建、约束或动画代码。
 *
 * 配置契约的其余部分按类型拆分为同目录下的兄弟文件：
 * - SKDialogPosition：停靠位置（决定约束锚点组合与是否支持拖拽）
 * - SKDialogAnimationType：入场/退场动画（9 种内置 + 1 个自定义扩展点）
 * - SKDialogPresentationMode：显示载体（独立 window / 指定控制器）
 * - SKDialogSizeMode：尺寸来源（固定 / 自适应 / 单向固定）
 *
 * 为什么这样分层（设计原理）：
 * 1. 配置与实现解耦：SKDialog（构建器）只负责收集调用方的意图，SKDialogViewController 与它
 *    下属的一整套管理器只负责解释并执行配置。任一方的内部重构都不会改变另一方的用法。
 * 2. 单一数据源（每个弹窗一份）：SKDialogConfig 是 struct，控制器持有自己那份副本，
 *    所有管理器都通过控制器读写它。因此"配置即状态"——容器尺寸被动态修改后，
 *    SKDialogContainerSizeManager 会把新的宽高回写进控制器的 config.sizeMode，
 *    使得"读 dialog.config"永远等于"看该弹窗当前的真实状态"，无需额外的同步机制。
 * 3. 传递成本低：配置是普通属性集合（值类型），宿主可以集中构建一次，再决定何时以何种方式展示；
 *    交给控制器后即与外部变量脱钩，不存在共享可变状态。
 *
 * 使用注意（值语义带来的两点变化）：
 * 1. 宿主只在展示前配置：SKDialogViewController.config 对库外只读（setter 为 internal），
 *    展示后需要改变外观或交互请新建弹窗；库内唯一的运行时写入是尺寸回写（见第 2 条）。
 * 2. 配置是值传递：传给 SKDialogViewController(config:) 之后再修改外部那份变量，
 *    不会影响已创建的弹窗；同一个 SKDialog 构建器展示两次，两个弹窗的配置互不干扰。
 *
 */

import Foundation
import UIKit

/// 弹窗配置。
///
/// 这是库对外的"参数清单"：SKDialog（链式构建器）负责写入，SKDialogViewController 与各管理器
/// 负责读取。每个属性注释里都标注了**实际消费位置**与需要注意的边界行为，
/// 因为这些细节决定了"改这个值是否真的有效果"。
///
/// 生命周期：配置随构建器一起创建，`show()` 时按值交给 SKDialogViewController 并由它持有；
/// 管理器一律通过控制器读写这份配置（动态回写也落在控制器的副本上）。
public struct SKDialogConfig {

    // MARK: - 显示模式配置

    /// 弹窗的显示载体，默认独立 window。
    /// 消费位置：SKDialogViewController.show() 与 dismissDialog() 的分支判定、
    /// SKDialogWindowManager（仅 window 模式参与）。
    public var presentationMode: SKDialogPresentationMode = .window

    /// 自定义 Window 的层级（仅在 window 模式下有意义）。
    ///
    /// 默认 `.alert + 1`：既高于普通 window，也高于系统 alert 层。
    /// 消费位置：SKDialogWindowManager.configureWindow()。
    /// 调低该值可能让弹窗被更高层级的 window（例如键盘、系统弹窗）遮挡。
    public var windowLevel: UIWindow.Level = UIWindow.Level.alert + 1

    // MARK: - 位置和大小配置

    /// 弹窗停靠位置。消费位置：约束锚点组合（SKDialogConstraintManager）、
    /// 拖拽方向判定（SKDialogGestureHandler）、滑动动画偏移方向（SKDialogAnimationStateManager）。
    public var position: SKDialogPosition = .center

    /// 尺寸模式。4 种状态与 4 个 case 一一对应（见 SKDialogSizeMode），同一意图只有一种写法。
    /// 消费位置：SKDialogConstraintManager.addSizeConstraints()；
    /// 动态改尺寸时会被 SKDialogContainerSizeManager 回写以保持与实际约束一致——
    /// 回写只做明确升格（`.fixedWidth` / `.fixedHeight` 在另一个方向也被定死后变为 `.fixed`），
    /// 不会产生模棱两可的组合。
    public var sizeMode: SKDialogSizeMode = .contentAdaptive

    /// 容器相对屏幕边缘的边距。
    ///
    /// 消费方式随位置而异（见 SKDialogConstraintManager.addPositionConstraints）：
    /// - `.top` / `.bottom`：`top`/`bottom` 决定垂直方向的贴边留白（以安全区还是屏幕物理边缘
    ///   为基准取决于 `extendToSafeArea`），`left`/`right` 作为水平方向的**最小**留白
    /// - `.center`：只使用 `left`/`right` 限制最大宽度，垂直方向不施加任何边距约束
    /// 也就是说，居中弹窗内容过高时不会被边距拦住，会直接顶到屏幕边缘。
    public var margins = UIEdgeInsets.zero

    // MARK: - 外观配置

    /// 容器视图背景色，默认 `.systemBackground`（自动适配深/浅色模式）。
    ///
    /// 注意作用范围：圆角与背景都只作用于容器 layer，而 contentView 会被约束到容器四边。
    /// 如果 contentView 自带不透明背景且是直角，视觉上会盖掉容器的圆角——
    /// 需要圆角观感时，内容视图应使用透明背景，或自行设置圆角。
    public var containerBackgroundColor: UIColor = .systemBackground

    /// 容器圆角半径（写入 containerView.layer.cornerRadius）。
    ///
    /// 与阴影的关联：SKDialogViewController.setupUI() 在 `showShadow` 为 true 时会显式把
    /// masksToBounds 设为 false（否则阴影会被图层裁剪掉），这也意味着容器**不会**把内容
    /// 裁剪进圆角内。若内容需要跟随圆角裁剪，请由内容视图自行处理（例如设置
    /// contentView.layer.cornerRadius + masksToBounds）。
    public var cornerRadius: CGFloat = 12

    /// 背景遮罩色（含透明度的完整颜色，默认 50% 黑）。
    ///
    /// 有两个消费点，改这一个值会同时影响它们：
    /// 1. 初始遮罩颜色（SKDialogViewController.setupUI）
    /// 2. 拖拽时按进度稀释遮罩：SKDialogGestureHandler.updateBackgroundAlpha 会以本颜色的
    ///    alpha 为基准最多淡化 50%，并把结果直接写回 backgroundView.backgroundColor
    /// 所以建议使用"颜色 + alpha"的半透明色，不要用完全不透明的颜色（否则淡化基准是 alpha 1.0，
    /// 遮罩变化会显得很轻微）。
    public var backgroundMaskColor: UIColor = UIColor.black.withAlphaComponent(0.5)

    // MARK: - 阴影配置

    /// 是否启用容器阴影。
    ///
    /// 关闭时完全不设置阴影属性（图层保持默认状态）；开启时才写入下面 4 个参数并把
    /// masksToBounds 显式置为 false。阴影作用于 containerView.layer，因此入场/退场动画中
    /// 它会跟随容器一起位移与缩放。
    public var showShadow: Bool = true

    /// 阴影颜色（CGColor 在 setupUI 时取自此处）。
    public var shadowColor: UIColor = .black

    /// 阴影偏移，默认 (0, 2)：光从正上方来，容器看起来"浮"在遮罩之上。
    public var shadowOffset: CGSize = CGSize(width: 0, height: 2)

    /// 阴影模糊半径，值越大边缘越柔和。
    public var shadowRadius: CGFloat = 8

    /// 阴影不透明度（0~1），默认 0.15：轻量投影，避免在深色模式下显得脏。
    public var shadowOpacity: Float = 0.15

    // MARK: - 交互配置

    /// 点击遮罩区域是否关闭弹窗。
    ///
    /// 生效路径：SKDialogGestureHandler 在 backgroundView 上挂 UITapGestureRecognizer，
    /// 只有落点在容器 frame 之外才会关闭（避免点到容器内的空白区域误关）。
    /// 由于手势挂在 backgroundView 上、容器位于其上层，点击容器本身不会命中该手势，
    /// frame 判断属于双重保险。
    /// 本属性同时是手势的初始启用状态。
    /// - Important: 配置在**展示前**确定——`SKDialogViewController.config` 对库外只读，
    ///   手势也只在安装那一刻读一次本值。展示后需要另一种交互形态时，请新建弹窗。
    public var dismissOnBackgroundTap: Bool = true

    /// 是否允许拖拽关闭（仅对底部 / 顶部弹窗有意义，居中弹窗没有可拖出的方向）。
    ///
    /// 消费位置：SKDialogGestureHandler.setupPanGesture() / updateGestureStates()，
    /// 判定条件为「position 是 .bottom 或 .top」**且**本开关为 true。
    /// - Important: 配置在**展示前**确定——手势只在安装那一刻读一次本值，
    ///   而 `config` 对库外只读，展示后没有运行时同步入口。
    /// - Note: 内容里若有可滚动的子视图，拖拽会让位给滚动，
    ///   详见 SKDialogGestureHandler 的手势准入判定。
    public var enablePanGestureDismiss: Bool = true

    // MARK: - 安全区域配置

    /// 容器是否延伸到安全区域之外（仅影响 `.top` / `.bottom` 的垂直约束基准）。
    ///
    /// - 为 true（默认）：以屏幕物理边缘为基准，容器贴到刘海 / Home Indicator 区域，
    ///   内容需自行处理安全区间距（宿主通常在内容视图内使用 safeAreaInsets 留白）
    /// - 为 false：以 safeAreaLayoutGuide 为基准，容器自动避开刘海与 Home Indicator，
    ///   但底部弹窗下方会露出一条遮罩色，视觉上"不沉浸"
    /// 居中弹窗不使用垂直边距，因此本配置对 `.center` 无影响。
    public var extendToSafeArea: Bool = true

    // MARK: - 动画配置

    /// 入场 / 退场动画类型，决定 SKDialogAnimationManager 使用哪一套实现。
    /// 也可在展示前随时修改；注意它会同时影响"预置的首帧状态"（见 fadeScaleInitialScale）。
    public var animationType: SKDialogAnimationType = .fadeScale

    /// 动画时长（秒）。
    /// 消费位置：SKDialogAnimationManager 中 9 种内置动画的入场与退场。
    /// 注意：容器尺寸变化的过渡动画**不**读取此值，它使用 SKDialogContainerSizeManager
    /// 内部的 SizeAnimationConfig.default（固定 0.3s）。
    public var animationDuration: TimeInterval = 0.3

    /// 弹簧动画阻尼：1.0 表示无回弹，越接近 0 回弹越明显。仅影响入场/退场动画。
    public var springDamping: CGFloat = 0.8

    /// 弹簧动画初速度，影响动画起步的"冲劲"（位移/秒量级）。仅影响入场/退场动画。
    public var springVelocity: CGFloat = 0.5

    /// 渐变缩放动画的起始缩放比例（0.8 表示由 80% 放大到 100%）。
    ///
    /// 消费位置：SKDialogAnimationStateManager.setupFadeScaleInitialState()（首帧预置）
    /// 与 FadeScaleAnimation 的入场/退场（动画起点与终点）。两处读同一个值，
    /// 因此"预置状态 → 动画起点"之间不会出现缩放跳变。
    public var fadeScaleInitialScale: CGFloat = 0.8

    // MARK: - Initialization

    /// 无参初始化，所有属性取上述默认值：
    /// 居中 / 内容自适应 / window 载体 / fadeScale 动画 / 可点遮罩关闭 / 带阴影。
    public init() {}

    // MARK: - 便利构造方法

    /// 创建底部面板配置。
    ///
    /// 与构建器预设 `SKDialog.bottom()` 的差异（两者并不等价，按需选择）：
    /// - 本方法只产出配置，不带内容视图，也不做链式预设
    /// - 圆角默认 16，而 `SKDialog.bottom()` 未显式设置圆角，取 config 默认的 12
    /// - 其余开关两者取值相同（拖拽关闭与延伸安全区都是 config 默认的开启状态）
    ///
    /// - Parameters:
    ///   - height: 面板高度；传 nil 表示高度由内容自适应
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，底部面板通常传 .zero 让面板横向占满
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置值
    public static func bottomSheet(
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 16,
        margins: UIEdgeInsets = UIEdgeInsets.zero,
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        var config = SKDialogConfig()
        config.position = .bottom
        // 只给高度方向：nil → .contentAdaptive，有值 → .fixedHeight（宽度始终随内容）
        config.sizeMode = SKDialogSizeMode(width: nil, height: height)
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .slideFromBottom
        config.presentationMode = presentationMode
        return config
    }

    /// 创建居中对话框配置。
    ///
    /// 尺寸映射与 `SKDialog.size(width:height:)` 完全一致（同一处映射规则，见 SKDialogSizeMode 的便利初始化器）：
    /// 两个方向都给 → `.fixed`；只给宽度 → `.fixedWidth`；只给高度 → `.fixedHeight`；都不给 → `.contentAdaptive`。
    ///
    /// - Parameters:
    ///   - width: 固定宽度；nil 表示该方向随内容变化
    ///   - height: 固定高度；nil 表示该方向随内容变化
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，默认四周 40（左右同时充当最大宽度限制）
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置值
    public static func centerDialog(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 12,
        margins: UIEdgeInsets = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        var config = SKDialogConfig()
        config.position = .center
        config.sizeMode = SKDialogSizeMode(width: width, height: height)
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .fadeScale
        config.presentationMode = presentationMode
        return config
    }

    /// 创建顶部提示条配置。
    ///
    /// 与构建器预设 `SKDialog.top()` 基本一致（圆角 16、可拖拽关闭、延伸安全区取默认值），
    /// 差异只在于本方法只产出配置：不带内容视图，也不做链式预设。
    ///
    /// - Parameters:
    ///   - height: 提示条高度；传 nil 表示高度由内容自适应
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，顶部提示条通常传 .zero
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置值
    public static func topSheet(
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 16,
        margins: UIEdgeInsets = UIEdgeInsets.zero,
        presentationMode: SKDialogPresentationMode = .window
    ) -> SKDialogConfig {
        var config = SKDialogConfig()
        config.position = .top
        // 只给高度方向：nil → .contentAdaptive，有值 → .fixedHeight（宽度始终随内容）
        config.sizeMode = SKDialogSizeMode(width: nil, height: height)
        config.cornerRadius = cornerRadius
        config.margins = margins
        config.animationType = .slideFromTop
        config.presentationMode = presentationMode
        return config
    }
}
