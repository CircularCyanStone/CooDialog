//
//  DialogEventLog.swift
//  SPMExample
//
//  页面顶部那块"回调轨迹"面板：把每个案例的四个动画回调按时间记下来。
//
//  为什么要放在页面上而不是只看控制台：弹窗的三个关键约定都跟"回调何时触发"有关——
//  入场回调只在动画正常跑完时触发、失败路径（没上屏）也必须回调、关闭回调不能丢。
//  这些用一条时间线对比最快：点一下按钮，抬眼看轨迹就知道有没有、顺序对不对。
//

import UIKit

/// 回调轨迹记录器：面板视图与数据都在这里，所有案例共用一个实例。
///
/// 标注 @MainActor：它持有并操作 UIKit 视图，且只会被主线程的回调与按钮事件写入。
@MainActor
final class DialogEventLog {

    /// 面板上最多显示几行（更早的轨迹仍保留在内存里，滚动查看用"全部"按钮不需要，暂时不做）
    private let maxVisibleLines = 5

    /// 面板本体（吸顶用）
    private let panel = UIView()

    /// 轨迹文本
    private let textLabel = UILabel()

    /// 保留的轨迹（只保留最近 200 条，避免长时间点击后无限增长）
    private var entries: [String] = []

    /// 相对时间基准：所有轨迹按"点击后第几秒"显示，跨案例的时间差一目了然
    private let startTime = Date()

    /// 记录一条轨迹。
    /// - Parameters:
    ///   - name: 案例名（例如 "A1 底部面板"）
    ///   - event: 事件名（四个回调名，或案例自己的说明，例如 "sizeMode -> fixed 300×360"）
    func record(_ name: String, _ event: String) {
        let elapsed = Date().timeIntervalSince(startTime)
        entries.append(String(format: "%6.2fs  %@  %@", elapsed, name, event))
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        refreshText()
    }

    /// 组装吸顶面板：标题行（含"清空"）+ 轨迹文本。
    /// 面板高度固定（5 行），因此下方清单不会因为轨迹条数变化而上下跳动。
    func makePanelView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "回调轨迹"
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel

        let hintLabel = UILabel()
        hintLabel.text = "点案例后看这里"
        hintLabel.font = .preferredFont(forTextStyle: .caption2)
        hintLabel.textColor = .tertiaryLabel

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, hintLabel, UIView(), clearButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        textLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textLabel.textColor = .label
        textLabel.numberOfLines = maxVisibleLines
        textLabel.lineBreakMode = .byTruncatingHead
        textLabel.accessibilityIdentifier = "log.trace"
        textLabel.text = placeholder

        let root = UIStackView(arrangedSubviews: [header, textLabel])
        root.axis = .vertical
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false

        panel.backgroundColor = .secondarySystemGroupedBackground
        panel.layer.cornerRadius = 12
        panel.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            root.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),
            // 固定 5 行高度：面板不随轨迹条数变化，吸顶内容不会跳动
            textLabel.heightAnchor.constraint(equalToConstant: 68),
        ])

        return panel
    }

    // MARK: - Private

    private var placeholder: String {
        "（暂无轨迹：点下面的案例按钮）"
    }

    private func refreshText() {
        guard !entries.isEmpty else {
            textLabel.text = placeholder
            return
        }
        textLabel.text = entries.suffix(maxVisibleLines).joined(separator: "\n")
    }

    @objc private func clearTapped() {
        entries.removeAll()
        refreshText()
    }
}
