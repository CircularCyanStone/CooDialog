//
//  SKDialogGestureHandler.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的手势处理器，专门负责处理弹窗的各种手势交互，包括背景点击关闭、拖拽手势等。
 * 该处理器将手势相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 背景点击：处理点击背景区域关闭弹窗的手势
 * - 拖拽手势：处理拖拽容器视图进行交互式关闭的手势
 * - 手势状态：管理手势的开始、变化、结束等状态
 * - 拖拽进度：计算拖拽进度并提供视觉反馈
 * - 自动关闭：根据拖拽距离和速度判断是否自动关闭弹窗
 *
 * 设计原理（两个手势为什么分别挂在不同视图上）：
 * - 背景点击挂在 backgroundView 上：语义就是"点遮罩关闭"
 * - 拖拽挂在 containerView 上：只有按住面板本身才触发，且面板在上层，
 *   两者从视图层级上天然互斥，不需要额外的识别器依赖配置
 *
 * 拖拽的两种实现手段（这是理解本文件的关键）：
 * - 拖拽过程：直接改 `containerView.center`（即时跟手，不平滑、无动画）
 * - 回弹/关闭：交给动画（容器 transform 由 SKDialogAnimationManager 处理）
 * 之所以敢直接改 center：容器虽然有 AutoLayout 约束，但约束只在下一次布局求解时
 * 才会覆盖 center，而拖拽期间不会触发布局，因此改 center 是可行且轻量的。
 * 反过来说——若拖拽过程中恰好发生了布局（宿主改尺寸、屏幕旋转），位移会被约束重置。
 *
 * 与配置的关系：
 * - `dismissOnBackgroundTap` 决定背景点击手势的启用状态
 * - 拖拽是否可用 = position 为 .bottom/.top **且** `enablePanGestureDismiss` 为 true，
 *   两个条件同时成立才会安装可用的拖拽手势
 */

import UIKit

/// SKDialog手势处理器
/// 负责管理弹窗的所有手势交互逻辑
///
/// - Note: 继承 NSObject 是协议要求（`UIGestureRecognizerDelegate` 继承自 `NSObjectProtocol`），
///   本类不使用消息转发，继承只为满足这一约束。
@MainActor
class SKDialogGestureHandler: NSObject {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?

    /// 背景点击手势识别器（持有引用的目的：需要按配置启停、需要能移除）
    private var backgroundTapGesture: UITapGestureRecognizer?

    /// 拖拽手势识别器（同上）
    private var panGesture: UIPanGestureRecognizer?

    /// 拖拽开始时的容器中心点（回弹时恢复到它）
    private var initialContainerCenter: CGPoint = .zero

    /// 拖拽开始时的遮罩基色与基准 alpha。
    /// 拖动过程中每帧都要按进度稀释遮罩（`updateBackgroundAlpha`），而基色与基准 alpha
    /// 在整个手势期间是常量，因此在 `.began` 时取一次即可，不必每帧回读 config 并解析颜色。
    private var dragMaskBaseColor: UIColor = .black
    private var dragMaskBaseAlpha: CGFloat = 0.5

    // MARK: - Initialization

    /// 初始化手势处理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
        super.init()
    }

    // MARK: - Public Methods

    /// 安装两个手势（在控制器 viewDidLoad 中调用一次）。
    func setupGestures() {
        setupBackgroundTapGesture()
        setupPanGesture()
    }
}

// MARK: - UIGestureRecognizerDelegate

/// 拖拽手势的准入判定，唯一目的是"把纵向滚动让给内容"。
///
/// 背景：拖拽手势挂在 containerView 上，而内容里的 UIScrollView / UITableView 自带 pan 手势。
/// 两个手势位于不同视图，UIKit 默认会**同时识别**——用户滚动列表时整个面板会跟着一起位移。
/// 这里在"手势即将开始"时做一次判定，把纵向滚动留给内容。
extension SKDialogGestureHandler: UIGestureRecognizerDelegate {

    /// 是否允许拖拽手势开始（判定细节见 `shouldBeginPan(at:velocity:position:)`）。
    /// - Note: 可滚动视图的识别靠 hitTest 链上是否为 UIScrollView，覆盖 UIScrollView /
    ///   UITableView / UICollectionView / UITextView 及其子类。内部自带滚动但自身不是
    ///   UIScrollView 的容器（例如 WKWebView）不在判定范围内——这类内容若与拖拽关闭冲突，
    ///   应由宿主通过 `config.enablePanGestureDismiss` 关掉拖拽。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
              let viewController = viewController else { return true }

        return shouldBeginPan(
            at: panGesture.location(in: viewController.containerView),
            velocity: panGesture.velocity(in: viewController.containerView),
            position: viewController.config.position
        )
    }

    /// 判定规则本体：给定触摸起点、速度与弹窗位置，判断面板是否应当接管这次拖动。
    ///
    /// 判定顺序：
    /// 1. 只接管纵向滑动（横向滑动与"把面板拖出屏幕"无关，交给内容自己处理）
    /// 2. 触摸起点若落在可纵向滚动的子视图内，且该视图在"关闭方向"上还有滚动余量，则不接管
    /// 3. 其余情况接管（拖动面板本身）
    ///
    /// 第 2 条里的"还有滚动余量"是关键：列表已经滚到顶部时继续下拉，内容已无处可滚，
    /// 这时应当把面板拖走——这也是 iOS 上贴边面板的常见手感。
    ///
    /// - Note: 独立成方法（而不是全部内联在 gestureRecognizerShouldBegin 里）是为了让规则
    ///   可被直接验证：手势识别器的速度与位置在单元测试里无法伪造。
    /// - Parameters:
    ///   - location: 触摸起点（containerView 坐标系）
    ///   - velocity: 拖动速度（containerView 坐标系）
    ///   - position: 弹窗停靠位置，决定"关闭方向"
    /// - Returns: true 表示面板接管这次拖动；false 表示交给内容处理（或方向不是纵向）
    func shouldBeginPan(at location: CGPoint, velocity: CGPoint, position: SKDialogPosition) -> Bool {
        // 1) 只接管纵向滑动
        guard abs(velocity.y) > abs(velocity.x) else { return false }

        guard let containerView = viewController?.containerView else { return true }

        // 2) 触摸起点落在可滚动的子视图内，且该方向还有滚动余量 → 让滚动优先
        var hitView = containerView.hitTest(location, with: nil)
        while let view = hitView, view !== containerView {
            if let scrollView = view as? UIScrollView,
               scrollViewHasRoom(scrollView, towardDismissal: position) {
                return false
            }
            hitView = view.superview
        }

        // 3) 其余情况：面板接管拖拽
        return true
    }

    /// 滚动视图在"面板关闭方向"上是否还有可滚动的内容。
    /// 有余量表示这次拖动应该用于滚动内容；没有余量（已到顶 / 已到底）才让面板接管。
    private func scrollViewHasRoom(_ scrollView: UIScrollView, towardDismissal position: SKDialogPosition) -> Bool {
        // 内容不足一屏（或只有横向滚动）：纵向没有可滚动的余量
        guard scrollView.contentSize.height > scrollView.bounds.height else { return false }

        switch position {
        case .bottom:
            // 向下拖 = 关闭：只有"不在顶部"时才有内容可以继续向下滚
            let topOffset = -scrollView.adjustedContentInset.top
            return scrollView.contentOffset.y > topOffset + 0.5
        case .top:
            // 向上拖 = 关闭：只有"不在底部"时才有内容可以继续向上滚
            let bottomOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            return scrollView.contentOffset.y < bottomOffset - 0.5
        case .center:
            // 居中弹窗没有可拖出的方向（手势在安装时已被禁用），保守地让滚动优先
            return true
        }
    }
}

// MARK: - Private

extension SKDialogGestureHandler {

    // MARK: - Background Tap

    /// 安装背景点击手势。
    ///
    /// 两个要点：
    /// - target 是 handler 自身，因此手势存活期间 handler 必须存活
    ///   （由 SKDialogViewController 强引用持有，生命周期一致）
    /// - 启用状态在安装时读取配置一次；之后改配置不会同步到这里（本类不提供重新同步入口）
    private func setupBackgroundTapGesture() {
        guard let viewController = viewController else { return }

        // 移除旧的手势
        // 先移除再安装：保证重复调用不会叠加多个识别器（叠加会导致一次点击触发多次 dismiss）
        removeBackgroundTapGesture()

        // 创建新的背景点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tapGesture.isEnabled = viewController.config.dismissOnBackgroundTap

        viewController.backgroundView.addGestureRecognizer(tapGesture)
        backgroundTapGesture = tapGesture
    }

    /// 移除背景点击手势（同时清空引用，保证"引用存在"等价于"手势已安装"）
    private func removeBackgroundTapGesture() {
        if let gesture = backgroundTapGesture {
            // 通过 gesture.view 反查宿主视图来移除，避免依赖控制器上的具体视图属性
            gesture.view?.removeGestureRecognizer(gesture)
            backgroundTapGesture = nil
        }
    }

    /// 处理背景点击事件。
    ///
    /// 命中判断用 `containerView.frame`（而不是 bounds）：frame 是容器在父视图坐标系中的位置，
    /// 与 `gesture.location(in: view)` 处于同一坐标系；且 frame 会包含 transform 的影响，
    /// 因此滑动动画进行中也能正确判定容器当前占用的区域。
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard let viewController = viewController else { return }

        // 确保点击的是背景视图而不是容器视图
        let location = gesture.location(in: viewController.view)
        let containerFrame = viewController.containerView.frame

        if !containerFrame.contains(location) {
            viewController.dismiss()
        }
    }

    // MARK: - Pan Gesture

    /// 安装拖拽手势。
    ///
    /// 启用条件：position 为 .bottom / .top（居中弹窗没有可拖出的方向）**且**
    /// `config.enablePanGestureDismiss` 为 true，两者缺一不可。
    private func setupPanGesture() {
        guard let viewController = viewController else { return }

        // 移除旧的手势
        removePanGesture()

        // 创建新的拖拽手势
        // delegate 用于"把纵向滚动让给内容"的判定，见文件下方的 gestureRecognizerShouldBegin
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self

        // 仅底部/顶部弹窗支持拖拽，且需要配置开关允许
        // （安装时读一次：config 在库外只读，展示后没有运行时同步入口）
        let supportsPanGesture = (viewController.config.position == .bottom || viewController.config.position == .top)
            && viewController.config.enablePanGestureDismiss
        panGestureRecognizer.isEnabled = supportsPanGesture

        viewController.containerView.addGestureRecognizer(panGestureRecognizer)
        panGesture = panGestureRecognizer
    }

    /// 移除拖拽手势
    private func removePanGesture() {
        if let gesture = panGesture {
            gesture.view?.removeGestureRecognizer(gesture)
            panGesture = nil
        }
    }

    /// 手势状态总入口：按状态分派到开始/变化/结束三段处理。
    /// 把 `.cancelled` 与 `.ended` 合并处理是有意的——两者都需要"决定关闭还是回弹"，
    /// 否则被系统打断（来电、多指手势竞争）时容器会停在半途，既不关闭也不归位。
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            handlePanBegan(gesture)
        case .changed:
            handlePanChanged(gesture)
        case .ended, .cancelled:
            handlePanEnded(gesture)
        default:
            break
        }
    }

    /// 拖拽开始：记录基准位置与遮罩基色，供后续计算位移、回弹目标与淡化进度。
    /// 用"记录起点"而不是每帧累加增量：每帧基于起点重算，避免浮点误差累积，
    /// 也让手势被打断后再次开始时状态是干净的。
    private func handlePanBegan(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }

        // 记录初始位置（回弹时的恢复目标）
        initialContainerCenter = viewController.containerView.center

        // 记录遮罩基色与它的基准 alpha（拖拽全程复用，见属性说明）
        dragMaskBaseColor = viewController.config.backgroundMaskColor
        dragMaskBaseAlpha = dragMaskBaseColor.cgColor.alpha
    }

    /// 拖拽进行中：按位置限制方向 → 直接移动 center → 用进度驱动遮罩淡化。
    ///
    /// 方向过滤（只允许"向外"拖）是交互设计上的必要约束：底部面板向上拖没有语义，
    /// 若允许会把容器拖进屏幕内部甚至盖住上方内容。这里通过把反方向位移夹到 0 实现"拖不动"，
    /// 手感上表现为阻尼到边界。
    private func handlePanChanged(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }

        let translation = gesture.translation(in: viewController.view)
        let position = viewController.config.position

        // 根据弹窗位置限制拖拽方向
        var allowedTranslation = translation

        switch position {
        case .bottom:
            // 底部弹窗只允许向下拖拽
            allowedTranslation.y = max(0, translation.y)
        case .top:
            // 顶部弹窗只允许向上拖拽
            allowedTranslation.y = min(0, translation.y)
        case .center:
            // 居中弹窗不支持拖拽
            // （正常情况下手势在安装时就被禁用了，这里是防御性返回）
            return
        }

        // 更新容器位置
        // 直接写 center：即时跟手。容器虽然有约束，但约束只在下一次布局求解时才会覆盖 center，
        // 拖拽期间不触发布局，因此这种写法是安全的
        let newCenter = CGPoint(
            x: initialContainerCenter.x,
            y: initialContainerCenter.y + allowedTranslation.y
        )
        viewController.containerView.center = newCenter

        // 计算拖拽进度并更新背景透明度
        let progress = calculateDragProgress(translation: allowedTranslation)
        updateBackgroundAlpha(progress: progress)
    }

    /// 拖拽结束：按"距离 + 速度"双阈值决定关闭还是回弹。
    ///
    /// 双阈值的原因：只有距离阈值会让"快速甩一下"无法关闭（位移小但意图明确）；
    /// 只有速度阈值则慢速拖到底也不会关闭。两者取或（||）覆盖了两种典型手势习惯。
    private func handlePanEnded(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }

        let translation = gesture.translation(in: viewController.view)
        let velocity = gesture.velocity(in: viewController.view)

        // 判断是否应该关闭弹窗
        if shouldDismissOnPanEnd(translation: translation, velocity: velocity) {
            // 关闭：走正常的 dismiss 流程（退场动画会把容器推向屏幕外，
            // 由于拖拽已经改变了 center，最终位移是"拖拽距离 + 动画距离"，视觉上像是被甩出去）
            viewController.dismiss()
        } else {
            // 恢复到原始位置
            restoreContainerPosition()
        }
    }

    /// 拖拽相关计算（进度、关闭阈值）用的基准高度：容器当前高度，带下限兜底。
    private func dragReferenceHeight() -> CGFloat {
        guard let viewController = viewController else { return Self.minimumDragReferenceHeight }
        // 布局求解前容器高度是 0，直接用会让"进度"算成 NaN、"关闭阈值"退化成 0
        //（后者意味着拖 1pt 就关闭）
        return max(viewController.containerView.bounds.height, Self.minimumDragReferenceHeight)
    }

    /// 基准高度的下限：与内容的最小高度（`SKDialogContainerSizeManager` 里的 44）保持一致，
    /// 也接近最小的可用触控尺寸。兜底只会在容器尚未布局时生效，正常拖拽中不会触发。
    private static let minimumDragReferenceHeight: CGFloat = 44

    /// 计算拖拽进度（0.0 ~ 1.0），用于驱动遮罩的淡化程度。
    ///
    /// 满进度的基准取"容器高度的一半"而不是整高：如果以整高为基准，
    /// 用户拖到一半时遮罩才淡 25%，反馈会显得迟钝；以半高为基准能让淡化在中段就明显起来。
    /// - Parameter translation: 拖拽偏移量
    /// - Returns: 拖拽进度（0.0 - 1.0）
    private func calculateDragProgress(translation: CGPoint) -> CGFloat {
        let dragDistance = abs(translation.y)

        // 拖拽距离超过容器高度的一半时进度为1
        let maxDragDistance = dragReferenceHeight() * 0.5
        let progress = min(dragDistance / maxDragDistance, 1.0)

        return progress
    }

    /// 按拖拽进度稀释遮罩颜色（最多淡化 50%）。
    ///
    /// 为什么改 `backgroundColor`（颜色自身的 alpha）而不是 `view.alpha`：
    /// backgroundView.alpha 是入场/退场动画的驱动通道——入场结束时被动画设为 1，
    /// 若拖拽期间也去改它，两者会互相覆盖（例如回弹时被动画覆盖成 0，遮罩直接消失）。
    /// 走颜色通道则与动画互不干扰。
    ///
    /// 基准是拖拽开始时记下的遮罩色与它自身的 alpha（`dragMaskBaseColor`）：
    /// 因此 `config.backgroundMaskColor` 建议使用半透明颜色，否则淡化幅度会显得很轻微。
    /// - Parameter progress: 拖拽进度
    private func updateBackgroundAlpha(progress: CGFloat) {
        guard let viewController = viewController else { return }

        // 根据拖拽进度调整背景透明度
        let newAlpha = dragMaskBaseAlpha * (1.0 - progress * 0.5) // 最多减少50%透明度

        viewController.backgroundView.backgroundColor = dragMaskBaseColor.withAlphaComponent(newAlpha)
    }

    /// 判断是否应该在拖拽结束时关闭弹窗。
    ///
    /// 阈值设定：
    /// - 距离：容器高度的 1/3（低于此值更可能只是误触或想看下方内容）
    /// - 速度：1000 pt/s（快速甩动即便位移很小也算明确意图）
    /// 取绝对值比较：方向已经被"只能向外拖"限制住了，因此不必区分正负。
    /// - Parameters:
    ///   - translation: 拖拽偏移量
    ///   - velocity: 拖拽速度
    /// - Returns: 是否应该关闭
    private func shouldDismissOnPanEnd(translation: CGPoint, velocity: CGPoint) -> Bool {
        let dragDistance = abs(translation.y)
        let dragVelocity = abs(velocity.y)

        // 拖拽距离超过容器高度的1/3或者拖拽速度超过阈值
        // （基准高度带兜底：容器未布局时不会退化成"拖 1pt 就关闭"）
        let distanceThreshold = dragReferenceHeight() / 3.0
        let velocityThreshold: CGFloat = 1000.0

        return dragDistance > distanceThreshold || dragVelocity > velocityThreshold
    }

    /// 回弹到拖拽前的位置（弹簧曲线，收尾自然）。
    ///
    /// 只恢复 center 与遮罩颜色，**不碰 transform**：容器的 transform 归动画管理器管，
    /// 拖拽期间它未被改动，所以无需也不应在此处重置。
    /// - Note: 回弹完成后 transform 仍是 identity，容器回到约束指定的位置，视觉上完全归位。
    private func restoreContainerPosition() {
        guard let viewController = viewController else { return }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.curveEaseOut],
            animations: {
                viewController.containerView.center = self.initialContainerCenter
                // 遮罩回到拖拽开始时的样子（用 .began 记下的基色，保证与淡化过程同源）
                viewController.backgroundView.backgroundColor = self.dragMaskBaseColor
            },
            completion: nil
        )
    }

    /// 让"当前启用中"的手势收到 `.cancelled` 并回到未识别状态；禁用态原样保留。
    /// 判定与操作写在一处，避免调用点各自判断（那正是"停手"调用会把禁用手势打开的原因）。
    private func cancelIfEnabled(_ gesture: UIGestureRecognizer?) {
        guard let gesture, gesture.isEnabled else { return }
        gesture.isEnabled = false
        gesture.isEnabled = true
    }
}

// MARK: - Debug & Testing

/// 调试 / 测试用的状态查询与强制复位入口，不参与生产路径。
extension SKDialogGestureHandler {

    /// 是否正处于拖拽进行中
    var isDragging: Bool {
        return panGesture?.state == .changed
    }

    /// 背景点击手势是否已启用
    var isBackgroundTapEnabled: Bool {
        return backgroundTapGesture?.isEnabled ?? false
    }

    /// 拖拽手势是否已启用
    var isPanGestureEnabled: Bool {
        return panGesture?.isEnabled ?? false
    }

    /// 强制结束当前手势。
    ///
    /// 手法说明：把 isEnabled 先置 false 再置回 true，会让正在进行的手势收到 `.cancelled`
    /// 并回到未识别状态；比直接 removeGestureRecognizer 温和（保留识别器与其绑定关系，
    /// 也不会打断随后可能到来的新触摸）。通常用于弹窗即将关闭、需要立刻停止交互的场景。
    ///
    /// - Important: 只对**当前处于启用状态**的手势做这一对操作。禁用态的手势（居中弹窗、
    ///   或宿主把 `enablePanGestureDismiss` / `dismissOnBackgroundTap` 关掉）必须原样留着：
    ///   无条件置回 true 会把配置明确禁止的交互重新打开，用户随后就能按禁忌的方式关掉弹窗。
    func cancelCurrentGestures() {
        cancelIfEnabled(panGesture)
        cancelIfEnabled(backgroundTapGesture)
    }
}
