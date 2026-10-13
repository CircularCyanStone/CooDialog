//
//  UIView+CooDialog.swift
//  TAIChat
//
//  Created by Assistant on 2024
//

/**
 * 文件功能描述：
 * 给 UIView 增加的"从任意子视图反查所属弹窗"的能力。宿主在自定义内容里放按钮时，
 * 往往只持有那个按钮（或其它子视图），拿不到承载它的弹窗控制器；
 * 本扩展通过响应链向上溯源，补上这段缺失的引用。
 *
 * 设计原理（为什么用响应链而不是别的方案）：
 * 视图无法直接知道自己被哪个控制器承载——UIKit 没有提供反向指针。
 * 响应链（`next` 指针）正是系统内置的"向上查找"通道：从任意视图出发，
 * 依次经过其父视图、控制器、window，直到命中目标。
 * 用它既不需要宿主传参，也不需要库侧维护"视图 → 弹窗"的映射表。
 *
 * 使用方式：
 * - 按钮事件里调用 `sender.closeCooDialog()`（sender 可为任意子视图）
 * - 或用 `view.isInCooDialog` 判断当前上下文是否在弹窗内
 *
 * 两条实现约束：
 * 1. 只公开必要 API：findCooDialogViewController 保持 private，
 *    避免 public extension 把实现细节扩散到整个 UIView 命名空间
 * 2. 显式标注 @MainActor（原因见下方说明），让跨线程误用变成编译错误而非运行时崩溃
 */

import Foundation
import UIKit

/// UIView扩展，提供CooDialog弹窗相关的便捷方法
/// 支持通过响应链和视图层级查找并关闭弹窗，提供按钮和手势的快捷操作
///
/// 结构约定：公开 API 集中在下方 `// MARK: - Public API` 段，私有实现集中在
/// `// MARK: - Private` 段；两段都必须显式标注 @MainActor（原因见下）。
///
/// - Important: 显式标注 `@MainActor`（而非依赖 `UIView` 推断）。
///   推断得到的隔离，违规时编译器只给 warning，宿主在后台线程调用可编译通过，
///   但 Swift 6 会为 `@MainActor` 方法插入运行时断言，最终在运行时崩溃。
///   显式标注可将该违规在编译期升级为 error。
// MARK: - Public API

@MainActor
extension UIView {

    /// 关闭当前视图所在的CooDialog弹窗。
    ///
    /// 实现要点：
    /// - 从 self 起沿 `next` 遍历，命中的第一个 CooDialogViewController 即为承载它的弹窗
    /// - 找到后立即 return：只关闭"最近的那个"弹窗，嵌套弹窗场景下不会连带关掉外层
    /// - 标注 `@objc` 是为了可被 Objective-C 调用（混编工程里按钮的 selector 常写在 OC 侧）
    ///
    /// 未命中时只在 DEBUG 下打印一行说明、不做断言：这是有意的——
    /// 该方法通常由按钮点击触发，而点击可能正好发生在弹窗关闭过程中（响应链已断开），
    /// 属于正常竞态而非程序错误，不应让宿主崩溃。
    /// Release 构建完全静默：库不在生产环境往控制台输出。
    @objc public func closeCooDialog() {
        var responder: UIResponder? = self
        while responder != nil {
            if let dialogVC = responder as? CooDialogViewController {
                dialogVC.dismiss()
                return
            }
            responder = responder?.next
        }

        #if DEBUG
        print("CooDialog: 响应链上找不到 CooDialogViewController（该视图可能已不在弹窗内）")
        #endif
    }

    /// 判断当前视图是否位于 CooDialog 弹窗内（沿响应链查找控制器）。
    /// 适用场景：同一段业务代码同时服务弹窗内与弹窗外的视图时用它区分上下文，
    /// 例如据此决定"关闭弹窗"还是"push 新页面"。
    public var isInCooDialog: Bool {
        return findCooDialogViewController() != nil
    }
}

// MARK: - Internal

/// 库内使用的视图层级工具，不对外公开（沿用"只公开必要 API"的约定）。
@MainActor
extension UIView {

    /// 沿响应链向上找到"管理本视图的控制器"（inline 模式挂载时用得上：
    /// 能挂进某个控制器就 `addChild`，见 `CooDialogViewController.attachInline(to:)`）。
    ///
    /// 为什么不公开：宿主想知道"我在不在弹窗里"用 `isInCooDialog` 就够了，
    /// 不需要自己找控制器；保持在 internal 也避免 public extension 把方法扩散到
    /// 整个 UIView 命名空间（与 findCooDialogViewController 同一条约定）。
    /// - Note: 视图尚未挂到任何控制器（纯 view 层级）时返回 nil——这不是异常情况：
    ///   inline 模式允许挂在没有控制器的视图上，只是拿不到 addChild 带来的那部分收益。
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Private

@MainActor
extension UIView {

    /// 通过响应链查找CooDialogViewController
    /// 作为 private 实现供内部复用（closeCooDialog 与 isInCooDialog 共用同一套遍历）；
    /// 若将来需要暴露给宿主，应改为返回可选值的 public 方法，而不是复制这段逻辑。
    private func findCooDialogViewController() -> CooDialogViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let dialogVC = responder as? CooDialogViewController {
                return dialogVC
            }
            responder = responder?.next
        }
        return nil
    }
}
