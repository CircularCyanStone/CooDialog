//
//  InlineCases.swift
//  SPMExample
//
//  I 组 · inline 模式：挂到指定视图上、全程不走 present 的那一半。
//
//  这一组的观察对象是"画布"——页面里一块带边框的视图。
//  与 window / viewController 两组最直观的差别：弹窗不盖整屏，只在画布内进出场；
//  同时它不隶属任何页面生命周期，关不关、什么时候关都由调用方说了算，
//  因此每个案例都在关闭完成后把画布收拾干净（否则下一次点击会看到上一块的残留）。
//

import UIKit
import CooDialog

extension ViewController {

    enum InlineCases {
        static let all: [Case] = [
            Case(title: "画布内的弹窗",
                 detail: "inline(in:)：遮罩只铺满这块画布，画布以外的界面不受影响；关闭后画布复原",
                 identifier: "case.inline.basic",
                 action: #selector(ViewController.showInlineDialog)),
            Case(title: "画布内的底部面板",
                 detail: "滑动距离以画布为准：面板从画布底边滑入，出界部分被裁剪；拖拽与遮罩点击照常",
                 identifier: "case.inline.panel",
                 action: #selector(ViewController.showInlinePanel)),
            Case(title: "画布变化时弹窗跟随",
                 detail: "展示后把画布改高：弹窗跟着变——贴合的是约束，不是上屏那一刻的 frame",
                 identifier: "case.inline.resize",
                 action: #selector(ViewController.showInlineResizing)),
            Case(title: "响应链关闭（画布内按钮）",
                 detail: "画布里的按钮只持有自己，用 closeCooDialog() 反查弹窗——挂载时的 addChild 保证了这条链",
                 identifier: "case.inline.responderChain",
                 action: #selector(ViewController.showInlineResponderChain)),
            Case(title: "不属于任何控制器的画布",
                 detail: "画布直接挂在窗口上（拿不到宿主控制器）：展示、动画、收尾照常，但响应链反查不再可用",
                 identifier: "case.inline.noHostController",
                 action: #selector(ViewController.showInlineWithoutHostController)),
            Case(title: "就挂在当前页面上（整页为画布）",
                 detail: "inline(in: view)：画布是本页自己的视图——不经过 present、也不建 window，遮罩铺满整页",
                 identifier: "case.inline.currentPage",
                 action: #selector(ViewController.showInlineOnCurrentPage)),
        ]
    }

    // MARK: - I6 就挂在当前页面上（整页画布）

    @objc func showInlineOnCurrentPage() {
        // 画布就是本页自己的视图：这正是"在当前显示的控制器上直接弹"的用法——
        // 不经过 present，也不建 window，弹窗按 inline 的规则挂在整页上。
        // 观感与另外两种载体几乎一致（遮罩铺满整页、面板贴屏幕底边），
        // 区别是它不占用本页的 present 位置：本页还 present 着别的控制器也照样能弹。
        let baseline = view.subviews.count

        let panel = PanelContentView(
            title: "就挂在当前页面上",
            message: "画布是本页自己的视图：没有 present、也没有自建 window。关闭后本页子视图数应回到 \(baseline) 个——弹窗连同它的遮罩一起被摘干净。",
            rowCount: 5
        )

        CooDialog.bottom()
            .contentView(panel)
            .inline(in: view)
            .backgroundColor(.secondarySystemBackground)
            .logging("I6 直接挂本页", into: log)
            .show()
            .addCompletionHandler { [weak self] in
                guard let self else { return }
                self.log.record("I6 直接挂本页", "关闭完成：本页子视图数 = \(self.view.subviews.count)（基线 \(baseline)）")
            }
    }

    // MARK: - 公共构造

    /// I 组共用的画布：页面中下部的一块带边框区域，返回它和它的高度约束（案例里要改高度）。
    /// 每次都从干净状态开始——先清掉上一轮残留的画布，避免案例连点时叠出多块。
    func makeInlineCanvas(
        height: CGFloat = 300
    ) -> (canvas: UIView, heightConstraint: NSLayoutConstraint) {
        view.subviews.filter { $0.tag == Self.inlineCanvasTag }.forEach { $0.removeFromSuperview() }

        let canvas = UIView()
        canvas.tag = Self.inlineCanvasTag
        canvas.backgroundColor = .quaternarySystemFill
        canvas.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        canvas.layer.borderWidth = 1
        canvas.layer.cornerRadius = 12
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)

        let heightConstraint = canvas.heightAnchor.constraint(equalToConstant: height)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            canvas.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            heightConstraint,
        ])
        return (canvas, heightConstraint)
    }

    // MARK: - I1 画布内的弹窗

    @objc func showInlineDialog() {
        let (canvas, _) = makeInlineCanvas()

        let card = MessageCardView(
            title: "画布内的弹窗",
            message: "遮罩只铺满这块画布：画布以外的界面既没被压暗，也不受影响。点画布里的空白处同样能关闭。"
        )
        card.addButton("关闭") { [weak card] in card?.closeCooDialog() }

        CooDialog.center()
            .contentView(card)
            .inline(in: canvas)
            .size(width: 220)
            .logging("I1 画布内弹窗", into: log)
            .show()
            .addCompletionHandler { [weak self, weak canvas] in
                guard let self else { return }
                self.log.record("I1 画布内弹窗", "关闭完成：画布子视图数 = \(canvas?.subviews.count ?? -1)")
                canvas?.removeFromSuperview()
            }
    }

    // MARK: - I2 画布内的底部面板

    @objc func showInlinePanel() {
        let (canvas, _) = makeInlineCanvas(height: 340)

        let panel = PanelContentView(
            title: "画布内的底部面板",
            message: "从画布底边滑入：滑动距离按画布高度算，超出的部分被画布裁掉。往下拖拽或点画布空白处都能关闭。",
            rowCount: 6
        )

        CooDialog.bottom()
            .contentView(panel)
            .inline(in: canvas)
            .backgroundColor(.secondarySystemBackground)
            .logging("I2 画布内面板", into: log)
            .show()
            .addCompletionHandler { [weak self, weak canvas] in
                self?.log.record("I2 画布内面板", "关闭完成：画布已复原")
                canvas?.removeFromSuperview()
            }
    }

    // MARK: - I3 画布变化时弹窗跟随

    @objc func showInlineResizing() {
        let (canvas, heightConstraint) = makeInlineCanvas(height: 200)

        let card = MessageCardView(
            title: "画布变化时弹窗跟随",
            message: "2 秒后这块画布会变高，弹窗跟着重新贴到底边——它贴合的是约束，不是上屏那一刻的 frame。"
        )
        card.addButton("关闭") { [weak card] in card?.closeCooDialog() }

        CooDialog.bottom()
            .contentView(card)
            .inline(in: canvas)
            .backgroundColor(.secondarySystemBackground)
            .logging("I3 画布变化", into: log)
            .show()
            .addCompletionHandler { [weak self, weak canvas] in
                self?.log.record("I3 画布变化", "关闭完成：画布已复原")
                canvas?.removeFromSuperview()
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak canvas] in
            guard canvas != nil else { return }
            heightConstraint.constant = 380
            UIView.animate(withDuration: 0.3) { self?.view.layoutIfNeeded() }
            self?.log.record("I3 画布变化", "画布已改高到 380")
        }
    }

    // MARK: - I4 响应链关闭

    @objc func showInlineResponderChain() {
        let (canvas, _) = makeInlineCanvas()

        let card = MessageCardView(
            title: "响应链关闭",
            message: "点下面的按钮：它会先报出自己是否在弹窗内，再靠 closeCooDialog() 沿响应链找到弹窗。挂载时 addChild 建立的父子关系正是这条链的前提。"
        )
        card.addButton("closeCooDialog()") { [weak self, weak card] in
            let inside = card?.isInCooDialog ?? false
            self?.log.record("I4 响应链", "点击时 isInCooDialog = \(inside)")
            card?.closeCooDialog()
        }

        CooDialog.center()
            .contentView(card)
            .inline(in: canvas)
            .size(width: 240)
            .logging("I4 响应链", into: log)
            .show()
            .addCompletionHandler { [weak self, weak canvas] in
                self?.log.record("I4 响应链", "关闭完成：画布已复原")
                canvas?.removeFromSuperview()
            }
    }

    // MARK: - I5 不属于任何控制器的画布

    @objc func showInlineWithoutHostController() {
        guard let window = view.window else { return }

        // 画布直接挂在窗口上：它不隶属任何控制器的视图层级，
        // 因此挂载时找不到宿主控制器（nearestViewController 为 nil），addChild 那一步跳过。
        // 展示、动画、收尾都照常——这一条正是"inline 不依赖控制器"的证明。
        let canvas = UIView()
        canvas.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        canvas.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.5).cgColor
        canvas.layer.borderWidth = 1
        canvas.layer.cornerRadius = 12
        canvas.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 40),
            canvas.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -40),
            canvas.centerYAnchor.constraint(equalTo: window.centerYAnchor),
            canvas.heightAnchor.constraint(equalToConstant: 220),
        ])

        let card = MessageCardView(
            title: "没有宿主控制器的画布",
            message: "这块画布直接挂在窗口上，不在任何控制器的层级里：挂载照常完成（跳过 addChild），动画与关闭收尾一样不缺。注意按钮只能用持有的控制器关闭——响应链上找不到弹窗。"
        )

        weak var weakDialog: CooDialogViewController?
        card.addButton("关闭") { weakDialog?.dismiss() }

        let dialog = CooDialog.center()
            .contentView(card)
            .inline(in: canvas)
            .size(width: 240)
            .logging("I5 无宿主控制器", into: log)
            .show()
        weakDialog = dialog

        dialog.addCompletionHandler { [weak self, weak canvas] in
            self?.log.record("I5 无宿主控制器", "关闭完成：画布已复原")
            canvas?.removeFromSuperview()
        }
    }
}

// MARK: - 画布标记

extension ViewController {
    /// "I 组画布"的标记：同一个 tag 只允许存在一块，新案例开始前会把旧的清掉
    static let inlineCanvasTag = 8101
}
