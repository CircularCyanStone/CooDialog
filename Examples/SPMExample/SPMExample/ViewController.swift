//
//  ViewController.swift
//  SPMExample
//
//  演示通过 Swift Package 集成 CooDialog 后的常见用法：
//  三种预设形态（底部面板 / 居中对话框 / 顶部提示条）、链式配置、
//  拖拽与滚动的协作、以及入场与关闭回调。
//

import UIKit
import CooDialog

final class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let stack = UIStackView(arrangedSubviews: [
            makeButton(title: "底部面板（列表可滚动，可下拉关闭）", action: #selector(showBottomPanel)),
            makeButton(title: "居中对话框（固定宽度）", action: #selector(showCenterDialog)),
            makeButton(title: "顶部提示条（2 秒后自动关闭）", action: #selector(showTopToast)),
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - 底部面板

    /// 面板里的列表可以正常滚动；只有列表已经滚到顶部、继续下拉时，才会把面板拖走关闭
    /// （这是库内置的"拖拽让位给滚动"策略，宿主不需要额外处理）。
    @objc private func showBottomPanel() {
        let panel = PanelContentView(title: "底部面板", rowCount: 20)

        SKDialog.bottom()
            .contentView(panel)
            .backgroundColor(.secondarySystemBackground)
            .shadow(show: true, radius: 12, opacity: 0.12)
            .onPresentAnimationDidFinish { print("[SPMExample] 底部面板已展开") }
            .show()
    }

    // MARK: - 居中对话框

    @objc private func showCenterDialog() {
        let card = CenterCardView()
        let dialog = SKDialog.center()
            .contentView(card)
            .size(width: 300)                       // 只固定宽度，高度随内容
            .cornerRadius(16)
            .animation(.fadeScale, duration: 0.25)
            .show()

        // 展示后仍能拿到控制器：用它关闭并带上"关闭完成"回调
        card.onConfirm = { [weak dialog] in
            dialog?.dismissDialog { print("[SPMExample] 对话框已关闭") }
        }
    }

    // MARK: - 顶部提示条

    @objc private func showTopToast() {
        let toast = ToastView(text: "已保存")
        let dialog = SKDialog.top()
            .contentView(toast)
            .cornerRadius(12)
            .extendToSafeArea(false)                // 避开刘海，内容自身留白即可
            .show()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak dialog] in
            dialog?.dismissDialog()
        }
    }
}

// MARK: - 内容视图

/// 底部面板内容：标题 + 关闭按钮 + 可滚动列表。
private final class PanelContentView: UIView {

    init(title: String, rowCount: Int) {
        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        // 不需要持有弹窗控制器：沿响应链反查所属弹窗即可
        closeButton.addTarget(self, action: #selector(closeTapped(_:)), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), closeButton])
        header.axis = .horizontal
        header.alignment = .center

        let rows = UIStackView(arrangedSubviews: (1...rowCount).map { index in
            let label = UILabel()
            label.text = "第 \(index) 行：滚动列表时不会拖动面板，滚到顶部后继续下拉才会关闭"
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.numberOfLines = 0
            return label
        })
        rows.axis = .vertical
        rows.spacing = 12

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            rows.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 260),
        ])

        let root = UIStackView(arrangedSubviews: [header, scrollView])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            // 底部面板默认贴屏幕下边缘（extendToSafeArea），用安全区避开 Home Indicator
            root.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func closeTapped(_ sender: UIView) {
        sender.closeSKDialog()
    }
}

/// 居中对话框内容：标题 + 说明 + 确认按钮（高度由内容撑开）。
private final class CenterCardView: UIView {

    /// 点击确认时回调（由 ViewController 接管关闭逻辑）
    var onConfirm: (() -> Void)?

    init() {
        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = "居中对话框"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = "宽度固定 300pt，高度由内容撑开；确认后关闭并打印关闭回调。"
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        let confirmButton = UIButton(type: .system)
        confirmButton.setTitle("确认", for: .normal)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        let root = UIStackView(arrangedSubviews: [titleLabel, messageLabel, confirmButton])
        root.axis = .vertical
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func confirmTapped() {
        onConfirm?()
    }
}

/// 顶部提示条内容：单行文案，宽度由内容决定。
private final class ToastView: UIView {

    init(text: String) {
        super.init(frame: .zero)

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
