//
//  TransitionCases.swift
//  SPMExample
//
//  T 组 · 转场验证：弹窗关闭之后，"该还回去的东西"有没有还。
//
//  为什么单独成组：库的收尾动作里有一半落在**系统转场真正跑完之后**——present 关系的摘除、
//  自建 window 的回收、key window 的归还、引用环的解开。这些在单元测试环境里观察不到
//  （测试用的 UIWindow 没有 scene，系统的 present / dismiss 转场根本不推进：
//  调完 host.dismiss(animated:false) 后 presentedViewController 照样不变），
//  只有跑在真实窗口环境里的示例工程才能验证。
//
//  怎么看结果：点一下案例，抬眼看顶部"回调轨迹"面板（可滚动，轨迹不会被截断）。每个探针最后都会
//  打出一行 **"结论：… ✓ / ✗"**——不用自己比对，直接看那行的勾叉；中间几行是采样过程，
//  想核对细节（窗口清单、层级、谁持有 key）时再看。
//
//  采样点的讲究（读代码时容易误会的一处）：库自身的收尾是**同步**的，而 UIKit 摘掉 present 关系、
//  把视图移出窗口是**异步**的（要到下一次 runloop 才落定）。所以在关闭回调里立刻读
//  `presentedViewController` / `view.window` 只会读到旧值——那是采样时机的问题，不是库没归还。
//  T1 因此等 0.5 秒后再采样；T2/T3 采的是库自己同步回收的窗口状态，在回调里读就是准的。
//
//  想跟代码的话，收尾链路按顺序经过这三处，断在这三个方法里即可：
//  1. `SKDialogViewController.dismiss(animated:completion:)` —— 状态推进到 .finished 与分派
//  2. `SKDialogViewController.completeDismissal(completion:)` —— 摘 present → 回收 window → 触发回调
//  3. `SKDialogWindowManager.removeCustomWindow()` —— 拆窗口树、归还 key window
//

import UIKit
import CooDialog

extension ViewController {

    enum TransitionCases {
        static let all: [Case] = [
            Case(title: "T1 宿主模式：关闭后 present 关系归还",
                 detail: "关闭后等系统转场落定再采样：present 关系应双清、视图应离开窗口层级（单测环境观察不到）",
                 identifier: "case.transition.hostedTeardown",
                 action: #selector(ViewController.probeHostedTeardown)),
            Case(title: "T2 window 模式：自建窗口回收 + key 归还",
                 detail: "展示前 / 展示后 / 关闭后各拍一次窗口快照：自建窗口应消失、key 应回到 App 窗口",
                 identifier: "case.transition.windowTeardown",
                 action: #selector(ViewController.probeWindowTeardown)),
            Case(title: "T3 上屏前关闭（本次修复的核心场景）",
                 detail: "show() 之后立刻 dismiss()：窗口应回落、key 应归还、弹窗不该冒出来、对象应被释放",
                 identifier: "case.transition.dismissBeforeAppear",
                 action: #selector(ViewController.probeDismissBeforeAppear)),
            Case(title: "T4 同一个实例再次展示",
                 detail: "第一轮自动关闭后用同一个弹窗实例再 show()：应重新进入展示状态并照常播入场动画",
                 identifier: "case.transition.reShow",
                 action: #selector(ViewController.probeReShow)),
        ]
    }

    // MARK: - 窗口观测（日志与结论行共用同一份数据）

    /// 当前场景里的全部窗口
    func currentWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    /// 场景里是否还有 CooDialog 自建的窗口。
    /// 判定依据是层级：库默认把自建窗口设为 `.alert + 1`，因此"层级高于 `.normal`"即自建。
    /// - Note: 键盘窗口的层级同样高于 `.normal`，本组探针都不聚焦输入框，不会误判。
    func hasDialogWindow() -> Bool {
        currentWindows().contains { $0.windowLevel > .normal }
    }

    /// key window 是否在 App 自己的窗口上（= 已经归还，而不是停在自建窗口）
    func isKeyWindowAppOwned() -> Bool {
        guard let key = currentWindows().first(where: { $0.isKeyWindow }) else { return false }
        return key.windowLevel <= .normal
    }

    /// 窗口清单（一行文本）：数量 + 每个窗口的"身份(层级)" + 谁是 key。
    /// 层级数字一并打出来——即便身份判定规则需要调整，也能直接从数字看出实际值。
    func windowSnapshot() -> String {
        let windows = currentWindows()
        let items = windows.map { window -> String in
            let role = window.windowLevel > .normal ? "自建" : "App"
            return "\(role)(lv\(Int(window.windowLevel.rawValue)))\(window.isKeyWindow ? "★key" : "")"
        }
        return "窗口 \(windows.count) 个：\(items.joined(separator: "、"))"
    }

    // MARK: - T1 宿主模式收尾

    @objc func probeHostedTeardown() {
        let name = "T1 宿主收尾"

        let dialog = SKDialogViewController(config: SKDialogConfig.centerDialog(
            width: 280,
            presentationMode: .viewController(self)
        ))
        dialog.addContentView(MessageCardView(
            title: "宿主模式收尾探针",
            message: "关掉我（点遮罩或拖走）：关闭后会等系统转场落定再采样，核对 present 关系与视图层级是否都归还给了本页。"
        ))

        // 弱引用观察，避免探针自己延长弹窗生命周期（否则"是否释放"永远是假阳性）
        weak var weakDialog = dialog

        dialog.addCompletionHandler { [weak self] in
            guard let self else { return }

            // 采样点必须等系统转场落定——库自身的收尾（状态复位、回调清理）在回调触发时已完成，
            // 但 UIKit 摘掉 present 关系、把视图移出窗口是**异步**的：在这一刻立刻读，
            // presentedViewController / view.window 都还是旧值（本库的契约只承诺"视觉上已消失、
            // window 与 key 已收尾"，不承诺这两个属性已刷新，见 SKDialogViewController.dismiss 的说明）。
            self.log.record(name, "关闭流程已走完，等系统转场落定后采样")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }

                let hostReleased = self.presentedViewController == nil

                if let stillAlive = weakDialog {
                    let dialogReleased = stillAlive.presentingViewController == nil
                    let viewDetached = stillAlive.view.window == nil
                    let stateReset = !stillAlive.isPresenting

                    self.log.record(name, "present 关系 宿主=\(hostReleased ? "nil ✓" : "非 nil ✗")、弹窗=\(dialogReleased ? "nil ✓" : "非 nil ✗")")
                    self.log.record(name, "视图层级 view.window=\(viewDetached ? "nil ✓" : "仍在窗口 ✗")、isPresenting=\(stateReset ? "false ✓" : "true ✗")")
                    self.log.record(name, "结论：\(hostReleased && dialogReleased && viewDetached && stateReset ? "收尾完整 ✓" : "有未归还项 ✗")")
                } else {
                    // 弹窗对象已被释放：宿主不再持有它（否则不可能释放），比"属性为 nil"更彻底的归还
                    self.log.record(name, "present 关系 宿主=\(hostReleased ? "nil ✓" : "非 nil ✗")")
                    self.log.record(name, "结论：\(hostReleased ? "收尾完整 ✓（弹窗对象已释放，无引用环）" : "有未归还项 ✗")")
                }
            }
        }

        dialog.show()
    }

    // MARK: - T2 window 模式收尾

    @objc func probeWindowTeardown() {
        let name = "T2 window 收尾"
        log.record(name, "展示前 \(windowSnapshot())")

        let dialog = SKDialog.center()
            .contentView(MessageCardView(
                title: "window 模式收尾探针",
                message: "关掉我：轨迹里对比展示前后的窗口清单——自建窗口应消失、key 应回到 App 窗口。"
            ))
            .show()

        weak var weakDialog = dialog

        log.record(name, "展示后 \(windowSnapshot())（此刻 key 应在自建窗口上）")

        dialog.addCompletionHandler { [weak self] in
            guard let self else { return }

            let windowRecycled = !self.hasDialogWindow()
            let keyReturned = self.isKeyWindowAppOwned()

            self.log.record(name, "关闭后 \(self.windowSnapshot())")
            self.log.record(name, "结论：自建窗口 \(windowRecycled ? "已回收 ✓" : "未回收 ✗")、key \(keyReturned ? "已归还 ✓" : "未归还 ✗")")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.log.record(name, "1 秒后弹窗对象 \(weakDialog == nil ? "已释放 ✓（无引用环）" : "仍存活 ✗（window 与弹窗成环）")")
            }
        }
    }

    // MARK: - T3 上屏前关闭（本次修复的核心场景）

    @objc func probeDismissBeforeAppear() {
        let name = "T3 上屏前关闭"
        log.record(name, "展示前 \(windowSnapshot())")

        let dialog = SKDialog.center()
            .contentView(MessageCardView(
                title: "（这个弹窗不该出现）",
                message: "如果你看到了我，说明“上屏前关闭”失效了——修复前它会自己冒出来并一直停在屏幕上。"
            ))
            .show()

        weak var weakDialog = dialog

        // 关键一步：show() 刚返回（present 已建立、入场动画还没发起）就关闭。
        // 修复前这次 dismiss 会被整体跳过：自建 window 不回收、弹窗随后被 viewDidAppear 拉起来。
        log.record(name, "show() 已返回，立刻 dismiss()")
        dialog.dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }

            let windowRecycled = !self.hasDialogWindow()
            let keyReturned = self.isKeyWindowAppOwned()
            let released = weakDialog == nil

            self.log.record(name, "1 秒后 \(self.windowSnapshot())")
            self.log.record(name, "结论：自建窗口 \(windowRecycled ? "已回收 ✓" : "未回收 ✗（弹窗多半已冒出来）")、key \(keyReturned ? "已归还 ✓" : "未归还 ✗")、弹窗对象 \(released ? "已释放 ✓" : "仍存活 ✗")")
        }
    }

    // MARK: - T4 同一个实例再次展示

    @objc func probeReShow() {
        let name = "T4 二次展示"

        let dialog = SKDialog.center()
            .contentView(MessageCardView(
                title: "二次展示探针",
                message: "第一轮 0.8 秒后自动关闭；随后用同一个实例再 show() 一次，看是否照常显示。"
            ))
            .show()

        dialog.addCompletionHandler { [weak self, weak dialog] in
            guard let self, let dialog else { return }
            self.log.record(name, "第一轮已关闭 isPresenting=\(dialog.isPresenting ? "true ✗" : "false ✓")")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                var didFinishFired = false
                dialog.presentAnimationDidFinishHandler = { didFinishFired = true }

                dialog.show()
                let stateRestored = dialog.isPresenting
                self.log.record(name, "第二轮 show() 后 isPresenting=\(stateRestored ? "true ✓" : "false ✗")")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.log.record(name, "第二轮 \(self.windowSnapshot())")
                    self.log.record(name, "结论：状态\(stateRestored ? "已离开已收尾 ✓" : "仍停在已收尾 ✗")、入场完成回调\(didFinishFired ? "已触发 ✓" : "未触发 ✗")")
                }
            }
        }

        // 自动收尾，让轨迹连贯：不用手点也能看到完整的一轮 → 二轮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak dialog] in
            dialog?.dismiss()
        }
    }
}
