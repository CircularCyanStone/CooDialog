//
//  StyleCases.swift
//  SPMExample
//
//  E 组 · 样式：遮罩色、容器色、圆角、阴影、window 层级。
//  这一组多是"参数一改就看得见"的效果，其中一个（E3）是文档里点名的坑：圆角会被内容盖住。
//

import UIKit
import CooDialog

extension ViewController {

    enum StyleCases {
        static let all: [Case] = [
            Case(title: "一套自定义外观",
                 detail: "maskColor / backgroundColor / cornerRadius / shadow 一次全改，都不需要动库",
                 identifier: "case.style.custom",
                 action: #selector(ViewController.showStyledDialog)),
            Case(title: "阴影开关对照",
                 detail: "先弹带阴影的，再弹 shadow(show: false) 的同款：有无投影对“浮起来”的观感差别",
                 identifier: "case.style.shadow",
                 action: #selector(ViewController.showShadowComparison)),
            Case(title: "圆角被内容盖住的坑",
                 detail: "内容自带不透明直角背景时容器圆角会失效；内容改用透明背景就恢复正常",
                 identifier: "case.style.cornerRadius",
                 action: #selector(ViewController.showCornerRadiusPitfall)),
            Case(title: "windowLevel 层级对照",
                 detail: "先弹 .normal 层级的，再弹默认（.alert + 1）：后者盖在它上面，且点击被上层遮罩拦住",
                 identifier: "case.style.windowLevel",
                 action: #selector(ViewController.showWindowLevelComparison)),
        ]
    }

    // MARK: - E1 一套自定义外观

    @objc func showStyledDialog() {
        let card = MessageCardView(
            title: "一套自定义外观",
            message: "遮罩改紫、容器改暖黄半透明、圆角 24、阴影更大更浓——全部通过配置方法完成，不需要改库。"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .maskColor(UIColor.systemPurple.withAlphaComponent(0.45))
            .backgroundColor(.systemYellow.withAlphaComponent(0.35))
            .cornerRadius(24)
            .shadow(show: true, color: .systemPurple, offset: CGSize(width: 0, height: 8), radius: 20, opacity: 0.35)
            .logging("E1 自定义外观", into: log)
            .show()
    }

    // MARK: - E2 阴影开关对照

    @objc func showShadowComparison() {
        let log = self.log

        let withShadow = MessageCardView(
            title: "带阴影（默认）",
            message: "shadow 默认开启：容器看起来浮在遮罩之上。1.8 秒后自动换成同款但关掉阴影的。"
        )

        let first = SKDialog.center()
            .contentView(withShadow)
            .fixedWidth(300)
            .cornerRadius(16)
            .logging("E2 带阴影", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak first] in
            first?.dismiss {
                let withoutShadow = MessageCardView(
                    title: "无阴影",
                    message: "shadow(show: false)：容器不再有投影，边界只能靠背景色与遮罩的对比来区分。"
                )
                SKDialog.center()
                    .contentView(withoutShadow)
                    .fixedWidth(300)
                    .cornerRadius(16)
                    .shadow(show: false)
                    .logging("E2 无阴影", into: log)
                    .show()
            }
        }
    }

    // MARK: - E3 圆角被内容盖住

    @objc func showCornerRadiusPitfall() {
        let log = self.log

        let opaque = MessageCardView(
            title: "内容自带不透明直角背景",
            message: "容器圆角设了 24，但内容是不透明的直角矩形、又四边贴合容器，于是圆角被盖住了。"
        )
        // 内容视图自己的背景：不透明 + 直角 → 正好盖住容器的圆角
        opaque.backgroundColor = .systemBlue.withAlphaComponent(0.85)

        let first = SKDialog.center()
            .contentView(opaque)
            .fixedWidth(300)
            .cornerRadius(24)
            .logging("E3 内容盖住圆角", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak first] in
            first?.dismiss {
                let transparent = MessageCardView(
                    title: "内容用透明背景",
                    message: "同一个容器、同样的圆角 24，只把内容背景去掉，圆角就正常显示了。"
                )
                SKDialog.center()
                    .contentView(transparent)
                    .fixedWidth(300)
                    .cornerRadius(24)
                    .logging("E3 内容透明", into: log)
                    .show()
            }
        }
    }

    // MARK: - E4 windowLevel 层级

    @objc func showWindowLevelComparison() {
        let log = self.log

        let lowCard = MessageCardView(
            title: "windowLevel = .normal",
            message: "先弹的这个层级低：1.2 秒后弹出的默认层级（.alert + 1）会盖在它上面，而它自己的内容点不到——点击会被上层遮罩拦住。"
        )

        let lowDialog = SKDialog.center()
            .contentView(lowCard)
            .fixedWidth(300)
            .windowLevel(.normal)
            .logging("E4 .normal 层级", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let highCard = MessageCardView(
                title: "windowLevel 默认（.alert + 1）",
                message: "我盖在刚才那个之上：两个弹窗都是自建 window，层级高的在上。"
            )
            highCard.addButton("关闭") { [weak highCard] in highCard?.closeSKDialog() }

            SKDialog.bottom()
                .contentView(highCard)
                .fixedHeight(220)
                .backgroundColor(.secondarySystemBackground)
                .logging("E4 默认层级", into: log)
                .show()
        }

        // 低层级的弹窗收不到点击（被上层遮罩拦住），所以安排它自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak lowDialog] in
            lowDialog?.dismiss()
        }
    }
}
