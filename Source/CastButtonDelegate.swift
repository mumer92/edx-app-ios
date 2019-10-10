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
    var castButton: GCKUICastButton { get set }
    func addCastButtonToNavigationBar()
}

//extension CastButtonDelegate where Self: UIViewController {
//    var castButton: GCKUICastButton {
//        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
//        button.tintColor = .gray
//        return button
//    }
//}


