//
//  PresetCases.swift
//  SPMExample
//
//  A 组 · 形态与预设：三种停靠位置 × 四种尺寸模式的真实组合。
//  这一组回答的是最朴素的问题——"我想要的那种弹窗，该怎么写出来"。
//

import UIKit
import CooDialog

extension ViewController {

    enum PresetCases {
        static let all: [Case] = [
            Case(title: "底部面板",
                 detail: "预设 SKDialog.bottom()：列表滚动时面板不动，滚到顶部继续下拉才拖走关闭",
                 identifier: "case.preset.bottomPanel",
                 action: #selector(ViewController.showBottomPanel)),
            Case(title: "居中对话框（固定宽 300）",
                 detail: ".size(width:) → fixedWidth：宽度钉死、高度由内容撑开",
                 identifier: "case.preset.centerDialog",
                 action: #selector(ViewController.showCenterDialog)),
            Case(title: "顶部提示条（2 秒后自动关）",
                 detail: "预设 SKDialog.top() + extendToSafeArea(false)：以安全区为基准，避开刘海",
                 identifier: "case.preset.topToast",
                 action: #selector(ViewController.showTopToast)),
            Case(title: "半屏面板（固定高 400）",
                 detail: ".fixedHeight：内容再多也只有 400 高，多出来的部分在列表里自己滚",
                 identifier: "case.preset.halfSheet",
                 action: #selector(ViewController.showHalfSheet)),
            Case(title: "固定宽高对话框（280×320）",
                 detail: ".size(width:height:) → fixed：内容超出就被压缩，容器尺寸一分不多",
                 identifier: "case.preset.fixedSize",
                 action: #selector(ViewController.showFixedSizeDialog)),
            Case(title: "完全自适应卡片",
                 detail: ".contentAdaptive()：不施加任何尺寸约束，宽度由这行短文案决定（对比上一项的固定宽度）",
                 identifier: "case.preset.contentAdaptive",
                 action: #selector(ViewController.showContentAdaptiveCard)),
            Case(title: "贴物理边缘 vs 避开刘海",
                 detail: "先后弹两条：extendToSafeArea(true) 顶到刘海下方，(false) 整条下移到安全区内",
                 identifier: "case.preset.safeArea",
                 action: #selector(ViewController.showSafeAreaComparison)),
        ]
    }

    // MARK: - A1 底部面板

    @objc func showBottomPanel() {
        let panel = PanelContentView(
            title: "底部面板",
            message: "列表滚到顶部之前，下拉只用于滚动；滚到顶再拉才驱动面板关闭（库内置的让位策略）"
        )

        SKDialog.bottom()
            .contentView(panel)
            .backgroundColor(.secondarySystemBackground)
            .shadow(show: true, radius: 12, opacity: 0.12)
            .logging("A1 底部面板", into: log)
            .show()
    }

    // MARK: - A2 居中对话框

    @objc func showCenterDialog() {
        let card = MessageCardView(
            title: "居中对话框",
            message: "宽度固定 300pt，高度由内容撑开。点“确认”后关闭，并打印关闭完成回调。"
        )
        card.addButton("确认") { [weak card] in card?.closeSKDialog() }

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(16)
            .animation(.fadeScale, duration: 0.25)
            .logging("A2 居中对话框", into: log)
            .show()

        // 展示后仍能拿到控制器：用它追加"关闭完成"回调
        dialog.addCompletionHandler { [weak self] in
            self?.log.record("A2 居中对话框", "关闭完成回调")
        }
    }

    // MARK: - A3 顶部提示条

    @objc func showTopToast() {
        let toast = ToastView(text: "已保存", subtitle: "extendToSafeArea(false)：整条在安全区内")
        let dialog = SKDialog.top()
            .contentView(toast)
            .cornerRadius(12)
            .extendToSafeArea(false)
            .logging("A3 顶部提示条", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak dialog] in
            dialog?.dismiss()
        }
    }

    // MARK: - A4 半屏面板

    @objc func showHalfSheet() {
        let panel = PanelContentView(
            title: "半屏面板",
            message: ".fixedHeight(400)：高度被钉死，列表只显示能放下的一部分，剩下的靠滚动",
            rowCount: 20
        )

        SKDialog.bottom()
            .contentView(panel)
            .fixedHeight(400)
            .backgroundColor(.secondarySystemBackground)
            .shadow(show: true, radius: 12, opacity: 0.12)
            .logging("A4 半屏面板", into: log)
            .show()
    }

    // MARK: - A5 固定宽高

    @objc func showFixedSizeDialog() {
        let card = MessageCardView(
            title: "固定宽高 280×320",
            message: """
            宽高都固定：内容比容器大时会被压缩，容器尺寸不会跟着内容走。
            这段文字是故意写长的——你可以看到它被容器截住，而不是把容器撑高。
            反过来，如果容器比内容大，内容会被拉伸（四边贴合），也不会保持自己的固有尺寸。
            """
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 280, height: 320)
            .cornerRadius(14)
            .logging("A5 固定宽高", into: log)
            .show()
    }

    // MARK: - A6 完全自适应

    @objc func showContentAdaptiveCard() {
        let card = MessageCardView(
            title: "完全自适应",
            message: "宽度由内容决定"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .contentAdaptive()
            .cornerRadius(14)
            .logging("A6 完全自适应", into: log)
            .show()
    }

    // MARK: - A7 安全区对照

    @objc func showSafeAreaComparison() {
        let log = self.log

        let flush = ToastView(text: "extendToSafeArea: true", subtitle: "贴屏幕物理边缘：内容顶进刘海区域")
        let flushDialog = SKDialog.top()
            .contentView(flush)
            .backgroundColor(.systemRed.withAlphaComponent(0.9))
            .extendToSafeArea(true)
            .logging("A7 贴物理边缘", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let safe = ToastView(text: "extendToSafeArea: false", subtitle: "以安全区为基准：整条移到刘海下方")
            let safeDialog = SKDialog.top()
                .contentView(safe)
                .backgroundColor(.systemGreen.withAlphaComponent(0.9))
                .extendToSafeArea(false)
                .logging("A7 避开刘海", into: log)
                .show()

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak safeDialog] in
                safeDialog?.dismiss()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak flushDialog] in
            flushDialog?.dismiss()
        }
    }
}
