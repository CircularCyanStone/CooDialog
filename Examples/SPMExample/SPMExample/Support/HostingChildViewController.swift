//
//  HostingChildViewController.swift
//  SPMExample
//
//  V4 用的宿主子页面：它自己弹一个宿主模式的弹窗，用来验证"弹窗隶属哪个页面"。
//

import UIKit
import CooDialog

/// 子页面：本页会自己弹一个 `presentationMode(.viewController(self))` 的弹窗。
///
/// 要观察的两件事：
/// 1. 关掉弹窗 → 本页还在（弹窗只是本页的一个子层级）
/// 2. 直接关掉本页 → 弹窗跟着一起消失，且**不会**触发弹窗自己的关闭回调
///    （它是被系统连同页面一起摘掉的，没有走弹窗的关闭流程）
final class HostingChildViewController: UIViewController {

    private let log: DialogEventLog

    init(log: DialogEventLog) {
        self.log = log
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let titleLabel = UILabel()
        titleLabel.text = "子页面"
        titleLabel.font = .preferredFont(forTextStyle: .title2)

        let messageLabel = UILabel()
        messageLabel.text = """
        本页会自己弹一个宿主模式的弹窗。试试两种关闭顺序：
        · 先关弹窗 → 本页还在
        · 直接关本页 → 弹窗一起消失（且不会触发弹窗自己的关闭回调）
        """
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        let showButton = UIButton(type: .system)
        showButton.setTitle("在本页弹出弹窗", for: .normal)
        showButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        showButton.addTarget(self, action: #selector(showDialog), for: .touchUpInside)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关掉本页", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        closeButton.addTarget(self, action: #selector(closeSelf), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, showButton, closeButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Actions

    @objc private func showDialog() {
        let card = MessageCardView(
            title: "隶属于本页的弹窗",
            message: "我是被这个子页面 present 出来的：它一被关掉，我也会跟着消失，不需要单独关我。"
        )
        card.addButton("关闭弹窗") { [weak card] in card?.closeSKDialog() }

        SKDialog.center()
            .contentView(card)
            .size(width: 280)
            .presentationMode(.viewController(self))
            .logging("V4 子页弹窗", into: log)
            .show()
    }

    @objc private func closeSelf() {
        dismiss(animated: true)
    }
}
