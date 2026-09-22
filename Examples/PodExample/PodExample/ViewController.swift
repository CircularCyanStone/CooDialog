//
//  ViewController.swift
//  PodExample
//
//  这是 CocoaPods 集成示例的占位文件：仓库里不包含 Podfile 与 Pods 目录，
//  所以本文件暂不 import CooDialog（否则未执行 pod install 的机器上无法编译）。
//
//  接入步骤：
//  1) 在 Examples/PodExample 目录下创建 Podfile：
//
//         platform :ios, '13.0'
//         target 'PodExample' do
//           use_frameworks!
//           pod 'CooDialog', :path => '../../'
//         end
//
//  2) 执行 `pod install`，然后打开 PodExample.xcworkspace（注意不是 .xcodeproj）
//  3) 在文件顶部加上 `import CooDialog`，即可按 Examples/SPMExample/SPMExample/ViewController.swift
//     里的写法使用同一套 API——两种集成方式的用法完全一致
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        // 集成完成后，这里可以写成：
        //
        //     SKDialog.bottom()
        //         .contentView(makePanelView())
        //         .show()
    }
}
