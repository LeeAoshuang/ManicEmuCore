//
//  GameController.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/3/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import ObjectiveC

private var gameControllerStateManagerKey = 0

//MARK: - GameControllerReceiver -
public protocol ControllerReceiverProtocol: class
{
    /// Equivalent to pressing a button, or moving an analog stick
    func gameController(_ gameController: GameController, didActivate input: Input, value: Double)
    
    /// Equivalent to releasing a button or an analog stick
    func gameController(_ gameController: GameController, didDeactivate input: Input)
}

//MARK: - GameController -
public protocol GameController: NSObjectProtocol
{
    var name: String { get }
        
    var playerIndex: Int? { get set }
    
    var inputType: GameControllerInputType { get }
    
    var defaultInputMapping: GameControllerInputMappingBase? { get }
}

public extension GameController
{
    private var stateManager: GameControllerStateUtils {
        var stateManager = objc_getAssociatedObject(self, &gameControllerStateManagerKey) as? GameControllerStateUtils
        
        if stateManager == nil
        {
            stateManager = GameControllerStateUtils(gameController: self)
            objc_setAssociatedObject(self, &gameControllerStateManagerKey, stateManager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        return stateManager!
    }
    
    var receivers: [ControllerReceiverProtocol] {
        return self.stateManager.receivers
    }
    
    var activatedInputs: [SomeInput: Double] {
        return self.stateManager.activatedInputs
    }
    
    var continueInputs: [SomeInput: Double] {
        return self.stateManager.continueInputs
    }
    
    func addReceiver(_ receiver: ControllerReceiverProtocol)
    {
        addReceiver(receiver, inputMapping: defaultInputMapping)
    }
    
    func addReceiver(_ receiver: ControllerReceiverProtocol, inputMapping: GameControllerInputMappingBase?)
    {
        stateManager.addReceiver(receiver, inputMapping: inputMapping)
    }
    
    func removeReceiver(_ receiver: ControllerReceiverProtocol)
    {
        stateManager.removeReceiver(receiver)
    }
    
    func activate(_ input: Input, value: Double = 1.0)
    {
        stateManager.activate(input, value: value)
    }
    
    func deactivate(_ input: Input)
    {
        stateManager.deactivate(input)
    }
    
    func sustain(_ input: Input, value: Double = 1.0)
    {
        stateManager.makeContinue(input, value: value)
    }
    
    func unsustain(_ input: Input)
    {
        stateManager.stopContinue(input)
    }
    
    func inputMapping(for receiver: ControllerReceiverProtocol) -> GameControllerInputMappingBase?
    {
        return stateManager.inputMapping(for: receiver)
    }
    
    func mappedInput(for input: Input, receiver: ControllerReceiverProtocol) -> Input?
    {
        return stateManager.mappedInput(for: input, receiver: receiver)
    }
}

public func ==(lhs: GameController?, rhs: GameController?) -> Bool
{
    switch (lhs, rhs)
    {
    case (nil, nil): return true
    case (_?, nil): return false
    case (nil, _?): return false
    case (let lhs?, let rhs?): return lhs.isEqual(rhs)
    }
}

public func !=(lhs: GameController?, rhs: GameController?) -> Bool
{
    return !(lhs == rhs)
}

public func ~=(pattern: GameController?, value: GameController?) -> Bool
{
    return pattern == value
}
