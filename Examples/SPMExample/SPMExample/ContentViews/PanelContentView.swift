//
//  PanelContentView.swift
//  SPMExample
//
//  底部 / 顶部面板的内容视图：标题 + 一行说明 + 关闭按钮 + 可滚动列表。
//  从 ViewController.swift 的私有内容视图搬出并通用化——它是"拖拽与滚动协作"、
//  "拖拽关闭"、"固定高度面板"三个案例共用的载体。
//

import UIKit
import CooDialog

/// 面板内容：标题 + 说明 + 关闭按钮 + 可滚动列表。
///
/// 滚动视图的高度约束用 999 优先级（而不是 required）：
/// 容器自适应时按 260 显示，容器被固定高度（A4 的 `.fixedHeight(400)`）或临时钉住时
/// 以容器为准，不会因为"内容想要 260"而与容器的固定尺寸打架。
final class PanelContentView: UIView {

    /// - Parameters:
    ///   - title: 面板标题
    ///   - message: 标题下的一行说明
    ///   - rowCount: 列表行数（行越多越能看出滚动与拖拽的让位关系）
    init(title: String, message: String, rowCount: Int = 12) {
        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        // 不需要持有弹窗控制器：沿响应链反查所属弹窗即可
        closeButton.addAction(UIAction { [weak self] _ in self?.closeSKDialog() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), closeButton])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        let rows = UIStackView(arrangedSubviews: (1...rowCount).map { index in
            let label = UILabel()
            label.text = "第 \(index) 行：滚动列表时不会拖动面板，滚到顶部后继续下拉才会关闭"
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.numberOfLines = 0
            return label
        })
        rows.axis = .vertical
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(rows)

        let preferredHeight = scrollView.heightAnchor.constraint(equalToConstant: 260)
        preferredHeight.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            rows.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            preferredHeight,
        ])

        let root = UIStackView(arrangedSubviews: [header, messageLabel, scrollView])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            // 底部面板默认贴屏幕下边缘（extendToSafeArea），因此用安全区避开 Home Indicator
            root.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
