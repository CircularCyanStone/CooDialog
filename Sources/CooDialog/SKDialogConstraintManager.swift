//
//  SKDialogConstraintManager.swift
//  SiKu
//
//  Created by SOLO Coding on 2024/01/15.
//  Copyright © 2024 SiKu. All rights reserved.
//

/**
 * 文件功能描述：
 * SKDialog弹窗组件的约束管理器，专门负责处理弹窗容器视图的约束设置、更新和管理。
 * 该管理器将约束相关的复杂逻辑从主控制器中分离出来，提高代码的可维护性和可读性。
 *
 * 类型功能描述：
 * - 约束设置：根据弹窗配置设置容器视图的位置、尺寸约束
 * - 约束更新：动态更新约束以适应不同的显示模式和尺寸要求
 * - 位置管理：处理弹窗在不同位置（顶部、居中、底部）的约束配置
 * - 尺寸管理：处理固定尺寸、内容自适应等不同尺寸模式的约束
 * - 安全区域：处理延伸到安全区域的约束配置
 *
 * 设计原理（为什么约束需要独立的管理器）：
 * 约束是"成组生效"的——位置约束和尺寸约束必须能整组停用、整组替换，否则会出现
 * "旧约束还没失效、新约束已经生效"导致的冲突警告。因此这里用一个数组集中持有本管理器
 * 创建的全部约束，所有增删都通过它进行，保证任一时点的激活集合是明确的。
 *
 * 与 SKDialogContainerSizeManager 的分工（容易混淆，注意区分）：
 * - 本管理器负责**结构性**的约束：新建、成组替换（配置改变、需要重建约束体系的场景）
 * - 容器尺寸的动态调整（改 constant 而不重建）由 SKDialogContainerSizeManager 负责，
 *   它依赖本管理器回写到控制器上的 containerWidthConstraint / containerHeightConstraint 引用
 */

import UIKit

/// SKDialog约束管理器
/// 负责管理弹窗容器视图的约束设置和更新
@MainActor
class SKDialogConstraintManager {

    // MARK: - Properties

    /// 弱引用主控制器，避免循环引用
    /// （控制器持有本管理器，若这里强引用回去就构成引用环）
    private weak var viewController: SKDialogViewController?

    /// 容器视图的约束引用，用于动态更新。
    /// - Note: 数组实际同时持有**背景遮罩**与**容器**两部分的约束（见 setupContainerConstraints），
    ///   命名沿用了历史叫法。因此 clearConstraints() 会把两部分一起清掉，
    ///   而 removePositionConstraints() 只在其中筛出尺寸约束予以保留。
    private var containerConstraints: [NSLayoutConstraint] = []

    // MARK: - Initialization

    /// 初始化约束管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods

    /// 建立整套约束（位置 + 尺寸 + 遮罩），并一次性激活。
    ///
    /// 调用时机：SKDialogViewController.viewDidLoad()，紧跟视图层级搭建之后。
    /// 之所以"先清除再建立"：本方法可能在重复配置后再次调用，
    /// 不清除会产生两组锚点不同的约束，直接导致布局冲突与不可预期的位置。
    func setupContainerConstraints() {
        guard viewController != nil else { return }

        // 清除之前的约束
        clearConstraints()

        // 设置背景遮罩约束（填满整个视图）
        setupBackgroundConstraints()

        // 设置容器视图约束
        setupContainerViewConstraints()

        // 激活所有约束（统一激活而不是逐个 isActive = true：
        // 一次性激活可以让 AutoLayout 在同一轮求解中看到完整约束集，避免中间态冲突日志）
        NSLayoutConstraint.activate(containerConstraints)
    }

    /// 用新的尺寸模式替换现有尺寸约束。
    ///
    /// - Note: 库内当前没有调用者。运行时的尺寸变化走的是 SKDialogContainerSizeManager
    ///   （改 constant，不重建约束），只有在需要整体切换尺寸语义（例如从固定尺寸切换到
    ///   内容自适应）时才需要调用本方法。
    /// - Parameter sizeMode: 新的尺寸模式
    func updateConstraintsForSizeMode(_ sizeMode: SKDialogSizeMode) {
        guard let viewController = viewController else { return }

        // 移除尺寸相关的约束
        removeSizeConstraints()

        // 根据新的尺寸模式添加约束
        addSizeConstraints(for: sizeMode)

        // 更新布局
        viewController.view.layoutIfNeeded()
    }

    /// 用新的位置替换现有位置约束（尺寸约束保留）。
    ///
    /// - Note: 库内当前没有调用者——弹窗位置在设计上是"展示前确定、展示后不变"的，
    ///   若要支持运行时换位，调用本方法后还需同步刷新拖拽手势与滑动动画的起点配置。
    /// - Parameter position: 新的位置
    func updateConstraintsForPosition(_ position: SKDialogPosition) {
        guard let viewController = viewController else { return }

        // 移除位置相关的约束
        removePositionConstraints()

        // 根据新位置添加约束
        addPositionConstraints(for: position)

        // 更新布局
        viewController.view.layoutIfNeeded()
    }

    // MARK: - Private Methods

    /// 清除所有约束（停用 + 清空引用，两边必须成对，否则数组里会残留已停用对象）
    private func clearConstraints() {
        NSLayoutConstraint.deactivate(containerConstraints)
        containerConstraints.removeAll()
    }

    /// 背景遮罩约束：与控制器 view 四边对齐。
    ///
    /// 用四边等值约束而不是 frame：遮罩需要跟随父视图尺寸变化（旋转、分屏）自动铺满，
    /// 用约束后无需任何额外代码即可自适应。
    private func setupBackgroundConstraints() {
        guard let viewController = viewController else { return }

        viewController.backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let backgroundConstraints = [
            viewController.backgroundView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            viewController.backgroundView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            viewController.backgroundView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            viewController.backgroundView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ]

        containerConstraints.append(contentsOf: backgroundConstraints)
    }

    /// 容器视图约束：位置 + 尺寸，二者都以 config 的当前取值为准。
    private func setupContainerViewConstraints() {
        guard let viewController = viewController else { return }

        viewController.containerView.translatesAutoresizingMaskIntoConstraints = false

        // 添加位置约束
        addPositionConstraints(for: viewController.config.position)

        // 添加尺寸约束
        addSizeConstraints(for: viewController.config.sizeMode)
    }

    /// 生成位置约束。位置决定垂直锚点，水平方向一律居中并受 margins 保护。
    /// - Parameter position: 弹窗位置
    private func addPositionConstraints(for position: SKDialogPosition) {
        guard let viewController = viewController else { return }

        let config = viewController.config
        let containerView = viewController.containerView
        // 强解包的前提：本方法只在视图已加载后调用（viewDidLoad 触发的约束搭建，
        // 以及运行时的位置更新），此时 view 必然存在
        let parentView = viewController.view!

        var positionConstraints: [NSLayoutConstraint] = []

        // 水平居中约束（所有位置都需要）——统一居中而不是用 left/right 定位，
        // 这样"横向占满"的底部面板只需把 margins 设为 .zero，无需额外分支
        positionConstraints.append(
            containerView.centerXAnchor.constraint(equalTo: parentView.centerXAnchor)
        )

        // 根据位置设置垂直约束
        switch position {
        case .top:
            if config.extendToSafeArea {
                // 贴屏幕物理上边缘（内容需自行避开刘海），margins.top 作为额外留白
                positionConstraints.append(
                    containerView.topAnchor.constraint(equalTo: parentView.topAnchor, constant: config.margins.top)
                )
            } else {
                // 贴安全区上边缘：自动避开刘海/状态栏
                positionConstraints.append(
                    containerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: config.margins.top)
                )
            }

        case .center:
            // 仅垂直居中：不施加任何上下边距约束，容器高度完全由自身尺寸决定
            // （配合 contentAdaptive 时，内容过高会直接顶出屏幕——这是有意的取舍，
            //  居中弹窗的边距语义在配置类中已说明）
            positionConstraints.append(
                containerView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor)
            )

        case .bottom:
            if config.extendToSafeArea {
                positionConstraints.append(
                    containerView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -config.margins.bottom)
                )
            } else {
                positionConstraints.append(
                    containerView.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor, constant: -config.margins.bottom)
                )
            }
        }

        // 添加水平边距约束
        // 用不等式（>= / <=）而不是等值：容器宽度可能是内容决定的（contentAdaptive / heightFixed），
        // 等值约束会与"宽度由内容撑开"打架。不等式只规定上下限——
        // 既实现了左右留白的最小保护，又给内容自适应留出自由度
        positionConstraints.append(contentsOf: [
            containerView.leadingAnchor.constraint(greaterThanOrEqualTo: parentView.leadingAnchor, constant: config.margins.left),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: parentView.trailingAnchor, constant: -config.margins.right)
        ])

        containerConstraints.append(contentsOf: positionConstraints)
    }

    /// 生成尺寸约束。
    ///
    /// - Parameter sizeMode: 尺寸模式
    ///
    /// 关键副作用：把创建的宽度/高度约束**回写**到控制器上
    /// （`containerWidthConstraint` / `containerHeightConstraint`）。
    /// 这两个引用是 SKDialogContainerSizeManager 后续动态改尺寸的抓手——
    /// 有了它们才能"只改 constant 不重建约束"，从而让尺寸变化可以动画过渡。
    private func addSizeConstraints(for sizeMode: SKDialogSizeMode) {
        guard let viewController = viewController else { return }

        let containerView = viewController.containerView
        var sizeConstraints: [NSLayoutConstraint] = []

        switch sizeMode {
        case .fixed(let width, let height):
            // 只对非 nil 的维度加约束：nil 表示"该方向不限制"，
            // 于是在约束层面就退化为自适应，与 contentAdaptive 的效果一致
            if let width = width {
                let widthConstraint = containerView.widthAnchor.constraint(equalToConstant: width)
                sizeConstraints.append(widthConstraint)
                viewController.containerWidthConstraint = widthConstraint
            }
            if let height = height {
                let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: height)
                sizeConstraints.append(heightConstraint)
                viewController.containerHeightConstraint = heightConstraint
            }

        case .widthFixed(let width):
            sizeConstraints.append(containerView.widthAnchor.constraint(equalToConstant: width))
            // 刚 append 的就是本模式新增的唯一宽度约束，直接取 last 回写引用
            viewController.containerWidthConstraint = sizeConstraints.last

        case .heightFixed(let height):
            sizeConstraints.append(containerView.heightAnchor.constraint(equalToConstant: height))
            viewController.containerHeightConstraint = sizeConstraints.last

        case .contentAdaptive:
            // 内容自适应模式不需要额外的尺寸约束
            // 容器会根据内容自动调整大小
            // 这是本库"自适应"的实现方式：不计算 frame，而是完全交给 AutoLayout 的内在尺寸链——
            // contentView 被约束到容器四边（见 addContentView），因此它的内在尺寸会向上传递，
            // 撑开容器；任何缺少内在尺寸/约束的内容都会让容器退化为 0 尺寸
            break
        }

        containerConstraints.append(contentsOf: sizeConstraints)
    }

    /// 移除尺寸约束（位置约束保持不变）
    private func removeSizeConstraints() {
        guard let viewController = viewController else { return }

        // 移除并重置约束引用
        // 引用与数组内容都要清理：只清引用会让数组里留下"已停用但被强持有"的对象，
        // 后续 clearConstraints()/去重判断都会受影响
        if let widthConstraint = viewController.containerWidthConstraint {
            widthConstraint.isActive = false
            containerConstraints.removeAll { $0 === widthConstraint }
            viewController.containerWidthConstraint = nil
        }

        if let heightConstraint = viewController.containerHeightConstraint {
            heightConstraint.isActive = false
            containerConstraints.removeAll { $0 === heightConstraint }
            viewController.containerHeightConstraint = nil
        }
    }

    /// 移除位置约束（尺寸约束保留）
    private func removePositionConstraints() {
        // 保留尺寸约束，只移除位置约束
        // 通过身份比较（===）筛选：约束对象是引用类型，只有同一实例才算"同一个约束"
        let sizeConstraints = containerConstraints.filter { constraint in
            return constraint === viewController?.containerWidthConstraint ||
                   constraint === viewController?.containerHeightConstraint
        }

        // 停用所有约束
        NSLayoutConstraint.deactivate(containerConstraints)

        // 只保留尺寸约束
        containerConstraints = sizeConstraints

        // 重新激活尺寸约束
        NSLayoutConstraint.activate(containerConstraints)
    }
}

// MARK: - Internal Access

/// 调试 / 测试用的自检入口，不参与生产路径。
extension SKDialogConstraintManager {

    /// 当前处于激活状态的约束（用于调试布局问题）
    var activeConstraints: [NSLayoutConstraint] {
        return containerConstraints.filter { $0.isActive }
    }

    /// 自检：容器是否已挂到视图树上，且存在至少一条位置类约束。
    /// 用途是快速判断"布局没生效"是配置问题还是约束没建起来的问题。
    var isConstraintsValid: Bool {
        guard let viewController = viewController else { return false }

        // 检查容器视图是否有父视图
        guard viewController.containerView.superview != nil else { return false }

        // 检查是否有基本的位置约束
        let hasPositionConstraints = containerConstraints.contains { constraint in
            constraint.firstItem === viewController.containerView &&
            (constraint.firstAttribute == .centerX || 
             constraint.firstAttribute == .centerY ||
             constraint.firstAttribute == .top ||
             constraint.firstAttribute == .bottom)
        }

        return hasPositionConstraints
    }
}
