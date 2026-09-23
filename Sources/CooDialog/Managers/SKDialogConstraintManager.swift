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
 * - 约束设置：根据弹窗配置建立遮罩铺满约束，以及容器的位置、尺寸约束
 * - 尺寸更新：动态改尺寸时改写已有约束的 constant，没有则补建并登记
 * - 位置管理：处理弹窗在不同位置（顶部、居中、底部）的约束配置
 * - 尺寸管理：处理固定尺寸、内容自适应等不同尺寸模式的约束
 * - 安全区域：处理延伸到安全区域的约束配置
 *
 * 设计原理（为什么约束需要独立的管理器，且要分两组账本）：
 * 两组约束的生命周期不同，混在一个数组里会让"清理"这件事没有明确边界：
 * - 遮罩约束（backgroundConstraints）：四边铺满，搭建时建一次，此后不再改动
 * - 容器约束（containerConstraints）：位置 + 尺寸，动态改尺寸时会逐条改写
 * 全部增删都通过这两个账本进行，保证任一时点的激活集合是明确的。
 *
 * 运行时的能力边界（重要，这是本类对外行为的定义）：
 * 位置与尺寸模式都在**展示前**确定。运行时只支持"改尺寸数值"——
 * 即 setContainerWidth / setContainerHeight（由 SKDialogContainerSizeManager 驱动），
 * 它改写已有约束的 constant，或在缺少该方向约束时补建一条。
 * 不支持运行时整体切换位置或尺寸语义：需要另一种形态时请新建弹窗
 * （SKDialogConfig 在库外只读，重建的成本也很低）。
 *
 * 与 SKDialogContainerSizeManager 的分工：
 * 后者负责计算内容尺寸、动画过渡与 config 回写，不直接接触 NSLayoutConstraint 对象；
 * 本管理器是约束的唯一持有者与唯一修改入口，二者的依赖方向单向（尺寸管理器 → 本管理器）。
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

    /// 遮罩约束账本：backgroundView 与控制器 view 的四边等值约束
    private var backgroundConstraints: [NSLayoutConstraint] = []

    /// 容器约束账本：位置约束 + 尺寸约束
    private var containerConstraints: [NSLayoutConstraint] = []

    /// 容器宽度约束（由 addSizeConstraints 建立，由 setContainerWidth 修改）。
    /// - Important: 不变量——`widthConstraint` 非 nil ⟺ 它已登记进 `containerConstraints` 且 `isActive`。
    ///   引用与账本必须同属一个类型，否则第二个写入方（例如"改尺寸"路径）会破坏这条不变量。
    private var widthConstraint: NSLayoutConstraint?

    /// 容器高度约束（语义与不变量同 widthConstraint）
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    /// 初始化约束管理器
    /// - Parameter viewController: 关联的弹窗控制器
    init(viewController: SKDialogViewController) {
        self.viewController = viewController
    }

    // MARK: - Public Methods

    /// 建立整套约束（遮罩铺满 + 容器位置 + 容器尺寸），并一次性激活。
    ///
    /// 调用时机：SKDialogViewController.viewDidLoad()，紧跟视图层级搭建之后。
    /// 之所以"先清除再建立"：本方法可能在重复配置后再次调用，
    /// 不清除会产生两组锚点不同的约束，直接导致布局冲突与不可预期的位置。
    func setupContainerConstraints() {
        // 清除之前的约束（连同尺寸约束引用，保证引用与账本始终同源）
        clearConstraints()

        // 设置背景遮罩约束（填满整个视图）
        setupBackgroundConstraints()

        // 设置容器视图约束
        setupContainerViewConstraints()

        // 激活所有约束（统一激活而不是逐个 isActive = true：
        // 一次性激活可以让 AutoLayout 在同一轮求解中看到完整约束集，避免中间态冲突日志）
        NSLayoutConstraint.activate(backgroundConstraints + containerConstraints)
    }

    // MARK: - Size Constraint Updates（动态改尺寸的落地点）

    /// 设置容器宽度：已有宽度约束时只改 constant（不重建约束，尺寸变化才能动画过渡）；
    /// 没有时（内容自适应模式）补建一条并**登记进账本**——补建与登记写在同一处，
    /// 保证不变量（引用非 nil ⟺ 已登记且已激活）始终只有一个维护者。
    ///
    /// 补建约束的优先级按尺寸模式分档（见 sizeConstraintPriority）：自适应模式是"临时钉住"，
    /// 内容变大时仍能撑开它；已明确固定的方向则压过内容诉求。
    ///
    /// 调用方：SKDialogContainerSizeManager（宿主改尺寸时按需驱动）。
    func setContainerWidth(_ width: CGFloat) {
        guard let viewController = viewController else { return }

        if let existing = widthConstraint {
            existing.constant = width
            return
        }

        let newConstraint = viewController.containerView.widthAnchor.constraint(equalToConstant: width)
        newConstraint.priority = sizeConstraintPriority(for: viewController.config.sizeMode)
        newConstraint.isActive = true
        containerConstraints.append(newConstraint)
        widthConstraint = newConstraint
    }

    /// 设置容器高度，逻辑与 setContainerWidth 完全对称。
    func setContainerHeight(_ height: CGFloat) {
        guard let viewController = viewController else { return }

        if let existing = heightConstraint {
            existing.constant = height
            return
        }

        let newConstraint = viewController.containerView.heightAnchor.constraint(equalToConstant: height)
        newConstraint.priority = sizeConstraintPriority(for: viewController.config.sizeMode)
        newConstraint.isActive = true
        containerConstraints.append(newConstraint)
        heightConstraint = newConstraint
    }
}

// MARK: - Private

extension SKDialogConstraintManager {

    /// 补建尺寸约束时使用的优先级。
    ///
    /// 分档的理由是"同一个 API 在两种模式下的本意不同"：
    /// - `.contentAdaptive` 下调用 `updateContainerHeight` 等入口，本意是"把尺寸临时钉到某个值"，
    ///   而不是"改变尺寸模式"。因此补建的约束必须**低于**内容的固有尺寸诉求
    ///   （content compression resistance 默认 750），内容变大时才能把它撑开——
    ///   若用 required，容器会被永久定死，而配置层仍写着 `.contentAdaptive`，
    ///   形成"配置说自适应、约束已钉死"的隐性不一致
    /// - `.fixed` / `.fixedWidth` / `.fixedHeight` 下，方向已被明确指定固定，就该压过内容诉求
    ///
    /// 取 500 而不是 `.defaultHigh`(750)：750 与内容抗压缩同优先级，AutoLayout 打破哪一条
    /// 并不确定（会打印冲突日志），行为不可预测；500 明确落在
    /// 「内容抗压缩 750」与「内容压缩（hugging）250」之间，于是行为是确定的：
    /// 内容更大 → 撑开容器（自适应语义成立）；内容更小 → 保持宿主设定的值（尊重显式调用）。
    private func sizeConstraintPriority(for sizeMode: SKDialogSizeMode) -> UILayoutPriority {
        switch sizeMode {
        case .contentAdaptive:
            return UILayoutPriority(500)
        case .fixed, .fixedWidth, .fixedHeight:
            return .required
        }
    }

    /// 清除所有约束：停用 + 清空两组账本 + 清空尺寸约束引用。
    /// 三件事必须成对完成——只清账本会让 `widthConstraint` / `heightConstraint` 指向
    /// "已停用且不在账本里"的悬空对象，之后 setContainerWidth 会改写一条失效的约束，
    /// 自检 isSizeConstraintsValid 也会误报不一致。
    private func clearConstraints() {
        NSLayoutConstraint.deactivate(backgroundConstraints)
        NSLayoutConstraint.deactivate(containerConstraints)
        backgroundConstraints.removeAll()
        containerConstraints.removeAll()
        widthConstraint = nil
        heightConstraint = nil
    }

    /// 背景遮罩约束：与控制器 view 四边对齐。
    ///
    /// 用四边等值约束而不是 frame：遮罩需要跟随父视图尺寸变化（旋转、分屏）自动铺满，
    /// 用约束后无需任何额外代码即可自适应。
    private func setupBackgroundConstraints() {
        guard let viewController = viewController else { return }

        viewController.backgroundView.translatesAutoresizingMaskIntoConstraints = false

        backgroundConstraints = [
            viewController.backgroundView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            viewController.backgroundView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            viewController.backgroundView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            viewController.backgroundView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ]
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
        // 强解包的前提：本方法只在视图已加载后调用（viewDidLoad 触发的约束搭建），
        // 此时 view 必然存在
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
        // 用不等式（>= / <=）而不是等值：容器宽度可能是内容决定的（.contentAdaptive / .fixedHeight），
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
    /// 关键副作用：把创建的宽度/高度约束**登记**在本类型的
    /// `widthConstraint` / `heightConstraint` 上（与 `containerConstraints` 账本同源）。
    /// 这两个引用是"改 constant 不重建约束"的抓手——有了它们，
    /// 运行时的尺寸变化（setContainerWidth / setContainerHeight）才能走轻量路径并动画过渡。
    private func addSizeConstraints(for sizeMode: SKDialogSizeMode) {
        guard let viewController = viewController else { return }

        let containerView = viewController.containerView
        var sizeConstraints: [NSLayoutConstraint] = []

        switch sizeMode {
        case .fixed(let width, let height):
            // 两个方向都固定：两条约束都建
            // （case 本身保证这里一定有值，不存在"只给一个方向"的可能）
            let widthConstraint = containerView.widthAnchor.constraint(equalToConstant: width)
            let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: height)
            sizeConstraints.append(contentsOf: [widthConstraint, heightConstraint])
            self.widthConstraint = widthConstraint
            self.heightConstraint = heightConstraint

        case .fixedWidth(let width):
            // 只固定宽度：高度方向不加约束，交给内容的内在尺寸决定
            let widthConstraint = containerView.widthAnchor.constraint(equalToConstant: width)
            sizeConstraints.append(widthConstraint)
            self.widthConstraint = widthConstraint

        case .fixedHeight(let height):
            // 只固定高度：宽度方向不加约束，交给内容的内在尺寸决定
            let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: height)
            sizeConstraints.append(heightConstraint)
            self.heightConstraint = heightConstraint

        case .contentAdaptive:
            // 不加任何尺寸约束，完全交给 AutoLayout 的内在尺寸链：
            // contentView 被约束到容器四边（见 addContentView），因此它的内在尺寸会向上传递，
            // 撑开容器；任何缺少内在尺寸/约束的内容都会让容器退化为 0 尺寸
            break
        }

        containerConstraints.append(contentsOf: sizeConstraints)
    }
}

// MARK: - Debug & Testing

/// 调试 / 测试用的自检入口，不参与生产路径。
extension SKDialogConstraintManager {

    /// 当前处于激活状态的约束（用于调试布局问题）
    var activeConstraints: [NSLayoutConstraint] {
        return (backgroundConstraints + containerConstraints).filter { $0.isActive }
    }

    /// 自检：尺寸约束与 `config.sizeMode` 是否一致，且引用与账本是否同源。
    ///
    /// 两件事一起查：
    /// 1. 引用与账本同源——非 nil 的引用必须已登记且已激活（防止"补建了但没登记"的脱节）
    /// 2. 约束组合与模式一一对应——模式声明固定的方向，必须都有对应约束：
    ///    `.fixed` 要求两条都在（它只表示"两个方向都固定"），
    ///    `.fixedWidth` / `.fixedHeight` 各要求一条，`.contentAdaptive` 不要求。
    ///    正因为"模式 ↔ 约束"严格对应，这里才能给出确定结论；旧设计允许 `.fixed` 传 nil，
    ///    那种状态下"只建了一条"属于合法，"不一致"就没有唯一答案。
    var isSizeConstraintsValid: Bool {
        guard let viewController = viewController else { return false }

        // 1) 引用与账本同源
        if let widthConstraint = widthConstraint,
           !(widthConstraint.isActive && containerConstraints.contains { $0 === widthConstraint }) {
            return false
        }
        if let heightConstraint = heightConstraint,
           !(heightConstraint.isActive && containerConstraints.contains { $0 === heightConstraint }) {
            return false
        }

        // 2) 约束组合与 sizeMode 一一对应
        switch viewController.config.sizeMode {
        case .fixed(_, _):
            return widthConstraint != nil && heightConstraint != nil
        case .fixedWidth(_):
            return widthConstraint != nil
        case .fixedHeight(_):
            return heightConstraint != nil
        case .contentAdaptive:
            // 不要求固定约束：运行中被 updateContainerHeight / updateContainerWidth 临时钉住某个方向时，
            // 补建的约束只是"当前尺寸状态"，模式本身仍是自适应，因此同样算一致
            return true
        }
    }

    /// 自检：遮罩是否铺满、容器是否已挂到视图树上，且存在至少一条位置类约束。
    /// 用途是快速判断"布局没生效"是配置问题还是约束没建起来的问题。
    var isConstraintsValid: Bool {
        guard let viewController = viewController else { return false }

        // 遮罩四条边必须齐全且处于激活状态（少了任何一条，遮罩都会塌缩或错位）
        guard backgroundConstraints.count == 4,
              backgroundConstraints.allSatisfy({ $0.isActive }) else { return false }

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
