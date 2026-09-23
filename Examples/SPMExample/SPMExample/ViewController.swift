//
//  ViewController.swift
//  SPMExample
//
//  验证台首页：把 CooDialog 的行为按"展示模式 + 能力"分成六组，一个个点开即可核对。
//  顶部吸顶的"回调轨迹"记录每个案例的动画回调，因此"回调有没有触发、顺序对不对、
//  失败路径有没有回调"不用去看控制台。
//
//  代码分布：案例实现在 Cases/（A 形态与预设 / B 动画 / C 交互 / D 运行时 / E 样式 /
//  V viewController 模式），内容视图在 ContentViews/，公共辅助在 Support/。
//

import UIKit
import CooDialog

final class ViewController: UIViewController {

    // MARK: - 共享状态

    /// 回调轨迹：所有案例共用，吸顶显示
    let log = DialogEventLog()

    /// B1 的动画游标：每点一次换下一种内置动画。
    /// 之所以留在主类型体内：扩展不能声明存储属性，而案例实现都写在扩展里。
    var animationCursor = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let logPanel = log.makePanelView()
        logPanel.translatesAutoresizingMaskIntoConstraints = false

        let list = UIStackView(arrangedSubviews: [
            makeSection("A · 形态与预设（window 模式）", cases: PresetCases.all),
            makeSection("B · 动画（window 模式）", cases: AnimationCases.all),
            makeSection("C · 交互（window 模式）", cases: InteractionCases.all),
            makeSection("D · 运行时操作（window 模式）", cases: RuntimeCases.all),
            makeSection("E · 样式（window 模式）", cases: StyleCases.all),
            makeSection("V · viewController 模式", cases: HostedCases.all),
        ])
        list.axis = .vertical
        list.spacing = 28
        list.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(list)

        view.addSubview(logPanel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            // 轨迹面板吸顶：案例列表滚到再深，回调轨迹也还在眼前
            logPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            logPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: logPanel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            list.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            list.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            list.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            list.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            list.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    // MARK: - UI

    /// 一个分组：组标题 + 该组案例（每条案例是一张两行式卡片）
    private func makeSection(_ title: String, cases: [Case]) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .secondaryLabel

        let cells = cases.map { item -> UIView in
            let cell = CaseCell(item)
            cell.addTarget(self, action: item.action, for: .touchUpInside)
            return cell
        }

        let column = UIStackView(arrangedSubviews: cells)
        column.axis = .vertical
        column.spacing = 8

        let section = UIStackView(arrangedSubviews: [titleLabel, column])
        section.axis = .vertical
        section.spacing = 10
        return section
    }
}
