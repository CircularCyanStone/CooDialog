//
//  SKDialogConfig.swift
//  TAIChat
//
//  Created by Assistant on 2024
//

/**
 * 文件功能描述：
 * 弹窗的「配置契约层」。整个库中只有这个文件描述"弹窗应该长什么样、从哪出现、怎么交互"，
 * 且全部以纯数据（枚举 + 属性）表达，不包含任何视图创建、约束或动画代码。
 *
 * 为什么这样分层（设计原理）：
 * 1. 配置与实现解耦：SKDialog（构建器）只负责收集调用方的意图，SKDialogViewController 与它
 *    下属的一整套管理器只负责解释并执行配置。任一方的内部重构都不会改变另一方的用法。
 * 2. 单一数据源：所有管理器共享同一个 SKDialogConfig 实例（引用类型）。因此"配置即状态"——
 *    容器尺寸被动态修改后，SKDialogContainerSizeManager 会把新的宽高回写进 sizeMode，
 *    使得"读 config"永远等于"看当前真实状态"，无需额外的同步机制。
 * 3. 传递成本低：配置是普通属性集合，宿主可以集中构建一次，再决定何时以何种方式展示。
 *
 * 使用注意（引用类型带来的一致性风险）：
 * config 是可变的引用类型。若同一个 config（或同一个 SKDialog 构建器）被复用给多个弹窗，
 * 对它的任何修改都会同时影响这些弹窗；同理，一个弹窗动态改尺寸时会改写共享的 sizeMode。
 * 需要"两个独立弹窗"时应各自创建新的配置。
 *
 * 文件内类型分工：
 * - SKDialogPosition：停靠位置（决定约束锚点组合与是否支持拖拽）
 * - SKDialogAnimationType：入场/退场动画（9 种内置 + 1 个自定义扩展点）
 * - SKDialogPresentationMode：显示载体（独立 window / 指定控制器）
 * - SKDialogSizeMode：尺寸来源（固定 / 自适应 / 单向固定）
 * - SKDialogConfig：以上配置项的容器，另含外观、阴影、交互、安全区、动画参数
 */

import Foundation
import UIKit

/// 弹窗的停靠位置。
///
/// 为什么用固定枚举而不是任意坐标：
/// SKDialogConstraintManager 完全依赖锚点约束（centerX / top / bottom）定位容器，把位置收敛
/// 为枚举后，每个取值都能映射成一组确定的锚点组合，运行时无需计算 frame，也就不会出现
/// "坐标与边距互相矛盾"这类非法配置。
///
/// 各取值带来的行为差异（这些差异是后续所有管理器的判定依据）：
/// - `.center`：垂直方向不受 margins 约束，内容过高会直接顶到屏幕边缘；没有"可退出的方向"，
///   因此不支持拖拽关闭。
/// - `.bottom` / `.top`：属于"贴边面板"，支持拖拽关闭，并可选择是否延伸进安全区
///   （见 `SKDialogConfig.extendToSafeArea`）。
public enum SKDialogPosition {
    case center     // 屏幕居中，垂直方向无 margins 约束，不支持拖拽
    case bottom     // 贴屏幕底部，支持向下拖拽关闭
    case top        // 贴屏幕顶部，支持向上拖拽关闭
}

/// 弹窗入场 / 退场动画类型。
///
/// 设计思路：把动画抽象成"可替换的策略"。9 种内置动画由 SKDialogAnimationManager 分发到
/// 各自独立的实现类（每个类只描述"起点是什么、终点是什么"）；`.custom` 则是留给宿主的扩展点——
/// 库外无法新增枚举 case，所以要有一个携带协议实现的 case，宿主才能真正注入自定义动画。
///
/// 命名规律（决定了视觉效果，不是同义词替换）：
/// - 不带后缀（如 `.slideFromBottom`）：容器只做位移，自身始终不透明，仅遮罩单独淡入
/// - 带 `WithFade`（如 `.slideFromBottomWithFade`）：位移同时让容器自身从透明淡入
/// 因此 WithFade 版本的主观速度感更慢、更"柔"，适合大面板；不带后缀的更适合轻量提示条。
public enum SKDialogAnimationType: Equatable {
    case slideFromBottom    // 从屏幕下方滑入（容器不淡入）
    case fadeScale          // 原地缩放淡入，默认缩放起点见 FadeScaleAnimation
    case slideFromTop       // 从屏幕上方滑入（容器不淡入）
    case slideFromLeft      // 从屏幕左侧滑入（容器不淡入）
    case slideFromRight     // 从屏幕右侧滑入（容器不淡入）
    case slideFromBottomWithFade    // 从下方滑入 + 容器淡入
    case slideFromTopWithFade       // 从上方滑入 + 容器淡入
    case slideFromLeftWithFade      // 从左侧滑入 + 容器淡入
    case slideFromRightWithFade     // 从右侧滑入 + 容器淡入
    case custom(SKDialogAnimationProtocol)  // 自定义动画：由宿主实现协议注入

    // 手写 Equatable 实现的原因（编译器无法自动合成）：
    // `.custom` 的关联值 SKDialogAnimationProtocol 是存在类型，协议本身不继承 Equatable，
    // 因此无法逐 case 比较关联值。这里对 9 种内置类型做真实比较，对 `.custom` 一律返回 false。
    // 于是需要留意语义边界：两个 `.custom` 即使指向同一种动画也判为不相等，
    // "不相等"只意味着"无法判定相等"，调用方不应据 == false 推断两动画不同
    // （若确需比较，应在协议中额外暴露标识符）。
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

/// 弹窗的显示载体模式。
///
/// 两种模式的本质区别是"弹窗隶属于谁"：
/// - `.window`（默认）：由独立的 UIWindow 承载。优点是弹窗不隶属任何控制器层级，可以盖过
///   导航栏、TabBar、以及已经 present 出来的控制器，也能在"没有合适 VC"的时机展示
///   （启动早期、网络回调、后台任务回到前台等）。代价是必须自己管理 window 生命周期与
///   key window 的恢复，这部分由 SKDialogWindowManager 负责。
/// - `.viewController(vc)`：由指定控制器 present。适合"弹窗明确属于某个页面"的场景，
///   可以随该页面一起被销毁；代价是受这个控制器的 present 链约束。
///
/// - Important: `.viewController` 携带的是**强引用**（枚举关联值 + 配置对象都是强引用）。
///   若把 `self` 传给一个被自己长期持有的配置（例如 `self.dialog = SKDialog.center()
///   .presentationMode(.viewController(self))`），就会形成
///   VC → 弹窗 → 配置 → VC 的引用环，需要改用 window 模式或传入父级控制器。
public enum SKDialogPresentationMode {
    case viewController(UIViewController)  // 由指定控制器 present（模态转场，强引用该控制器）
    case window                           // 由库自建的 UIWindow 承载（默认，层级最高，无宿主 VC）
}

/// 容器尺寸的确定方式。
///
/// 为什么用一个枚举而不是 `width: CGFloat?` + `height: CGFloat?` 两个属性：
/// 两个可选值能组合出 4 种状态，其中"两者都为空"到底是"宽度自适应"还是"没配置"是歧义的；
/// 枚举把合法状态显式化，让"宽高分别如何确定"只有 4 种可能，约束管理器也就能为每种模式给出
/// 互斥且确定的约束组合。
///
/// 与约束的对应关系（见 SKDialogConstraintManager.addSizeConstraints）：
/// - `.fixed`：按给定值添加等宽/等高常量约束，传 nil 的维度不加约束
/// - `.widthFixed` / `.heightFixed`：只固定一个方向，另一个方向交给内容决定
/// - `.contentAdaptive`：完全不添加尺寸约束，容器尺寸由内容视图的内在尺寸 + 位置约束共同求解
public enum SKDialogSizeMode {
    case fixed(width: CGFloat?, height: CGFloat?)  // 固定尺寸，nil 维度不约束
    case contentAdaptive                           // 完全由内容撑开，不加尺寸约束
    case widthFixed(CGFloat)                      // 只固定宽度，高度随内容
    case heightFixed(CGFloat)                     // 只固定高度，宽度随内容
}


/// 弹窗配置。
///
/// 这是库对外的"参数清单"：SKDialog（链式构建器）负责写入，SKDialogViewController 与各管理器
/// 负责读取。每个属性注释里都标注了**实际消费位置**与需要注意的边界行为，
/// 因为这些细节决定了"改这个值是否真的有效果"。
///
/// 生命周期：配置随构建器一起创建，被 SKDialogViewController 强引用并在整个弹窗生命周期内
/// 保持同一实例（管理器的动态回写也发生在同一实例上）。
public class SKDialogConfig {

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

    /// 尺寸模式。统一管理宽高，避免"分别设置宽高"带来的非法组合。
    /// 消费位置：SKDialogConstraintManager.addSizeConstraints()；
    /// 动态改尺寸时会被 SKDialogContainerSizeManager 回写以保持与实际约束一致。
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
    /// 本属性同时是手势的初始启用状态，显示后被修改**不会**自动同步到手势（需要调用
    /// SKDialogGestureHandler.updateGestureStates()）。
    public var dismissOnBackgroundTap: Bool = true

    /// 是否允许拖拽关闭（仅对底部 / 顶部弹窗有意义，居中弹窗没有可拖出的方向）。
    ///
    /// 消费位置：SKDialogGestureHandler.setupPanGesture() / updateGestureStates()，
    /// 判定条件为「position 是 .bottom 或 .top」**且**本开关为 true。
    /// 手势在展示时（viewDidLoad）读取此值，展示后修改需调用
    /// SKDialogGestureHandler.updateGestureStates() 才会同步到已安装的手势。
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
    /// 与构建器预设 `SKDialog.bottom()` 的差异（两者默认值并不等价，按需选择）：
    /// - 本方法只产出配置，不带内容视图，也不做链式预设
    /// - 圆角默认 16（config 自身默认是 12）
    /// - 拖拽与安全区沿用 config 默认值，而不是像构建器那样显式开启
    ///
    /// - Parameters:
    ///   - height: 面板高度；传 nil 表示高度由内容自适应
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，底部面板通常传 .zero 让面板横向占满
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置实例
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

    /// 创建居中对话框配置。
    ///
    /// - Note: 内部使用 `.fixed(width:height:)`；两个参数都传 nil 时不会添加任何尺寸约束，
    ///   约束层面的效果与 `.contentAdaptive` 相同。二者的差别在后续的动态改尺寸：
    ///   `.fixed` 模式会被改写为带具体常量的 `.fixed`，而 `.contentAdaptive` 保持不变。
    ///   若希望语义明确、保留"始终自适应"的意图，建议直接使用 `.contentAdaptive`。
    ///
    /// - Parameters:
    ///   - width: 固定宽度；nil 表示不约束宽度
    ///   - height: 固定高度；nil 表示不约束高度
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，默认四周 40（左右同时充当最大宽度限制）
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置实例
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

    /// 创建顶部提示条配置。
    ///
    /// 与构建器预设 `SKDialog.top()` 的差异同 `bottomSheet`：本方法的圆角为 16、
    /// 且不额外设置手势与安全区相关开关。
    ///
    /// - Parameters:
    ///   - height: 提示条高度；传 nil 表示高度由内容自适应
    ///   - cornerRadius: 容器圆角
    ///   - margins: 边距，顶部提示条通常传 .zero
    ///   - presentationMode: 显示载体，默认独立 window
    /// - Returns: 可直接传给 SKDialogViewController 的配置实例
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
