#
# Be sure to run `pod lib lint CooDialog.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'CooDialog'
  s.version          = '0.0.1'
  s.summary          = '基于 AutoLayout 的 iOS 弹窗组件：底部面板 / 居中对话框 / 顶部提示条，内置 9 种动画与拖拽关闭。'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
CooDialog 是一个基于 AutoLayout 的轻量弹窗组件（iOS 13+），特点：

- 三种形态：底部面板、居中对话框、顶部提示条
- 9 种内置入场/退场动画，并可通过 SKDialogAnimationProtocol 注入自定义动画
- 交互：点击遮罩关闭、拖拽关闭；内容里存在可滚动视图时，纵向滚动自动让位给内容
- 载体可选：默认由独立 UIWindow 承载（层级最高，不受宿主控制器层级限制），也可指定控制器 present
- 展示后支持动态改尺寸（带过渡动画），入场/退场各时机都有回调可插入业务逻辑
                       DESC

  s.homepage         = 'https://github.com/CircularCyanStone/CooDialog'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'CircularCyanStone' => '2963460@qq.com' }
  s.source           = { :git => 'https://github.com/CircularCyanStone/CooDialog.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  # 与 Package.swift 的 .iOS(.v13) 对齐：代码已使用 iOS 13 API
  # （UIWindow(windowScene:)、UIApplication.connectedScenes），
  # 且 MainActor.assumeIsolated 亦要求 iOS 13+。
  s.ios.deployment_target = '13.0'

  # Pod target 的编译模式。宿主调用侧的 actor 隔离检查强度由宿主自己的
  # SWIFT_VERSION 决定，与此值无关，故此处取 5.0 以兼容更广的工具链。
  # 若希望 Pod target 同样启用 Swift 6 严格并发检查，可改为 '6.0'（需 Xcode 16+）。
  s.swift_version = '5.0'

  s.source_files = 'Sources/CooDialog/**/*'
  
  # s.resource_bundles = {
  #   'CooDialog' => ['CooDialog/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
