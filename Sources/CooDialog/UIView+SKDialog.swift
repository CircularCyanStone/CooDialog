//
//  UIView+SKDialog.swift
//  TAIChat
//
//  Created by Assistant on 2024
//

import Foundation
import UIKit

/// UIView扩展，提供SKDialog弹窗相关的便捷方法
/// 支持通过响应链和视图层级查找并关闭弹窗，提供按钮和手势的快捷操作

// MARK: - UIView Extension for SKDialog

extension UIView {
    
    /// 关闭当前视图所在的SKDialog弹窗
    /// 通过响应链查找SKDialogViewController并关闭
    @objc public func closeSKDialog() {
        var responder: UIResponder? = self
        while responder != nil {
            if let dialogVC = responder as? SKDialogViewController {
                dialogVC.dismissDialog()
                return
            }
            responder = responder?.next
        }
        
        print("SKDialog Warning: No SKDialogViewController found in responder chain")
    }
    
    /// 通过响应链查找SKDialogViewController
    private func findSKDialogViewController() -> SKDialogViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let dialogVC = responder as? SKDialogViewController {
                return dialogVC
            }
            responder = responder?.next
        }
        return nil
    }
}

// MARK: - Convenience Methods

extension UIView {
    
    /// 检查当前视图是否在SKDialog中
    public var isInSKDialog: Bool {
        return findSKDialogViewController() != nil
    }
}
