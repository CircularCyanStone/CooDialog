# CooDialog

iOS 弹窗组件：一个基于 AutoLayout 的轻量弹窗，提供**底部面板 / 居中对话框 / 顶部提示条**三种形态，
内置 9 种入场退场动画、拖拽关闭、点击遮罩关闭。展示载体三选一：独立 `UIWindow`（默认、层级最高）/
由指定控制器 `present` / 挂到指定视图上（不产生任何 `present` 关系）。

- 部署目标：iOS 13+
- 语言：Swift（SPM 下使用 Swift 6 语言模式；CocoaPods 下按 podspec 的 `swift_version` 编译）
- 工具链：SPM 需要 **Xcode 16+**（`Package.swift` 声明的 `swift-tools-version: 6.0`
  是硬门槛，低于它的工具链无法解析这个包）；CocoaPods 走 podspec 的 `swift_version = '5.0'`，
  Xcode 15+ 即可（源码用到 `@MainActor` 与 `MainActor.assumeIsolated`）
- 依赖：仅 UIKit

## 安装

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/CircularCyanStone/CooDialog.git", from: "0.0.2")
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
CooDialog.bottom()
    .contentView(makePanelView())
    .show()
```

链式配置一个居中对话框：

```swift
let dialog = CooDialog.center()
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

`CooDialog` 的配置方法都返回 `self`，可任意顺序链式书写；写同一份数据的方法会互相覆盖
（例如 `size(width:)` 与 `fixedWidth(_:)` 改的都是尺寸模式）。

| 方法 | 说明 |
| --- | --- |
| `position(_:)` | 停靠位置：`.center` / `.bottom` / `.top` |
| `presentationMode(_:)` / `inline(in:)` | 显示载体：`.window`（默认，独立窗口、层级最高）/ `.viewController(vc)`（由指定控制器 present）/ `.inline(view)`（挂到指定视图上，不产生任何 present 关系）。三者的实现差异只有"由谁承载弹窗的视图"，其余完全共用 |
| `size(width:height:)` | 给几个方向就固定几个方向：都给 → 固定宽高；只给宽 → 宽度固定、高度随内容；都不给 → 完全自适应 |
| `contentAdaptive()` / `fixedWidth(_:)` / `fixedHeight(_:)` | 上一条的等价写法 |
| `margins(_:)` | 边距。顶部/底部弹窗：`top`/`bottom` 是贴边留白，`left`/`right` 是最小横向留白；居中弹窗：只用 `left`/`right` 限制最大宽度 |
| `extendToSafeArea(_:)` | 顶部/底部弹窗是否贴屏幕物理边缘（默认 true，内容需自行处理刘海 / Home Indicator 间距） |
| `animation(_:)` / `animation(_:duration:damping:velocity:)` | 动画类型与手感（时长、阻尼、初速度） |
| `dismissOnBackgroundTap(_:)` | 点击遮罩是否关闭（默认 true） |
| `enablePanGestureDismiss(_:)` | 是否支持拖拽关闭（仅顶部/底部，默认 true） |
| `maskColor(_:)` / `backgroundColor(_:)` / `cornerRadius(_:)` | 遮罩色、容器背景色、圆角 |
| `shadow(show:color:offset:radius:opacity:)` | 一次性设置阴影参数 |
| `windowLevel(_:)` | 自建 window 的层级（默认 `.alert + 1`；仅 `.window` 载体有效） |
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

dialog.isPresenting                           // 当前是否还开着：挂到宿主上即为 true，收尾完成变 false
```

内容视图里无需持有弹窗引用，沿响应链反查即可：

```swift
@objc func closeTapped(_ sender: UIView) { sender.closeCooDialog() }

if view.isInCooDialog { ... }                 // 判断当前上下文是否在弹窗内
```

## 挂到任意视图（inline）

不想走模态、也不想要独立窗口时，把弹窗挂到页面里的某一块视图上——这块视图就是它的"画布"：

```swift
CooDialog.center()
    .inline(in: previewArea)              // 等价于 .presentationMode(.inline(previewArea))
    .contentView(makeCard())
    .size(width: 240)
    .show()
```

- **遮罩铺满这块画布**，不会盖住画布之外的界面；容器超出画布的部分会被裁剪，
  因此 `slideFromBottom` 这类动画是"从画布底边滑入"，而不是从屏幕底边
- **不产生任何 `present` 关系**：不需要有一个"合适"的控制器，也不受"它是否已 present 别的控制器"约束；
  关闭后画布自动恢复原样（视图摘除、父子关系解除、相关约束清理）
- 挂载时会尝试挂进画布所在的控制器（`addChild`）：`closeCooDialog()` / `isInCooDialog` 的响应链查找
  与外观回调照常生效；画布不在任何控制器下时跳过这一步，展示照常
- 其余能力与另外两种载体完全一致：四种动画回调、动态改尺寸、点击遮罩关闭、拖拽关闭、`isPresenting`；
  内容尺寸的上限以画布为准（而不是屏幕）

画布尺寸变化（旋转、约束调整）时弹窗跟着变——贴合的是约束，而不是上屏那一刻的 frame。

想在**当前显示的页面上**直接弹（不经过 `present`、也不建 window）时，把画布传成页面自己的视图即可：

```swift
CooDialog.bottom()
    .contentView(panel)
    .inline(in: view)                    // 整页为画布
    .show()
```

它与 `.window` / `.viewController` 的观感几乎一致（遮罩铺满整页、底部面板贴屏幕底边），
区别只在于没有任何呈现关系：宿主控制器不必"空闲"，弹窗也不会随它一起被系统销毁。

两条容易被忽略的细节：

- **安全区按物理屏幕算**：`extendToSafeArea = false` 时容器贴的是 `safeAreaLayoutGuide`，
  它的 inset 由窗口传播而来——画布完全落在安全区内时等同于贴画布边；画布本身延伸进刘海 /
  Home Indicator 区域时，面板会避开那块系统区域（`extendToSafeArea = true` 则始终贴物理边）。
- **内容比画布大时**：横向会被位置约束压回画布内（内容自己的固定宽度让位），
  纵向则允许溢出、超出部分被画布裁掉——这是"内容自适应只保证容器有尺寸来源、
  不保证内容一定放得下"这条既有取舍在画布上的表现。要限制它就显式给尺寸：
  `.fixed(width:height:)`、`updateContainerSize(_:_:)`（带过渡动画），或让内容自身可压缩 / 可滚动。
  挂载时会检查一次并在 DEBUG 下打印提示，不必自己去猜。

## 直接使用控制器（不经过构建器）

`CooDialogViewController` 是 `open` 的，可以继承后覆写生命周期方法：

```swift
final class MyDialog: CooDialogViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // containerView / backgroundView 都是公开属性，可继续定制外观
    }
}

var config = CooDialogConfig.centerDialog(width: 280)
config.dismissOnBackgroundTap = false
let dialog = MyDialog(config: config)
dialog.addContentView(makeCardView())
dialog.show()
```

`CooDialogConfig` 另有 `bottomSheet(height:cornerRadius:margins:presentationMode:)` 与 `topSheet(...)`，
用于只要一份配置的场景。

## 自定义动画

实现 `CooDialogAnimationProtocol`（入场 + 退场两个方法，**各调用一次 `completion`**），再通过 `.custom` 注入：

```swift
struct MyAnimation: CooDialogAnimationProtocol {
    func performPresentAnimation(backgroundView: UIView, containerView: UIView,
                                 config: CooDialogConfig, completion: @escaping () -> Void) {
        containerView.transform = CGAffineTransform(rotationAngle: .pi / 6).scaledBy(x: 0.6, y: 0.6)
        containerView.alpha = 0
        CooDialogAnimationUtils.springAnimation(
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
                                 config: CooDialogConfig, completion: @escaping () -> Void) {
        CooDialogAnimationUtils.springAnimation(
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
- **展示的前置条件**（present 的两条路径）：承接弹窗的那个控制器不能已经 present 别的控制器。
  `.viewController` 还要求它的视图已进入窗口层级；`.window` 的宿主是现造的，天然满足。
  不满足时 `show(completion:)` 会立即回调（不会静默失败），DEBUG 下会打印一行说明。
  `.inline` 不走 present，因此没有这条前置条件——画布尚未上屏或尺寸为 0 时只在 DEBUG 提示，不会阻断展示。
- **入场动画的时机**：present 的两条路径在视图真正出现在屏幕上时播放（`viewDidAppear`），
  因此无论走哪条路径、甚至宿主自己 `present` 控制器，入场都会被发起且只发起一次；
  `.inline` 的上屏不是 UIKit 的转场事件，由 `show()` 在挂载完成时当场发起（同样只发起一次）。
- **入场回调的时机**：`onPresentAnimationDidFinish` 只在入场动画**正常跑完**时触发；
  若弹窗在入场途中被关闭，它不会触发（此时"显示完成"已经不再成立）。
- **内容自适应需要内在尺寸**：`.contentAdaptive`（或只固定一个方向）时容器尺寸由内容的内在尺寸决定，
  内容若没有任何尺寸来源，容器会退化为 0 尺寸。
- **关闭可以早于上屏**：`show()` 之后、入场动画发起之前调用 `dismiss()` 同样有效——
  它会走完整的关闭收尾（摘掉载体关系：present 关系或 inline 挂载、回收自建 window、触发各项回调），
  此后到达的 `viewDidAppear` 也不会再把弹窗拉起来。任何时候都可以用
  `CooDialogViewController.isPresenting` 判断弹窗是否还开着。
- **键盘不归库管**：弹窗不会自动避让键盘。内容里有输入框时由宿主自行处理
  （监听键盘通知调整内容约束，或用 `dialog.updateContainerHeight(_:)` 让容器跟着键盘长高）。

## 示例

`Examples/` 下有两个 Xcode 工程：

- **`SPMExample`**：演示 Swift Package 集成与常见用法，直接打开即可运行
  （工程用 `XCLocalSwiftPackageReference` 指向仓库根目录，不需要网络）。
  案例按展示模式分组：预设与样式、九种动画、运行时改尺寸与回调、手势交互、宿主模式、inline 模式。
- **`PodExample`**：演示 CocoaPods 集成。在 `Examples/PodExample` 目录下执行 `pod install`
  （Podfile 已入库，用 `:path => '../../'` 指向本地源码），然后打开 `PodExample.xcworkspace`
  （注意不是 `.xcodeproj`），并按工程内 `ViewController.swift` 顶部的说明加上 `import CooDialog`。

## License

MIT，见 [LICENSE](LICENSE)。
