//
//  SKDialogViewController.swift
//  TAIChat
//
//  Created by Assistant on 2024
//
// 文件功能描述：弹窗基础控制器，提供统一的弹窗显示和管理功能
// 类型功能描述：集成各个管理器，提供完整的弹窗解决方案，支持多种动画效果、手势交互和显示模式
//
// 设计原理（本类在架构中的定位：编排者，而非实现者）：
// 一个弹窗要同时处理"位置约束、尺寸变化、手势、动画状态、window 生命周期、内容装载"六件事，
// 全塞进一个控制器会变成难以维护的巨型类。因此这里按关注点拆成 6 个管理器，控制器本身只保留：
// 1. 共享的视图与状态（containerView / backgroundView / 尺寸约束引用 / 显示状态）
// 2. 生命周期编排（何时搭建 UI、何时播放入场动画、关闭时按模式分流收尾）
// 3. 对外 API 的稳定门面（转发给管理器，宿主无需感知内部拆分）
// 管理器之间不互相引用，一律通过控制器上的这些共享属性协作，依赖关系因此保持单层。
//
// 生命周期关键时序（理解本文件的主线）：
// init(config:) → viewDidLoad（建 UI → 建约束 → 装手势 → 预置动画起点）
// → show() / viewDidAppear（触发 presentDialog，入场动画）
// → viewDidLayoutSubviews（布局完成后校正滑动起点）
// → dismissDialog（退场动画 → 按模式收尾：隐藏 window 或 dismiss 控制器）

import UIKit

/// 弹窗基础控制器
///
/// 对外以 `open` 暴露：宿主可以继承它覆写生命周期方法，并用公开的 `containerView` / `config` /
/// 各动画回调做定制。
/// 扩展面刻意止步于此——核心流程（`show` / `dismissDialog` / `addContentView`）只可调用、不可覆写：
/// 展示方式由 `config.presentationMode` 表达，覆写它们会绕过 `isPresenting` 去重、window 回收等内部时序，
/// 而这些时序正是本类对外契约（回调必触发、window 必释放）的保障。
/// 全部 API 均在主 actor 上，需在主线程调用。
@MainActor
open class SKDialogViewController: UIViewController {

    // MARK: - Properties

    // 本区含公开属性与内部存储：extension 不能声明存储属性，因此两者都集中在主类型体内；
    // 方法则按可见性分区——公开 API 在本类型体内，internal / private 见下方扩展。

    /// 弹窗配置（值类型，库外只读；setter 为 internal 供尺寸回写使用）。
    /// 控制器持有自己那份副本，所有管理器都通过它读取配置；
    /// 动态改尺寸时 SKDialogContainerSizeManager 会把新的 sizeMode 写回这份副本。
    public internal(set) var config: SKDialogConfig

    /// 动画管理器：入场/退场动画的唯一出口。
    /// 用 let 而非 lazy：构造时即可创建（构造阶段不做任何 UIKit 操作），之后不再替换。
    /// 它不持有配置——每次执行动画时由本控制器把当前的 config 传进去。
    private let animationManager: SKDialogAnimationManager

    /// 约束管理器：负责创建/成组替换容器的位置与尺寸约束。
    /// 以下管理器都声明为 lazy：它们在初始化时需要引用 self（`init(viewController: self)`），
    /// 而在 `super.init` 完成前访问 self 是不允许的；lazy 把创建推迟到首次使用时，
    /// 天然规避了这个时序限制。首次访问发生在 viewDidLoad，此时 self 已完全初始化。
    private lazy var constraintManager: SKDialogConstraintManager = SKDialogConstraintManager(viewController: self)

    /// 手势处理器：背景点击关闭与拖拽关闭
    private lazy var gestureHandler: SKDialogGestureHandler = SKDialogGestureHandler(viewController: self)

    /// 动画状态管理器：预置动画起点、布局后校正滑动偏移
    private lazy var animationStateManager: SKDialogAnimationStateManager = SKDialogAnimationStateManager(viewController: self)

    /// Window模式管理器：自建 window 的显示与释放
    private lazy var windowManager: SKDialogWindowManager = SKDialogWindowManager(viewController: self)

    /// 容器尺寸管理器：运行时动态改尺寸（改 constant + 回写配置 + 动画过渡）
    private lazy var containerSizeManager: SKDialogContainerSizeManager = SKDialogContainerSizeManager(viewController: self)

    /// 容器视图：承载宿主提供的内容，圆角/阴影/动画都作用在它身上。
    /// 公开为 let（引用不可变、对象可变）：宿主可在外层做进一步视觉定制；
    /// 同时它也是各管理器共享的协作点（约束、手势、动画都直接引用同一实例）。
    public let containerView: UIView = UIView()

    /// 背景遮罩视图：铺满整个控制器 view，负责拦截点击与提供视觉压暗
    public let backgroundView: UIView = UIView()

    // 以下两个约束引用是 internal（非宿主 API）：它们是"约束管理器 ↔ 尺寸管理器"之间的协作点，
    // 存储属性不能放进 extension，故留在主类型体内（与 config 的 internal setter 同理）。

    /// 容器宽度约束（由 SKDialogConstraintManager 创建时写入，供 SKDialogContainerSizeManager 动态改 constant；
    /// nil 表示当前模式没有宽度约束，即宽度由内容决定）
    /// - Note: 宿主改尺寸请用 `updateContainerWidth(_:animated:)` 等公开方法（会同步回写 config 并做过渡动画），
    ///   读尺寸请用 `containerView.frame`；直接改这里会绕过两者，让 config 与实际约束不一致。
    var containerWidthConstraint: NSLayoutConstraint?

    /// 容器高度约束（语义同上）
    var containerHeightConstraint: NSLayoutConstraint?

    /// 是否正在显示（含入场动画中）。
    /// 用途：viewDidAppear 与 show() 都可能发起入场，用它保证入口只被真正执行一次；
    /// 同时作为 dismissDialog 的前置条件。
    private var isPresenting = false

    /// 弹窗关闭完成回调（两种显示模式语义一致：真正收尾后才执行）。
    /// 执行时机：
    /// - window 模式：自建 window 已隐藏并释放之后
    /// - viewController 模式：系统 dismiss 完成之后
    /// 用 `addCompletionHandler(_:)` 可追加多个回调；`dismissDialog(completion:)` 传的是一次性回调。
    public var completionHandler: (() -> Void)?

    /// 弹窗显示动画开始回调
    public var presentAnimationWillStartHandler: (() -> Void)?

    /// 弹窗显示动画完成回调
    public var presentAnimationDidFinishHandler: (() -> Void)?

    /// 弹窗关闭动画开始回调
    public var dismissAnimationWillStartHandler: (() -> Void)?

    /// 弹窗关闭动画完成回调
    public var dismissAnimationDidFinishHandler: (() -> Void)?

    // MARK: - Initialization

    /// 指定配置初始化（构建器与配置便利方法走的都是这条路径）。
    /// 这里立即创建动画管理器并搭建视图层级（setupViewController → 触发后续生命周期），
    /// 因此初始化后即可安全调用公开 API。
    public init(config: SKDialogConfig = SKDialogConfig()) {
        self.config = config
        self.animationManager = SKDialogAnimationManager()
        super.init(nibName: nil, bundle: nil)
        setupViewController()
    }

    /// Storyboard / XIB 初始化路径：此路径无法注入配置，只能退化为默认配置。
    /// 常规使用请走 `init(config:)`，否则弹窗位置、动画等全部为默认值。
    required public init?(coder: NSCoder) {
        self.config = SKDialogConfig()
        self.animationManager = SKDialogAnimationManager()
        super.init(coder: coder)
        setupViewController()
    }

    // MARK: - Lifecycle

    /// 搭建阶段：顺序不能颠倒。
    /// 1. setupUI：先建立 backgroundView / containerView 的层级与外观
    /// 2. 约束：约束必须引用的视图都已存在（并且背景与容器都要关掉 autoresizing 翻译）
    /// 3. 手势：依赖视图已存在，可在约束之前或之后安装
    open override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        constraintManager.setupContainerConstraints()
        gestureHandler.setupGestures()
    }

    /// 入场动画的触发点之一（另一个是 show() 内部的兜底调用）。
    ///
    /// 为什么在这个时机播放：viewDidAppear 表示视图已经进入屏幕层级且完成布局，
    /// 此时动画的位移与透明度变化才真正可见；若在 viewDidLoad 里播，
    /// 动画会赶在视图上屏之前跑完（或被首帧吞掉），用户看不到过程。
    ///
    /// 用 isPresenting 做守卫的原因：window 模式下 show() 会在 windowManager 完成上屏
    /// 之后继续同步调用一次 presentDialog，而 window 上屏又会异步触发本方法，
    /// 两条路径都需要"能发起入场"，靠这个标记做去重。
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isPresenting {
            presentDialog()
        }
    }

    /// 布局完成后校正滑动动画的起点（详见 SKDialogAnimationStateManager）。
    /// 只在入场动画尚未完成时生效（状态为 .initial）：此前 AutoLayout 每次求解都可能改变容器尺寸
    /// （内容变化、旋转、安全区变化），而"从屏幕外滑入"的距离取决于容器尺寸，必须跟着更新。
    /// 入场完成后状态推进为 .final，这里不再改写容器 transform，避免把它推回屏幕外。
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 在布局完成后，为自适应尺寸模式更新精确的滑动偏移量
        animationStateManager.updateSlideOffsetAfterLayout()
    }

    // MARK: - Public Methods

    /// 显示弹窗（展示入口）：按 `config.presentationMode` 自动选择展示方式。
    ///
    /// - `.window`：由 window 管理器自建 UIWindow 装载本控制器并上屏，随后发起入场动画
    /// - `.viewController(vc)`：由 vc 以 `animated: false` present（系统转场关闭，
    ///   视觉动画全部由库自绘），随后发起入场动画
    ///
    /// 这是与 `SKDialog` 构建器并列的另一种用法：继承本类后直接调用本方法即可展示，
    /// 不需要经过构建器。
    /// - Note: 刻意非 `open`：展示方式的差异请通过 `config.presentationMode` 表达；
    ///   覆写本方法会绕过 `isPresenting` 去重与两种模式的分发/收尾逻辑（window 回收、系统 dismiss）。
    ///   返回 `Self` 与是否 `open` 无关，子类照样能拿到自己的类型。
    ///
    /// - Parameter completion: **显示完成**回调（window 上屏后 / present 转场结束后触发）。
    ///   它不是关闭回调——需要"关闭后执行"的逻辑请用 `addCompletionHandler(_:)` 或
    ///   `dismissDialog(completion:)`；window 创建失败（例如无可用 scene）时同样会被调用，
    ///   保证"调用必回调"。
    /// - Returns: self，便于链式书写（子类可拿到自己的类型）。
    /// - Note: 入场动画统一由 `presentDialog()` 发起，它有 `isPresenting` 去重，
    ///   因此 viewDidAppear 与本方法内的兜底调用不会重复播放动画。
    @discardableResult
    public func show(completion: (() -> Void)? = nil) -> Self {
        switch config.presentationMode {
        case .window:
            // window 管理器负责：建 window → 装载本控制器 → 上屏 → 调用 completion
            windowManager.showInWindow(completion: completion)
            // window 上屏会异步触发 viewDidAppear → presentDialog；
            // 这里同步再发起一次兜底（isPresenting 去重），覆盖
            // "已上屏但 viewDidAppear 尚未回调"的边缘时序，保证入场一定会被发起
            presentDialog()
        case .viewController(let viewController):
            // 使用指定的视图控制器显示（animated: false 禁用系统转场，
            // 入场动画完全由库控制，避免与系统转场叠加）
            viewController.present(self, animated: false) {
                completion?()
                self.presentDialog()
            }
        }
        return self
    }

    /// 消失弹窗（播放退场动画后按显示模式收尾）。
    ///
    /// - Parameter completion: 关闭完成的回调闭包，默认为nil
    ///
    /// 两种收尾路径：
    /// - window 模式：隐藏并释放自建 window（window 持有控制器，必须在这里解开），
    ///   随后触发 completionHandler 与传入的 completion
    /// - viewController 模式：走 `dismiss(animated: false)`，系统转场同样禁用，
    ///   视觉上只保留库自绘的退场动画；dismiss 的 completion 里再触发上述两个回调
    /// - `case .none`：`self` 已被释放时（回调闭包捕获的是 weak self）走这里，
    ///   仅调用传入的 completion，保证调用方的等待流程不会悬空
    ///
    /// 未处于显示状态时直接回调：保证"调用 dismiss 一定会收到完成通知"，
    /// 宿主因此不必自己判断当前状态。
    /// - Note: 刻意非 `open`：本类全部关闭路径（背景点击 / 拖拽 / `UIView.closeSKDialog()` /
    ///   `dismiss()`）都收敛到这一份收尾实现，覆写会让这些路径一起被替换；漏调 super 还会残留
    ///   `isPresenting` 状态、导致 window 无法释放。需要"关闭前拦截"请在调用方判断后再决定是否调用。
    public func dismissDialog(completion: (() -> Void)? = nil) {
        guard isPresenting else { 
            completion?()
            return 
        }
        isPresenting = false

        // 通知动画即将开始
        dismissAnimationWillStartHandler?()

        animationManager.performDismissAnimation(
            backgroundView: backgroundView,
            containerView: containerView,
            config: config
        ) { [weak self] in
            // 通知动画已完成
            self?.dismissAnimationDidFinishHandler?()

            // 根据显示模式进行不同的处理
            switch self?.config.presentationMode {
            case .window:
                // 自建 window 由管理器回收（同时把 key window 还给原窗口）
                self?.hideCustomWindow()
                // 与 viewController 分支保持一致：收尾后触发 completionHandler，
                // 使 addCompletionHandler(_:) 注册的回调在 window 模式下同样会被执行
                self?.completionHandler?()
                completion?()
            case .viewController(_):
                // 控制器模式：交给系统 dismiss，转场动画关闭（视觉已由自绘动画完成）
                self?.dismiss(animated: false) {
                    self?.completionHandler?()
                    completion?()
                }
            case .none:
                // self 已释放：没有视图需要清理，直接回调
                completion?()
                break
            }

            // 及时清理所有回调，避免内存泄漏
            self?.completionHandler = nil
            self?.dismissAnimationWillStartHandler = nil
            self?.dismissAnimationDidFinishHandler = nil
        }
    }

    /// 简化的消失方法，兼容旧版本API。
    /// - Note: 刻意非 `open`：它只是 `dismissDialog()` 的转发壳，覆写它会让
    ///   "背景点击 / 拖拽关闭"与"主动关闭"两条路径行为分叉。
    public func dismiss() {
        dismissDialog()
    }

    /// 添加内容视图到容器（四边贴合）。
    ///
    /// 为什么是四边贴合而不是给定尺寸：容器的"内容自适应"正是靠这条约束链实现的——
    /// contentView 的内在尺寸（或它自己的子约束）会经由四边约束传递给容器，
    /// AutoLayout 据此决定容器大小。因此内容视图若没有任何内在尺寸，
    /// 容器会退化为 0 尺寸。
    ///
    /// - Note: 可以多次调用，但每次都是 addSubview，**不会**移除上一个内容视图
    ///   （多个内容会叠加在一起）。替换内容需要宿主自行处理旧视图。
    /// - Note: 刻意非 `open`：装配面只有一个——需要包装/装饰内容时，请在外面包好后传入本方法，
    ///   或直接对公开的 `containerView` 操作。
    public func addContentView(_ contentView: UIView) {
        containerView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    /// 添加完成回调到现有回调链中（组合而非替换）。
    ///
    /// 实现方式是把新回调包在旧回调之后执行，因此多次调用会形成
    /// "先注册的先执行"的串行链；每个回调都会被执行，除非其中途销毁了控制器。
    /// - Parameter additionalCompletion: 要添加的额外完成回调
    public func addCompletionHandler(_ additionalCompletion: @escaping () -> Void) {
        let originalCompletion = self.completionHandler
        self.completionHandler = {
            originalCompletion?()
            additionalCompletion()
        }
    }

    // MARK: - Container Size Update Methods

    /// 动态更新容器高度。
    ///
    /// 控制器只做转发：真正的三步（改约束、回写配置、动画布局）都在尺寸管理器里，
    /// 这样宿主既能通过控制器调用，也能从构建器返回的控制器实例上直接操作。
    /// - Parameters:
    ///   - height: 新的高度值
    ///   - animated: 是否使用动画过渡，默认为 true
    /// - Note: 此方法会同步更新 config.sizeMode 以保持配置一致性
    public func updateContainerHeight(_ height: CGFloat, animated: Bool = true) {
        containerSizeManager.updateContainerHeight(height, animated: animated)
    }

    /// 动态更新容器宽度。
     /// - Parameters:
     ///   - width: 新的宽度值
     ///   - animated: 是否使用动画过渡，默认为 true
     /// - Note: 此方法会同步更新 config.sizeMode 以保持配置一致性
     public func updateContainerWidth(_ width: CGFloat, animated: Bool = true) {
         containerSizeManager.updateContainerWidth(width, animated: animated)
     }

     /// 动态更新容器尺寸（宽度和高度）。
     /// 一次事务内同时改两个方向，因此只会产生一段过渡动画，而不是先宽后高的两段。
     /// - Parameters:
     ///   - width: 新的宽度值
     ///   - height: 新的高度值
     ///   - animated: 是否使用动画过渡，默认为 true
     /// - Note: 此方法会同步更新 config.sizeMode 为 .fixed 模式
     public func updateContainerSize(width: CGFloat, height: CGFloat, animated: Bool = true) {
         containerSizeManager.updateContainerSize(CGSize(width: width, height: height), animated: animated)
     }
}

// MARK: - Internal

extension SKDialogViewController {

    /// 播放弹窗的入场动画（内部入口，不负责上屏）。
    ///
    /// 调用时机：`show()` 发起展示之后（window 已上屏 / present 已完成），以及
    /// `viewDidAppear`；两条路径都会先经过 `isPresenting` 去重，保证只播一次。
    /// 它假设视图已经在屏幕层级里——对外展示请用 `show()`，单独调用它既不会建 window、
    /// 也不会 present。
    ///
    /// 时序：先触发 "will start" 回调（宿主可在此做数据准备），再执行动画，
    /// 动画结束时更新内部状态、触发 "did finish" 回调，并立刻清空这两个回调。
    /// 提前置 isPresenting = true 的作用是让重复调用直接返回，
    /// 避免同一弹窗被连续 present 两次（动画会互相打断）。
    func presentDialog() {
        guard !isPresenting else { return }
        isPresenting = true

        // 通知动画即将开始
        presentAnimationWillStartHandler?()

        animationManager.performPresentAnimation(
            backgroundView: backgroundView,
            containerView: containerView,
            config: config
        ) { [weak self] in
            // 推进动画状态机到 .final：此后布局不再重设滑动起点。
            // 若不推进（状态一直停在 .initial），弹窗显示后任何一次布局都会把容器推回屏幕外，
            // 详见 SKDialogAnimationStateManager 的说明
            self?.animationStateManager.markAnimationCompleted()
            // 通知动画已完成
            self?.presentAnimationDidFinishHandler?()
            // 及时清理回调，避免内存泄漏
            // 回调通常捕获宿主的 self，若一直留着会延长宿主对象的生命周期；
            // 入场只发生一次，用完即弃是安全的
            self?.presentAnimationWillStartHandler = nil
            self?.presentAnimationDidFinishHandler = nil
        }
    }
}

// MARK: - Private

extension SKDialogViewController {

    /// 配置模态转场参数。
    /// - `.overFullScreen`：本控制器只覆盖不替换，需要让下层界面保持可见（遮罩是半透明的）。
    /// - `.crossDissolve`：仅在宿主以 `present(_:animated: true)` 使用本控制器时才会生效——
    ///   库内部一律用 `animated: false`，入场动画由 SKDialogAnimationManager 自绘，
    ///   避免系统转场与自绘动画叠加导致"双重动画"。
    private func setupViewController() {
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    /// 搭建视图层级与初始外观。
    ///
    /// addSubview 的顺序即 z 序：先加背景，后加容器，容器才能盖在遮罩之上。
    private func setupUI() {
        view.backgroundColor = UIColor.clear

        // 背景遮罩
        // alpha 从 0 开始：入场动画负责把它推到 1（淡入遮罩）
        backgroundView.backgroundColor = config.backgroundMaskColor
        backgroundView.alpha = 0
        view.addSubview(backgroundView)

        // 容器视图
        containerView.backgroundColor = config.containerBackgroundColor
        containerView.layer.cornerRadius = config.cornerRadius
        view.addSubview(containerView)

        // 阴影效果
        // 只有开启阴影时才写图层属性：maskToBounds = false 是阴影可见的前提
        //（shadow 会被图层裁剪掉），同时也意味着容器不会把子视图裁进圆角内
        if config.showShadow {
            containerView.layer.masksToBounds = false
            containerView.layer.shadowColor = config.shadowColor.cgColor
            containerView.layer.shadowOffset = config.shadowOffset
            containerView.layer.shadowRadius = config.shadowRadius
            containerView.layer.shadowOpacity = config.shadowOpacity
        }

        // 根据动画类型预设容器视图的初始状态，避免闪现问题
        // 必须在布局之前完成：这样首帧渲染出的就是"起点状态"，而不是最终位置
        animationStateManager.setupInitialAnimationState()
    }

    /// 隐藏自定义Window
    private func hideCustomWindow() {
        windowManager.hideCustomWindow()
    }
}
