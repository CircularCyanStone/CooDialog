//
//  SKDialogAnimationType.swift
//  SiKu
//
//  入场 / 退场动画类型（9 种内置 + 1 个自定义扩展点）。配置契约的一部分，从 SKDialogConfig.swift 拆出。
//

import UIKit

/// 弹窗入场 / 退场动画类型。
///
/// 设计思路：把动画抽象成"可替换的策略"。8 种滑动内置类型共用一个实现
/// （`SlideAnimation`，差异由"方向 + 是否淡入"表达），原地缩放淡入是另一个实现；
/// `.custom` 则是留给宿主的扩展点——库外无法新增枚举 case，
/// 所以要有一个携带协议实现的 case，宿主才能真正注入自定义动画。
/// 各类型与实现、方向的对应关系集中定义在文件末尾的 `slideDirection` / `fadesContainerWhileSliding`。
///
/// 命名规律（决定了视觉效果，不是同义词替换）：
/// - 不带后缀（如 `.slideFromBottom`）：容器只做位移，自身始终不透明，仅遮罩单独淡入
/// - 带 `WithFade`（如 `.slideFromBottomWithFade`）：位移同时让容器自身从透明淡入
/// 因此 WithFade 版本的主观速度感更慢、更"柔"，适合大面板；不带后缀的更适合轻量提示条。
public enum SKDialogAnimationType: Equatable {
    case slideFromBottom    // 从屏幕下方滑入（容器不淡入）
    case fadeScale          // 原地缩放淡入，默认缩放起点见 FadeScaleAnimation
    case slideFromTop       // 从屏幕上方滑入（容器不淡入）
    case slideFromLeft      // 从屏幕左侧滑入（容器不淡入）
    case slideFromRight     // 从屏幕右侧滑入（容器不淡入）
    case slideFromBottomWithFade    // 从下方滑入 + 容器淡入
    case slideFromTopWithFade       // 从上方滑入 + 容器淡入
    case slideFromLeftWithFade      // 从左侧滑入 + 容器淡入
    case slideFromRightWithFade     // 从右侧滑入 + 容器淡入
    case custom(SKDialogAnimationProtocol)  // 自定义动画：由宿主实现协议注入

    // 手写 Equatable 实现的原因（编译器无法自动合成）：
    // `.custom` 的关联值 SKDialogAnimationProtocol 是存在类型，协议本身不继承 Equatable，
    // 因此无法逐 case 比较关联值。这里对 9 种内置类型做真实比较，对 `.custom` 一律返回 false。
    // 于是需要留意语义边界：两个 `.custom` 即使指向同一种动画也判为不相等，
    // "不相等"只意味着"无法判定相等"，调用方不应据 == false 推断两动画不同
    // （若确需比较，应在协议中额外暴露标识符）。
    public static func == (lhs: SKDialogAnimationType, rhs: SKDialogAnimationType) -> Bool {
        switch (lhs, rhs) {
        case (.slideFromBottom, .slideFromBottom),
             (.fadeScale, .fadeScale),
             (.slideFromTop, .slideFromTop),
             (.slideFromLeft, .slideFromLeft),
             (.slideFromRight, .slideFromRight),
             (.slideFromBottomWithFade, .slideFromBottomWithFade),
             (.slideFromTopWithFade, .slideFromTopWithFade),
             (.slideFromLeftWithFade, .slideFromLeftWithFade),
             (.slideFromRightWithFade, .slideFromRightWithFade):
            return true
        case (.custom(_), .custom(_)):
            // 对于自定义动画，由于协议类型无法直接比较，返回false
            // 如果需要比较自定义动画，建议在协议中添加标识符属性
            return false
        default:
            return false
        }
    }
}

// MARK: - 实现映射（internal）

extension SKDialogAnimationType {

    /// 滑动方向。`nil` 表示"不靠位移入场"——目前只有 `fadeScale` 与 `.custom`。
    ///
    /// 这是"哪些类型属于滑动动画、朝哪个方向滑"的唯一判定处：
    /// 动画实现（`SlideAnimation`）、首帧预置与布局后校正（`SKDialogAnimationStateManager`）
    /// 都从这里取，不再各自 switch 一遍。
    var slideDirection: SlideAnimation.Direction? {
        switch self {
        case .slideFromBottom, .slideFromBottomWithFade: return .bottom
        case .slideFromTop, .slideFromTopWithFade: return .top
        case .slideFromLeft, .slideFromLeftWithFade: return .left
        case .slideFromRight, .slideFromRightWithFade: return .right
        case .fadeScale, .custom: return nil
        }
    }

    /// 入场时容器是否跟随遮罩一起淡入（即枚举里的 WithFade 系列）。
    /// 非滑动动画不使用这个标记：`fadeScale` 的淡入写在它自己的实现里，自定义动画自行决定。
    var fadesContainerWhileSliding: Bool {
        switch self {
        case .slideFromBottomWithFade, .slideFromTopWithFade,
             .slideFromLeftWithFade, .slideFromRightWithFade:
            return true
        case .slideFromBottom, .slideFromTop, .slideFromLeft, .slideFromRight,
             .fadeScale, .custom:
            return false
        }
    }
}
