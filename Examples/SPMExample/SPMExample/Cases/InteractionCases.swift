//
//  InteractionCases.swift
//  SPMExample
//
//  C 组 · 交互：拖拽、遮罩点击、嵌套弹窗、响应链反查。
//  这一组验证的是"手怎么和弹窗打交道"——每个开关都对应一种真实的手势行为。
//

import UIKit
import CooDialog

extension ViewController {

    enum InteractionCases {
        static let all: [Case] = [
            Case(title: "关闭拖拽（与 A1 对照）",
                 detail: "enablePanGestureDismiss(false)：同样的面板，怎么拖都不走，只能点“关闭”",
                 identifier: "case.interaction.noPan",
                 action: #selector(ViewController.showPanelWithoutPan)),
            Case(title: "关闭遮罩点击",
                 detail: "dismissOnBackgroundTap(false)：点遮罩没有任何反应，必须点按钮",
                 identifier: "case.interaction.noMaskTap",
                 action: #selector(ViewController.showDialogWithoutMaskTap)),
            Case(title: "嵌套弹窗（只关最内层）",
                 detail: "弹窗里再弹一个：点内层的关闭，外层仍在——响应链命中的是最近的那个",
                 identifier: "case.interaction.nested",
                 action: #selector(ViewController.showNestedDialogs)),
            Case(title: "按钮埋在 3 层容器里",
                 detail: "closeSKDialog() 沿响应链上溯，嵌套层数与能否找到弹窗无关；按钮先报出 isInSKDialog",
                 identifier: "case.interaction.deepNested",
                 action: #selector(ViewController.showDeepNestedClose)),
            Case(title: "拖拽时的遮罩淡化",
                 detail: "按住面板往下拖：遮罩随进度变浅；不到阈值松手会回弹，不会误关",
                 identifier: "case.interaction.dimming",
                 action: #selector(ViewController.showDimmingPanel)),
        ]
    }

    // MARK: - C1 关闭拖拽

    @objc func showPanelWithoutPan() {
        let panel = PanelContentView(
            title: "拖拽已关闭",
            message: "enablePanGestureDismiss(false)：怎么拖都不关，列表滚动照常工作",
            rowCount: 8
        )

        SKDialog.bottom()
            .contentView(panel)
            .enablePanGestureDismiss(false)
            .backgroundColor(.secondarySystemBackground)
            .shadow(show: true, radius: 12, opacity: 0.12)
            .logging("C1 禁用拖拽", into: log)
            .show()
    }

    // MARK: - C2 关闭遮罩点击

    @objc func showDialogWithoutMaskTap() {
        let card = MessageCardView(
            title: "遮罩不可点关",
            message: "dismissOnBackgroundTap(false)：点遮罩没有反应，只能点下面的按钮。"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .dismissOnBackgroundTap(false)
            .logging("C2 禁用遮罩点击", into: log)
            .show()
    }

    // MARK: - C3 嵌套弹窗

    @objc func showNestedDialogs() {
        let log = self.log

        let inner = MessageCardView(
            title: "内层弹窗",
            message: "点“关闭内层”只会关掉我：closeSKDialog() 命中的是响应链上最近的那一层，外层不受影响。"
        )
        inner.addButton("关闭内层") { [weak inner] in inner?.closeSKDialog() }

        let outer = MessageCardView(
            title: "外层弹窗",
            message: "点“弹出内层”会在上面再叠一层；把内层关掉之后，我还在这里。"
        )
        outer.addButton("弹出内层") {
            SKDialog.center()
                .contentView(inner)
                .size(width: 280)
                .cornerRadius(14)
                .backgroundColor(.tertiarySystemBackground)
                .logging("C3 内层", into: log)
                .show()
        }
        outer.addButton("关闭外层") { [weak outer] in outer?.closeSKDialog() }

        SKDialog.center()
            .contentView(outer)
            .size(width: 300)
            .logging("C3 外层", into: log)
            .show()
    }

    // MARK: - C4 深层嵌套的按钮

    @objc func showDeepNestedClose() {
        SKDialog.center()
            .contentView(DeepNestedCloseView())
            .size(width: 320)
            .cornerRadius(16)
            .logging("C4 深层按钮", into: log)
            .show()
    }

    // MARK: - C5 拖拽时的遮罩淡化

    @objc func showDimmingPanel() {
        let panel = PanelContentView(
            title: "拖拽时的遮罩",
            message: "遮罩色是 70% 黑：拖动时以它的 alpha 为基准最多淡化一半，松手回弹会恢复",
            rowCount: 4
        )

        SKDialog.bottom()
            .contentView(panel)
            .maskColor(.black.withAlphaComponent(0.7))
            .backgroundColor(.secondarySystemBackground)
            .shadow(show: true, radius: 12, opacity: 0.12)
            .logging("C5 遮罩淡化", into: log)
            .show()
    }
}
