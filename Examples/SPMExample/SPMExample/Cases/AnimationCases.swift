//
//  AnimationCases.swift
//  SPMExample
//
//  B 组 · 动画：9 种内置动画、自定义动画注入、以及手感参数的作用。
//  这几种差异（方向、是否跟随遮罩淡入、时长/阻尼）光看代码是感受不到的，必须真放一遍。
//

import UIKit
import CooDialog

extension ViewController {

    enum AnimationCases {

        static let all: [Case] = [
            Case(title: "九种内置动画（每点一次换下一种）",
                 detail: "依次播放 slideFrom* / *WithFade / fadeScale；轨迹面板会标出当前是哪种",
                 identifier: "case.animation.builtin",
                 action: #selector(ViewController.showNextBuiltinAnimation)),
            Case(title: "自定义动画（旋转 + 缩放）",
                 detail: "库实现 SKDialogAnimationProtocol 后经 .custom 注入——扩展动画不需要改库",
                 identifier: "case.animation.custom",
                 action: #selector(ViewController.showCustomAnimationCard)),
            Case(title: "手感对照（0.1s 干脆 vs 0.6s 柔和）",
                 detail: "animation(_:duration:damping:velocity:)：时长与弹簧参数对观感的影响",
                 identifier: "case.animation.feel",
                 action: #selector(ViewController.showAnimationFeelComparison)),
        ]

        /// B1 的轮播清单：动画名 + 类型 + 与滑动方向匹配的停靠位置。
        /// 位置要跟着动画方向走——"从上滑入"却停在屏幕底部，看起来就不成立了。
        static let builtin: [(name: String, type: SKDialogAnimationType, position: SKDialogPosition)] = [
            ("slideFromBottom", .slideFromBottom, .bottom),
            ("slideFromTop", .slideFromTop, .top),
            ("slideFromLeft", .slideFromLeft, .center),
            ("slideFromRight", .slideFromRight, .center),
            ("slideFromBottomWithFade", .slideFromBottomWithFade, .bottom),
            ("slideFromTopWithFade", .slideFromTopWithFade, .top),
            ("slideFromLeftWithFade", .slideFromLeftWithFade, .center),
            ("slideFromRightWithFade", .slideFromRightWithFade, .center),
            ("fadeScale", .fadeScale, .center),
        ]
    }

    // MARK: - B1 九种内置动画

    @objc func showNextBuiltinAnimation() {
        let items = AnimationCases.builtin
        let index = animationCursor % items.count
        animationCursor += 1
        let item = items[index]

        let positionText: String
        switch item.position {
        case .center: positionText = "居中"
        case .bottom: positionText = "底部"
        case .top: positionText = "顶部"
        }

        let card = MessageCardView(
            title: item.name,
            message: "第 \(index + 1)/\(items.count) 种内置动画；停靠位置：\(positionText)。再点一次按钮看下一种。"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        let builder = SKDialog()
            .position(item.position)
            .animation(item.type)
            .contentView(card)
            .cornerRadius(14)

        // 居中位置需要左右边距来限制最大宽度；贴边位置保持零边距才能真正"贴边"
        switch item.position {
        case .center:
            builder.margins(UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40))
        case .bottom, .top:
            builder.margins(.zero)
        }

        builder.logging("B1 \(item.name)", into: log).show()
    }

    // MARK: - B2 自定义动画

    @objc func showCustomAnimationCard() {
        let card = MessageCardView(
            title: "自定义动画",
            message: "旋转 + 缩放：动画实现在示例工程里（SpinScaleAnimation），通过 .custom 注入给库。"
        )
        card.addButton("关闭") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 300)
            .cornerRadius(16)
            .animation(.custom(SpinScaleAnimation()), duration: 0.45, damping: 0.55)
            .logging("B2 自定义动画", into: log)
            .show()
    }

    // MARK: - B3 手感对照

    @objc func showAnimationFeelComparison() {
        let log = self.log

        let fastCard = MessageCardView(title: "0.1s / damping 1.0", message: "干脆：几乎没有过渡过程，适合轻量提示")
        fastCard.addButton("关闭") { [weak fastCard] in fastCard?.closeSKDialog() }

        let fastDialog = SKDialog.bottom()
            .contentView(fastCard)
            .fixedHeight(200)
            .backgroundColor(.secondarySystemBackground)
            .animation(.slideFromBottom, duration: 0.1, damping: 1.0)
            .logging("B3 0.1s 干脆", into: log)
            .show()

        // 1.2 秒后收起快的，再放慢的：两个面板都贴底，串行展示才看得清各自的过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak fastDialog] in
            fastDialog?.dismiss {
                let softCard = MessageCardView(title: "0.6s / damping 0.55", message: "柔和：过程更长、带一点回弹，适合大面板")
                softCard.addButton("关闭") { [weak softCard] in softCard?.closeSKDialog() }

                SKDialog.bottom()
                    .contentView(softCard)
                    .fixedHeight(200)
                    .backgroundColor(.secondarySystemBackground)
                    .animation(.slideFromBottomWithFade, duration: 0.6, damping: 0.55)
                    .logging("B3 0.6s 柔和", into: log)
                    .show()
            }
        }
    }
}
