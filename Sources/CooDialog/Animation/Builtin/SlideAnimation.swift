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
/// 1. 入场前先求解一次布局（`superview?.layoutIfNeeded()`）：滑动距离取决于容器**在父视图中的位置与尺寸**，
///    两者未知时会退化成兜底距离（见 `slideOffset`），避免出现"零位移"的假滑动
/// 2. 退场不再求解布局：拖拽可能已经改变了容器的 center，此刻求解会把用户拖出来的位移
///    抹掉（约束把视图拉回原位），视觉上表现为莫名其妙的"回弹"
///    （距离仍然按当前位置现算，因此"还差多少才出屏"是准确的）
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
        // 确保 AutoLayout 已求解：下面的 frame 必须同时反映真实尺寸与位置，滑动距离才算得准
        containerView.superview?.layoutIfNeeded()

        let offset = Self.slideOffset(
            for: direction,
            containerFrame: Self.measureUnshiftedFrame(of: containerView),
            superviewBounds: containerView.superview?.bounds ?? .zero
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
        // 距离按容器当前实际位置算：拖拽已经把它移走一段时，算出的正是"还差多少"才完全出屏
        let offset = Self.slideOffset(
            for: direction,
            containerFrame: Self.measureUnshiftedFrame(of: containerView),
            superviewBounds: containerView.superview?.bounds ?? .zero
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

    /// 出屏位移量（带符号）：正值表示"从下方/右方进入"，负值表示"从上方/左方进入"。
    ///
    /// 算法：量出容器**完全移出父视图**所需的距离，也就是"容器靠近该方向的边"到
    /// "父视图那一侧的外边缘"之间的间隔。
    ///
    /// 为什么不按"容器尺寸 + 边距"来算：那个公式隐含了"容器贴着屏幕边"的前提，
    /// 只在 `.top` / `.bottom` 位置成立，换成居中弹窗或窄容器就会算短，
    /// 起点仍留在屏幕内（看起来是从屏幕中间飘出来，而不是滑进来）。
    /// 按容器的实际位置来算则天然覆盖全部情况：
    /// - 贴边面板：结果等价于"容器高度 + 该侧边距"
    /// - 居中弹窗：得到"半个父视图 + 半个容器"，真正从屏幕外开始
    /// - 拖拽后关闭：容器已被拖走一段，算出的正是"还差多少"才完全出屏
    ///
    /// - Important: 全库只有这一处计算滑动距离——入场前的预置首帧
    ///   （`SKDialogAnimationStateManager`）与这里的动画起点都调用它。
    ///   两处各算一套时，首帧预置的位置与动画起点会不一致，肉眼可见地跳一下。
    /// - Parameters:
    ///   - direction: 起点方向（退场沿同一方向反向使用）
    ///   - containerFrame: 容器**去掉位移后**的 frame，父视图坐标系（见 `measureUnshiftedFrame`）
    ///   - superviewBounds: 容器父视图的 bounds
    /// - Returns: 位移量（带符号，直接用于生成平移变换）
    static func slideOffset(for direction: Direction, containerFrame: CGRect, superviewBounds: CGRect) -> CGFloat {
        switch direction {
        case .top:
            // 向上出屏：容器的底边要挪到父视图顶边之上
            return -max(containerFrame.maxY - superviewBounds.minY, minimumSlideDistance)
        case .bottom:
            // 向下出屏：容器的顶边要挪到父视图底边之下
            return max(superviewBounds.maxY - containerFrame.minY, minimumSlideDistance)
        case .left:
            // 向左出屏：容器的右边要挪到父视图左边之左
            return -max(containerFrame.maxX - superviewBounds.minX, minimumSlideDistance)
        case .right:
            // 向右出屏：容器的左边要挪到父视图右边之右
            return max(superviewBounds.maxX - containerFrame.minX, minimumSlideDistance)
        }
    }

    /// 量出容器"去掉位移后"的 frame（父视图坐标系）。
    ///
    /// 为什么必须先归零再量：容器此刻可能正带着上一次设置的起点位移（预置首帧或上一次布局校正
    /// 留下的），直接读 `frame` 量到的是"已经在屏幕外"的位置，于是新距离会被算成正常值的两倍
    /// ——越校正越远，最终把弹窗永久推出屏幕。归零是安全的：两个调用点紧接着都会重新设置
    /// transform（起点或终点），因此不需要恢复。
    ///
    /// - Note: 只归零 transform，**不动 center**——拖拽改的正是 center，
    ///   那是"容器当前实际在哪"的一部分，退场时要把它算进距离里。
    static func measureUnshiftedFrame(of containerView: UIView) -> CGRect {
        containerView.transform = .identity
        return containerView.frame
    }

    /// 布局尚未求解时的兜底滑动距离：即便算出的距离退化（容器或父视图还没尺寸），
    /// 也保证有一段可见的位移，而不是"零位移的假滑动"。正常布局完成后不会触发。
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
