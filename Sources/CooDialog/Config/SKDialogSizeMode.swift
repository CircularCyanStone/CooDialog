//
//  SKDialogSizeMode.swift
//  SiKu
//
//  容器尺寸的确定方式（固定 / 自适应 / 单向固定）。配置契约的一部分，从 SKDialogConfig.swift 拆出。
//

import UIKit

/// 容器尺寸的确定方式。
///
/// 为什么用一个枚举而不是 `width: CGFloat?` + `height: CGFloat?` 两个属性：
/// 两个可选值能组合出 4 种状态，其中"两者都为空"到底是"宽度自适应"还是"没配置"是歧义的；
/// 枚举把合法状态显式化，让"宽高分别如何确定"只有 4 种可能，约束管理器也就能为每种模式给出
/// 互斥且确定的约束组合。
///
/// 与约束的对应关系（见 SKDialogConstraintManager.addSizeConstraints）：
/// - `.fixed`：按给定值添加等宽/等高常量约束，传 nil 的维度不加约束
/// - `.widthFixed` / `.heightFixed`：只固定一个方向，另一个方向交给内容决定
/// - `.contentAdaptive`：完全不添加尺寸约束，容器尺寸由内容视图的内在尺寸 + 位置约束共同求解
public enum SKDialogSizeMode {
    case fixed(width: CGFloat?, height: CGFloat?)  // 固定尺寸，nil 维度不约束
    case contentAdaptive                           // 完全由内容撑开，不加尺寸约束
    case widthFixed(CGFloat)                      // 只固定宽度，高度随内容
    case heightFixed(CGFloat)                     // 只固定高度，宽度随内容
}
