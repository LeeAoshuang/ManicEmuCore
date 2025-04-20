//
//  ExtensibleEnum.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/9/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import Foundation

public protocol CustomEnum: Hashable, Codable, RawRepresentable where RawValue == String {}

public extension CustomEnum
{
    init(_ rawValue: String)
    {
        self.init(rawValue: rawValue)!
    }
    
    init(from decoder: Decoder) throws
    {
        let container = try decoder.singleValueContainer()
        
        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)!
    }
    
    func encode(to encoder: Encoder) throws
    {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

#if FRAMEWORK || STATIC_LIBRARY || SWIFT_PACKAGE

// Conform types to ExtensibleEnum to receive automatic Codable conformance + implementation.
extension GameType: CustomEnum {}
extension CheatType: CustomEnum {}
extension GameControllerInputType: CustomEnum {}

#else

public struct GameType: ExtensibleEnum
{
    public let rawValue: String
    
    public init(rawValue: String)
    {
        self.rawValue = rawValue
    }
}

public struct CheatType: ExtensibleEnum
{
    public let rawValue: String
    
    public init(rawValue: String)
    {
        self.rawValue = rawValue
    }
}

public struct GameControllerInputType: ExtensibleEnum
{
    public let rawValue: String
    
    public init(rawValue: String)
    {
        self.rawValue = rawValue
    }
}

#endif
