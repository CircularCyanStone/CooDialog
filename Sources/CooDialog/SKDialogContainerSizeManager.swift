//
//  SKDialogContainerSizeManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的容器尺寸管理器，专门负责处理弹窗容器视图的尺寸动态更新和管理。
 * 该管理器将容器尺寸相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 尺寸更新：动态更新容器的宽度、高度或整体尺寸
 * - 约束同步：更新尺寸时同步更新相关约束
 * - 配置同步：更新尺寸时同步更新弹窗配置
 * - 动画支持：支持尺寸变化的动画效果
 * - 内容适配：根据内容自动调整容器尺寸
 *
 * 设计原理（为什么"改尺寸"要做三件事）：
 * 一次尺寸变更包含三个必须同步的环节，缺一都会留下不一致：
 * 1. 改约束（写 constant）：这是唯一真正影响布局的动作
 * 2. 回写 config.sizeMode：让"配置"继续等于"当前真实状态"，否则后续任何基于 config 的
 *    判断（重建约束、自检）都会与实际情况不符
 * 3. 在动画块内 layoutIfNeeded：单纯改 constant 不会产生动画，只有当布局求解发生在
 *    UIView.animate 的闭包内，UIKit 才会把受影响的 frame 变化插值成过渡动画
 *
 * 与 SKDialogConstraintManager 的分工：
 * 本管理器只使用控制器上已存在的 containerWidthConstraint / containerHeightConstraint 引用
 * 改 constant（或在其为 nil 时补建），不重建整套约束——这样已经激活的位置约束不受影响，
 * 尺寸变化可以平滑过渡。需要整体切换尺寸语义时才回到 SKDialogConstraintManager。
 *
 * 典型使用场景：内容异步变化后需要重新贴合弹窗尺寸
 * （例如 WebView 加载完成、键盘弹出、列表增删行、文案换行导致高度变化）。
 */

import UIKit

/// SKDialog容器尺寸管理器
/// 负责管理弹窗容器视图的尺寸动态更新
@MainActor
class SKDialogContainerSizeManager {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    private weak var viewController: SKDialogViewController?

    /// 尺寸变化动画配置。
    ///
    /// 用私有结构体集中参数（而不是散落的字面量）的理由：尺寸过渡是全库统一的一种动画，
    /// 集中后既便于统一调整，也不会污染公开 API。
    ///
    /// - Note: 这套参数与 SKDialogConfig 中的入场/退场动画参数**相互独立**：
    ///   尺寸变化始终使用这里的 0.3s / damping 0.8 / velocity 0，
    ///   宿主调整 `config.animationDuration` 不会影响尺寸过渡。
    ///   options 里的 .curveEaseInOut 只在非弹簧路径下才有意义，
    ///   此处保留是为了与其它动画调用形态保持一致。
    private struct SizeAnimationConfig {
        let duration: TimeInterval
        let damping: CGFloat
        let velocity: CGFloat
        let options: UIView.AnimationOptions

        static let `default` = SizeAnimationConfig(
            duration: 0.3,
            damping: 0.8,
            velocity: 0,
            options: [.curveEaseInOut]
        )
    }

    // MARK: - Initialization

    /// 初始化容器尺寸管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods - Height Management

    /// 动态更新容器高度（约束 + 配置 + 动画布局三步）。
    ///
    /// 调用时机：内容高度变化后，宿主主动调用（控制器上的
    /// `updateContainerHeight(_:animated:)` 就是转发到这里）。
    /// - Parameters:
    ///   - height: 新的高度值（点）
    ///   - animated: 是否用弹簧动画过渡；内容突变（如展开/收起）建议 true，
    ///     首帧贴合（如展示前预计算）建议 false
    ///   - completion: 更新完成回调
    func updateContainerHeight(_ height: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        // 控制器已释放时仍然回调：保证调用方的后续流程不会因为"视图没了"而被卡住
        guard viewController != nil else {
            completion?()
            return
        }

        // 更新约束
        updateHeightConstraint(height)

        // 更新配置
        updateConfigForHeightChange(height)

        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }

    /// 按当前内容反算高度并应用。
    ///
    /// - Note: 库内当前没有调用者（forceRefreshSize() 内部间接调用 adjustSizeToContent）。
    ///   保留的用途：宿主在内容变化后要求"重新贴合内容"。
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustHeightToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }

        // 计算内容所需高度
        let contentHeight = calculateContentHeight()

        // 更新高度
        updateContainerHeight(contentHeight, animated: animated, completion: completion)
    }

    // MARK: - Public Methods - Width Management

    /// 动态更新容器宽度。与高度版本逻辑对称。
    /// - Parameters:
    ///   - width: 新的宽度值
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func updateContainerWidth(_ width: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }

        // 更新约束
        updateWidthConstraint(width)

        // 更新配置
        updateConfigForWidthChange(width)

        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }

    /// 按当前内容反算宽度并应用。
    /// - Note: 库内当前没有调用者，保留给宿主按需调用。
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustWidthToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }

        // 计算内容所需宽度
        let contentWidth = calculateContentWidth()

        // 更新宽度
        updateContainerWidth(contentWidth, animated: animated, completion: completion)
    }

    // MARK: - Public Methods - Size Management

    /// 动态更新容器宽高（一次事务内同时改两个方向，避免"先宽后高"的两段动画）。
    /// - Parameters:
    ///   - size: 新的尺寸
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func updateContainerSize(_ size: CGSize, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }

        // 更新约束
        updateSizeConstraints(size)

        // 更新配置
        updateConfigForSizeChange(size)

        // 执行布局更新
        performLayoutUpdate(animated: animated, completion: completion)
    }

    /// 按当前内容反算宽高并应用。
    /// - Note: 库内无直接调用者（仅在 forceRefreshSize() 中被间接调用）。
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 更新完成回调
    func adjustSizeToContent(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard viewController != nil else {
            completion?()
            return
        }

        // 计算内容所需尺寸
        let contentSize = calculateContentSize()

        // 更新尺寸
        updateContainerSize(contentSize, animated: animated, completion: completion)
    }

    // MARK: - Private Methods - Constraint Updates

    /// 更新（或按需补建）高度约束。
    ///
    /// 为什么要处理"没有约束"的情况：`.contentAdaptive` 模式下容器本来没有高度约束，
    /// 此时要求一个确定高度，就必须现场补一条并把引用交给控制器，
    /// 后续再改高度才能走"改 constant"的轻量路径。
    /// 补建的约束是 required 优先级，因此它会胜出内容的内在尺寸，把高度定下来。
    ///
    /// - Note: 补建的约束只被激活、未登记进 SKDialogConstraintManager 的约束数组，
    ///   若之后触发整套约束重建（setupContainerConstraints），它会残留在容器上。
    private func updateHeightConstraint(_ height: CGFloat) {
        guard let viewController = viewController else { return }

        if let heightConstraint = viewController.containerHeightConstraint {
            heightConstraint.constant = height
        } else {
            // 如果没有高度约束，创建一个新的
            let newConstraint = viewController.containerView.heightAnchor.constraint(equalToConstant: height)
            newConstraint.isActive = true
            viewController.containerHeightConstraint = newConstraint
        }
    }

    /// 更新（或按需补建）宽度约束，逻辑同 updateHeightConstraint。
    private func updateWidthConstraint(_ width: CGFloat) {
        guard let viewController = viewController else { return }

        if let widthConstraint = viewController.containerWidthConstraint {
            widthConstraint.constant = width
        } else {
            // 如果没有宽度约束，创建一个新的
            let newConstraint = viewController.containerView.widthAnchor.constraint(equalToConstant: width)
            newConstraint.isActive = true
            viewController.containerWidthConstraint = newConstraint
        }
    }

    /// 同时更新宽高约束（两条都走上面的容错路径）
    private func updateSizeConstraints(_ size: CGSize) {
        updateWidthConstraint(size.width)
        updateHeightConstraint(size.height)
    }

    // MARK: - Private Methods - Config Updates

    /// 把"高度已确定"这一事实写回配置，使 config.sizeMode 与实际约束保持一致。
    ///
    /// 各分支的语义（这是"回写"而非"覆盖"的原因）：
    /// - `.fixed`：保留原宽度，仅更新高度（宽度是调用方明确指定的，不能丢）
    /// - `.heightFixed`：更新固定高度（保持"只固定高度"的原始意图）
    /// - `.widthFixed`：升格为 `.fixed`（因为现在高度也被定死了，不再是"高度随内容"）
    /// - `.contentAdaptive`：**不改**——自适应弹窗被动态改高度后，仍应允许后续内容继续撑开它；
    ///   若在这里改成 .fixed，弹窗就被永久钉死，后续内容变化不再生效
    private func updateConfigForHeightChange(_ height: CGFloat) {
        guard let viewController = viewController else { return }

        // 根据当前尺寸模式更新配置
        switch viewController.config.sizeMode {
        case .fixed(let width, _):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .heightFixed(_):
            viewController.config.sizeMode = .heightFixed(height)
        case .widthFixed(let width):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .contentAdaptive:
            // 内容自适应模式不需要更新配置
            break
        }
    }

    /// 把"宽度已确定"写回配置（规则与高度版镜像）。
    private func updateConfigForWidthChange(_ width: CGFloat) {
        guard let viewController = viewController else { return }

        // 根据当前尺寸模式更新配置
        switch viewController.config.sizeMode {
        case .fixed(_, let height):
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .widthFixed(_):
            viewController.config.sizeMode = .widthFixed(width)
        case .heightFixed(let height):
            // 升格为 .fixed：高度仍固定，宽度从此也固定
            viewController.config.sizeMode = .fixed(width: width, height: height)
        case .contentAdaptive:
            // 内容自适应模式不需要更新配置
            break
        }
    }

    /// 同时给出宽高时，配置直接收敛为 `.fixed`（两个方向都已有确定值）
    private func updateConfigForSizeChange(_ size: CGSize) {
        guard let viewController = viewController else { return }

        viewController.config.sizeMode = .fixed(width: size.width, height: size.height)
    }

    // MARK: - Private Methods - Content Size Calculation

    /// 计算尺寸上限时使用的"可用屏幕区域"。
    ///
    /// 优先取弹窗所在 window 的场景坐标空间：iPad 分屏 / Slide Over / 多窗口下，
    /// 这才是真实可用区域，而 `UIScreen.main.bounds` 会返回整屏尺寸（偏大）。
    /// 弹窗尚未上屏（取不到 scene）时回退到 `UIScreen.main.bounds`，与历史行为一致。
    private var availableScreenBounds: CGRect {
        if let scene = viewController?.view.window?.windowScene {
            return scene.coordinateSpace.bounds
        }
        return UIScreen.main.bounds
    }

    /// 反算内容所需高度。
    ///
    /// 算法：让 AutoLayout 在"宽度已确定、高度取最小可行值"的前提下求解一次，
    /// 得到的就是内容当前的理想高度——这与遍历子视图累加 frame 的做法有本质区别：
    /// AutoLayout 下 frame 可能尚未确定、也不反映约束意图，只有 systemLayoutSizeFitting
    /// 的结果才与当前约束体系一致。
    ///
    /// - Returns: 内容高度（最小 44pt，保证单行文本/触控目标不会被压扁）
    private func calculateContentHeight() -> CGFloat {
        guard let viewController = viewController else { return 0 }

        // 获取容器视图的当前宽度
        let containerWidth = viewController.containerView.bounds.width

        // 如果容器宽度为0，使用可用区域宽度减去边距
        // （容器还没布局时的兜底，避免用 0 宽度去反算高度导致结果失真）
        let availableWidth = containerWidth > 0 ? containerWidth :
            availableScreenBounds.width - viewController.config.margins.left - viewController.config.margins.right

        // 计算内容视图所需的高度
        // 水平方向 required：宽度是外部给定的前提，必须遵守；
        // 垂直方向 fittingSizeLevel：高度取最小可行的紧凑值，而不是拉伸填满
        let targetSize = CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height)
        let contentHeight = viewController.containerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        return max(contentHeight, 44) // 最小高度44
    }

    /// 反算内容所需宽度（与高度版镜像：宽度取最小可行值，高度固定）。
    ///
    /// 结果会被夹在 [100, 屏幕宽度 - 左右边距] 之间，避免单行超长文本把弹窗拉成满屏宽。
    /// - Returns: 内容宽度
    private func calculateContentWidth() -> CGFloat {
        guard let viewController = viewController else { return 0 }

        // 获取容器视图的当前高度
        let containerHeight = viewController.containerView.bounds.height

        // 如果容器高度为0，使用一个合理的默认值
        let availableHeight = containerHeight > 0 ? containerHeight : 200

        // 计算内容视图所需的宽度
        let targetSize = CGSize(width: UIView.layoutFittingCompressedSize.width, height: availableHeight)
        let contentWidth = viewController.containerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .required
        ).width

        // 限制最大宽度为可用区域宽度减去边距
        let maxWidth = availableScreenBounds.width - viewController.config.margins.left - viewController.config.margins.right

        return min(max(contentWidth, 100), maxWidth) // 最小宽度100，最大宽度为屏幕宽度减去边距
    }

    /// 反算内容所需尺寸（两个方向都取最小可行值，即"压缩尺寸"）。
    ///
    /// 上限取屏幕尺寸减去边距，下限取 100×44。
    /// - Note: 上限取自 availableScreenBounds——优先使用弹窗所在 window 的场景尺寸，
    ///   因此在 iPad 分屏 / 多窗口下得到的是真实可用区域而非整屏尺寸；
    ///   仅在弹窗尚未上屏时回退到 `UIScreen.main.bounds`。
    /// - Returns: 内容尺寸
    private func calculateContentSize() -> CGSize {
        guard let viewController = viewController else { return .zero }

        // 使用系统布局计算合适的尺寸
        let fittingSize = viewController.containerView.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )

        // 限制尺寸范围
        let maxWidth = availableScreenBounds.width - viewController.config.margins.left - viewController.config.margins.right
        let maxHeight = availableScreenBounds.height - viewController.config.margins.top - viewController.config.margins.bottom

        let width = min(max(fittingSize.width, 100), maxWidth)
        let height = min(max(fittingSize.height, 44), maxHeight)

        return CGSize(width: width, height: height)
    }

    // MARK: - Private Methods - Layout Updates

    /// 统一执行布局更新（并保证 completion 一定被调用）。
    ///
    /// 动画的关键点：约束变更必须发生在动画块**之前**，而在块内只调用 `layoutIfNeeded()`。
    /// UIKit 的动画机制是"在动画块内触发的属性变化才会被插值"——
    /// 子视图 frame 是由这次布局求解算出来的，所以只要把求解放进块内，
    /// 宽高变化就会表现为平滑过渡，而不是瞬间跳变。
    /// - Parameters:
    ///   - animated: 是否使用动画
    ///   - completion: 完成回调
    private func performLayoutUpdate(animated: Bool, completion: (() -> Void)?) {
        guard let viewController = viewController else {
            completion?()
            return
        }

        if animated {
            let config = SizeAnimationConfig.default

            UIView.animate(
                withDuration: config.duration,
                delay: 0,
                usingSpringWithDamping: config.damping,
                initialSpringVelocity: config.velocity,
                options: config.options,
                animations: {
                    viewController.view.layoutIfNeeded()
                },
                completion: { _ in
                    completion?()
                }
            )
        } else {
            // 非动画路径：立即求解布局并同步回调，调用方可在其后立刻读取新尺寸
            viewController.view.layoutIfNeeded()
            completion?()
        }
    }
}

// MARK: - Internal Access

/// 调试 / 测试用的只读快照与强制刷新入口，不参与生产路径。
extension SKDialogContainerSizeManager {

    /// 容器当前的实际尺寸（布局求解后的 bounds，浮点值为测量结果）
    var currentContainerSize: CGSize {
        guard let viewController = viewController else { return .zero }
        return viewController.containerView.bounds.size
    }

    /// 当前尺寸约束的常量值（nil 表示该方向没有约束，即自适应）
    var currentConstraintValues: (width: CGFloat?, height: CGFloat?) {
        guard let viewController = viewController else { return (nil, nil) }

        let width = viewController.containerWidthConstraint?.constant
        let height = viewController.containerHeightConstraint?.constant

        return (width, height)
    }

    /// 自检：约束引用与 sizeMode 是否一致（可用于测试中断言配置与实现没有脱节）
    var isSizeConstraintsValid: Bool {
        guard let viewController = viewController else { return false }

        switch viewController.config.sizeMode {
        case .fixed(_, _):
            // 固定尺寸模式要求宽高约束都存在
            return viewController.containerWidthConstraint != nil && viewController.containerHeightConstraint != nil
        case .widthFixed(_):
            return viewController.containerWidthConstraint != nil
        case .heightFixed(_):
            return viewController.containerHeightConstraint != nil
        case .contentAdaptive:
            return true // 内容自适应模式不需要固定约束
        }
    }

    /// 强制刷新尺寸：立即重排一次，若处于自适应模式则再按内容重新贴合。
    ///
    /// 适用场景：内容已经变化但 AutoLayout 尚未失效（宿主直接改了子视图的内部状态、
    /// 或异步数据在布局之后才回填），需要强制走一遍"布局 → 反算尺寸"的流程。
    func forceRefreshSize() {
        guard let viewController = viewController else { return }

        // 强制重新计算布局
        viewController.containerView.setNeedsLayout()
        viewController.containerView.layoutIfNeeded()

        // 如果是内容自适应模式，重新调整尺寸
        if case .contentAdaptive = viewController.config.sizeMode {
            adjustSizeToContent(animated: false)
        }
    }
}
