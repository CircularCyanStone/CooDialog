//
//  SKDialogPresentationMode.swift
//  SiKu
//
//  显示载体（独立 UIWindow / 指定控制器 present）。配置契约的一部分，从 SKDialogConfig.swift 拆出。
//

import UIKit

/// 弹窗的显示载体模式。
///
/// 两种模式的本质区别是"弹窗隶属于谁"：
/// - `.window`（默认）：由独立的 UIWindow 承载。优点是弹窗不隶属任何控制器层级，可以盖过
///   导航栏、TabBar、以及已经 present 出来的控制器，也能在"没有合适 VC"的时机展示
///   （启动早期、网络回调、后台任务回到前台等）。代价是必须自己管理 window 生命周期与
///   key window 的恢复，这部分由 SKDialogWindowManager 负责。
/// - `.viewController(vc)`：由指定控制器 present。适合"弹窗明确属于某个页面"的场景，
///   可以随该页面一起被销毁；代价是受这个控制器的 present 链约束。
///
/// 实现上两者的差异只有一处——**由谁来 present 弹窗**：`.window` 自建一个 UIWindow，
/// 并在其中准备一个透明宿主控制器，由它 present；`.viewController` 直接用宿主给的控制器。
/// 宿主一旦确定，展示动作、入场/退场动画、关闭收尾就完全共用同一条路径
///（见 SKDialogViewController.show / dismissDialog），不再是两套机制。
///
/// - Important: `.viewController` 携带的是**强引用**（枚举关联值本身即强引用；配置虽然是值类型，
///   但其中的这个关联值同样会延长该控制器的生命周期）。
///   若把 `self` 传给一个被自己长期持有的配置（例如 `self.dialog = SKDialog.center()
///   .presentationMode(.viewController(self))`），就会形成
///   VC → 弹窗 → 配置 → VC 的引用环，需要改用 window 模式或传入父级控制器。
public enum SKDialogPresentationMode {
    case viewController(UIViewController)  // 由指定控制器 present（模态转场，强引用该控制器）
    case window                           // 由库自建的 UIWindow 承载（默认，层级最高，无宿主 VC）
}
