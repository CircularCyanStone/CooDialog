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
// 1. 共享的视图与状态（containerView / backgroundView / config / 显示状态与本类回调）
// 2. 生命周期编排（何时搭建 UI、何时播放入场动画、关闭时收尾）
// 3. 对外 API 的稳定门面（转发给管理器，宿主无需感知内部拆分）
// 管理器之间的依赖必须单向且无环：目前只有"尺寸管理器 → 约束管理器"这一条
//（尺寸变更必须落到约束上，这是二者本征的协作方向，且不构成环）。
// 视图、配置、展示状态等跨管理器共享的对象仍一律通过控制器协作；
// 但某个管理器的内部状态（例如约束引用）不再提升到控制器上——那会让同一份状态出现两个维护者。
// 对应地，SKDialogConstraintManager 持有约束引用与账本（containerConstraints），
// 并对尺寸管理器开放 setContainerWidth / setContainerHeight 作为唯一的修改入口。
//
// 展示与动画的分界（两条线各自只有一个归属，读代码时按这个顺序看）：
// - "怎么上屏"全部在 show()：两种模式只差"由谁来 present 本控制器"（见 presentationHost()），
//   确定宿主之后就只剩一句 host.present，差异被压到最小
// - "什么时候播入场动画"只有 viewDidAppear：视图上屏是 UIKit 的事件，
//   走哪条展示路径都会走到它，因此不需要在别处补兜底调用
//
// 生命周期关键时序（理解本文件的主线）：
// init(config:) → viewDidLoad（建 UI → 建约束 → 装手势 → 预置动画起点）
// → show()（确定宿主 → present，只负责上屏）
// → viewDidAppear（触发 presentDialog，播入场动画）
// → viewDidLayoutSubviews（动画开始前校正滑动起点）
// → dismissDialog（退场动画 → 摘掉 present 关系 → 回收自建 window → 触发关闭回调）

import UIKit

/// 弹窗基础控制器
///
/// 对外以 `open` 暴露：宿主可以继承它覆写生命周期方法，并用公开的 `containerView` / `config` /
/// 各动画回调做定制。
/// 扩展面刻意止步于此——核心流程（`show` / `dismissDialog` / `addContentView`）只可调用、不可覆写：
/// 展示方式由 `config.presentationMode` 表达，覆写它们会绕过 `isPresenting` 去重、window 回收等内部时序，
/// 而这些时序正是本类对外契约（回调必触发、window 必释放）的保障。
/// 唯一的例外是 UIKit 签名的 `dismiss(animated:completion:)`：它被覆写成"收口到 `dismissDialog()`"
/// （不覆写的话，那个签名会绕过全部收尾，详见方法说明），子类无需也不应再动它。
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

    /// Window模式管理器：自建 window 的创建、配置、上屏与回收。
    /// 唯一不需要引用 self 的管理器——它需要的窗口层级由调用方按参数传入
    /// （见 presentationHost()），因此不必 lazy，也不参与上面那条"构造时序"的约定。
    private let windowManager = SKDialogWindowManager()

    /// 容器尺寸管理器：运行时动态改尺寸（计算内容尺寸 + 动画过渡 + 回写配置）。
    /// 约束的落地（改 constant / 补建 / 登记）全部交给它依赖的约束管理器，
    /// 因此本管理器不再需要控制器暴露任何约束引用。这里访问另一个 lazy 属性是允许的
    /// （lazy 初始化器在首次访问时求值，此刻 self 已完全初始化，约束管理器会按需先建好）。
    private lazy var containerSizeManager: SKDialogContainerSizeManager = SKDialogContainerSizeManager(
        viewController: self,
        constraintManager: self.constraintManager
    )

    /// 容器视图：承载宿主提供的内容，圆角/阴影/动画都作用在它身上。
    /// 公开为 let（引用不可变、对象可变）：宿主可在外层做进一步视觉定制；
    /// 同时它也是各管理器共享的协作点（约束、手势、动画都直接引用同一实例）。
    public let containerView: UIView = UIView()

    /// 背景遮罩视图：铺满整个控制器 view，负责拦截点击与提供视觉压暗
    public let backgroundView: UIView = UIView()

    /// 是否正在显示（含入场动画中）。
    /// 用途：viewDidAppear 与 show() 都可能发起入场，用它保证入口只被真正执行一次；
    /// 同时作为 dismissDialog 的前置条件。
    private var isPresenting = false

    /// 弹窗关闭完成回调（两种显示模式语义一致：退场动画结束、收尾动作已执行之后）。
    /// 执行时机：退场动画结束的那一刻，此时自建 window（若有）已隐藏、key window 已归还，
    /// 弹窗即将从宿主上摘除（系统的 dismiss 要到下一次 runloop 才完全落定，
    /// 因此回调内读 `presentingViewController` / `view.window` 可能还是旧值——本库的契约
    /// 只承诺"视觉上已消失、window 与 key 状态已收尾"，不承诺那两个属性已刷新）。
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

    /// 入场动画的触发点（**唯一**的一个）。
    ///
    /// 为什么在这个时机播放：viewDidAppear 表示视图已经真正出现在屏幕上、且这一轮布局已完成，
    /// 此时位移与透明度变化才看得见；若在 viewDidLoad 里播，动画会赶在视图上屏之前跑完
    ///（或被首帧吞掉），用户看不到过程。放在这里还有个附带好处：无论宿主是走 `show()`
    /// 还是自己 present 本控制器，只要视图上屏就一定会走到，不需要在别处补触发点。
    ///
    /// 为什么还要 `isPresenting` 守卫：viewDidAppear 不是"只来一次"的回调——
    /// 弹窗被别的界面盖住又重新露出、或关闭后再次展示时都会再触发一次，
    /// 而入场动画只应播一次（重复播会让动画互相打断）。
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

    /// 显示弹窗（展示入口）。
    ///
    /// 两种模式的差异只有一处：**由谁来 present 本弹窗**。
    /// - `.window`：由 window 管理器自建一个 UIWindow（层级最高、不依赖宿主 VC），
    ///   并在其中准备一个透明宿主控制器
    /// - `.viewController(vc)`：直接用宿主指定的控制器
    ///
    /// 确定宿主之后，展示动作只有一句 `host.present(self, animated: false)`——
    /// 系统转场关闭，视觉动画完全由库自绘（见 `SKDialogAnimationUtils`）。
    ///
    /// 这是与 `SKDialog` 构建器并列的另一种用法：继承本类后直接调用本方法即可展示，
    /// 不需要经过构建器。
    /// - Note: 刻意非 `open`：展示方式的差异请通过 `config.presentationMode` 表达；
    ///   覆写本方法会绕过 `isPresenting` 去重与收尾逻辑（window 回收、系统 dismiss）。
    ///   返回 `Self` 与是否 `open` 无关，子类照样能拿到自己的类型。
    ///
    /// - Parameter completion: **显示完成**回调（present 转场结束后触发，window 模式同样如此）。
    ///   它不是关闭回调——需要"关闭后执行"的逻辑请用 `addCompletionHandler(_:)` 或
    ///   `dismissDialog(completion:)`；**无法展示时同样会被调用**，保证"调用必回调"，
    ///   覆盖 window 创建失败（无可用 scene）、宿主已 present 其它控制器、
    ///   以及宿主的视图尚未进入 window 层级三种情形。
    /// - Returns: self，便于链式书写（子类可拿到自己的类型）。
    /// - Note: **本方法不发起入场动画**，只负责把视图弄上屏。入场动画统一由
    ///   `viewDidAppear` 触发（见 `presentDialog()`），因此"视图何时真正上屏"与
    ///   "动画何时开始"是两个职责，各自只有一个归属，不需要在多个时机兜底。
    @discardableResult
    public func show(completion: (() -> Void)? = nil) -> Self {
        // 拿不到可用宿主时同样要回调：宿主既看不到弹窗、也收不到通知是最糟的结果
        //（UIKit 拒绝 present 时不会调用 completion），见 presentationHost() 的两个前置条件。
        guard let host = presentationHost() else {
            #if DEBUG
            print("SKDialog: 无法展示弹窗（宿主已 present 其它控制器、视图尚未进入 window 层级，或没有可用的 UIWindowScene）")
            #endif
            completion?()
            return self
        }

        host.present(self, animated: false) { completion?() }
        return self
    }

    /// 消失弹窗（播放退场动画后收尾）。
    ///
    /// - Parameter completion: 关闭完成的回调闭包，默认为nil
    ///
    /// 收尾时机：**退场动画结束的那一刻**（此时弹窗在视觉上已经消失），
    /// 之后按固定顺序做三件事，两种模式共用同一条路径：
    /// 1. 把弹窗从宿主上摘下来（`dismiss(animated: false)`，系统转场关闭，
    ///    视觉上只保留库自绘的退场动画）
    /// 2. `.window` 模式额外回收自建 window（连同 key window 的归还；其它模式为空操作）
    /// 3. 触发"关闭完成"回调
    /// 顺序不能颠倒：先摘掉 present 关系、再拆 window，环才是从里到外解开的；
    /// 回调放在最后，宿主读到的 window / key 状态已经是收尾后的
    /// （但系统 dismiss 的移除要到下一次 runloop 才落定，所以那一步的"关系解除"
    ///  可能比回调晚一瞬——这是刻意不依赖系统时序的代价，也是它的意义所在）。
    /// - `case .none`：`self` 已被释放时（回调闭包捕获的是 weak self）走这里，
    ///   仅调用传入的 completion，保证调用方的等待流程不会悬空
    ///
    /// 为什么回调不挂在系统 `dismiss` 的 completion 上：
    /// 那个 completion 何时回调由 UIKit 决定（转场排队时会延后，环境异常时甚至不会回调）。
    /// 一旦"清理"与"触发"不在同一个同步块里，就会出现"先清空、后触发"——回调永久丢失，
    /// 且同一个 API 在两种模式下表现不一致。现在的写法不依赖任何系统时序。
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
            guard let self else {
                // self 已释放：没有视图需要清理，直接回调调用方
                completion?()
                return
            }

            // 通知动画已完成
            self.dismissAnimationDidFinishHandler?()

            // 收尾：先摘掉 present 关系，再回收自建 window，最后才通知宿主
            self.dismissFromHost()
            self.removeCustomWindowIfNeeded()
            self.finishDismiss(completion: completion)
        }
    }

    /// 简化的消失方法，兼容旧版本API。
    /// - Note: 刻意非 `open`：它只是 `dismissDialog()` 的转发壳，覆写它会让
    ///   "背景点击 / 拖拽关闭"与"主动关闭"两条路径行为分叉。
    public func dismiss() {
        dismissDialog()
    }

    /// 关闭弹窗（UIKit 签名），收口到 `dismissDialog()`。
    ///
    /// 为什么必须覆写：本类的关闭入口有两个"名字"——`dismiss()`（旧 API）与本方法（UIKit 签名）。
    /// 不覆写时，`dialog.dismiss(animated: true)` 会走到 UIKit 的实现，而那是个静默陷阱：
    /// - window 模式：控制器是自建 window 的 rootViewController、并没有被谁 present，
    ///   UIKit 的实现找不到可以 dismiss 的对象，**什么都不做**（弹窗不关，也不报错）
    /// - `.viewController` 模式：控制器确实会被移除，但完全绕过本类的收尾——
    ///   完成回调丢失、`isPresenting` 残留、window 引用环（window → 控制器 → windowManager → window）
    ///   不会被打断
    /// 覆写后两种写法都收敛到同一条收尾路径，与背景点击 / 拖拽关闭的行为一致。
    ///
    /// - Note: `animated` 仅用于与 UIKit 签名对齐——退场动画由本库自绘，系统转场一律关闭
    ///   （与 `show()` 里 present 时使用 `animated: false` 对称）。
    ///   需要"关闭后执行"的逻辑请用 `completion`，或 `addCompletionHandler(_:)` 追加。
    open override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissDialog(completion: completion)
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
    ///   （`.contentAdaptive` 除外：自适应弹窗只被临时钉住高度，模式本身不变，
    ///   内容变大时仍能把它撑开——补建的约束优先级低于内容的固有尺寸诉求）
    public func updateContainerHeight(_ height: CGFloat, animated: Bool = true) {
        containerSizeManager.updateContainerHeight(height, animated: animated)
    }

    /// 动态更新容器宽度。
    /// - Parameters:
    ///   - width: 新的宽度值
    ///   - animated: 是否使用动画过渡，默认为 true
    /// - Note: 此方法会同步更新 config.sizeMode 以保持配置一致性（`.contentAdaptive` 除外，同 `updateContainerHeight`）
    public func updateContainerWidth(_ width: CGFloat, animated: Bool = true) {
        containerSizeManager.updateContainerWidth(width, animated: animated)
    }

    /// 动态更新容器尺寸（宽度和高度）。
    /// 一次事务内同时改两个方向，因此只会产生一段过渡动画，而不是先宽后高的两段。
    /// - Parameters:
    ///   - width: 新的宽度值
    ///   - height: 新的高度值
    ///   - animated: 是否使用动画过渡，默认为 true
    /// - Note: 此方法会把 config.sizeMode 收敛为 `.fixed`（三个尺寸回写入口共用这一条规则）；
    ///   `.contentAdaptive` 除外，与上面两个方法一致
    public func updateContainerSize(width: CGFloat, height: CGFloat, animated: Bool = true) {
        containerSizeManager.updateContainerSize(CGSize(width: width, height: height), animated: animated)
    }
}

// MARK: - Internal

extension SKDialogViewController {

    /// 播放弹窗的入场动画（内部入口，不负责上屏）。
    ///
    /// 调用时机：**只有 `viewDidAppear` 一处**——视图真正出现在屏幕上时。
    /// 它假设视图已经在屏幕层级里：对外展示请用 `show()`，单独调用它既不会建 window、
    /// 也不会 present；反过来，把视图弄上屏这件事也不该由它承担（两件事各有唯一归属）。
    ///
    /// 时序：先触发 "will start" 回调（宿主可在此做数据准备），再校正并冻结滑动起点，
    /// 最后执行动画；动画**正常结束**时更新内部状态、触发 "did finish" 回调，并立刻清空这两个回调；
    /// 若入场被打断（弹窗在入场途中被关闭），则只推进内部状态、不触发 "did finish"
    /// （此时弹窗已进入关闭流程，再报告"显示完成"会误导宿主）。
    /// 提前置 isPresenting = true 的角色有两层：既是"重复调用直接返回"的闸门，
    /// 也是"弹窗是否处于展示中"的状态（dismissDialog 的前置条件、是否报告 did finish 都看它）。
    func presentDialog() {
        guard !isPresenting else { return }
        isPresenting = true

        // 通知动画即将开始
        presentAnimationWillStartHandler?()

        // 起点校正的最后一次机会，然后立刻冻结：必须先校正（此刻容器尺寸已由约束求解确定），
        // 再切到 .animating 让后续布局不再触碰 transform。
        // 这一步是必需的——动画期间任何一次布局（宿主回填尺寸、内容异步撑开、旋转）都会走到
        // SKDialogViewController.viewDidLayoutSubviews → updateSlideOffsetAfterLayout()，
        // 若状态仍是 .initial，那里会直接改写 containerView.transform，
        // 从而取消正在播放的 UIView 动画并把容器永久留在屏幕外（弹窗再也看不见）。
        animationStateManager.updateSlideOffsetAfterLayout()
        animationStateManager.markAnimationStarted()

        animationManager.performPresentAnimation(
            backgroundView: backgroundView,
            containerView: containerView,
            config: config
        ) { [weak self] in
            // 推进动画状态机到 .final：此后布局不再重设滑动起点。
            // 若不推进（状态一直停在 .initial），弹窗显示后任何一次布局都会把容器推回屏幕外，
            // 详见 SKDialogAnimationStateManager 的说明
            self?.animationStateManager.markAnimationCompleted()
            // 通知动画已完成——但只在弹窗仍处于展示中时通知：
            // 入场动画被打断时（用户在 0.3 秒内点了遮罩、或代码紧接着调用了 dismissDialog）
            // 这个回调同样会到达，而此刻弹窗已经进入关闭流程。注意上一行的状态推进
            // 不能跟着一起跳过：markAnimationCompleted 是布局校正的开关。
            if self?.isPresenting == true {
                self?.presentAnimationDidFinishHandler?()
            }
            // 及时清理回调，避免内存泄漏
            // 回调通常捕获宿主的 self，若一直留着会延长宿主对象的生命周期；
            // 入场只发生一次，用完即弃是安全的
            self?.presentAnimationWillStartHandler = nil
            self?.presentAnimationDidFinishHandler = nil
        }
    }

    /// 自检：尺寸约束与 `config.sizeMode` 是否一致、引用与账本是否同源（调试 / 测试用）。
    /// 实现完全委托给 SKDialogConstraintManager——约束的账本在它手里，控制器只做转发。
    var isSizeConstraintsValid: Bool {
        constraintManager.isSizeConstraintsValid
    }

    /// 强制刷新尺寸（调试 / 测试用）：立即重排一次，自适应模式下再按内容重新贴合。
    /// 同样只做转发，实现见 SKDialogContainerSizeManager.forceRefreshSize。
    func forceRefreshSize() {
        containerSizeManager.forceRefreshSize()
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

    /// 为本次展示确定"由谁来 present 本弹窗"，并确认它当前确实可用。
    ///
    /// 两种模式**唯一**的差异就在这个方法的开头：window 模式现造一个宿主
    /// （顺带把自建 window 建好上屏），viewController 模式用宿主给的那个。
    /// 之后的判断与展示动作完全共用。
    ///
    /// - Returns: 可用的宿主；`nil` 表示这次展示无法进行，`show()` 会走"调用必回调"的失败路径。
    ///   失败有三种可能：没有可用的 UIWindowScene（window 模式）、宿主的视图还没进入 window 层级、
    ///   宿主已经 present 了别的控制器——后两种 UIKit 都会直接拒绝 present 且不回调。
    private func presentationHost() -> UIViewController? {
        let host: UIViewController
        switch config.presentationMode {
        case .window:
            guard let windowHost = windowManager.makeHostForPresentation(windowLevel: config.windowLevel) else { return nil }
            host = windowHost
        case .viewController(let given):
            host = given
        }

        // 注：访问 host.view 会让尚未加载的视图开始加载，与 UIKit 在 present 内部的行为一致
        guard host.view.window != nil, host.presentedViewController == nil else { return nil }
        return host
    }

    /// 回收自建 window（非 window 模式时为空操作）。
    private func removeCustomWindowIfNeeded() {
        guard case .window = config.presentationMode else { return }
        windowManager.removeCustomWindow()
    }

    /// 把弹窗从宿主上摘下来（两种模式的收尾终点）。
    ///
    /// 为什么单独成一个方法：`dismiss(animated:completion:)` 已被本类覆写为"收口到 dismissDialog"，
    /// 而这里的调用点在动画的逃逸闭包里——闭包内不能写 `super`，若写成 `self.dismiss(...)`
    /// 会再次进入覆写实现、无限递归。以实例方法的身份转发到 `super` 才能绕开覆写。
    ///
    /// - Note: 只摘 present 关系，不负责回收 window——顺序上必须先做这一步，
    ///   环（window → 宿主 → 弹窗 → windowManager → window）才是从里到外解开的。
    private func dismissFromHost() {
        super.dismiss(animated: false)
    }

    /// 关闭收尾：触发"关闭完成"相关的两个回调，然后清空一次性回调。
    ///
    /// 为什么"清理"必须收敛在这里、而不是交给系统 `dismiss` 的 completion：
    /// 那个 completion 何时回调由 UIKit 决定（转场排队时会延后，环境异常时甚至不会回调）。
    /// 一旦"触发"与"清理"不在同一个同步块里，就会出现"先清空、后触发"——回调永久丢失，
    /// 且同一个 API 在两种模式下表现不一致。收敛到本方法后，两条路径都是"先回调、后清理"。
    private func finishDismiss(completion: (() -> Void)?) {
        completionHandler?()
        completion?()

        completionHandler = nil
        dismissAnimationWillStartHandler = nil
        dismissAnimationDidFinishHandler = nil
        // 入场回调正常已在 presentDialog 完成时清空；若入场被打断（尚未清空），这里一并回收
        presentAnimationWillStartHandler = nil
        presentAnimationDidFinishHandler = nil
    }
}
