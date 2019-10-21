//
//  CastButtonDelegate.swift
//  edX
//
//  Created by Muhammad Umer on 10/7/19.
//  Copyright © 2019 edX. All rights reserved.
//

import Foundation
import GoogleCast

protocol CastButtonDelegate {
    var castButton: GCKUICastButton { get }
    var castButtonItem: UIBarButtonItem { get }
}

extension CastButtonDelegate where Self: UIViewController {
    var castButton: GCKUICastButton {
        return ChromeCastManager.shared.castButton
    }
    
    var castButtonItem: UIBarButtonItem {
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}

extension CastButtonDelegate where Self: UIPageViewController {
    var castButton: GCKUICastButton {
        return ChromeCastManager.shared.castButton
    }
    
    var castButtonItem: UIBarButtonItem {
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}

extension CastButtonDelegate where Self: UITabBarController {
    var castButton: GCKUICastButton {
        return ChromeCastManager.shared.castButton
    }
    
    var castButtonItem: UIBarButtonItem {
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}
