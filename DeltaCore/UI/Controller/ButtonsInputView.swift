//
//  ButtonsInputView.swift
//  DeltaCore
//
//  Created by Riley Testut on 8/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class ButtonsInputView: UIView
{
    var isHapticEnabled = true
    //添加震感的样式
    var hapticFeedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = .soft {
        didSet {
            feedbackGenerator = UIImpactFeedbackGenerator(style: hapticFeedbackStyle)
        }
    }
    
    var items: [ControllerSkin.Item]?
    
    var activateHandler: ((Set<SomeInput>) -> Void)?
    var deactivateHandler: ((Set<SomeInput>) -> Void)?
    
    var image: UIImage? {
        get {
            return imageView.image
        }
        set {
            imageView.image = newValue
        }
    }
    
    private let imageView = UIImageView(frame: .zero)
    
    private var feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    
    private var touchMappingDic: [UITouch: Set<SomeInput>] = [:]
    private var preTouchInputs = Set<SomeInput>()
    private var touchInputs: Set<SomeInput> {
        return self.touchMappingDic.values.reduce(Set<SomeInput>(), { $0.union($1) })
    }
    
    override var intrinsicContentSize: CGSize {
        return imageView.intrinsicContentSize
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        isMultipleTouchEnabled = true
        
        feedbackGenerator.prepare()
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        NSLayoutConstraint.activate([imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     imageView.topAnchor.constraint(equalTo: topAnchor),
                                     imageView.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            touchMappingDic[touch] = []
        }
        
        updateInputs(for: touches)
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        updateInputs(for: touches)
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            touchMappingDic[touch] = nil
        }
        
        updateInputs(for: touches)
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        return touchesEnded(touches, with: event)
    }
    
    func inputs(at point: CGPoint) -> [Input]?
    {
        guard let items = self.items else { return nil }
        
        var point = point
        point.x /= self.bounds.width
        point.y /= self.bounds.height
        
        var inputs: [Input] = []
        
        for item in items
        {
            guard item.extendedFrame.contains(point) else { continue }
            
            switch item.inputs
            {
            // Don't return inputs for thumbsticks or touch screens since they're handled separately.
            case .directional where item.kind == .thumbstick: break
            case .touch: break
                
            case .standard(let itemInputs):
                inputs.append(contentsOf: itemInputs)
            
            case let .directional(up, down, left, right):

                let divisor: CGFloat
                if case .thumbstick = item.kind
                {
                    divisor = 2.0
                }
                else
                {
                    divisor = 3.0
                }
                
                let topRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.frame.minY - item.extendedFrame.minY))
                let bottomRect = CGRect(x: item.extendedFrame.minX, y: item.frame.maxY - item.frame.height / divisor, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.extendedFrame.maxY - item.frame.maxY))
                let leftRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.frame.minX - item.extendedFrame.minX), height: item.extendedFrame.height)
                let rightRect = CGRect(x: item.frame.maxX - item.frame.width / divisor, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.extendedFrame.maxX - item.frame.maxX), height: item.extendedFrame.height)
                
                if topRect.contains(point)
                {
                    inputs.append(up)
                }
                
                if bottomRect.contains(point)
                {
                    inputs.append(down)
                }
                
                if leftRect.contains(point)
                {
                    inputs.append(left)
                }
                
                if rightRect.contains(point)
                {
                    inputs.append(right)
                }
            }
        }
        
        return inputs
    }
    
    func updateInputs(for touches: Set<UITouch>)
    {
        // Don't add the touches if it has been removed in touchesEnded:/touchesCancelled:
        for touch in touches where touchMappingDic[touch] != nil
        {
            guard touch.view == self else { continue }
            
            let point = touch.location(in: self)
            let inputs = Set((inputs(at: point) ?? []).map { SomeInput($0) })
            
            let menuInput = SomeInput(stringValue: StandardGameControllerInput.menu.stringValue, intValue: nil, type: .controller(.controllerSkin))
            if inputs.contains(menuInput)
            {
                // If the menu button is located at this position, ignore all other inputs that might be overlapping.
                touchMappingDic[touch] = [menuInput]
            }
            else
            {
                touchMappingDic[touch] = Set(inputs)
            }
        }
        
        let activatedInputs = touchInputs.subtracting(preTouchInputs)
        let deactivatedInputs = preTouchInputs.subtracting(touchInputs)
        
        // We must update previousTouchInputs *before* calling activate() and deactivate().
        // Otherwise, race conditions that cause duplicate touches from activate() or deactivate() calls can result in various bugs.
        preTouchInputs = touchInputs
        
        if !activatedInputs.isEmpty
        {
            activateHandler?(activatedInputs)
            
            if isHapticEnabled
            {
                switch UIDevice.current.feedbackLevel
                {
                case .feedbackGenerator: feedbackGenerator.impactOccurred()
                case .basic, .unsupported: UIDevice.current.vibrate()
                }
            }
        }
        
        if !deactivatedInputs.isEmpty
        {
            deactivateHandler?(deactivatedInputs)
        }
    }
}
