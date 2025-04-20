//
//  AudioRendering.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/29/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import Foundation

@objc(MANCAudioRendering)
public protocol AudioRenderProtocol: NSObjectProtocol
{
    var audioBuffer: RingingBuffer { get }
}
