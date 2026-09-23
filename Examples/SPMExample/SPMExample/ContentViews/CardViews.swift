//
//  CardViews.swift
//  SPMExample
//
//  弹窗内容视图的通用件：绝大多数案例的内容都是"标题 + 说明 + 若干按钮"，
//  因此只有这一个可变形的卡片类 + 一个可展开的变体，不需要为每个案例写一个视图类。
//

import UIKit

// MARK: - 基础卡片

/// 通用卡片：标题 + 说明 + 若干按钮；四边留白由自身约束给出（容器四边贴合它）。
///
/// 非 final：`ResizableCardView` 在它之上加了"展开/收起"这一层交互，
/// 复用同一套排版与按钮机制。
class MessageCardView: UIView {

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    /// 按钮容器：子类要往指定位置插按钮（展开/收起固定在最前），故对同文件开放
    fileprivate let buttonStack = UIStackView()

    /// - Parameters:
    ///   - title: 卡片标题（较大字号）
    ///   - message: 说明文案（多行；宽度由容器决定，容器自适应时反过来决定容器宽度）
    init(title: String, message: String) {
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0

        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        buttonStack.axis = .vertical
        buttonStack.spacing = 8

        let root = UIStackView(arrangedSubviews: [titleLabel, messageLabel, buttonStack])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 追加一个按钮（可以在弹窗展示之后再调用，界面上即时生效）。
    /// 按钮顺序即调用顺序；回调里要关闭弹窗时，用持有的控制器或 `sender.closeSKDialog()`。
    @discardableResult
    func addButton(_ title: String, handler: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        buttonStack.addArrangedSubview(button)
        return button
    }

    /// 更新说明文案（用于"内容变长/变短"这类需要观察容器反应的案例）
    func setMessage(_ text: String) {
        messageLabel.text = text
    }
}

// MARK: - 可展开卡片

/// 可展开卡片：内容在"收起一句话 / 展开一段话"之间切换，切换时回调宿主。
///
/// 存在的意义是把"内容变化"与"容器尺寸怎么变"拆开：
/// 卡片只负责改自己的内容，尺寸要不要跟着改由案例决定——
/// D1 调 `updateContainerHeight` 改容器，D3 故意不调、用来验证内容自己能撑开容器。
final class ResizableCardView: MessageCardView {

    /// 展开状态变化回调（参数为变化后的状态）
    var onToggle: ((Bool) -> Void)?

    private let collapsedText: String
    private let expandedText: String
    private let toggleButton = UIButton(type: .system)

    private(set) var isExpanded = false

    /// - Parameters:
    ///   - title: 卡片标题
    ///   - collapsed: 收起状态下的说明
    ///   - expanded: 展开状态下的说明
    init(title: String, collapsed: String, expanded: String) {
        self.collapsedText = collapsed
        self.expandedText = expanded
        super.init(title: title, message: collapsed)

        toggleButton.setTitle("展开更多", for: .normal)
        toggleButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        // 固定放在最前：先让它改变内容，再看容器如何响应
        buttonStack.insertArrangedSubview(toggleButton, at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func toggle() {
        isExpanded.toggle()
        setMessage(isExpanded ? expandedText : collapsedText)
        toggleButton.setTitle(isExpanded ? "收起" : "展开更多", for: .normal)
        onToggle?(isExpanded)
    }
}
