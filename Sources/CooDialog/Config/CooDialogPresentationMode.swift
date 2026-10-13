//
//  CooDialogPresentationMode.swift
//  SiKu
//
//  显示载体（独立 UIWindow / 指定控制器 present / 指定视图挂载）。
//  配置契约的一部分，从 CooDialogConfig.swift 拆出。
//

import UIKit

/// 弹窗的显示载体模式。
///
/// 三种模式的本质区别是"弹窗隶属于谁、在哪里上屏"：
/// - `.window`（默认）：由独立的 UIWindow 承载。优点是弹窗不隶属任何控制器层级，可以盖过
///   导航栏、TabBar、以及已经 present 出来的控制器，也能在"没有合适 VC"的时机展示
///   （启动早期、网络回调、后台任务回到前台等）。代价是必须自己管理 window 生命周期与
///   key window 的恢复，这部分由 CooDialogWindowManager 负责。
/// - `.viewController(vc)`：由指定控制器 present。适合"弹窗明确属于某个页面"的场景，
///   可以随该页面一起被销毁；代价是受这个控制器的 present 链约束。
/// - `.inline(view)`：挂到指定视图上，**不产生任何 present 关系**。传入的视图就是弹窗的
///   "画布"：遮罩铺满它、容器的定位与滑动都以它为基准、超出它的部分会被裁剪。
///   适合"弹窗只属于页面里的某一块区域"（局部预览、卡片内弹层）以及手上只有视图、
///   拿不到合适控制器的时机。收益与代价同源：它不会盖住画布之外的界面，
///   也不会随页面生命周期自动收尾——仍然需要显式 `dismiss()`。
///
/// 实现上三者的差异只有一处——**由谁来承载弹窗的视图**：
/// `.window` 自建一个 UIWindow，并在其中准备一个透明宿主控制器，由它 present；
/// `.viewController` 直接用宿主给的控制器 present；`.inline` 连 present 都不走，
/// 把弹窗的视图直接挂到传入的视图上。载体一旦确定，入场/退场动画、约束、手势、
/// 关闭收尾就完全共用同一条路径（见 `CooDialogViewController.show / dismiss`），
/// 不再是三套机制。
///
/// - Important: `.viewController` 与 `.inline` 携带的都是**强引用**（枚举关联值本身即强引用；
///   配置虽然是值类型，但其中的这个关联值同样会延长被引用对象的生命周期）。
///   若把 `self` 传给一个被自己长期持有的配置（例如 `self.dialog = CooDialog.center()
///   .presentationMode(.viewController(self))`），就会形成
///   VC → 弹窗 → 配置 → VC 的引用环，需要改用 window 模式或传入父级控制器。
///   `.inline` 传入的视图本身不会反向引用弹窗，因此环的关键在于"这个视图是不是由
///   持有配置的那一方长期持有"，判断方式同上。
public enum CooDialogPresentationMode {
    case viewController(UIViewController)  // 由指定控制器 present（模态转场，强引用该控制器）
    case window                           // 由库自建的 UIWindow 承载（默认，层级最高，无宿主 VC）
    case inline(UIView)                   // 挂到指定视图上（不走 present，强引用该视图）
}
