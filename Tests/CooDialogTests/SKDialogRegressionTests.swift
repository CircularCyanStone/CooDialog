import Testing
import UIKit
@testable import CooDialog

/// 本轮代码评审修复项对应的回归测试。
///
/// 与 `SKDialogBehaviourTests` 的分工：那个文件覆盖"配置项与状态机曾经失效"的长期契约，
/// 这里覆盖本轮评审新修/新加的行为，每条都对应一个可观察的现象：
/// 1. 遮罩约束不能从账本里"消失"（历史上重建位置约束时会把遮罩约束一起丢掉）
/// 2. `.viewController` 模式下 present 被系统拒绝时，show 的完成回调仍然要回调
/// 3. `.viewController` 模式下关闭弹窗，两个"关闭完成"回调都必须触发（不能因清理时机而丢）
/// 4. 入场动画被打断时不报告"显示完成"，正常完成时仍然报告
/// 5. 面板拖拽要让位给内容里的可滚动列表（列表到顶时才由面板接管）
/// 6. 入场动画进行中的布局不得把容器改写回屏幕外（否则滑动动画被打断、弹窗永久消失）
/// 7. 自适应弹窗被动态改尺寸后，内容变大仍能把它撑开（配置与约束两层语义一致）
/// 8. 滑动距离按容器在父视图中的实际位置算：居中弹窗的起点也要完全在屏幕外；
///    拖拽后关闭时算出的正是"还差多少"，不会对拖拽位移视而不见
/// 9. `dismiss(animated:)` 必须收口到库的收尾（否则两种模式的回调与 window 回收都会丢）
/// 10. 展示链路统一：两种模式都归结为"由某个控制器 present 弹窗"，
///     `.window` 只是多准备了一个自建 window 与其宿主，不再是另一套上屏机制
///
/// - Note: 与 present 相关的用例需要一个"视图已进入窗口层级"的宿主控制器，
///   否则 UIKit 会直接拒绝 present（见第 2 组用例），因此这里用 UIWindow 现搭一个环境。
/// - Note: window 模式的**成功**路径无法在这里覆盖——测试宿主没有 UIWindowScene，
///   `presentationHost()` 里的自建 window 必然失败。那条链路需要跑 Examples 下的示例工程验证。
@MainActor
struct SKDialogRegressionTests {

    // MARK: - 公共构造

    /// 构造一个已装配内容的弹窗控制器（不展示），并给它一个确定的画布尺寸。
    /// - Note: 显式设置 `view.frame` 是因为测试环境没有窗口，AutoLayout 需要一个确定的画布
    ///   才能算出容器与内容的真实 frame（拖拽准入的命中判定依赖它）。
    private func makeDialog(
        contentSize: CGSize = CGSize(width: 300, height: 200),
        configure: (inout SKDialogConfig) -> Void = { _ in }
    ) -> (dialog: SKDialogViewController, content: UIView) {
        var config = SKDialogConfig()
        config.animationDuration = 0.05          // 缩短动画时长，让测试等待更短
        config.springDamping = 1                // 无回弹，便于断言最终状态
        configure(&config)

        // 内容尺寸约束用低优先级：模拟"内容只是希望这么大"，
        // 这样其它测试改容器尺寸时不会与内容约束产生冲突日志
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        let contentWidth = content.widthAnchor.constraint(equalToConstant: contentSize.width)
        let contentHeight = content.heightAnchor.constraint(equalToConstant: contentSize.height)
        contentWidth.priority = .defaultLow
        contentHeight.priority = .defaultLow
        NSLayoutConstraint.activate([contentWidth, contentHeight])

        let dialog = SKDialogViewController(config: config)
        dialog.addContentView(content)
        dialog.loadViewIfNeeded()               // 触发 viewDidLoad：建视图、约束、手势、预置动画状态
        dialog.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        dialog.view.layoutIfNeeded()
        return (dialog, content)
    }

    /// 构造一个已上屏（view 处于窗口层级）的宿主控制器。
    /// - Note: 只在测试内使用 `isHidden = false` 而不抢 key window，避免影响其它用例。
    private func makeHostInWindow() -> (host: UIViewController, window: UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return (host, window)
    }

    /// 等待动画结束（留出充裕余量）
    private func waitForAnimation() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    /// 从容器上的拖拽手势反查手势处理器（delegate 即处理器自身），供准入判定测试直接调用
    private func panHandler(of dialog: SKDialogViewController) -> SKDialogGestureHandler? {
        dialog.containerView.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first?
            .delegate as? SKDialogGestureHandler
    }

    // MARK: - 1. 遮罩约束

    @Test("遮罩始终铺满控制器视图：四条边约束齐全且处于激活状态")
    func backgroundViewStaysPinnedToEdges() {
        let (dialog, _) = makeDialog { $0.position = .bottom }

        #expect(dialog.backgroundView.superview === dialog.view)

        let edgeConstraints = dialog.view.constraints.filter { constraint in
            (constraint.firstItem === dialog.backgroundView || constraint.secondItem === dialog.backgroundView)
                && [.top, .bottom, .leading, .trailing].contains(constraint.firstAttribute)
        }

        // 修复前：一旦走"重建位置约束"的路径，遮罩的四条约束会被一起停用并丢弃，
        // 遮罩塌成 0 尺寸（既看不见也点不到）。这条断言把该不变量钉住。
        #expect(edgeConstraints.count == 4)
        #expect(edgeConstraints.allSatisfy { $0.isActive })
    }

    // MARK: - 2. present 被拒绝时的回调

    @Test("viewController 模式：宿主已 present 其它控制器时，show 的完成回调仍会被调用")
    func viewControllerModeReportsBusyHostThroughCompletion() {
        let (host, window) = makeHostInWindow()

        // 先占用宿主的 present 槽位：UIKit 会拒绝第二次 present，且不回调 completion
        host.present(UIViewController(), animated: false)
        #expect(host.presentedViewController != nil)

        let (dialog, _) = makeDialog { $0.presentationMode = .viewController(host) }

        var shown = false
        dialog.show { shown = true }

        // 弹窗确实没有被 present
        #expect(host.presentedViewController !== dialog)
        // 但"调用必回调"的约定成立（修复前这里收不到任何通知）
        #expect(shown)

        // 收尾：把占位控制器 dismiss 掉，避免影响其它用例
        host.dismiss(animated: false)
        window.isHidden = true
    }

    @Test("viewController 模式：宿主视图尚未进入窗口层级时，show 的完成回调仍会被调用")
    func viewControllerModeReportsDetachedHostThroughCompletion() {
        // 裸控制器：view 不在任何窗口里，UIKit 同样会拒绝 present 且不回调 completion
        let host = UIViewController()
        host.loadViewIfNeeded()

        let (dialog, _) = makeDialog { $0.presentationMode = .viewController(host) }

        var shown = false
        dialog.show { shown = true }

        #expect(host.presentedViewController !== dialog)
        #expect(shown)
    }

    // MARK: - 3. 控制器模式的关闭回调

    @Test("viewController 模式：关闭弹窗时 addCompletionHandler 与 dismiss 的完成回调都会触发")
    func viewControllerModeTriggersBothDismissCallbacks() async throws {
        let host = UIViewController()
        host.loadViewIfNeeded()

        let (dialog, _) = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        var handlerCallCount = 0
        dialog.addCompletionHandler { handlerCallCount += 1 }

        // 说明：本环境里系统的 present / dismiss 转场不会跑完（completion 永不回调、dismiss 不生效），
        // 所以这里直接发起入场再走真实的关闭流程。这恰好复现了修复目标——
        // 收尾若挂在系统 dismiss 的 completion 上，两个回调在这种时序下都会丢。
        dialog.presentDialog()
        try await waitForAnimation()

        var dismissCompletionCalled = false
        dialog.dismiss { dismissCompletionCalled = true }
        try await waitForAnimation()

        #expect(handlerCallCount == 1)
        #expect(dismissCompletionCalled)
    }

    // MARK: - 4. 入场被打断

    @Test("入场动画被打断（展示途中被关闭）时，不触发“显示完成”回调")
    func interruptedPresentationDoesNotReportFinish() {
        // 用"可手动结束"的动画替代真实动画，让时序完全确定：
        // 真实动画的完成时机在测试进程里不稳定（视图未真正上屏时可能被系统提前结算）
        let animation = ManualCompletionAnimation()
        let (dialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .custom(animation)
        }

        var didFinish = false
        dialog.presentAnimationDidFinishHandler = { didFinish = true }

        dialog.presentDialog()                  // 发起入场：动画被挂起，尚未结束
        dialog.dismiss()                  // 展示途中关闭：isPresenting 置为 false，退场立即收尾
        animation.finishPresentAnimation()      // 入场动画"这才结束"

        // 修复前：入场的完成回调照样触发 did finish，
        // 宿主的"启动轮询 / 自动聚焦"会在弹窗已经关闭时被执行
        #expect(didFinish == false)
    }

    @Test("入场动画正常完成时，仍然触发“显示完成”回调")
    func completedPresentationReportsFinish() {
        let animation = ManualCompletionAnimation()
        let (dialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .custom(animation)
        }

        var didFinish = false
        dialog.presentAnimationDidFinishHandler = { didFinish = true }

        dialog.presentDialog()
        animation.finishPresentAnimation()

        #expect(didFinish)
    }

    // MARK: - 5. 拖拽与滚动视图的协作

    @Test("拖拽准入：列表未到顶时让滚动优先，已到顶时才由面板接管")
    func panDefersToScrollableContent() {
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        scrollView.contentSize = CGSize(width: 300, height: 1000)   // 内容高于可视区 → 可纵向滚动

        let (dialog, content) = makeDialog { $0.position = .bottom }
        content.addSubview(scrollView)
        dialog.view.layoutIfNeeded()

        // 模拟"入场已完成"的稳定状态：容器可见且无位移。
        // 默认 fadeScale 的预置首帧会把 alpha 置 0，而 hitTest 对 alpha ≤ 0.01 的视图直接返回 nil。
        dialog.containerView.alpha = 1
        dialog.containerView.transform = .identity

        guard let handler = panHandler(of: dialog) else {
            Issue.record("拖拽手势或其 delegate 未装配，无法验证准入判定")
            return
        }

        let pointInsideScrollView = CGPoint(x: 150, y: 100)
        let downwardDrag = CGPoint(x: 0, y: 300)

        // 列表在顶部：向下已无内容可滚 → 面板接管（可下拉关闭）
        scrollView.contentOffset = .zero
        #expect(handler.shouldBeginPan(at: pointInsideScrollView, velocity: downwardDrag, position: .bottom))

        // 列表已滚动：还有内容可以向下滚 → 让滚动优先，面板不动
        scrollView.contentOffset = CGPoint(x: 0, y: 200)
        #expect(handler.shouldBeginPan(at: pointInsideScrollView, velocity: downwardDrag, position: .bottom) == false)

        // 横向滑动不接管（与"把面板拖出屏幕"无关）
        #expect(handler.shouldBeginPan(at: pointInsideScrollView, velocity: CGPoint(x: 300, y: 20), position: .bottom) == false)
    }

    @Test("拖拽准入：内容没有可滚动区域时，面板正常接管拖动")
    func panTakesOverWhenContentIsNotScrollable() {
        let (dialog, _) = makeDialog { $0.position = .bottom }

        // 同上：先让容器处于"入场已完成"的可见状态，否则 hitTest 会直接返回 nil，
        // 这条断言会以"命中失败"的形式意外通过
        dialog.containerView.alpha = 1
        dialog.containerView.transform = .identity

        guard let handler = panHandler(of: dialog) else {
            Issue.record("拖拽手势或其 delegate 未装配，无法验证准入判定")
            return
        }

        #expect(handler.shouldBeginPan(at: CGPoint(x: 150, y: 100), velocity: CGPoint(x: 0, y: 300), position: .bottom))
    }

    // MARK: - 6. 尺寸回写规则

    @Test("同时给出宽高的尺寸回写：自适应模式不被钉死，固定模式收敛为 .fixed")
    func sizeWriteBackRespectsAdaptiveMode() {
        // 自适应弹窗：只被临时钉住尺寸，模式本身仍是自适应（否则后续内容变化再也撑不开）
        let (adaptiveDialog, _) = makeDialog { $0.sizeMode = .contentAdaptive }
        adaptiveDialog.updateContainerSize(width: 250, height: 180, animated: false)
        #expect(adaptiveDialog.config.sizeMode == .contentAdaptive)

        // 单向固定：两个方向都定死之后收敛为 .fixed（这是"两方向都已有确定值"的准确表达）
        let (fixedWidthDialog, _) = makeDialog { $0.sizeMode = .fixedWidth(200) }
        fixedWidthDialog.updateContainerSize(width: 250, height: 180, animated: false)
        #expect(fixedWidthDialog.config.sizeMode == .fixed(width: 250, height: 180))
    }

    @Test("按内容重算尺寸（forceRefreshSize）不会把自适应弹窗钉成固定尺寸")
    func refreshingSizeKeepsAdaptiveMode() {
        let (dialog, _) = makeDialog { $0.sizeMode = .contentAdaptive }

        dialog.forceRefreshSize()

        // 修复前：这条路径会无条件回写 .fixed，一次"按内容重算"就把自适应弹窗永久钉死
        #expect(dialog.config.sizeMode == .contentAdaptive)
    }

    // MARK: - 7. 滑动距离（预置首帧与动画起点同源）

    @Test("滑动距离只有一套公式：预置首帧的位移与 slideOffset 完全一致")
    func slideOffsetIsSharedBetweenPresetAndAnimation() {
        let margins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let (dialog, _) = makeDialog { config in
            config.position = .bottom
            config.animationType = .slideFromBottom
            config.margins = margins
        }

        // 布局完成后 viewDidLayoutSubviews 会按真实尺寸校正起点
        dialog.view.layoutIfNeeded()

        // 先记下实际施加的位移，再按同一公式复算（量位置时会先把位移归零）
        let appliedTx = dialog.containerView.transform.tx
        let appliedTy = dialog.containerView.transform.ty
        let expected = SlideAnimation.slideOffset(
            for: .bottom,
            containerFrame: SlideAnimation.measureUnshiftedFrame(of: dialog.containerView),
            superviewBounds: dialog.view.bounds
        )

        #expect(abs(appliedTy - expected) < 0.001)
        // 纵向滑动不应带水平位移
        #expect(appliedTx == 0)
    }

    @Test("居中弹窗配滑动动画时，起点同样完全在屏幕外")
    func centeredDialogSlidesInFromOffscreen() {
        // 居中弹窗停在屏幕中央，旧公式（只看容器尺寸）算出的位移会让它留一半在屏幕内，
        // 看起来像"从屏幕中间飘出来"而不是滑进来
        let (bottomDialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .slideFromBottom
        }
        bottomDialog.view.layoutIfNeeded()
        #expect(bottomDialog.containerView.frame.minY >= bottomDialog.view.bounds.maxY)

        let (topDialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .slideFromTop
        }
        topDialog.view.layoutIfNeeded()
        #expect(topDialog.containerView.frame.maxY <= topDialog.view.bounds.minY)

        let (rightDialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .slideFromRight
        }
        rightDialog.view.layoutIfNeeded()
        #expect(rightDialog.containerView.frame.minX >= rightDialog.view.bounds.maxX)
    }

    @Test("拖拽后关闭：退场位移按容器当前位置现算，恰好把面板补送到屏幕外")
    func dismissAfterDragStillPushesPanelOffscreen() {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.animationType = .slideFromBottom
        }
        dialog.view.layoutIfNeeded()

        // 模拟"用户已经把面板向下拖了一段"（拖拽直接改 center，下一次布局前约束不会覆盖它）
        let originalCenter = dialog.containerView.center
        dialog.containerView.center = CGPoint(x: originalCenter.x, y: originalCenter.y + 30)

        // 退场位移按当前位置现算（量位置时会先把预置的起点位移归零；center 是拖拽结果，不归零）
        let frame = SlideAnimation.measureUnshiftedFrame(of: dialog.containerView)
        let offset = SlideAnimation.slideOffset(
            for: .bottom,
            containerFrame: frame,
            superviewBounds: dialog.view.bounds
        )

        // 终点 = 拖拽后的位置 + 位移，恰好落在父视图底边（不多推一个容器高，也不少推）
        // 旧公式对拖拽位移无感知，会按"容器高度 + 边距"多推，与这里的精确值不符
        #expect(abs((frame.minY + offset) - dialog.view.bounds.maxY) < 0.001)
    }

    @Test("预置位移作用在正确的轴上（左右滑动用 x，上下滑动用 y）")
    func slidePresetUsesCorrectAxis() {
        let (leftDialog, _) = makeDialog { $0.animationType = .slideFromLeft }
        leftDialog.view.layoutIfNeeded()
        #expect(leftDialog.containerView.transform.tx < 0)      // 从左侧进入 → 负位移
        #expect(leftDialog.containerView.transform.ty == 0)

        let (topDialog, _) = makeDialog { $0.animationType = .slideFromTop }
        topDialog.view.layoutIfNeeded()
        #expect(topDialog.containerView.transform.ty < 0)       // 从上方进入 → 负位移
        #expect(topDialog.containerView.transform.tx == 0)
    }

    // MARK: - 8. 入场动画期间发生布局

    @Test("入场动画进行中发生布局，滑动动画不被中断（容器不得停在屏幕外）")
    func layoutDuringPresentationDoesNotBreakSlideAnimation() async throws {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.animationType = .slideFromBottom
            $0.animationDuration = 0.5      // 拉长动画，"动画进行中"这个窗口足够宽
        }
        // 先布局一次，让起点基于真实尺寸算出来（等价于真实环境里 window 上屏后的首帧）
        dialog.view.layoutIfNeeded()

        dialog.presentDialog()

        // 模拟入场动画期间到来的一次布局：宿主回填尺寸、内容异步撑开、旋转都会走到这里
        dialog.view.setNeedsLayout()
        dialog.view.layoutIfNeeded()

        // 修复前：布局会把 transform 改写回屏幕外的起点，从而取消正在播放的动画，
        // 容器永久停在屏幕外（弹窗再也看不见），但"显示完成"回调照常触发
        #expect(dialog.containerView.transform == .identity)

        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(dialog.containerView.transform == .identity)
    }

    @Test("入场动画期间回填尺寸：尺寸变化生效，入场动画照常完成")
    func sizeBackfillDuringPresentationKeepsAnimation() async throws {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.animationType = .slideFromBottom
            $0.animationDuration = 0.5
        }
        dialog.view.layoutIfNeeded()

        var didFinish = false
        dialog.presentAnimationDidFinishHandler = { didFinish = true }

        dialog.presentDialog()
        dialog.updateContainerHeight(300)   // 异步内容回来了，宿主回填高度（动画进行中）

        try await Task.sleep(nanoseconds: 900_000_000)

        #expect(dialog.containerView.transform == .identity)
        #expect(abs(dialog.containerView.bounds.height - 300) < 0.001)
        #expect(didFinish)
    }

    // MARK: - 9. 自适应模式被动态改尺寸后仍可被内容撑开

    @Test("自适应弹窗被动态改尺寸后，内容变大仍能把它撑开")
    func adaptiveDialogStillGrowsWithContent() {
        let (dialog, content) = makeDialog { $0.sizeMode = .contentAdaptive }

        // 内容此时只有低优先级的尺寸诉求，容器约束压得住它 → "临时钉住"生效
        dialog.updateContainerHeight(150, animated: false)
        #expect(abs(dialog.containerView.bounds.height - 150) < 0.001)
        // 钉住的只是约束上的一个临时值，配置层面的模式仍然是自适应
        #expect(dialog.config.sizeMode == .contentAdaptive)

        // 内容获得了更强的尺寸诉求（例如异步加载完成的图片、固定高度的自定义视图）
        let tallContent = UIView()
        tallContent.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tallContent)
        NSLayoutConstraint.activate([
            tallContent.topAnchor.constraint(equalTo: content.topAnchor),
            tallContent.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tallContent.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tallContent.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tallContent.heightAnchor.constraint(equalToConstant: 400),
        ])

        dialog.view.setNeedsLayout()
        dialog.view.layoutIfNeeded()

        // 修复前：补建的高度约束是 required，容器被永久钉在 150，内容只会被压扁
        #expect(abs(dialog.containerView.bounds.height - 400) < 0.001)
    }

    // MARK: - 10. 关闭入口收口

    // MARK: - 11. 展示链路（两种模式共用同一条 present 路径）

    @Test("show() 把弹窗 present 到宿主上：present 关系是展示的唯一形态")
    func showPresentsDialogOntoHost() {
        let (host, window) = makeHostInWindow()
        let (dialog, _) = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        dialog.show()

        // 弹窗是被"宿主 present 出来"的，而不是被塞成某个容器的 root——
        // 这正是 window 模式与 viewController 模式的共同点（差异只在宿主是谁）。
        // - Note: 这里只验证 present 关系；"视图进窗口层级 → viewDidAppear → 入场动画"
        //   那一段依赖真实转场，测试宿主跑不完（转场不推进），需靠 Examples 的示例工程验证。
        #expect(dialog.presentingViewController === host)
        #expect(host.presentedViewController === dialog)

        host.dismiss(animated: false)
        window.isHidden = true
    }

    @Test("dismiss(animated:) 收口到库的关闭流程，不会绕过收尾")
    func systemDismissSignatureIsRoutedToLibraryTeardown() async throws {
        let host = UIViewController()
        host.loadViewIfNeeded()

        let (dialog, _) = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        var handlerCalled = false
        dialog.addCompletionHandler { handlerCalled = true }

        dialog.presentDialog()
        try await waitForAnimation()

        // 修复前：这个签名会走到 UIKit 的实现，两个"关闭完成"回调都会丢
        //（window 模式下更是静默什么都不做，弹窗根本不关）
        var completionCalled = false
        dialog.dismiss(animated: true) { completionCalled = true }
        try await waitForAnimation()

        #expect(handlerCalled)
        #expect(completionCalled)
    }
}

/// 可手动控制结束时刻的动画实现：入场时把 completion 挂起，由测试决定何时"动画结束"。
/// 用它替代真实动画，可以完全确定地复现"入场尚未结束就被关闭"的时序。
@MainActor
final class ManualCompletionAnimation: SKDialogAnimationProtocol {

    private var presentCompletion: (() -> Void)?

    /// 结束入场动画（触发挂起的 completion）
    func finishPresentAnimation() {
        presentCompletion?()
        presentCompletion = nil
    }

    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        presentCompletion = completion      // 挂起：由测试决定何时结束
    }

    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        completion()                        // 退场立即收尾，方便断言
    }
}
