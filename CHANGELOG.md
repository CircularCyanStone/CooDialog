# Changelog

本文件记录 CooDialog 的对外变更，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.0.3] - 2026-10-13

### 新增

- **第三种展示载体 `.inline(UIView)`**：把弹窗挂到指定视图上，全程不产生 `present` 关系。
  传入的视图就是弹窗的"画布"——遮罩铺满它，容器的定位与滑动动画以它为基准，超出它的部分会被裁剪。

  ```swift
  CooDialog.center()
      .inline(in: previewArea)          // 等价于 .presentationMode(.inline(previewArea))
      .contentView(makeCard())
      .show()
  ```

  适合"弹窗只属于页面里的某一块区域"（局部预览、卡片内弹层），以及手上只有视图、
  拿不到合适控制器的时机。挂载时会尝试挂进宿主所在的控制器（`addChild`），
  因此 `closeCooDialog()` / `isInCooDialog` 的响应链查找与外观回调照常生效。

- 动画、约束、手势、动态改尺寸、四个动画回调、`isPresenting` 在 `.inline` 下与另外两种载体
  完全一致：三者只在"由谁承载弹窗的视图"上不同，上屏之后共用同一条链路。
  唯一按载体取值的配置是内容尺寸上限——`.inline` 下以宿主视图的 bounds 为准（而不是屏幕）。

### 破坏性变更（对宿主）

- `CooDialogPresentationMode` 新增 `.inline(UIView)` case。对宿主**源码兼容**，
  但若宿主对该枚举写了穷尽 `switch`（没有 `default`），需要补上这个分支才能编译通过。

### 备注

- `.inline` 的遮罩只覆盖传入的那块视图，不会盖住整屏；弹窗也不会随页面生命周期自动收尾，
  仍然需要显式 `dismiss()`。

## [0.0.2] - 2026-10-13

**破坏性变更**：库内所有 `SKDialog` 前缀统一改为 `CooDialog`，旧名不保留兼容别名，
升级后需要改名（把 `SKDialog` 全局替换为 `CooDialog` 即可）。

### 变更

- **对外类型与成员全部改名**：

  | 旧名 | 新名 |
  | --- | --- |
  | `SKDialog` | `CooDialog` |
  | `SKDialogViewController` | `CooDialogViewController` |
  | `SKDialogConfig` | `CooDialogConfig` |
  | `SKDialogPosition` | `CooDialogPosition` |
  | `SKDialogSizeMode` | `CooDialogSizeMode` |
  | `SKDialogPresentationMode` | `CooDialogPresentationMode` |
  | `SKDialogAnimationType` | `CooDialogAnimationType` |
  | `SKDialogAnimationProtocol` | `CooDialogAnimationProtocol` |
  | `SKDialogAnimationUtils` | `CooDialogAnimationUtils` |
  | `UIView.closeSKDialog()` | `UIView.closeCooDialog()` |
  | `UIView.isInSKDialog` | `UIView.isInCooDialog` |

  内部类型同步改名（`SKDialogAnimationManager` / `SKDialogAnimationStateManager` /
  `SKDialogConstraintManager` / `SKDialogContainerSizeManager` / `SKDialogGestureHandler` /
  `SKDialogWindowManager`），源码文件名一并改为 `CooDialog*.swift`。
- README、podspec 的 description 与两个示例工程（SPMExample / PodExample）里的名称同步更新。

### 迁移

1. 宿主工程里把 `SKDialog` 全局替换为 `CooDialog`。
2. 接入方式不变：CocoaPods 仍是 `pod 'CooDialog'`，SPM 仍是从本仓库按版本号拉取。
3. 除命名外没有行为变更：链式配置、`show()`、`dismiss()` 与各回调时机与 0.0.1 一致。

## [0.0.1] - 2026-10-08

首个公开版本：底部面板 / 居中对话框 / 顶部提示条三种形态，9 种内置入场退场动画，
默认以独立 `UIWindow` 承载（也可改为由指定控制器 present）。

### 修复

- **首次上屏前调用 `dismiss()` 会被整体跳过**：`show()` 成功之后、`viewDidAppear` 之前
  调用的关闭现在会正常收尾——摘掉 present 关系、回收自建 window，并照常触发两个动画回调
  与"关闭完成"回调。修复前这段时间里的关闭完全无效（弹窗留在屏幕上、`presentingViewController`
  不摘除），`.window` 模式下自建 window 还会与控制器互相强引用而一起泄漏，随后到达的
  `viewDidAppear` 更会把已经要求关闭的弹窗重新拉起来。
- **关闭之后迟到的 `viewDidAppear` 不再"复活"弹窗**：展示状态收敛为状态机
  （`.idle` / `.presented` / `.presenting` / `.finished`），已收尾的弹窗不会再发起入场。
- **`cancelCurrentGestures()` 不再打开配置禁用的手势**：现在只取消"当前启用中"的手势，
  居中弹窗与 `enablePanGestureDismiss(false)` / `dismissOnBackgroundTap(false)` 关掉的交互
  保持禁用状态（修复前一次复位会把它们全部打开，用户随后能按配置明确禁止的方式关闭弹窗）。
- **CocoaPods 集成路径此前编译不通过**：`CooDialogAnimationManager.makeAnimation()`
  补上显式 `@MainActor`。在 podspec 的 `swift_version = '5.0'` 下，该方法会被视为
  nonisolated，构造主 actor 隔离的动画实现时报
  "call to main actor-isolated initializer in a synchronous nonisolated context"；
  Swift 6 模式的隔离推断恰好能通过，因此这个问题只在 pod 侧暴露。

### 新增

- `CooDialogViewController.isPresenting`：公开的展示状态查询，从弹窗挂到宿主上那一刻起为 true，
  直到关闭收尾完成。宿主不必再自己维护"这个弹窗还开着吗"的标记。
- 同一个弹窗实例支持关闭后再次展示：`show()` 会把上一轮的状态清回起点
  （修复前第二轮会被上一轮的状态挡住，入场动画不再发起）。

### 变更

- 底部预设圆角统一为 16：`CooDialog.bottom()` 此前未显式设置圆角（走配置默认的 12），
  与 `CooDialogConfig.bottomSheet()` 的 16 不一致；现在两个入口观感一致。
- SPM 工具链门槛由 `swift-tools-version: 6.2` 降到 `6.0`：Xcode 16 及以上即可集成
  （此前要求 Xcode 26+）。源码未使用 6.2 专属特性，全部测试在该门槛下通过。
- `Examples/PodExample` 补上 `Podfile`，README 的 CocoaPods 示例说明与仓库内容对齐。
- README 补充键盘避让的说明（库不接管键盘，由宿主自行处理）。

### 文档

- 新增本 CHANGELOG 与 CI 工作流（`.github/workflows/ci.yml`）。
