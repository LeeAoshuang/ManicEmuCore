//
//  ControllerInputView.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/17/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import UIKit

private var isKeyboardWindowKey: UInt8 = 0

internal extension UIWindow
{
    // Hacky, but allows us to reliably detect keyboard window without private APIs.
    var isKeyboardWindow: Bool {
        get { objc_getAssociatedObject(self, &isKeyboardWindowKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &isKeyboardWindowKey, newValue as NSNumber, objc_AssociationPolicy.OBJC_ASSOCIATION_COPY) }
    }
}

class ControllerInputView: UIInputView
{
    let controllerView: ControllerView
    
    private var previousBounds: CGRect?
    
    private var ratioConstraint: NSLayoutConstraint? {
        didSet {
            oldValue?.isActive = false
        }
    }
    
    init(frame: CGRect)
    {
        self.controllerView = ControllerView(frame: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        self.controllerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.controllerView.isControllerInputView = true
        
        super.init(frame: frame, inputViewStyle: .keyboard)
        
        addSubview(controllerView)
        
        translatesAutoresizingMaskIntoConstraints = false
        allowsSelfSizing = true
        
        setNeedsUpdateConstraints()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() 
    {
        super.didMoveToWindow()
        
        guard let window = self.window else { return }
        window.isKeyboardWindow = true
        
        if self.bounds.width == window.bounds.width
        {
            // Keyboard already matches window width, but other traits might have changed so update controller skin just to be safe.
            // Limit this to when widths match to avoid duplicate calls to updateControllerSkin() via layoutSubviews().
            self.controllerView.updateSkin()
        }
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        guard
            let controllerSkin = controllerView.controllerSkin,
            let traits = controllerView.controllerSkinTraits,
            let aspectRatio = controllerSkin.aspectRatio(for: traits)
        else { return }
        
        if self.bounds != previousBounds
        {
            controllerView.updateSkin()
        }
        
        previousBounds = self.bounds
        
        let multiplier = aspectRatio.height / aspectRatio.width
        guard ratioConstraint?.multiplier != multiplier else { return }
        
        ratioConstraint = self.heightAnchor.constraint(equalTo: self.widthAnchor, multiplier: multiplier)
        ratioConstraint?.isActive = true
    }
}
