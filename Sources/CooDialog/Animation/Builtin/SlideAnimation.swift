//
//  SlideAnimation.swift
//  SiKu
//
//  内置动画实现：贴边面板的滑动（4 个方向 × 是否淡入，共 8 种内置类型）。
//  由 SKDialogAnimationManager 按 config.animationType 分发；无状态 struct，每次调用前临时构造、用完即弃。
//

import UIKit

/// 贴边面板的滑动动画：容器从屏幕外沿某个方向滑入（可叠加淡入），退场时沿原路滑回。
///
/// 一个实现覆盖 8 种内置滑动类型：差别只有"位移在哪根轴、符号、容器是否淡入"三处，
/// 因此这里用「方向 + 是否淡入」两个参数表达，而不是拆成 8 个几乎相同的类型
/// （拆开意味着同一个兜底值、同一条距离公式要维护 8 份）。
///
/// 两条与其它动画不同的实现约定：
/// 1. 入场前先求解一次布局（`superview?.layoutIfNeeded()`）：滑动距离取决于容器尺寸，
///    尺寸未知时会退化成兜底距离（见 `slideOffset`），避免出现"零位移"的假滑动
/// 2. 退场不再求解布局：拖拽可能已经改变了容器的 center，此刻求解会把用户拖出来的位移
///    抹掉（约束把视图拉回原位），视觉上表现为莫名其妙的"回弹"
struct SlideAnimation: SKDialogAnimationProtocol {

    /// 滑动方向：容器入场时的起点所在方向
    enum Direction {
        case top
        case bottom
        case left
        case right
    }

    /// 入场起点方向（同时决定退场的去向——两者镜像，首尾一致）
    let direction: Direction

    /// 入场时容器是否从全透明淡入。
    /// `false` 表示容器全程可见、只有遮罩淡入：速度感更强，适合轻量的提示条；
    /// `true`（WithFade 系列）观感更柔和，适合较高的面板。
    let fadesContainer: Bool

    // MARK: - SKDialogAnimationProtocol

    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 确保 AutoLayout 已求解：下面的 bounds 必须反映真实尺寸，滑动距离才算得准
        containerView.superview?.layoutIfNeeded()

        let offset = Self.slideOffset(
            for: direction,
            containerSize: containerView.bounds.size,
            margins: config.margins
        )

        // 起点：屏幕外（带符号位移）＋ （可选）全透明，遮罩始终从透明淡入
        containerView.transform = direction.translation(offset: offset)
        containerView.alpha = fadesContainer ? 0 : 1
        backgroundView.alpha = 0

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.transform = .identity
                if fadesContainer {
                    containerView.alpha = 1
                }
            },
            completion: { _ in
                completion()
            }
        )
    }

    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 注意：这里刻意不调用 layoutIfNeeded（原因见类型注释）
        let offset = Self.slideOffset(
            for: direction,
            containerSize: containerView.bounds.size,
            margins: config.margins
        )

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.transform = direction.translation(offset: offset)
                if fadesContainer {
                    containerView.alpha = 0
                }
            },
            completion: { _ in
                completion()
            }
        )
    }

    // MARK: - 滑动距离（全库唯一公式）

    /// 入场起点的位移量（带符号）：正值表示"从下方/右方进入"，负值表示"从上方/左方进入"。
    ///
    /// 距离 = 容器在滑动轴上的尺寸 + 该方向的边距，保证起点完全在屏幕外
    /// （即便是贴边面板，也不会露出一个边角）。
    ///
    /// - Important: 全库只有这一处计算滑动距离——入场前的预置首帧
    ///   （`SKDialogAnimationStateManager`）与这里的动画起点都调用它。
    ///   两处各算一套时，首帧预置的位置与动画起点会不一致，肉眼可见地跳一下。
    /// - Parameters:
    ///   - direction: 起点方向
    ///   - containerSize: 容器尺寸（AutoLayout 求解后的 bounds）
    ///   - margins: 弹窗配置里的边距
    /// - Returns: 位移量（带符号，直接用于生成平移变换）
    static func slideOffset(for direction: Direction, containerSize: CGSize, margins: UIEdgeInsets) -> CGFloat {
        switch direction {
        case .top:
            return -(max(containerSize.height, minimumSlideDistance) + margins.top)
        case .bottom:
            return max(containerSize.height, minimumSlideDistance) + margins.bottom
        case .left:
            return -(max(containerSize.width, minimumSlideDistance) + margins.left)
        case .right:
            return max(containerSize.width, minimumSlideDistance) + margins.right
        }
    }

    /// 布局尚未求解时的兜底滑动距离：即便尺寸未知，也保证有一段可见的位移，
    /// 而不是"零位移的假滑动"。正常布局完成后不会触发。
    private static let minimumSlideDistance: CGFloat = 100
}

// MARK: - 方向

extension SlideAnimation.Direction {

    /// 位移是否作用在水平轴
    var isHorizontal: Bool {
        switch self {
        case .left, .right: return true
        case .top, .bottom: return false
        }
    }

    /// 把位移量转成对应轴上的平移变换。
    /// 入场用它把容器摆到屏幕外的起点；退场用同一个变换把容器送回起点，首尾一致。
    func translation(offset: CGFloat) -> CGAffineTransform {
        isHorizontal
            ? CGAffineTransform(translationX: offset, y: 0)
            : CGAffineTransform(translationX: 0, y: offset)
    }
}
