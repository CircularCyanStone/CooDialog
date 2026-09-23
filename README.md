# CooDialog

iOS 弹窗组件：一个基于 AutoLayout 的轻量弹窗，提供**底部面板 / 居中对话框 / 顶部提示条**三种形态，
内置 9 种入场退场动画、拖拽关闭、点击遮罩关闭，默认以独立 `UIWindow` 承载（也可改为由指定控制器 present）。

- 部署目标：iOS 13+
- 语言：Swift（SPM 下使用 Swift 6 语言模式；CocoaPods 下按 podspec 的 `swift_version` 编译）
- 工具链：SPM 需要 **Swift 6.2+（Xcode 26+）**——`Package.swift` 声明的 `swift-tools-version: 6.2`
  是硬门槛，低于它的工具链无法解析这个包；CocoaPods 走 podspec 的 `swift_version = '5.0'`，
  Xcode 15+ 即可（源码用到 `@MainActor` 与 `MainActor.assumeIsolated`）
- 依赖：仅 UIKit

## 安装

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/CircularCyanStone/CooDialog.git", from: "0.0.1")
]
```

### CocoaPods

```ruby
pod 'CooDialog'
```

## 快速开始

```swift
import CooDialog

// 一行展示底部面板（预设：从底部滑入 / 内容自适应 / 可拖拽 / 延伸安全区）
SKDialog.bottom()
    .contentView(makePanelView())
    .show()
```

链式配置一个居中对话框：

```swift
let dialog = SKDialog.center()
    .contentView(makeCardView())
    .size(width: 280)                    // 只固定宽度，高度随内容
    .cornerRadius(16)
    .animation(.fadeScale, duration: 0.25, damping: 0.85)
    .dismissOnBackgroundTap(true)
    .onPresentAnimationDidFinish { inputField.becomeFirstResponder() }
    .show()

// 展示后仍可动态改尺寸（自带过渡动画）
dialog.updateContainerHeight(320)
```

`show()` 返回承载弹窗的控制器，它是**操控已展示弹窗的唯一入口**：动态改尺寸、追加完成回调、主动关闭都通过它。

## 常用配置

`SKDialog` 的配置方法都返回 `self`，可任意顺序链式书写；写同一份数据的方法会互相覆盖
（例如 `size(width:)` 与 `fixedWidth(_:)` 改的都是尺寸模式）。

| 方法 | 说明 |
| --- | --- |
| `position(_:)` | 停靠位置：`.center` / `.bottom` / `.top` |
| `presentationMode(_:)` | 显示载体：`.window`（默认，独立窗口、层级最高）/ `.viewController(vc)`。两者的实现差异只有"由谁来 present 弹窗"，其余完全共用 |
| `size(width:height:)` | 给几个方向就固定几个方向：都给 → 固定宽高；只给宽 → 宽度固定、高度随内容；都不给 → 完全自适应 |
| `contentAdaptive()` / `fixedWidth(_:)` / `fixedHeight(_:)` | 上一条的等价写法 |
| `margins(_:)` | 边距。顶部/底部弹窗：`top`/`bottom` 是贴边留白，`left`/`right` 是最小横向留白；居中弹窗：只用 `left`/`right` 限制最大宽度 |
| `extendToSafeArea(_:)` | 顶部/底部弹窗是否贴屏幕物理边缘（默认 true，内容需自行处理刘海 / Home Indicator 间距） |
| `animation(_:)` / `animation(_:duration:damping:velocity:)` | 动画类型与手感（时长、阻尼、初速度） |
| `dismissOnBackgroundTap(_:)` | 点击遮罩是否关闭（默认 true） |
| `enablePanGestureDismiss(_:)` | 是否支持拖拽关闭（仅顶部/底部，默认 true） |
| `maskColor(_:)` / `backgroundColor(_:)` / `cornerRadius(_:)` | 遮罩色、容器背景色、圆角 |
| `shadow(show:color:offset:radius:opacity:)` | 一次性设置阴影参数 |
| `windowLevel(_:)` | 自建 window 的层级（默认 `.alert + 1`） |
| `onPresentAnimationWillStart(_:)` / `onPresentAnimationDidFinish(_:)` | 入场动画开始前 / 正常结束后 |
| `onDismissAnimationWillStart(_:)` / `onDismissAnimationDidFinish(_:)` | 退场动画开始前 / 结束后 |
| `contentView(_:)` | 装载内容视图（四边贴合容器，"内容自适应"的尺寸正来源于此） |

内置动画：`.fadeScale`（默认）、`.slideFromBottom` / `.slideFromTop` / `.slideFromLeft` / `.slideFromRight`，
以及各自的 `WithFade` 版本（容器跟随遮罩一起淡入，观感更柔和），另有 `.custom(你的实现)`。

## 关闭弹窗

```swift
dialog.dismiss()                              // 播放退场动画后收尾
dialog.dismiss { print("已关闭") }             // 带关闭完成回调
dialog.addCompletionHandler { /* 追加回调，先注册的先执行 */ }
```

内容视图里无需持有弹窗引用，沿响应链反查即可：

```swift
@objc func closeTapped(_ sender: UIView) { sender.closeSKDialog() }

if view.isInSKDialog { ... }                 // 判断当前上下文是否在弹窗内
```

## 直接使用控制器（不经过构建器）

`SKDialogViewController` 是 `open` 的，可以继承后覆写生命周期方法：

```swift
final class MyDialog: SKDialogViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // containerView / backgroundView 都是公开属性，可继续定制外观
    }
}

var config = SKDialogConfig.centerDialog(width: 280)
config.dismissOnBackgroundTap = false
let dialog = MyDialog(config: config)
dialog.addContentView(makeCardView())
dialog.show()
```

`SKDialogConfig` 另有 `bottomSheet(height:cornerRadius:margins:presentationMode:)` 与 `topSheet(...)`，
用于只要一份配置的场景。

## 自定义动画

实现 `SKDialogAnimationProtocol`（入场 + 退场两个方法，**各调用一次 `completion`**），再通过 `.custom` 注入：

```swift
struct MyAnimation: SKDialogAnimationProtocol {
    func performPresentAnimation(backgroundView: UIView, containerView: UIView,
                                 config: SKDialogConfig, completion: @escaping () -> Void) {
        containerView.transform = CGAffineTransform(rotationAngle: .pi / 6).scaledBy(x: 0.6, y: 0.6)
        containerView.alpha = 0
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration, damping: config.springDamping,
            velocity: config.springVelocity,
            animations: {
                backgroundView.alpha = 1
                containerView.alpha = 1
                containerView.transform = .identity
            },
            completion: { _ in completion() }
        )
    }

    func performDismissAnimation(backgroundView: UIView, containerView: UIView,
                                 config: SKDialogConfig, completion: @escaping () -> Void) {
        SKDialogAnimationUtils.springAnimation(
            duration: config.animationDuration, damping: config.springDamping,
            velocity: config.springVelocity,
            animations: { backgroundView.alpha = 0; containerView.alpha = 0 },
            completion: { _ in completion() }
        )
    }
}
```

## 行为约定（值得先知道）

- **配置在展示前确定**：`dialog.config` 对库外只读，展示后要改外观或交互请新建弹窗（动态改尺寸除外）。
- **值语义**：配置按值交给控制器；同一个构建器展示两次，两个弹窗的配置互不干扰。
- **拖拽与滚动共存**：面板内容里有可滚动视图时，纵向滚动让位给内容；
  只有当列表已经滚到顶部（或底部）时，拖拽才驱动面板关闭。
- **展示的前置条件**（两种模式通用）：承接弹窗的那个控制器不能已经 present 别的控制器。
  `.viewController` 模式还要求它的视图已进入窗口层级；`.window` 模式的宿主是现造的，天然满足。
  不满足时 `show(completion:)` 会立即回调（不会静默失败），DEBUG 下会打印一行说明。
- **入场动画的时机**：视图真正出现在屏幕上时（`viewDidAppear`）播放，因此无论哪种模式、
  甚至宿主自己 `present` 控制器，入场都会被发起且只发起一次。
- **入场回调的时机**：`onPresentAnimationDidFinish` 只在入场动画**正常跑完**时触发；
  若弹窗在入场途中被关闭，它不会触发（此时"显示完成"已经不再成立）。
- **内容自适应需要内在尺寸**：`.contentAdaptive`（或只固定一个方向）时容器尺寸由内容的内在尺寸决定，
  内容若没有任何尺寸来源，容器会退化为 0 尺寸。

## 示例

`Examples/` 下有两个 Xcode 工程：`SPMExample` 演示 Swift Package 集成与常见用法；
`PodExample` 演示 CocoaPods 集成（需先 `pod install`）。

## License

MIT，见 [LICENSE](LICENSE)。
