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
        let castButton = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        castButton.tintColor = OEXStyles.shared().primaryBaseColor()
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}

extension CastButtonDelegate where Self: UIPageViewController {
    var castButtonItem: UIBarButtonItem {
        let castButton = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        castButton.tintColor = OEXStyles.shared().primaryBaseColor()
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}

extension CastButtonDelegate where Self: UITabBarController {
    var castButtonItem: UIBarButtonItem {
        let castButton = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        castButton.tintColor = OEXStyles.shared().primaryBaseColor()
        let castButtonItem =  UIBarButtonItem(customView: castButton)
        return castButtonItem
    }
}
