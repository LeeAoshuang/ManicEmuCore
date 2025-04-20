//
//  GameControllerInputMapping.swift
//  DeltaCore
//
//  Created by Riley Testut on 7/22/17.
//  Copyright © 2017 Riley Testut. All rights reserved.
//

import Foundation

public struct GameControllerInputMapping: GameControllerInputMappingBase, Codable
{
    public var name: String?
    public var gameControllerInputType: GameControllerInputType
    
    public var supportedInputs: [Input] {
        return inputMappings.keys.map { SomeInput(stringValue: $0, intValue: nil, type: .controller(gameControllerInputType)) }
    }
    
    private var inputMappings: [String: SomeInput]
    
    public init(gameControllerInputType: GameControllerInputType)
    {
        self.gameControllerInputType = gameControllerInputType
        
        self.inputMappings = [:]
    }
    
    public func input(forControllerInput controllerInput: Input) -> Input?
    {
        precondition(controllerInput.type == .controller(gameControllerInputType), "controllerInput.type must match GameControllerInputMapping.gameControllerInputType")
        
        let input = inputMappings[controllerInput.stringValue]
        return input
    }
    
    public init(fileURL: URL) throws
    {
        let data = try Data(contentsOf: fileURL)
        
        let decoder = PropertyListDecoder()
        self = try decoder.decode(GameControllerInputMapping.self, from: data)
    }
    
    public func write(to url: URL) throws
    {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    public mutating func set(_ input: Input?, forControllerInput controllerInput: Input)
    {
        precondition(controllerInput.type == .controller(gameControllerInputType), "controllerInput.type must match GameControllerInputMapping.gameControllerInputType")
        
        if let input = input
        {
            inputMappings[controllerInput.stringValue] = SomeInput(input)
        }
        else
        {
            inputMappings[controllerInput.stringValue] = nil
        }
    }
}
