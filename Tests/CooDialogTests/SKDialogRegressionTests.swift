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
///
/// - Note: 与 present 相关的用例需要一个"视图已进入窗口层级"的宿主控制器，
///   否则 UIKit 会直接拒绝 present（见第 2 组用例），因此这里用 UIWindow 现搭一个环境。
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

    @Test("viewController 模式：关闭弹窗时 addCompletionHandler 与 dismissDialog 的完成回调都会触发")
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
        dialog.dismissDialog { dismissCompletionCalled = true }
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
        dialog.dismissDialog()                  // 展示途中关闭：isPresenting 置为 false，退场立即收尾
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

        let expected = SlideAnimation.slideOffset(
            for: .bottom,
            containerSize: dialog.containerView.bounds.size,
            margins: margins
        )

        #expect(abs(dialog.containerView.transform.ty - expected) < 0.001)
        // 纵向滑动不应带水平位移
        #expect(dialog.containerView.transform.tx == 0)
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
