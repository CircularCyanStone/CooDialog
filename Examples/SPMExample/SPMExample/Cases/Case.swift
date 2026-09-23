//
//  Case.swift
//  SPMExample
//
//  案例清单的数据结构：一条 Case 就是一个可以点的验证项。
//  把"主文案 / 在验证什么 / 自动化锚点 / 动作"收在一个类型里，清单本身就充当这份示例的说明书。
//

import UIKit

/// 一个可执行的验证案例
struct Case {

    /// 按钮主文案（做什么）
    let title: String

    /// 这个案例在验证什么（显示在主文案下方，让"点之前"就知道该看什么）
    let detail: String

    /// accessibilityIdentifier：给将来的 UI 自动化留的锚点，也方便用 Xcode 的 UI 检查器定位
    let identifier: String

    /// 点击后执行的方法（都定义在 ViewController 的各个案例扩展里）
    let action: Selector
}

/// 两行式案例按钮：主文案 + 验证说明。
///
/// 用 UIControl 而不是 UIButton：这里需要两行排版和自定义高亮反馈，
/// UIButton 的 titleLabel 撑不起这个结构（它的排版逻辑只服务单行/多行标题）。
final class CaseCell: UIControl {

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(_ item: Case) {
        super.init(frame: .zero)

        accessibilityIdentifier = item.identifier
        // 让整块卡片成为一个无障碍元素：VoiceOver 能读出"做什么 + 在验证什么"，
        // 后续接 UI 自动化时也能直接用它定位
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.title
        accessibilityHint = item.detail
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 10

        titleLabel.text = item.title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.numberOfLines = 0

        detailLabel.text = item.detail
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 2
        // 点击命中整块卡片（子视图不参与命中判定，手势统一落在 UIControl 上）
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground }
    }
}
