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
    var castButtonItem: UIBarButtonItem { get }
}

extension CastButtonDelegate where Self: UIViewController {
    var castButtonItem: UIBarButtonItem {
       return ChromeCastManager.shared.castButtonItem
    }
}

extension CastButtonDelegate where Self: UIPageViewController {
    var castButtonItem: UIBarButtonItem {
        return ChromeCastManager.shared.castButtonItem
    }
}

extension CastButtonDelegate where Self: UITabBarController {
    var castButtonItem: UIBarButtonItem {
        return ChromeCastManager.shared.castButtonItem
    }
}
