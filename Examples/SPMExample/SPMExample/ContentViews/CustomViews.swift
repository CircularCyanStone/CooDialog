//
//  CustomViews.swift
//  SPMExample
//
//  专用内容视图与自定义动画：只有个别案例需要的部件集中在这里。
//

import UIKit
import CooDialog

// MARK: - 提示条

/// 提示条内容：单行文案 + 可选副标题，宽度由内容决定（配合顶部/底部弹窗使用）。
final class ToastView: UIView {

    /// - Parameters:
    ///   - text: 主文案
    ///   - subtitle: 副文案（例如用来标注当前用的是哪种配置）
    init(text: String, subtitle: String? = nil) {
        super.init(frame: .zero)

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 2

        if let subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 0
            stack.addArrangedSubview(subtitleLabel)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 深层嵌套的关闭按钮

/// 把"关闭弹窗"按钮埋在 3 层嵌套容器里（C4）。
///
/// 验证点：响应链反查与嵌套层数无关。按钮本身不认识弹窗控制器，
/// `closeSKDialog()` 从自己出发沿 `next` 一路上溯，穿过多层父视图照样能找到。
/// 为了让人看清"找没找到"，先把判定结果写进标签、停留一秒再真正关闭。
final class DeepNestedCloseView: UIView {

    private let resultLabel = UILabel()

    init() {
        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = "按钮埋在 3 层容器里"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = "点最里面那颗按钮：它先报出自己在不在弹窗内，一秒后才真正关闭。"
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.numberOfLines = 0
        resultLabel.text = "isInSKDialog = ?"

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭弹窗", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        closeButton.addTarget(self, action: #selector(closeTapped(_:)), for: .touchUpInside)

        // 三层同心的嵌套容器：每层只做一件事——再包一层
        let layer3 = Self.makeNestedLayer(color: .systemBlue, content: closeButton)
        let layer2 = Self.makeNestedLayer(color: .systemGreen, content: layer3)
        let layer1 = Self.makeNestedLayer(color: .systemOrange, content: layer2)

        let root = UIStackView(arrangedSubviews: [titleLabel, messageLabel, layer1, resultLabel])
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

    /// 一层带描边的容器（描边只是让嵌套关系肉眼可见）
    private static func makeNestedLayer(color: UIColor, content: UIView) -> UIView {
        let layer = UIView()
        layer.layer.borderColor = color.withAlphaComponent(0.5).cgColor
        layer.layer.borderWidth = 1
        layer.layer.cornerRadius = 8

        content.translatesAutoresizingMaskIntoConstraints = false
        layer.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: layer.topAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: layer.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: layer.trailingAnchor, constant: -8),
            content.bottomAnchor.constraint(equalTo: layer.bottomAnchor, constant: -8),
        ])
        return layer
    }

    @objc private func closeTapped(_ sender: UIView) {
        resultLabel.text = "isInSKDialog = \(sender.isInSKDialog) → 已命中所属弹窗，1 秒后关闭"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak sender] in
            sender?.closeSKDialog()
        }
    }
}

// MARK: - 自定义动画

/// 旋转 + 缩放的入场/退场动画（B2）。
///
/// 它存在的意义不是好看，而是证明"库外能注入动画"这条路是通的：
/// 实现 `SKDialogAnimationProtocol` 后经 `.animation(.custom(...))` 传入即可，
/// 不需要改库，也不会与内置动画共用任何代码——只有 easing 曲线复用了公开的
/// `SKDialogAnimationUtils`，以保证手感与内置动画一致。
///
/// 两条硬性约定（协议要求）：起点由动画自己设置（内置动画也这么做，因此动画是自包含的）；
/// 无论动画是否被打断，`completion` 都必须被恰好调用一次。
struct SpinScaleAnimation: SKDialogAnimationProtocol {

    func performPresentAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        backgroundView.alpha = 0
        containerView.alpha = 0
        containerView.transform = CGAffineTransform(rotationAngle: -.pi / 8).scaledBy(x: 0.5, y: 0.5)

        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in completion() }
        )
    }

    func performDismissAnimation(
        backgroundView: UIView,
        containerView: UIView,
        config: SKDialogConfig,
        completion: @escaping () -> Void
    ) {
        // 退场与入场镜像：同样的方向与比例，看起来像"转回去"
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration,
            damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 0
                containerView.alpha = 0
                containerView.transform = CGAffineTransform(rotationAngle: .pi / 8).scaledBy(x: 0.5, y: 0.5)
            },
            completion: { _ in completion() }
        )
    }
}
