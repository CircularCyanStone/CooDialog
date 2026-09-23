//
//  RuntimeCases.swift
//  SPMExample
//
//  D 组 · 运行时操作：展示之后还能做什么。
//  "配置展示前定死" 是库的一条硬约定，唯一的例外是运行时改尺寸；
//  这一组顺带验证回调链、打断入场、幂等关闭这些边界语义。
//

import UIKit
import CooDialog

extension ViewController {

    enum RuntimeCases {
        static let all: [Case] = [
            Case(title: "动态改高度（展开 / 收起）",
                 detail: "updateContainerHeight：观察容器带动画长高，以及 sizeMode 从 fixedWidth 升格为 fixed",
                 identifier: "case.runtime.height",
                 action: #selector(ViewController.showResizableCard)),
            Case(title: "动态改宽 + 高（一次事务）",
                 detail: "updateContainerSize：两个方向同时改，只产生一段过渡动画；sizeMode 收敛为 fixed",
                 identifier: "case.runtime.size",
                 action: #selector(ViewController.showResizeBothDimensions)),
            Case(title: "自适应弹窗被改尺寸后仍能被内容撑开",
                 detail: "contentAdaptive 下 updateContainerHeight 只临时钉住高度，不改模式；内容变长时容器照样被撑开",
                 identifier: "case.runtime.adaptive",
                 action: #selector(ViewController.showAdaptiveAfterResize)),
            Case(title: "追加多个关闭回调",
                 detail: "addCompletionHandler 是组合而非覆盖：先注册的先执行，最后才是 dismiss 的一次性回调",
                 identifier: "case.runtime.completionChain",
                 action: #selector(ViewController.showCompletionChain)),
            Case(title: "入场途中被关闭",
                 detail: "展示 0.05 秒后立刻关闭：轨迹里有 present.willStart，但没有 present.didFinish",
                 identifier: "case.runtime.interrupted",
                 action: #selector(ViewController.showInterruptedPresent)),
            Case(title: "关闭是幂等的（连点两次）",
                 detail: "第二次 dismiss 因已不在展示状态而立刻回调，退场轨迹只有一轮（关闭是幂等的）",
                 identifier: "case.runtime.idempotent",
                 action: #selector(ViewController.showIdempotentDismiss)),
        ]
    }

    // MARK: - D1 动态改高度

    @objc func showResizableCard() {
        let card = ResizableCardView(
            title: "动态改高度",
            collapsed: "初始：宽度固定 300、高度随内容（此刻 sizeMode = fixedWidth 300）",
            expanded: "展开后调用 updateContainerHeight(360)：容器长高，sizeMode 从 fixedWidth 升格为 fixed——高度一旦被明确指定，就不再是“随内容”了"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(14)
            .logging("D1 动态改高度", into: log)
            .show()

        card.onToggle = { [weak self, weak dialog] expanded in
            guard let dialog else { return }
            let height: CGFloat = expanded ? 360 : 200
            dialog.updateContainerHeight(height)
            self?.log.record("D1 动态改高度", "updateContainerHeight(\(Int(height))) → sizeMode \(dialog.config.sizeMode.shortDescription)")
        }

        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }
    }

    // MARK: - D2 动态改宽高

    @objc func showResizeBothDimensions() {
        let card = MessageCardView(
            title: "改宽 + 改高",
            message: "updateContainerSize 在一次事务里同时改两个方向，因此只会有一段过渡动画，而不是先宽后高的两段。"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300, height: 200)
            .cornerRadius(14)
            .logging("D2 宽高同改", into: log)
            .show()

        card.addButton("改成 320×260") { [weak self, weak dialog] in
            guard let dialog else { return }
            dialog.updateContainerSize(width: 320, height: 260)
            self?.log.record("D2 宽高同改", "updateContainerSize(320, 260) → sizeMode \(dialog.config.sizeMode.shortDescription)")
        }
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }
    }

    // MARK: - D3 自适应被改尺寸后仍能撑开

    @objc func showAdaptiveAfterResize() {
        let card = ResizableCardView(
            title: "自适应 + 先钉尺寸",
            collapsed: "当前是 contentAdaptive：高度完全由内容决定",
            expanded: "内容变长了，容器被一起撑高——说明刚才“临时钉住”的高度没有把模式改成 fixed，只是补了一条低优先级的约束"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .contentAdaptive()
            .cornerRadius(14)
            .logging("D3 自适应", into: log)
            .show()

        card.addButton("先临时钉到 140 高") { [weak self, weak dialog] in
            guard let dialog else { return }
            dialog.updateContainerHeight(140)
            self?.log.record("D3 自适应", "updateContainerHeight(140) → sizeMode 仍是 \(dialog.config.sizeMode.shortDescription)")
        }
        card.onToggle = { [weak self] expanded in
            self?.log.record("D3 自适应", expanded ? "内容展开（未调用任何改尺寸 API）" : "内容收起")
        }
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }
    }

    // MARK: - D4 回调链

    @objc func showCompletionChain() {
        let card = MessageCardView(
            title: "回调链",
            message: "关闭时按注册顺序依次触发：两条 addCompletionHandler，最后才是 dismiss 自己带的一次性回调。"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(14)
            .logging("D4 回调链", into: log)
            .show()

        dialog.addCompletionHandler { [weak self] in
            self?.log.record("D4 回调链", "第 1 条 addCompletionHandler")
        }
        dialog.addCompletionHandler { [weak self] in
            self?.log.record("D4 回调链", "第 2 条 addCompletionHandler")
        }

        card.addButton("关闭") { [weak self, weak dialog] in
            dialog?.dismiss { self?.log.record("D4 回调链", "dismiss 的一次性回调（最后）") }
        }
    }

    // MARK: - D5 入场被打断

    @objc func showInterruptedPresent() {
        let card = MessageCardView(
            title: "入场途中被关闭",
            message: "这个弹窗会在展示 0.05 秒后立刻关闭：轨迹里能看到 present.willStart 与完整的退场过程，但没有 present.didFinish——入场被打断时，库不会谎报“显示完成”。"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(14)
            .animation(.slideFromBottomWithFade, duration: 0.6)
            .logging("D5 打断入场", into: log)
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak dialog] in
            dialog?.dismiss()
        }
    }

    // MARK: - D6 幂等关闭

    @objc func showIdempotentDismiss() {
        let card = MessageCardView(
            title: "连点两次关闭",
            message: "两次 dismiss 只产生一轮退场轨迹：第一次正常播动画，第二次因为已不在展示状态而立刻回调。"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(14)
            .logging("D6 幂等关闭", into: log)
            .show()

        card.addButton("连点两次关闭") { [weak self, weak dialog] in
            guard let dialog else { return }
            dialog.dismiss { self?.log.record("D6 幂等关闭", "第 1 次 dismiss 的回调（动画结束后）") }
            dialog.dismiss { self?.log.record("D6 幂等关闭", "第 2 次 dismiss 的回调（立刻返回，因为已不在展示中）") }
        }
    }
}
