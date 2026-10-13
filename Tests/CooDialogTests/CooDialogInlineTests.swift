//
//  CooDialogInlineTests.swift
//  CooDialogTests
//
//  inline 展示模式（`presentationMode = .inline(view)`）的回归测试。
//
//  这一组要守住的是"挂到宿主视图上"这条与 present 完全无关的上屏路径，逐条对应它承诺的行为：
//  1. 上屏 = 挂到宿主视图上：四边贴合、能挂进宿主控制器就挂、不产生任何 present 关系
//  2. 入场动画照常发起且只发起一次（addChild 之后 UIKit 迟到的 viewDidAppear 不得造成第二次）
//  3. 关闭收尾完整：退场动画 → 视图摘除 → 父子关系解除 → 关闭回调
//  4. 早于入场完成就关闭、关闭后再次展示（同一个实例复用）都不漏收尾、不重复挂载
//  5. 响应链查找照常生效（closeCooDialog / isInCooDialog）——它依赖 addChild 建立的
//     `controller.view.next === controller` 这条链接，正是最容易被拆掉的一环
//  6. 宿主视图尺寸变化时弹窗跟随（贴合的是约束，不是上屏那一刻的 frame）
//
//  另外守一条"画布语义"：弹窗的"屏幕"就是宿主视图——测试里用的画布远小于窗口，
//  因此任何按整屏尺寸取值的实现都会在这里露出来。
//

import Testing
import UIKit
@testable import CooDialog

@MainActor
struct CooDialogInlineTests {

    // MARK: - 公共构造

    /// 保活创建过的窗口：UIWindow 一旦被释放，挂在它上面的视图就会脱离窗口层级
    ///（`view.window` 变 nil），挂载时的 DEBUG 提示会因此误报"宿主视图尚未上屏"。
    private static var retainedWindows: [UIWindow] = []

    /// 构造一块已上屏的"画布"：宿主控制器视图内的一块区域，附带它的高度约束（便于测试改尺寸）。
    private func makeCanvas(
        size: CGSize = CGSize(width: 320, height: 400)
    ) -> (canvas: UIView, heightConstraint: NSLayoutConstraint, host: UIViewController, window: UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        Self.retainedWindows.append(window)

        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(canvas)

        let heightConstraint = canvas.heightAnchor.constraint(equalToConstant: size.height)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: host.view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            canvas.widthAnchor.constraint(equalToConstant: size.width),
            heightConstraint,
        ])
        host.view.layoutIfNeeded()

        return (canvas, heightConstraint, host, window)
    }

    /// 构造一个已装配内容的弹窗控制器（不展示）。内容用低优先级固定尺寸，避免 0 尺寸容器。
    private func makeDialog(
        configure: (inout CooDialogConfig) -> Void = { _ in }
    ) -> CooDialogViewController {
        var config = CooDialogConfig()
        config.animationDuration = 0.05          // 缩短动画时长，让测试等待更短
        config.springDamping = 1                // 无回弹，便于断言最终状态
        configure(&config)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        let contentWidth = content.widthAnchor.constraint(equalToConstant: 200)
        let contentHeight = content.heightAnchor.constraint(equalToConstant: 100)
        contentWidth.priority = .defaultLow
        contentHeight.priority = .defaultLow
        NSLayoutConstraint.activate([contentWidth, contentHeight])

        let dialog = CooDialogViewController(config: config)
        dialog.addContentView(content)
        return dialog
    }

    /// 等待动画结束（留出充裕余量）
    private func waitForAnimation() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: - 1. 上屏路径

    @Test("inline：show() 把弹窗挂到宿主视图上，四边贴合、挂进宿主控制器，且不产生任何 present 关系")
    func inlineShowAttachesToHostView() {
        let (canvas, _, host, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        dialog.show()
        canvas.layoutIfNeeded()

        #expect(dialog.view.superview === canvas)
        #expect(dialog.view.frame == canvas.bounds)
        // 能挂进宿主控制器就挂进：响应链与外观回调都依赖这段关系
        #expect(dialog.parent === host)
        // 全程不走 present——这正是 inline 与另外两种模式的根本差异
        #expect(host.presentedViewController == nil)
        #expect(dialog.presentingViewController == nil)
        #expect(dialog.isPresenting)
    }

    /// "画布语义"的守门测试：弹窗的"屏幕"是宿主视图，不是窗口。
    /// 宿主视图远小于窗口时，任何按整屏尺寸取值的实现都会在这里露出来。
    @Test("inline：弹窗的坐标系与尺寸基准是宿主视图，而不是窗口")
    func inlineUsesCanvasAsScreen() {
        let canvasSize = CGSize(width: 200, height: 150)
        let (canvas, _, _, window) = makeCanvas(size: canvasSize)
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        dialog.show()
        canvas.layoutIfNeeded()

        #expect(dialog.view.bounds.size == canvasSize)
        #expect(window.bounds.size != canvasSize)  // 前提成立：画布确实不是整屏
    }

    @Test("inline：同一个实例重复 show 不重复挂载、不重复播入场")
    func inlineRepeatedShowIsIdempotent() async throws {
        let (canvas, _, host, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        var willStartCount = 0
        dialog.presentAnimationWillStartHandler = { willStartCount += 1 }

        dialog.show()
        dialog.show()
        try await waitForAnimation()

        #expect(willStartCount == 1)
        #expect(host.children.count(where: { $0 === dialog }) == 1)
        #expect(canvas.subviews.count == 1)
    }

    // MARK: - 2. 入场动画

    @Test("inline：入场动画发起且只发起一次，落定后容器回到终态")
    func inlinePresentsOnceAndSettles() async throws {
        let (canvas, _, _, _) = makeCanvas()
        let dialog = makeDialog {
            $0.presentationMode = .inline(canvas)
            $0.animationType = .fadeScale
        }

        var willStartCount = 0
        var didFinishCount = 0
        dialog.presentAnimationWillStartHandler = { willStartCount += 1 }
        dialog.presentAnimationDidFinishHandler = { didFinishCount += 1 }

        dialog.show()
        // addChild 之后 UIKit 还会（异步）送来一次 viewDidAppear：不得造成第二次入场
        try await waitForAnimation()

        #expect(willStartCount == 1)
        #expect(didFinishCount == 1)
        #expect(dialog.containerView.transform == .identity)
        #expect(dialog.containerView.alpha == 1)
        #expect(dialog.backgroundView.alpha == 1)
    }

    // MARK: - 3. 关闭收尾

    @Test("inline：dismiss 把视图从宿主摘掉、解除父子关系，并触发关闭回调")
    func inlineDismissDetachesFromHost() async throws {
        let (canvas, _, host, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        var didDismiss = false
        dialog.addCompletionHandler { didDismiss = true }

        dialog.show()
        try await waitForAnimation()
        dialog.dismiss()
        try await waitForAnimation()

        #expect(dialog.view.superview == nil)
        #expect(dialog.parent == nil)
        #expect(!host.children.contains(where: { $0 === dialog }))
        #expect(didDismiss)
        #expect(!dialog.isPresenting)
    }

    @Test("inline：show 之后立刻 dismiss（入场尚未跑完），收尾同样完整")
    func inlineDismissBeforeAnimationFinishes() async throws {
        let (canvas, _, host, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        var didDismiss = false
        dialog.addCompletionHandler { didDismiss = true }

        dialog.show()
        dialog.dismiss()
        try await waitForAnimation()

        #expect(dialog.view.superview == nil)
        #expect(!host.children.contains(where: { $0 === dialog }))
        #expect(didDismiss)
        #expect(!dialog.isPresenting)
    }

    @Test("inline：关闭后用同一个实例再次 show，重新挂载并重新播入场")
    func inlineRePresentAfterDismiss() async throws {
        let (canvas, _, host, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        dialog.show()
        try await waitForAnimation()
        dialog.dismiss()
        try await waitForAnimation()

        var didFinishCount = 0
        dialog.presentAnimationDidFinishHandler = { didFinishCount += 1 }

        dialog.show()
        try await waitForAnimation()

        #expect(dialog.isPresenting)
        #expect(dialog.view.superview === canvas)
        #expect(host.children.contains(where: { $0 === dialog }))
        #expect(didFinishCount == 1)
    }

    // MARK: - 4. 响应链

    @Test("inline：内容视图沿响应链仍能命中弹窗，closeCooDialog 生效")
    func inlineKeepsResponderChainLookup() async throws {
        let (canvas, _, _, _) = makeCanvas()
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        let button = UIButton(type: .system)
        dialog.addContentView(button)

        dialog.show()
        try await waitForAnimation()

        #expect(button.isInCooDialog)
        button.closeCooDialog()
        try await waitForAnimation()

        #expect(!dialog.isPresenting)
        #expect(dialog.view.superview == nil)
    }

    // MARK: - 5. 跟随宿主视图尺寸

    @Test("inline：宿主视图尺寸变化后弹窗跟随（贴合的是约束，不是上屏那一刻的 frame）")
    func inlineFollowsCanvasResize() {
        let (canvas, heightConstraint, host, _) = makeCanvas(size: CGSize(width: 320, height: 200))
        let dialog = makeDialog { $0.presentationMode = .inline(canvas) }

        dialog.show()
        host.view.layoutIfNeeded()
        #expect(dialog.view.bounds.height == 200)

        heightConstraint.constant = 500
        host.view.layoutIfNeeded()

        #expect(canvas.bounds.height == 500)
        #expect(dialog.view.bounds.height == 500)
    }

    // MARK: - 6. 布局基准

    @Test("inline：容器相对画布定位（居中 / 贴底都以画布为基准，不是屏幕）")
    func inlineContainerLaysOutRelativeToCanvas() {
        // 画布贴在窗口左上角（200×150），窗口是 390×844：
        // 两种基准的差别足够大，断言不会"两边都成立"
        let canvasSize = CGSize(width: 200, height: 150)
        let (canvas, _, _, window) = makeCanvas(size: canvasSize)

        let centerDialog = makeDialog {
            $0.presentationMode = .inline(canvas)
            $0.position = .center
        }
        centerDialog.show()
        canvas.layoutIfNeeded()

        let canvasCenter = canvas.convert(
            CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: window
        )
        let containerCenter = centerDialog.containerView.convert(
            CGPoint(x: centerDialog.containerView.bounds.midX, y: centerDialog.containerView.bounds.midY),
            to: window
        )
        #expect(abs(containerCenter.x - canvasCenter.x) < 0.5)
        #expect(abs(containerCenter.y - canvasCenter.y) < 0.5)
        // 前提校验：窗口中心离画布中心很远（否则上面两条断言无法区分"相对画布"与"相对屏幕"）
        #expect(abs(window.bounds.midY - canvasCenter.y) > 100)

        centerDialog.dismiss(animated: false)

        let bottomDialog = makeDialog {
            $0.presentationMode = .inline(canvas)
            $0.position = .bottom
        }
        bottomDialog.show()
        canvas.layoutIfNeeded()

        // 容器底边 = 画布底边（两者同在 controller.view 坐标系里，也就是画布坐标系）
        #expect(abs(bottomDialog.containerView.frame.maxY - canvas.bounds.height) < 0.5)
        // 前提校验：窗口底边离画布底边也很远
        #expect(window.bounds.height - canvas.bounds.height > 100)

        bottomDialog.dismiss(animated: false)
    }

    // MARK: - 7. 画布就是宿主控制器自己的视图

    @Test("inline：画布就是宿主控制器自己的视图（当前显示的页面直接弹）")
    func inlineCanvasIsHostViewItself() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        Self.retainedWindows.append(window)
        host.view.layoutIfNeeded()

        let baseline = host.view.subviews.count
        let dialog = makeDialog { $0.presentationMode = .inline(host.view) }

        dialog.show()
        host.view.layoutIfNeeded()

        // 画布就是宿主自己的 view：弹窗视图直接挂在这一层上，遮罩铺满整页
        #expect(dialog.view.superview === host.view)
        #expect(dialog.view.frame == host.view.bounds)
        #expect(dialog.parent === host)
        #expect(host.presentedViewController == nil)
        #expect(host.view.subviews.count == baseline + 1)

        dialog.dismiss()
        try await waitForAnimation()

        // 收尾要把这一页恢复原样：弹窗视图摘掉、父子关系解除，本页子视图数回到基线
        #expect(host.view.subviews.count == baseline)
        #expect(dialog.parent == nil)
        #expect(!dialog.isPresenting)
    }

    // MARK: - 8. 内容大于画布时的契约

    @Test("inline：内容大于画布时，容器横向被压回画布内、纵向允许溢出（内容自适应的既有取舍）")
    func inlineOversizedContentBehavior() {
        let (canvas, _, _, _) = makeCanvas(size: CGSize(width: 200, height: 150))

        var config = CooDialogConfig()
        config.presentationMode = .inline(canvas)
        let dialog = CooDialogViewController(config: config)

        // 内容用 required 尺寸，且两个方向都大于画布：模拟"宿主给了固定尺寸的卡片、画布却很小"
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 300),
            content.heightAnchor.constraint(equalToConstant: 260),
        ])
        dialog.addContentView(content)

        dialog.show()
        canvas.layoutIfNeeded()

        // 横向：位置约束里的两条不等式是必需的，容器宽度被限制在画布内（内容自己的宽度诉求让位）
        #expect(dialog.containerView.frame.width <= canvas.bounds.width + 0.5)
        // 纵向：居中弹窗刻意不设上下边距约束，容器可以比画布高，超出部分由画布裁掉
        #expect(dialog.containerView.frame.height > canvas.bounds.height)
        #expect(dialog.containerView.frame.minY < 0)

        dialog.dismiss(animated: false)
    }
}
