//
//  UIWindowScene+StageManager.swift
//  DeltaCore
//
//  Created by Riley Testut on 8/1/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import UIKit

@objc private protocol UIWindowSceneHidden: NSObjectProtocol
{
    var customWindowingEnabled: Bool { get }
}

@available(iOS 16, *)
extension UIWindowScene
{
    @_spi(Internal)
    public var isStageUtilsEnabled: Bool {
        guard self.responds(to: #selector(getter: UIWindowSceneHidden.customWindowingEnabled)) else { return false }
        
        let windowScene = unsafeBitCast(self, to: UIWindowSceneHidden.self)
        let isStageManagerEnabled = windowScene.customWindowingEnabled
        return isStageManagerEnabled
    }
}
