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
//  轨迹的两个出口（同一批文本，各适合一种场景）：
// - 面板：可滚动的只读文本视图，轨迹条数与单行长度都不受面板高度限制；
//   想整段取走就点标题行的"复制"。
// - 控制台：每行都带 `[CooDialog]` 前缀打到 Xcode 控制台，在控制台搜索框输入它即可过滤出全部轨迹。
//

import UIKit

/// 回调轨迹记录器：面板视图与数据都在这里，所有案例共用一个实例。
///
/// 标注 @MainActor：它持有并操作 UIKit 视图，且只会被主线程的回调与按钮事件写入。
@MainActor
final class DialogEventLog {

    /// 轨迹可视区的高度（点）。文本视图可滚动，因此这里只决定"一屏能看几行"，
    /// 不再限制"一共能看几条"——轨迹多了滚动即可，最新的那条始终自动露出来。
    private let visibleHeight: CGFloat = 96

    /// 面板本体（吸顶用）
    private let panel = UIView()

    /// 轨迹文本：只读、可滚动、可选中（长按选中与"复制"按钮互补）
    private let textView = UITextView()

    /// 保留的轨迹（只保留最近 200 条，避免长时间点击后无限增长）
    private var entries: [String] = []

    /// 相对时间基准：所有轨迹按"点击后第几秒"显示，跨案例的时间差一目了然
    private let startTime = Date()

    /// 记录一条轨迹。
    /// - Parameters:
    ///   - name: 案例名（例如 "A1 底部面板"）
    ///   - event: 事件名（四个回调名，或案例自己的说明，例如 "sizeMode -> fixed 300×360"）
    ///
    /// - Note: 同一条轨迹写两份出口——面板上显示（抬眼看），同时打到 Xcode 控制台（便于整段复制）。
    ///   控制台行带 `[CooDialog]` 前缀：在 Xcode 控制台的搜索框里输入它，就能把库的轨迹
    ///   从系统日志里过滤出来，整段选中复制即可。
    func record(_ name: String, _ event: String) {
        let elapsed = Date().timeIntervalSince(startTime)
        let line = String(format: "%6.2fs  %@  %@", elapsed, name, event)
        entries.append(line)
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        refreshText()

        print("[CooDialog] \(line)")
    }

    /// 组装吸顶面板：标题行（含"复制""清空"）+ 轨迹文本。
    /// 面板高度固定，因此下方清单不会因为轨迹条数变化而上下跳动。
    func makePanelView() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "回调轨迹"
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel

        let hintLabel = UILabel()
        hintLabel.text = "可滚动 · 点案例后看这里"
        hintLabel.font = .preferredFont(forTextStyle: .caption2)
        hintLabel.textColor = .tertiaryLabel

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        let copyButton = UIButton(type: .system)
        copyButton.setTitle("复制", for: .normal)
        copyButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        copyButton.addTarget(self, action: #selector(copyTapped(_:)), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, hintLabel, UIView(), copyButton, clearButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = false
        // 清零内边距，让轨迹行与面板左右边界对齐（默认值会额外缩进）
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "log.trace"
        textView.text = placeholder

        let root = UIStackView(arrangedSubviews: [header, textView])
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
            // 固定高度：面板不随轨迹条数变化，吸顶内容不会跳动；轨迹本身可滚动查看
            textView.heightAnchor.constraint(equalToConstant: visibleHeight),
        ])

        return panel
    }

    // MARK: - Private

    private var placeholder: String {
        "（暂无轨迹：点下面的案例按钮）"
    }

    private func refreshText() {
        guard !entries.isEmpty else {
            textView.text = placeholder
            return
        }

        // 全部轨迹都放进去（不再只取最后 5 行），超出可视区由滚动解决
        textView.text = entries.joined(separator: "\n")

        // 最新的那条在最后：每次记录后自动滚到底，保证"刚点完的那一下"一定看得见
        textView.scrollRangeToVisible(NSRange(location: (textView.text as NSString).length, length: 0))
    }

    @objc private func clearTapped() {
        entries.removeAll()
        refreshText()
    }

    /// 把**全部**轨迹拷进剪贴板——跑完一轮案例后一键取走结果。
    ///
    /// 与 `record` 打到控制台的是同一批文本，两种取法适合不同场景：
    /// 控制台适合连着 Xcode 跑、边跑边看；剪贴板适合已经跑完、想整段贴给别人时。
    @objc private func copyTapped(_ sender: UIButton) {
        UIPasteboard.general.string = entries.isEmpty ? "（暂无轨迹）" : entries.joined(separator: "\n")

        // 用按钮标题做反馈，而不是往轨迹里插一行"已复制"——免得复制这个动作本身污染结果
        sender.setTitle("已复制", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak sender] in
            sender?.setTitle("复制", for: .normal)
        }
    }
}
