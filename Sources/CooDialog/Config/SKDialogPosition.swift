//
//  SKDialogPosition.swift
//  SiKu
//
//  弹窗的停靠位置（center / bottom / top）。配置契约的一部分，从 SKDialogConfig.swift 拆出。
//

import UIKit

/// 弹窗的停靠位置。
///
/// 为什么用固定枚举而不是任意坐标：
/// SKDialogConstraintManager 完全依赖锚点约束（centerX / top / bottom）定位容器，把位置收敛
/// 为枚举后，每个取值都能映射成一组确定的锚点组合，运行时无需计算 frame，也就不会出现
/// "坐标与边距互相矛盾"这类非法配置。
///
/// 各取值带来的行为差异（这些差异是后续所有管理器的判定依据）：
/// - `.center`：垂直方向不受 margins 约束，内容过高会直接顶到屏幕边缘；没有"可退出的方向"，
///   因此不支持拖拽关闭。
/// - `.bottom` / `.top`：属于"贴边面板"，支持拖拽关闭，并可选择是否延伸进安全区
///   （见 `SKDialogConfig.extendToSafeArea`）。
/// 遵循 Equatable（无关联值，自动合成）：宿主与测试可以直接比较两个位置是否相同。
public enum SKDialogPosition: Equatable {
    case center     // 屏幕居中，垂直方向无 margins 约束，不支持拖拽
    case bottom     // 贴屏幕底部，支持向下拖拽关闭
    case top        // 贴屏幕顶部，支持向上拖拽关闭
}
