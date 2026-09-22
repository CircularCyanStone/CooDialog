//
//  SKDialogSizeMode.swift
//  SiKu
//
//  容器尺寸的确定方式（固定 / 单向固定 / 自适应）。配置契约的一部分，从 SKDialogConfig.swift 拆出。
//

import UIKit

/// 容器尺寸的确定方式：**4 种状态 ↔ 4 个 case 一一对应，同一意图只有一种写法**。
///
/// 为什么用一个枚举而不是 `width: CGFloat?` + `height: CGFloat?` 两个属性：
/// 两个可选值能组合出 4 种状态，其中"两者都为空"到底是"宽度自适应"还是"没配置"是歧义的；
/// 枚举把合法状态显式化。它的前提是"一状态一写法"，因此这里**刻意不给 `.fixed` 留 nil**：
/// 只固定一个方向用 `.fixedWidth` / `.fixedHeight`，两个方向都随内容用 `.contentAdaptive`。
///
/// 为什么允许 `.fixed` 传 nil 是错的（旧设计留下的坑，已废除）：
/// `.fixed(300, nil)` 在约束层面与 `.fixedWidth(300)` 完全一样（都只加一条宽度约束），
/// 于是同一个意图有了两种写法；更糟的是 `.fixed(nil, nil)`——它在约束层面等同于
/// `.contentAdaptive`，却会在动态改尺寸时被钉成固定尺寸（不再随内容变化），
/// 让"看着是自适应"的弹窗在某个时刻悄悄僵住。收敛成"一状态一写法"之后，
/// `config.sizeMode` 里的值才真实反映意图，运行时回写与自检也才有确定的判定标准。
///
/// 与约束的对应关系（见 SKDialogConstraintManager.addSizeConstraints）：
/// - `.fixed`：添加等宽 + 等高两条常量约束
/// - `.fixedWidth` / `.fixedHeight`：只添加一个方向的常量约束，另一个方向交给内容决定
/// - `.contentAdaptive`：不添加尺寸约束，容器尺寸由内容视图的内在尺寸 + 位置约束共同求解
///
/// 构造入口（链路自顶向下，命名一一对齐）：
/// - `SKDialog.size(width:height:)`：按"给了几个方向"映射到本枚举的四种状态之一
/// - `SKDialog.fixedWidth(_:)` / `fixedHeight(_:)` / `contentAdaptive()`：与对应 case 同名同序
/// - `SKDialogConfig.centerDialog(width:height:)` / `bottomSheet(height:)` / `topSheet(height:)`：同一套映射
/// - 也允许宿主直接写 `config.sizeMode`——case 本身已保证不会出现模棱两可的组合
/// 遵循 Equatable（关联值均为 CGFloat，自动合成）：宿主与测试可以直接比较两个模式是否相同，
/// 也让"某种写法映射出的模式是否符合预期"这类断言成立。
public enum SKDialogSizeMode: Equatable {

    /// 宽高都固定（两个方向都必须给值；只固定一个方向请用 `.fixedWidth` / `.fixedHeight`）
    case fixed(width: CGFloat, height: CGFloat)

    /// 只固定宽度，高度随内容
    case fixedWidth(CGFloat)

    /// 只固定高度，宽度随内容
    case fixedHeight(CGFloat)

    /// 宽高都随内容（不添加任何尺寸约束）
    case contentAdaptive
}

// MARK: - 映射规则（internal）

extension SKDialogSizeMode {

    /// 按"给了几个方向"映射到具体模式——**全库唯一的"可选宽高 → 尺寸模式"规则**。
    ///
    /// - 两个方向都给 → `.fixed`
    /// - 只给宽度 → `.fixedWidth`（高度随内容）
    /// - 只给高度 → `.fixedHeight`（宽度随内容）
    /// - 都不给 → `.contentAdaptive`
    ///
    /// 消费这条规则的入口（三条，行为由这里统一保证，不需要各自实现一遍）：
    /// 1. `SKDialog.size(width:height:)`
    /// 2. `SKDialogConfig.centerDialog(width:height:)`
    /// 3. `SKDialogConfig.bottomSheet(height:)` / `topSheet(height:)`（只给高度方向）
    init(width: CGFloat?, height: CGFloat?) {
        switch (width, height) {
        case let (width?, height?):
            self = .fixed(width: width, height: height)
        case let (width?, nil):
            self = .fixedWidth(width)
        case let (nil, height?):
            self = .fixedHeight(height)
        case (nil, nil):
            self = .contentAdaptive
        }
    }
}
