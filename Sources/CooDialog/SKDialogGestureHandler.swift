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
@MainActor
class SKDialogGestureHandler {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?

    /// 背景点击手势识别器（持有引用的目的：需要按配置启停、需要能移除）
    private var backgroundTapGesture: UITapGestureRecognizer?

    /// 拖拽手势识别器（同上）
    private var panGesture: UIPanGestureRecognizer?

    /// 拖拽开始时的容器中心点（回弹时恢复到它）
    private var initialContainerCenter: CGPoint = .zero

    // MARK: - Initialization

    /// 初始化手势处理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods

    /// 安装两个手势（在控制器 viewDidLoad 中调用一次）。
    func setupGestures() {
        setupBackgroundTapGesture()
        setupPanGesture()
    }

    /// 移除全部手势。
    /// - Note: 库内当前没有调用者（控制器的生命周期与手势一致，不需要中途拆除）。
    ///   保留给"复用同一个控制器展示不同配置"的场景：先移除再按新配置重建。
    func removeGestures() {
        removeBackgroundTapGesture()
        removePanGesture()
    }

    /// 按当前配置刷新手势的启用状态。
    /// - Note: 库内当前没有调用者。配置是运行时可变的对象，修改
    ///   `config.dismissOnBackgroundTap` 后必须调用本方法才会同步到已安装的手势上
    ///   （`setupXxxGesture` 只在安装那一刻读取一次配置）。
    func updateGestureStates() {
        guard let viewController = viewController else { return }

        // 更新背景点击手势状态
        backgroundTapGesture?.isEnabled = viewController.config.dismissOnBackgroundTap

        // 更新拖拽手势状态：仅底部/顶部弹窗支持拖拽，且需要配置开关允许
        let supportsPanGesture = (viewController.config.position == .bottom || viewController.config.position == .top)
            && viewController.config.enablePanGestureDismiss
        panGesture?.isEnabled = supportsPanGesture
    }

    // MARK: - Private Methods - Background Tap

    /// 安装背景点击手势。
    ///
    /// 两个要点：
    /// - target 是 handler 自身，因此手势存活期间 handler 必须存活
    ///   （由 SKDialogViewController 强引用持有，生命周期一致）
    /// - 启用状态在安装时读取配置一次；之后改配置不会自动生效（见 updateGestureStates）
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

    // MARK: - Private Methods - Pan Gesture

    /// 安装拖拽手势。
    ///
    /// 启用条件：position 为 .bottom / .top（居中弹窗没有可拖出的方向）**且**
    /// `config.enablePanGestureDismiss` 为 true，两者缺一不可。
    private func setupPanGesture() {
        guard let viewController = viewController else { return }

        // 移除旧的手势
        removePanGesture()

        // 创建新的拖拽手势
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))

        // 仅底部/顶部弹窗支持拖拽，且需要配置开关允许
        // （展示后再改 enablePanGestureDismiss，需调用 updateGestureStates() 才会同步）
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
        guard viewController != nil else { return }

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

    /// 拖拽开始：记录基准位置，供后续计算位移与回弹目标。
    /// 用"记录起点"而不是每帧累加增量：每帧基于起点重算，避免浮点误差累积，
    /// 也让手势被打断后再次开始时状态是干净的。
    private func handlePanBegan(_ gesture: UIPanGestureRecognizer) {
        guard let viewController = viewController else { return }

        // 记录初始位置（回弹时的恢复目标）
        initialContainerCenter = viewController.containerView.center
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

    /// 计算拖拽进度（0.0 ~ 1.0），用于驱动遮罩的淡化程度。
    ///
    /// 满进度的基准取"容器高度的一半"而不是整高：如果以整高为基准，
    /// 用户拖到一半时遮罩才淡 25%，反馈会显得迟钝；以半高为基准能让淡化在中段就明显起来。
    /// - Parameter translation: 拖拽偏移量
    /// - Returns: 拖拽进度（0.0 - 1.0）
    private func calculateDragProgress(translation: CGPoint) -> CGFloat {
        guard let viewController = viewController else { return 0 }

        let containerHeight = viewController.containerView.bounds.height
        let dragDistance = abs(translation.y)

        // 拖拽距离超过容器高度的一半时进度为1
        let maxDragDistance = containerHeight * 0.5
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
    /// 基准是配置色自身的 alpha：因此 `config.backgroundMaskColor` 建议使用半透明颜色，
    /// 否则淡化幅度会显得很轻微。
    /// - Parameter progress: 拖拽进度
    private func updateBackgroundAlpha(progress: CGFloat) {
        guard let viewController = viewController else { return }

        // 根据拖拽进度调整背景透明度
        let originalAlpha = viewController.config.backgroundMaskColor.cgColor.alpha
        let newAlpha = originalAlpha * (1.0 - progress * 0.5) // 最多减少50%透明度

        viewController.backgroundView.backgroundColor = viewController.config.backgroundMaskColor.withAlphaComponent(newAlpha)
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
        guard let viewController = viewController else { return false }

        let containerHeight = viewController.containerView.bounds.height
        let dragDistance = abs(translation.y)
        let dragVelocity = abs(velocity.y)

        // 拖拽距离超过容器高度的1/3或者拖拽速度超过阈值
        let distanceThreshold = containerHeight / 3.0
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
                viewController.backgroundView.backgroundColor = viewController.config.backgroundMaskColor
            },
            completion: nil
        )
    }
}

// MARK: - Internal Access

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
    func cancelCurrentGestures() {
        panGesture?.isEnabled = false
        panGesture?.isEnabled = true

        backgroundTapGesture?.isEnabled = false
        backgroundTapGesture?.isEnabled = true
    }
}
