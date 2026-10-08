import Testing
import UIKit
@testable import CooDialog

/// 展示状态（`SKDialogViewController`）与手势复位（`SKDialogGestureHandler`）的回归测试。
///
/// 覆盖的是两条"配置/状态曾经被绕过"的缺陷，以及由它们带出的对外契约：
/// 1. `show()` 成功之后、`viewDidAppear` 之前调用 `dismiss()` 必须真正收尾——
///    旧实现把这一段当成"还没展示"，于是整条关闭流程被跳过；`.window` 模式下自建 window
///    还会与控制器因互相强引用而一起泄漏，随后到达的 viewDidAppear 更会把弹窗重新拉起来
/// 2. 关闭之后迟到的 viewDidAppear 不得再发起入场（弹窗"复活"）
/// 3. `isPresenting` 的语义：从挂到宿主上到收尾完成之间为 true
/// 4. `cancelCurrentGestures()` 只能取消"当前启用中"的手势，不得把配置禁用的手势打开
/// 5. 同一个实例再次展示仍然成立（收尾后状态清回起点，第二轮能正常播入场动画）
///
/// - Note: 与 present 关系相关的断言（"弹窗被从宿主上摘下来"、`.window` 模式回收自建 window）
///   无法在本环境覆盖：测试用的 UIWindow 没有 UIWindowScene，系统的 present / dismiss 转场
///   不会推进——`host.dismiss(animated: false)` 调用后 `presentedViewController` 依旧不变。
///   本文件因此只断言库自身的收尾动作（状态推进 + 各回调），那部分与系统转场无关；
///   转场相关的行为需跑 `Examples/` 下的示例工程验证。
@MainActor
struct SKDialogPresentationStateTests {

    // MARK: - 公共构造

    /// 构造一个已装配内容的弹窗控制器（不展示）。
    private func makeDialog(
        configure: (inout SKDialogConfig) -> Void = { _ in }
    ) -> SKDialogViewController {
        var config = SKDialogConfig()
        config.animationDuration = 0.05          // 缩短动画时长，让测试等待更短
        config.springDamping = 1                // 无回弹，便于断言最终状态
        configure(&config)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        let contentWidth = content.widthAnchor.constraint(equalToConstant: 300)
        let contentHeight = content.heightAnchor.constraint(equalToConstant: 200)
        contentWidth.priority = .defaultLow
        contentHeight.priority = .defaultLow
        NSLayoutConstraint.activate([contentWidth, contentHeight])

        let dialog = SKDialogViewController(config: config)
        dialog.addContentView(content)
        dialog.loadViewIfNeeded()
        dialog.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        dialog.view.layoutIfNeeded()
        return dialog
    }

    /// 构造一个已上屏的宿主控制器（`present` 的前置条件：视图已进入窗口层级）
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

    /// 从容器上的拖拽手势反查手势处理器（delegate 即处理器自身）
    private func panHandler(of dialog: SKDialogViewController) -> SKDialogGestureHandler? {
        dialog.containerView.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first?
            .delegate as? SKDialogGestureHandler
    }

    // MARK: - 1. 首次上屏前关闭

    @Test("show() 之后、入场动画发起之前关闭：关闭收尾完整执行，弹窗不再处于展示状态")
    func dismissingBeforeFirstAppearanceTearsDownPresentation() async throws {
        let (host, window) = makeHostInWindow()

        let dialog = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        var willStart = false
        var didFinish = false
        var completed = false
        dialog.dismissAnimationWillStartHandler = { willStart = true }
        dialog.dismissAnimationDidFinishHandler = { didFinish = true }
        dialog.addCompletionHandler { completed = true }

        dialog.show()
        // show 成功即"已挂到宿主上"：此时入场动画还没发起（viewDidAppear 未到）
        #expect(host.presentedViewController === dialog)
        #expect(dialog.isPresenting)

        // 修复前：这里被整体跳过（isPresenting 仍为 false），关闭流程一步都不走——
        // present 关系留着、自建 window 留着、各回调一个都不触发
        dialog.dismiss()
        try await waitForAnimation()

        #expect(dialog.isPresenting == false, "关闭后必须退出展示状态")
        // 关闭流程的完整语义：两个动画回调与"关闭完成"回调都要触发（与正常关闭一致）。
        // 这三条同时成立，就说明 dismiss 走的是完整的收尾路径而不是被吞掉
        //（收尾里还包含"摘掉 present 关系"与"回收自建 window"，见文件头说明）
        #expect(willStart, "关闭流程开始回调必须触发")
        #expect(didFinish, "关闭流程结束回调必须触发")
        #expect(completed, "关闭完成回调必须触发")

        window.isHidden = true
    }

    @Test("首次上屏前关闭之后，迟到的 viewDidAppear 不得把弹窗重新拉起来")
    func lateAppearanceDoesNotReviveDismissedDialog() async throws {
        let (host, window) = makeHostInWindow()

        let dialog = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        dialog.show()
        dialog.dismiss()
        try await waitForAnimation()

        var willStartFired = false
        var didFinishFired = false
        dialog.presentAnimationWillStartHandler = { willStartFired = true }
        dialog.presentAnimationDidFinishHandler = { didFinishFired = true }

        // 关闭之后 UIKit 仍可能补上一次 viewDidAppear；它的唯一出口就是这个方法
        // （修复前：这里会把已完成关闭的弹窗重新推进到"展示中"并播放入场动画）
        dialog.presentDialog()

        #expect(willStartFired == false, "已关闭的弹窗不得重新发起入场")
        #expect(didFinishFired == false)
        #expect(dialog.isPresenting == false)

        window.isHidden = true
    }

    // MARK: - 2. 关闭的幂等与"调用必回调"

    @Test("连续两次 dismiss：只有一轮收尾，两次的参数回调都会执行")
    func dismissIsIdempotentAndAlwaysReportsThroughCompletion() async throws {
        let (host, window) = makeHostInWindow()

        let dialog = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.animationType = .fadeScale
        }

        var teardownCount = 0
        dialog.addCompletionHandler { teardownCount += 1 }

        dialog.show()
        dialog.presentDialog()          // 入场发起，处于展示中
        try await waitForAnimation()

        var firstCompletion = false
        var secondCompletion = false
        dialog.dismiss { firstCompletion = true }
        dialog.dismiss { secondCompletion = true }   // 第二次：已不在展示状态 → 立刻回调
        try await waitForAnimation()

        #expect(firstCompletion)
        #expect(secondCompletion, "重复 dismiss 必须立刻回调，不能悬空")
        #expect(teardownCount == 1, "收尾只应发生一轮")

        window.isHidden = true
    }

    // MARK: - 3. 未展示时的关闭语义不变

    @Test("从未展示过的弹窗：dismiss 只回调，不触发任何关闭回调")
    func dismissWithoutPresentationOnlyReportsThroughCompletion() {
        // window 模式 + 测试环境没有可用 scene → show() 无法上屏，状态停在 .idle
        let dialog = makeDialog {
            $0.presentationMode = .window
            $0.animationType = .fadeScale
        }

        var willStart = false
        var didFinish = false
        var completed = false
        dialog.dismissAnimationWillStartHandler = { willStart = true }
        dialog.dismissAnimationDidFinishHandler = { didFinish = true }
        dialog.addCompletionHandler { completed = true }

        dialog.show()
        #expect(dialog.isPresenting == false, "没能上屏就不算展示中")

        var completionCalled = false
        dialog.dismiss { completionCalled = true }

        #expect(completionCalled)
        // "关闭完成"的前提是"曾经展示过"：这里不触发（与修复前一致）
        #expect(completed == false)
        #expect(willStart == false)
        #expect(didFinish == false)
    }

    // MARK: - 4. 手势复位不得覆盖配置

    @Test("cancelCurrentGestures 不得把配置禁用掉的手势打开")
    func cancelGesturesKeepsDisabledGesturesDisabled() {
        let dialog = makeDialog {
            $0.position = .bottom
            $0.enablePanGestureDismiss = false
            $0.dismissOnBackgroundTap = false
        }

        guard let handler = panHandler(of: dialog) else {
            Issue.record("拖拽手势或其 delegate 未装配，无法验证复位行为")
            return
        }

        #expect(handler.isPanGestureEnabled == false)
        #expect(handler.isBackgroundTapEnabled == false)

        // 修复前：这一对"关-开"会把两个禁用手势一起打开，
        // 用户随后点遮罩 / 拖面板就能按配置明确禁止的方式关掉弹窗
        handler.cancelCurrentGestures()

        #expect(handler.isPanGestureEnabled == false, "禁用的拖拽手势必须保持禁用")
        #expect(handler.isBackgroundTapEnabled == false, "禁用的遮罩点击手势必须保持禁用")
    }

    @Test("居中弹窗调用 cancelCurrentGestures 后依然不能拖拽")
    func cancelGesturesKeepsCenterDialogUndraggable() {
        let dialog = makeDialog { $0.position = .center }

        guard let handler = panHandler(of: dialog) else {
            Issue.record("拖拽手势或其 delegate 未装配，无法验证复位行为")
            return
        }

        #expect(handler.isPanGestureEnabled == false)

        handler.cancelCurrentGestures()

        #expect(handler.isPanGestureEnabled == false)
    }

    @Test("启用中的手势调用 cancelCurrentGestures 后仍是启用状态（配置语义不变）")
    func cancelGesturesKeepsEnabledGesturesEnabled() {
        let dialog = makeDialog { $0.position = .bottom }

        guard let handler = panHandler(of: dialog) else {
            Issue.record("拖拽手势或其 delegate 未装配，无法验证复位行为")
            return
        }

        #expect(handler.isPanGestureEnabled)
        #expect(handler.isBackgroundTapEnabled)

        handler.cancelCurrentGestures()

        #expect(handler.isPanGestureEnabled)
        #expect(handler.isBackgroundTapEnabled)
    }

    // MARK: - 5. 同一实例再次展示

    @Test("同一个实例关闭后再次展示：状态离开已收尾，入场可以重新发起")
    func dialogCanBeShownAgainAfterDismissal() async throws {
        let (host, window) = makeHostInWindow()

        let dialog = makeDialog {
            $0.presentationMode = .viewController(host)
            $0.position = .bottom
            $0.animationType = .slideFromBottom
        }

        // 第一轮：展示 → 关闭
        dialog.show()
        dialog.presentDialog()
        try await waitForAnimation()
        dialog.dismiss()
        try await waitForAnimation()
        #expect(dialog.isPresenting == false)

        var willStartFired = false
        dialog.presentAnimationWillStartHandler = { willStartFired = true }

        // 收尾之后：状态是"已收尾"，因此再调 presentDialog() 不得发起入场
        dialog.presentDialog()
        #expect(willStartFired == false, "已收尾的弹窗不得再发起入场")

        // 再次展示：`show()` 把上一轮的状态清回起点，于是入场重新可以发起。
        // - Note: 这里刻意只断言"入场能重新发起"，不断言第二轮真的上了屏——本环境里
        //   上一轮的 present 关系摘不掉（无 scene window 跑不完系统转场），第二轮会因此
        //   命不中 present 的前置条件。判据仍然是可靠的：若状态没被清回起点而停在
        //   .finished，presentDialog() 会直接被守卫挡住，下面这条断言就会失败。
        dialog.show()
        dialog.presentDialog()
        #expect(willStartFired, "再次展示后入场必须能重新发起（说明状态已离开已收尾）")

        try await waitForAnimation()
        #expect(dialog.containerView.transform == .identity)

        dialog.dismiss()
        window.isHidden = true
    }
}
