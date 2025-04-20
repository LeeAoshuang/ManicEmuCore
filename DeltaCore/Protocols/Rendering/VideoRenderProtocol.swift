//
//  VideoRendering.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/29/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import Foundation
import CoreGraphics

@objc(MANCVideoRenderProtocol)
public protocol VideoRenderProtocol: NSObjectProtocol {
    var videoBuffer: UnsafeMutablePointer<UInt8>? { get }
    
    var viewport: CGRect { get set }
    
    func prepare()
    func processFrame()
}
