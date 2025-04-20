//
//  DeltaCoreProtocol.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/29/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import AVFoundation

public protocol ManicEmuCoreProtocol: CustomStringConvertible
{
    /* General */
    var name: String { get }
    var identifier: String { get }
    var version: String? { get }
    
    var gameType: GameType { get }
    var gameSaveExtension: String { get }
    
    // Should be associated type, but Swift type system makes this difficult, so ¯\_(ツ)_/¯
    var gameInputType: Input.Type { get }
    
    /* Rendering */
    var audioFormat: AVAudioFormat { get }
    var videoFormat: VideoFormat { get }
    
    /* Cheats */
    var supportCheatFormats: Set<CheatFormat> { get }
    
    /* Emulation */
    var emulatorConnector: EmulatorBase { get }
    
    var resourceBundle: Bundle { get }
}

public extension ManicEmuCoreProtocol
{
    var version: String? {
        return nil
    }
    
    var resourceBundle: Bundle {
        #if FRAMEWORK
        let bundle = Bundle(for: type(of: self.emulatorBridge))
        #elseif STATIC_LIBRARY || SWIFT_PACKAGE
        let bundle: Bundle
        
        if let library = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first {
            bundle = Bundle(url: URL(fileURLWithPath: library + "/System.bundle"))!
        }
        else {
            bundle = Bundle(for: type(of: emulatorConnector))
        }
        #else
        let bundle = Bundle.main
        #endif
        
        return bundle
    }
    var directoryURL: URL {
        let directoryURL = ManicEmu.coresDirectoryURL.appendingPathComponent(name, isDirectory: true)
        
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        
        return directoryURL
    }
    
}

public extension ManicEmuCoreProtocol
{
    var description: String {
        return "\(name) (\(identifier))"
    }
}

public func ==(lhs: ManicEmuCoreProtocol?, rhs: ManicEmuCoreProtocol?) -> Bool
{
    return lhs?.identifier == rhs?.identifier
}

public func !=(lhs: ManicEmuCoreProtocol?, rhs: ManicEmuCoreProtocol?) -> Bool
{
    return !(lhs == rhs)
}

public func ~=(lhs: ManicEmuCoreProtocol?, rhs: ManicEmuCoreProtocol?) -> Bool
{
    return lhs == rhs
}
