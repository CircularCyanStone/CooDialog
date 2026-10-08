//
//  ViewController.swift
//  PodExample
//
//  这是 CocoaPods 集成示例：用的 API 与 SPMExample 完全一致，只是接入方式不同。
//
//  接入步骤（Podfile 已入库，用 `:path` 指向仓库根目录的本地源码）：
//  1) 在 Examples/PodExample 目录下执行 `pod install`
//  2) 打开 PodExample.xcworkspace（注意不是 .xcodeproj），运行后点按钮即可看到弹窗
//  3) 真实项目里把 Podfile 的 `:path` 换成 `pod 'CooDialog'`（走远端版本，见 README）
//

import UIKit
import CooDialog

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        let button = UIButton(type: .system)
        button.setTitle("弹一个居中对话框", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(showDialog), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// 与 SPM 集成写法完全相同的一条链式调用：配置 → 装内容 → 展示。
    /// （`SKDialog.center()` 已预设居中定位、缩放淡入与四周 40 边距，这里只覆盖宽度）
    @objc private func showDialog() {
        // 内容自己负责留白：容器会把内容四边贴合，因此边距写在这一层
        let content = UIView()
        content.layoutMargins = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)

        let label = UILabel()
        label.text = "这个弹窗由 CooDialog 通过 CocoaPods 集成而来。点遮罩即可关闭。"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.layoutMarginsGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: content.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: content.layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: content.layoutMarginsGuide.bottomAnchor),
        ])

        SKDialog.center()
            .contentView(content)
            .size(width: 280)
            .show()
    }
}
