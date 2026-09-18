import Testing
import UIKit
@testable import CooDialog

/// 弹窗行为回归测试。
///
/// 覆盖的是几处"配置项/状态机曾经失效"的问题，每个测试都对应一次具体修复：
/// 1. 滑动类动画入场完成后，布局变化不得再把容器推回屏幕外（动画状态机需推进到 .final）
/// 2. `enablePanGestureDismiss = false` 时应真正禁用拖拽手势
/// 3. `fadeScaleInitialScale` 应同时作用于入场与退场（而不是被硬编码的 0.8 覆盖）
/// 4. window 模式关闭后，`addCompletionHandler` 注册的回调应被执行
@MainActor
struct SKDialogBehaviourTests {

    /// 构造一个带内容的弹窗控制器：内容用固定尺寸约束，避免出现 0 尺寸容器。
    private func makeDialog(
        configure: (SKDialogConfig) -> Void = { _ in }
    ) -> (SKDialogViewController, UIView) {
        let config = SKDialogConfig()
        config.animationDuration = 0.05          // 缩短动画时长，让测试等待更短
        config.springDamping = 1                // 无回弹，便于断言最终状态
        configure(config)

        // 内容的尺寸约束用低优先级：模拟"内容只是希望这么大"，
        // 这样测试里宿主主动改容器尺寸时不会与内容约束产生冲突日志
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        let contentWidth = content.widthAnchor.constraint(equalToConstant: 300)
        let contentHeight = content.heightAnchor.constraint(equalToConstant: 200)
        contentWidth.priority = .defaultLow
        contentHeight.priority = .defaultLow
        NSLayoutConstraint.activate([contentWidth, contentHeight])

        let dialog = SKDialogViewController(config: config)
        dialog.addContentView(content)
        dialog.loadViewIfNeeded()               // 触发 viewDidLoad：建视图、约束、手势、预置动画状态
        return (dialog, content)
    }

    /// 等待动画结束（留出充裕余量）
    private func waitForAnimation() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: - 1. 入场完成后布局不得改变容器位置

    @Test("滑动动画入场完成后，布局变化不改变容器 transform")
    func slidingDialogKeepsTransformAfterLayout() async throws {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.animationType = .slideFromBottom
        }

        dialog.presentDialog()
        try await waitForAnimation()

        #expect(dialog.containerView.transform == .identity)

        // 模拟宿主在弹窗可见后改变尺寸（等价于旋转、键盘等任一次布局）
        dialog.updateContainerHeight(150, animated: false)
        dialog.view.setNeedsLayout()
        dialog.view.layoutIfNeeded()

        // 修复前：这里会变成"屏幕外"的滑动偏移，弹窗肉眼可见地飞出屏幕
        #expect(dialog.containerView.transform == .identity)
    }

    @Test("带淡入的滑动动画同样不受后续布局影响")
    func slidingWithFadeDialogKeepsTransformAfterLayout() async throws {
        let (dialog, _) = makeDialog {
            $0.position = .top
            $0.animationType = .slideFromTopWithFade
        }

        dialog.presentDialog()
        try await waitForAnimation()
        #expect(dialog.containerView.transform == .identity)

        dialog.updateContainerWidth(280, animated: false)
        dialog.view.layoutIfNeeded()

        #expect(dialog.containerView.transform == .identity)
        #expect(dialog.containerView.alpha == 1)
    }

    // MARK: - 2. 拖拽开关

    @Test("enablePanGestureDismiss 为 true 时安装可用的拖拽手势")
    func panGestureEnabledByDefault() {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.enablePanGestureDismiss = true
        }

        let pan = dialog.containerView.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first
        #expect(pan != nil)
        #expect(pan?.isEnabled == true)
    }

    @Test("enablePanGestureDismiss 为 false 时拖拽手势被禁用")
    func panGestureDisabledByConfig() {
        let (dialog, _) = makeDialog {
            $0.position = .bottom
            $0.enablePanGestureDismiss = false
        }

        let pan = dialog.containerView.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first
        // 手势仍然安装（便于运行时切换），但必须是禁用状态
        #expect(pan != nil)
        #expect(pan?.isEnabled == false)
    }

    @Test("居中弹窗不安装可用的拖拽手势")
    func centerDialogHasNoPanGesture() {
        let (dialog, _) = makeDialog {
            $0.position = .center
        }

        let pan = dialog.containerView.gestureRecognizers?
            .compactMap { $0 as? UIPanGestureRecognizer }
            .first
        #expect(pan?.isEnabled != true)
    }

    // MARK: - 3. 缩放淡入的起止比例来自配置

    @Test("fadeScaleInitialScale 同时决定入场起点与退场终点")
    func fadeScaleUsesConfiguredScale() async throws {
        let (dialog, _) = makeDialog {
            $0.position = .center
            $0.animationType = .fadeScale
            $0.fadeScaleInitialScale = 0.5
        }

        // 首帧预置状态用的是配置值
        #expect(abs(dialog.containerView.transform.a - 0.5) < 0.001)

        dialog.presentDialog()
        try await waitForAnimation()
        #expect(dialog.containerView.transform == .identity)

        dialog.dismissDialog()
        try await waitForAnimation()

        // 修复前这里是硬编码的 0.8
        #expect(abs(dialog.containerView.transform.a - 0.5) < 0.001)
    }

    // MARK: - 4. window 模式的关闭回调

    @Test("window 模式下关闭弹窗会触发 completionHandler")
    func windowModeInvokesCompletionHandlerOnDismiss() async throws {
        let (dialog, _) = makeDialog {
            $0.presentationMode = .window
            $0.position = .center
            $0.animationType = .fadeScale
        }

        var closed = false
        dialog.addCompletionHandler { closed = true }

        // 即便当前环境没有可用的 UIWindowScene（window 创建失败），
        // 入场动画与关闭流程依然会执行，回调语义与真实环境一致
        dialog.showInWindow()
        try await waitForAnimation()

        dialog.dismissDialog()
        try await waitForAnimation()

        #expect(closed)
    }
}
