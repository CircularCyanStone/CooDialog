//
//  HostedCases.swift
//  SPMExample
//
//  V 组 · viewController 模式：由指定控制器 present 的那一半。
//
//  与 window 模式最大的不同是"弹窗隶属某个页面"，因此这一组不光有成功路径，
//  还有两条前置条件失败路径（宿主已 present 其它控制器 / 宿主视图未进入 window 层级）——
//  库承诺这两条路径下 `show(completion:)` 也会回调，而不是静默什么都不发生。
//  也正因为要观察这个 completion，这些案例走的是"直接构造控制器"的用法。
//

import UIKit
import CooDialog

extension ViewController {

    enum HostedCases {
        static let all: [Case] = [
            Case(title: "归属当前页面的弹窗",
                 detail: "presentationMode(.viewController(self))：弹窗由本页 present，关闭后本页回到前台",
                 identifier: "case.hosted.basic",
                 action: #selector(ViewController.showHostedDialog)),
            Case(title: "宿主已 present 其它控制器（失败路径）",
                 detail: "先占住 present 再弹：弹窗不会出现，但 show(completion:) 立刻回调，不是静默失败",
                 identifier: "case.hosted.busy",
                 action: #selector(ViewController.showHostedWhileBusy)),
            Case(title: "宿主视图未进入 window 层级（失败路径）",
                 detail: "对一个从未上屏的控制器弹：同样立刻回调，保证“调用必回调”",
                 identifier: "case.hosted.offscreen",
                 action: #selector(ViewController.showHostedOffscreen)),
            Case(title: "子页面里的弹窗随页面销毁",
                 detail: "先弹子页、在子页里弹窗，再关掉子页：弹窗一起消失，且不走自己的关闭回调",
                 identifier: "case.hosted.child",
                 action: #selector(ViewController.showHostedFromChild)),
            Case(title: "dismiss(animated:) 收口",
                 detail: "UIKit 同名方法被覆写成库的关闭流程：回调照常触发，收尾不会被绕过",
                 identifier: "case.hosted.dismissAnimated",
                 action: #selector(ViewController.showHostedDismissAnimated)),
            Case(title: "宿主模式的拖拽与遮罩点击",
                 detail: "宿主模式同样支持拖拽关闭与点遮罩关闭，关闭后 presentedViewController 重新为 nil",
                 identifier: "case.hosted.panel",
                 action: #selector(ViewController.showHostedBottomPanel)),
            Case(title: "宿主模式下动态改尺寸",
                 detail: "宿主模式里 updateContainerHeight 同样生效，sizeMode 的回写规则与 window 模式一致",
                 identifier: "case.hosted.resize",
                 action: #selector(ViewController.showHostedResize)),
            Case(title: "宿主模式下的回调链",
                 detail: "两条 addCompletionHandler + dismiss 的一次性回调，按注册顺序执行",
                 identifier: "case.hosted.completionChain",
                 action: #selector(ViewController.showHostedCompletionChain)),
            Case(title: "同一宿主上再弹一个（自然触发的失败）",
                 detail: "在已展示的宿主弹窗里再弹第二个：命中“宿主已 present 其它控制器”这条前置条件",
                 identifier: "case.hosted.nestedRejection",
                 action: #selector(ViewController.showHostedNestedRejection)),
        ]
    }

    // MARK: - 公共构造

    /// V 组共用的宿主模式配置：弹窗由当前页面 present
    func makeHostedConfig(width: CGFloat) -> SKDialogConfig {
        SKDialogConfig.centerDialog(width: width, presentationMode: .viewController(self))
    }

    // MARK: - V1 基础

    @objc func showHostedDialog() {
        let card = MessageCardView(
            title: "宿主模式弹窗",
            message: "这个弹窗由当前页面 present：关掉它之后，本页重新成为前台（presentedViewController 回到 nil）。"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .presentationMode(.viewController(self))
            .logging("V1 宿主基础", into: log)
            .show()
    }

    // MARK: - V2 宿主已 present 其它控制器

    @objc func showHostedWhileBusy() {
        let log = self.log

        // 先用一个普通页面占住本页的 present 位置
        let blocker = UIViewController()
        blocker.view.backgroundColor = .secondarySystemGroupedBackground

        let label = UILabel()
        label.text = "我先占住了 present\n（下面那个弹窗因此弹不出来）"
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.textAlignment = .center

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关掉我", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        closeButton.addAction(UIAction { [weak blocker] _ in blocker?.dismiss(animated: false) }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, closeButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        blocker.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: blocker.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blocker.view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: blocker.view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: blocker.view.trailingAnchor, constant: -32),
        ])

        present(blocker, animated: false) { [weak self] in
            guard let self else { return }

            let dialog = SKDialogViewController(config: self.makeHostedConfig(width: 300))
            dialog.addContentView(MessageCardView(
                title: "不该出现",
                message: "宿主此刻已经 present 了别的控制器，这个弹窗展示不了——`show(completion:)` 会立刻回调，稍后回到案例页可在轨迹里看到这一行。"
            ))
            dialog.show { [weak self] in
                self?.log.record("V2 宿主已忙", "show completion —— 未展示（符合预期）")
            }
        }

        // 占用页面不需要手动关（谁都能关）——这里自动收场，避免挡住案例页
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak blocker] in
            blocker?.dismiss(animated: false)
        }
    }

    // MARK: - V3 宿主视图未进入 window 层级

    @objc func showHostedOffscreen() {
        // 只创建、不展示、不 addChild：这个宿主的视图永远不会进入 window 层级
        let offscreenHost = UIViewController()

        let dialog = SKDialogViewController(config: SKDialogConfig.centerDialog(
            width: 300,
            presentationMode: .viewController(offscreenHost)
        ))
        dialog.addContentView(MessageCardView(
            title: "不该出现",
            message: "宿主的视图从未进入 window 层级，UIKit 会直接拒绝这次 present。"
        ))
        dialog.show { [weak self] in
            self?.log.record("V3 宿主未上屏", "show completion —— 未展示（符合预期）")
        }
    }

    // MARK: - V4 子页面里的弹窗

    @objc func showHostedFromChild() {
        present(HostingChildViewController(log: log), animated: true)
    }

    // MARK: - V5 dismiss(animated:) 收口

    @objc func showHostedDismissAnimated() {
        let card = MessageCardView(
            title: "UIKit 签名关闭",
            message: "1 秒后自动调用 dismiss(animated: true)：它被库覆写成完整关闭流程，因此回调照常触发（若是 UIKit 的原生实现，这些回调会全部丢失）。"
        )

        let dialog = SKDialogViewController(config: makeHostedConfig(width: 300))
        dialog.addContentView(card)
        dialog.logging("V5 dismiss(animated:)", into: log)
        dialog.show { [weak self, weak dialog] in
            self?.log.record("V5 dismiss(animated:)", "show completion —— 已 present")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dialog?.dismiss(animated: true) { [weak self] in
                    self?.log.record("V5 dismiss(animated:)", "completion 触发：收尾没有被绕过")
                }
            }
        }
    }

    // MARK: - V6 宿主模式的拖拽与遮罩

    @objc func showHostedBottomPanel() {
        let panel = PanelContentView(
            title: "宿主模式底部面板",
            message: "拖拽关闭与点遮罩关闭在宿主模式同样生效；关闭后本页回到前台",
            rowCount: 10
        )

        let dialog = SKDialog.bottom()
            .contentView(panel)
            .backgroundColor(.secondarySystemBackground)
            .presentationMode(.viewController(self))
            .logging("V6 宿主模式面板", into: log)
            .show()

        dialog.addCompletionHandler { [weak self] in
            guard let self else { return }
            let isBack = self.presentedViewController == nil
            self.log.record("V6 宿主模式面板", "关闭完成：presentedViewController == nil → \(isBack)")
        }
    }

    // MARK: - V7 宿主模式下动态改尺寸

    @objc func showHostedResize() {
        let card = ResizableCardView(
            title: "宿主模式改尺寸",
            collapsed: "初始：宽度固定 300、高度随内容",
            expanded: "展开后 updateContainerHeight(340)：宿主模式与 window 模式的尺寸行为完全一致"
        )

        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .presentationMode(.viewController(self))
            .logging("V7 宿主模式改尺寸", into: log)
            .show()

        card.onToggle = { [weak self, weak dialog] expanded in
            guard let dialog else { return }
            let height: CGFloat = expanded ? 340 : 200
            dialog.updateContainerHeight(height)
            self?.log.record("V7 宿主模式改尺寸", "updateContainerHeight(\(Int(height))) → sizeMode \(dialog.config.sizeMode.shortDescription)")
        }
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }
    }

    // MARK: - V8 宿主模式下的回调链

    @objc func showHostedCompletionChain() {
        let card = MessageCardView(
            title: "宿主模式回调链",
            message: "关闭时依次触发：两条 addCompletionHandler，最后是 dismiss 的一次性回调。"
        )

        let dialog = SKDialogViewController(config: makeHostedConfig(width: 300))
        dialog.addContentView(card)
        dialog.logging("V8 宿主回调链", into: log)
        dialog.addCompletionHandler { [weak self] in
            self?.log.record("V8 宿主回调链", "第 1 条 addCompletionHandler")
        }
        dialog.addCompletionHandler { [weak self] in
            self?.log.record("V8 宿主回调链", "第 2 条 addCompletionHandler")
        }

        card.addButton("关闭") { [weak self, weak dialog] in
            dialog?.dismiss { self?.log.record("V8 宿主回调链", "dismiss 的一次性回调（最后）") }
        }

        dialog.show()
    }

    // MARK: - V9 同一宿主上的第二次展示

    @objc func showHostedNestedRejection() {
        let log = self.log

        let first = SKDialogViewController(config: makeHostedConfig(width: 300))
        let card = MessageCardView(
            title: "第一个宿主弹窗",
            message: "点下面的按钮，试着在同一个宿主上再弹一个——那次会命中“宿主已 present 其它控制器”这条前置条件，因而不展示。"
        )
        card.addButton("再弹一个（预期失败）") { [weak self] in
            guard let self else { return }

            let second = SKDialogViewController(config: self.makeHostedConfig(width: 280))
            second.addContentView(MessageCardView(
                title: "第二个（不该出现）",
                message: "如果看到我，说明前置条件检查失效了。"
            ))
            second.show { [weak self] in
                self?.log.record("V9 第二个", "show completion —— 未展示（宿主已 present 其它控制器）")
            }
        }
        card.addButton("关闭第一个") { [weak first] in first?.dismiss() }

        first.addContentView(card)
        first.logging("V9 第一个", into: log)
        first.show { [weak self] in
            self?.log.record("V9 第一个", "show completion —— 已 present")
        }
    }
}
