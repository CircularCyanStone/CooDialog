//
//  SKDialogViewController.swift
//  TAIChat
//
//  Created by Assistant on 2024
//
// 文件功能描述：弹窗基础控制器，提供统一的弹窗显示和管理功能
// 类型功能描述：集成各个管理器，提供完整的弹窗解决方案，支持多种动画效果、手势交互和显示模式

import UIKit

/// 弹窗基础控制器
@MainActor
open class SKDialogViewController: UIViewController {
    
    // MARK: - Properties
    
    /// 弹窗配置
    public let config: SKDialogConfig
    
    /// 动画管理器
    private let animationManager: SKDialogAnimationManager
    
    /// 约束管理器
    private lazy var constraintManager: SKDialogConstraintManager = SKDialogConstraintManager(viewController: self)
    
    /// 手势处理器
    private lazy var gestureHandler: SKDialogGestureHandler = SKDialogGestureHandler(viewController: self)
    
    /// 动画状态管理器
    private lazy var animationStateManager: SKDialogAnimationStateManager = SKDialogAnimationStateManager(viewController: self)
    
    /// Window模式管理器
    private lazy var windowManager: SKDialogWindowManager = SKDialogWindowManager(viewController: self)
    
    /// 容器尺寸管理器
    private lazy var containerSizeManager: SKDialogContainerSizeManager = SKDialogContainerSizeManager(viewController: self)
    
    /// 容器视图
    public let containerView: UIView = UIView()
    
    /// 背景遮罩视图
    public let backgroundView: UIView = UIView()
    
    /// 容器宽度约束
    public var containerWidthConstraint: NSLayoutConstraint?
    
    /// 容器高度约束
    public var containerHeightConstraint: NSLayoutConstraint?
    
    /// 是否正在显示
    private var isPresenting = false
    
    /// 跟踪弹窗是否已完成显示动画
    private var isDialogPresented = false
    
    /// 弹窗完成回调
    /// 在弹窗关闭时执行的回调闭包
    public var completionHandler: (() -> Void)?
    
    /// 弹窗显示动画开始回调
    public var presentAnimationWillStartHandler: (() -> Void)?
    
    /// 弹窗显示动画完成回调
    public var presentAnimationDidFinishHandler: (() -> Void)?
    
    /// 弹窗关闭动画开始回调
    public var dismissAnimationWillStartHandler: (() -> Void)?
    
    /// 弹窗关闭动画完成回调
    public var dismissAnimationDidFinishHandler: (() -> Void)?
    
    // MARK: - Initialization
    
    public init(config: SKDialogConfig = SKDialogConfig()) {
        self.config = config
        self.animationManager = SKDialogAnimationManager(config: config)
        super.init(nibName: nil, bundle: nil)
        setupViewController()
    }
    
    required public init?(coder: NSCoder) {
        self.config = SKDialogConfig()
        self.animationManager = SKDialogAnimationManager(config: config)
        super.init(coder: coder)
        setupViewController()
    }
    
    // MARK: - Lifecycle
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        constraintManager.setupContainerConstraints()
        gestureHandler.setupGestures()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isPresenting {
            presentDialog()
        }
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // 在布局完成后，为自适应尺寸模式更新精确的滑动偏移量
        animationStateManager.updateSlideOffsetAfterLayout()
    }
    
    // MARK: - Setup
    
    private func setupViewController() {
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.clear
        
        // 背景遮罩
        backgroundView.backgroundColor = config.backgroundMaskColor
        backgroundView.alpha = 0
        view.addSubview(backgroundView)
        
        // 容器视图
        containerView.backgroundColor = config.containerBackgroundColor
        containerView.layer.cornerRadius = config.cornerRadius
        view.addSubview(containerView)
        
        // 阴影效果
        if config.showShadow {
            containerView.layer.masksToBounds = false
            containerView.layer.shadowColor = config.shadowColor.cgColor
            containerView.layer.shadowOffset = config.shadowOffset
            containerView.layer.shadowRadius = config.shadowRadius
            containerView.layer.shadowOpacity = config.shadowOpacity
        }
        
        // 根据动画类型预设容器视图的初始状态，避免闪现问题
        animationStateManager.setupInitialAnimationState()
    }
    

    

    

    

    
    // MARK: - Actions
    
    @objc private func backgroundTapped() {
        dismiss()
    }
    
    // MARK: - Drag Helper Methods
    
    private func calculateDragProgress(translation: CGPoint) -> CGFloat {
        let containerHeight = containerView.bounds.height
        guard containerHeight > 0 else { return 0 }
        
        let dragDistance: CGFloat
        switch config.position {
        case .bottom:
            dragDistance = max(0, translation.y) // 只允许向下拖拽
        case .top:
            dragDistance = max(0, -translation.y) // 只允许向上拖拽
        case .center:
            return 0 // 居中弹窗不支持拖拽
        }
        
        return min(1.0, dragDistance / containerHeight)
    }
    
    private func updateContainerForDrag(progress: CGFloat, translation: CGPoint) {
        let dampedProgress = progress * 0.8 // 添加阻尼效果
        
        switch config.position {
        case .bottom:
            let yTranslation = max(0, translation.y * dampedProgress)
            containerView.transform = CGAffineTransform(translationX: 0, y: yTranslation)
            
        case .top:
            let yTranslation = min(0, translation.y * dampedProgress)
            containerView.transform = CGAffineTransform(translationX: 0, y: yTranslation)
            
        case .center:
            break
        }
        
        // 更新背景透明度
        backgroundView.alpha = 1 - (progress * 0.5)
    }
    
    private func shouldDismissForDrag(translation: CGPoint, velocity: CGPoint) -> Bool {
        let containerHeight = containerView.bounds.height
        let dismissThreshold: CGFloat = containerHeight * 0.3 // 30%的高度阈值
        let velocityThreshold: CGFloat = 1000 // 速度阈值
        
        switch config.position {
        case .bottom:
            return translation.y > dismissThreshold || velocity.y > velocityThreshold
        case .top:
            return -translation.y > dismissThreshold || velocity.y < -velocityThreshold
        case .center:
            return false
        }
    }
    
    // MARK: - Public Methods
    
    /// 显示弹窗
    open func presentDialog() {
        guard !isPresenting else { return }
        isPresenting = true
        
        // 通知动画即将开始
        presentAnimationWillStartHandler?()
        
        animationManager.performPresentAnimation(
            backgroundView: backgroundView,
            containerView: containerView
        ) { [weak self] in
            // 标记弹窗已完成显示动画
            self?.isDialogPresented = true
            // 通知动画已完成
            self?.presentAnimationDidFinishHandler?()
            // 及时清理回调，避免内存泄漏
            self?.presentAnimationWillStartHandler = nil
            self?.presentAnimationDidFinishHandler = nil
        }
    }
    
    /// 消失弹窗
    /// - Parameter completion: 关闭完成的回调闭包，默认为nil
    open func dismissDialog(completion: (() -> Void)? = nil) {
        guard isPresenting else { 
            completion?()
            return 
        }
        isPresenting = false
        isDialogPresented = false // 重置显示状态
        
        // 通知动画即将开始
        dismissAnimationWillStartHandler?()
        
        animationManager.performDismissAnimation(
            backgroundView: backgroundView,
            containerView: containerView
        ) { [weak self] in
            // 通知动画已完成
            self?.dismissAnimationDidFinishHandler?()
            
            // 根据显示模式进行不同的处理
            switch self?.config.presentationMode {
            case .window:
                self?.hideCustomWindow()
                completion?()
            case .viewController(_):
                self?.dismiss(animated: false) {
                    self?.completionHandler?()
                    completion?()
                }
            case .none:
                completion?()
                break
            }
            
            // 及时清理所有回调，避免内存泄漏
            self?.completionHandler = nil
            self?.dismissAnimationWillStartHandler = nil
            self?.dismissAnimationDidFinishHandler = nil
        }
    }
    
    /// 简化的消失方法，兼容旧版本API
    open func dismiss() {
        dismissDialog()
    }
    
    /// 添加内容视图到容器
    open func addContentView(_ contentView: UIView) {
        containerView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    /// 添加完成回调到现有回调链中
    /// - Parameter additionalCompletion: 要添加的额外完成回调
    public func addCompletionHandler(_ additionalCompletion: @escaping () -> Void) {
        let originalCompletion = self.completionHandler
        self.completionHandler = {
            originalCompletion?()
            additionalCompletion()
        }
    }
    
    // MARK: - Container Size Update Methods
    
    /// 动态更新容器高度
    /// - Parameters:
    ///   - height: 新的高度值
    ///   - animated: 是否使用动画过渡，默认为 true
    /// - Note: 此方法会同步更新 config.sizeMode 以保持配置一致性
    public func updateContainerHeight(_ height: CGFloat, animated: Bool = true) {
        containerSizeManager.updateContainerHeight(height, animated: animated)
    }
    
    /// 动态更新容器宽度
     /// - Parameters:
     ///   - width: 新的宽度值
     ///   - animated: 是否使用动画过渡，默认为 true
     /// - Note: 此方法会同步更新 config.sizeMode 以保持配置一致性
     public func updateContainerWidth(_ width: CGFloat, animated: Bool = true) {
         containerSizeManager.updateContainerWidth(width, animated: animated)
     }
     
     /// 动态更新容器尺寸（宽度和高度）
     /// - Parameters:
     ///   - width: 新的宽度值
     ///   - height: 新的高度值
     ///   - animated: 是否使用动画过渡，默认为 true
     /// - Note: 此方法会同步更新 config.sizeMode 为 .fixed 模式
     public func updateContainerSize(width: CGFloat, height: CGFloat, animated: Bool = true) {
         containerSizeManager.updateContainerSize(CGSize(width: width, height: height), animated: animated)
     }
 }

// MARK: - Window Mode Support

extension SKDialogViewController {
    
    /// 使用自定义Window显示弹窗
    /// 这种方式可以在任何地方显示弹窗，不依赖于现有的视图控制器层级
    /// - Parameter completion: 显示完成后的回调
    public func showInWindow(completion: (() -> Void)? = nil) {
        self.completionHandler = completion
        
        // 使用Window管理器显示
        windowManager.showInWindow(completion: completion)
        
        // 显示弹窗
        show()
    }
    
    /// 显示弹窗的内部方法
    private func show() {
        // 根据显示模式进行不同的处理
        switch config.presentationMode {
        case .window:
            // Window模式已经在showInWindow中处理
            presentDialog()
        case .viewController(let viewController):
            // 使用指定的视图控制器显示
            viewController.present(self, animated: false) {
                self.presentDialog()
            }
        }
    }
    
    /// 隐藏自定义Window
    private func hideCustomWindow() {
        windowManager.hideCustomWindow()
    }
}
