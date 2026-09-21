import Testing
import UIKit
@testable import CooDialog

/// 弹窗行为回归测试。
///
/// 覆盖的是几处"配置项/状态机曾经失效"的问题，以及展示入口的对外契约；
/// 每个测试都对应一次具体修复或一条新增契约：
/// 1. 滑动类动画入场完成后，布局变化不得再把容器推回屏幕外（动画状态机需推进到 .final）
/// 2. `enablePanGestureDismiss = false` 时应真正禁用拖拽手势
/// 3. `fadeScaleInitialScale` 应同时作用于入场与退场（而不是被硬编码的 0.8 覆盖）
/// 4. window 模式关闭后，`addCompletionHandler` 注册的回调应被执行
/// 5. 配置改为值类型（struct）后，控制器持有的那份仍必须被动画读到，不得停留在构造时的快照
/// 6. 同一个构建器展示两次，两个弹窗的配置必须互相独立（值语义，不再共享同一引用）
/// 7. 动态改尺寸后 sizeMode 的回写仍须对读取 config 的一方可见
/// 8. `show()` 作为展示入口：按配置分发、显示完成回调必被调用，且不经过 SKDialog 也能直接使用
@MainActor
struct SKDialogBehaviourTests {

    /// 构造一个带内容的弹窗控制器：内容用固定尺寸约束，避免出现 0 尺寸容器。
    private func makeDialog(
        configure: (inout SKDialogConfig) -> Void = { _ in }
    ) -> (SKDialogViewController, UIView) {
        var config = SKDialogConfig()
        config.animationDuration = 0.05          // 缩短动画时长，让测试等待更短
        config.springDamping = 1                // 无回弹，便于断言最终状态
        configure(&config)

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
        dialog.show()
        try await waitForAnimation()

        dialog.dismissDialog()
        try await waitForAnimation()

        #expect(closed)
    }

    // MARK: - 5. 配置的值语义

    @Test("控制器构造后修改 config，动画实现读到的应是最新值（不得是构造时的快照）")
    func configChangeAfterInitReachesAnimation() {
        let recorder = ConfigRecordingAnimation()
        var config = SKDialogConfig()
        config.animationDuration = 0.05
        config.animationType = .custom(recorder)

        let dialog = SKDialogViewController(config: config)
        dialog.loadViewIfNeeded()

        // 控制器已构造完成后再改配置：AnimationManager 若持有快照，这里就会静默失效
        dialog.config.animationDuration = 2.0
        dialog.presentDialog()

        #expect(recorder.presentDuration == 2.0)
    }

    @Test("同一个构建器展示两次，两个弹窗的配置互相独立")
    func builderReuseKeepsConfigsIndependent() {
        let builder = SKDialog.center().cornerRadius(20)
        let first = builder.show()
        builder.cornerRadius(40)
        let second = builder.show()

        // 配置为引用类型时 first 会被第二次修改污染（两个都会是 40）
        #expect(first.config.cornerRadius == 20)
        #expect(second.config.cornerRadius == 40)

        // 收尾：两个弹窗都处于 window 模式，显式关闭以免残留 key window 影响后续用例
        first.dismissDialog()
        second.dismissDialog()
    }

    @Test("动态改尺寸后 sizeMode 的回写对读取 config 的一方可见")
    func sizeModeWriteBackStaysVisible() {
        let (dialog, _) = makeDialog {
            $0.sizeMode = .widthFixed(200)
        }

        dialog.updateContainerHeight(150, animated: false)

        guard case .fixed(let width, let height) = dialog.config.sizeMode else {
            Issue.record("预期回写为 .fixed(width: 200, height: 150)，实际为 \(dialog.config.sizeMode)")
            return
        }
        #expect(width == 200)
        #expect(height == 150)
    }

    // MARK: - 8. 直接使用 SKDialogViewController（不经过 SKDialog）

    @Test("show(completion:) 的显示完成回调必被调用，且入场动画照常发起")
    func showInvokesCompletionAndPresents() async throws {
        let (dialog, _) = makeDialog {
            $0.presentationMode = .window
            $0.position = .center
            $0.animationType = .fadeScale
        }

        var shown = false
        let returned = dialog.show { shown = true }

        // 返回 self，便于链式书写
        #expect(returned === dialog)
        // 当前环境无可用 UIWindowScene（window 创建失败），但"调用必回调"的约定仍成立
        #expect(shown)

        try await waitForAnimation()
        // 入场动画照常完成：容器回到 identity
        #expect(dialog.containerView.transform == .identity)

        dialog.dismissDialog()
    }

    @Test("继承 SKDialogViewController 后可直接 show()，无需经过 SKDialog")
    func subclassedDialogCanShowDirectly() async throws {
        var config = SKDialogConfig()
        config.animationDuration = 0.05
        config.springDamping = 1
        config.position = .bottom
        config.animationType = .slideFromBottom

        let dialog = SubclassedDialog(config: config)
        dialog.loadViewIfNeeded()

        // 继承路径下可直接用公开回调插桩入场时机（无需经过构建器）
        var willStartCount = 0
        dialog.presentAnimationWillStartHandler = { willStartCount += 1 }

        // 子类覆写的 open 生命周期方法确实被走到：这是本类承诺给宿主的覆写面
        #expect(dialog.viewDidLoadCount == 1)

        // 展示入口只可调用、不可覆写；返回类型仍是子类自身（Self），子类成员可直接链式使用
        let returned: SubclassedDialog = dialog.show()
        #expect(returned === dialog)

        try await waitForAnimation()
        #expect(dialog.containerView.transform == .identity)
        // 入场动画只发起一次：show() 内的兜底调用与 viewDidAppear 已用 isPresenting 去重
        #expect(willStartCount == 1)

        dialog.dismissDialog()
    }
}

/// 用于验证"继承 SKDialogViewController 直接使用"这条路径：不经过 SKDialog 构建器。
/// 覆写的是本类承诺给宿主的覆写面——open 的生命周期方法；
/// 展示入口 `show()` 刻意非 open（只可调用、不可覆写），因此不在这里拦截。
@MainActor
final class SubclassedDialog: SKDialogViewController {

    /// viewDidLoad 被调用的次数：证明子类覆写的生命周期方法确实参与展示流程
    private(set) var viewDidLoadCount = 0

    override func viewDidLoad() {
        viewDidLoadCount += 1
        super.viewDidLoad()
    }
}

/// 记录型动画实现：只把"本次动画收到的配置"记下来，不做任何视觉变化。
/// 用于验证「控制器 → 动画实现」这条链路上读到的是最新配置，而不是构造时的快照。
@MainActor
final class ConfigRecordingAnimation: SKDialogAnimationProtocol {

    private(set) var presentDuration: TimeInterval = -1
    private(set) var dismissDuration: TimeInterval = -1

    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        presentDuration = config.animationDuration
        completion()
    }

    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        dismissDuration = config.animationDuration
        completion()
    }
}
