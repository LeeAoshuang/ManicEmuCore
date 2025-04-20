//
//  ControllerDebugView.swift
//  DeltaCore
//
//  Created by Riley Testut on 12/20/15.
//  Copyright © 2015 Riley Testut. All rights reserved.
//

import UIKit
import Foundation

internal class InputDebugView: UIView
{
    var items: [ControllerSkin.Item]? {
        didSet {
            updateItems()
        }
    }
    
    weak var placementLayoutGuide: UILayoutGuide?
    
    private var itemViews = [ItemView]()
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        initialize()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        initialize()
    }
    
    private func initialize()
    {
        backgroundColor = UIColor.clear
        isUserInteractionEnabled = false
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        for view in itemViews
        {
            var containingFrame = bounds
            if let layoutGuide = placementLayoutGuide, view.item.placement == .app
            {
                containingFrame = layoutGuide.layoutFrame
            }
            
            let frame = view.item.extendedFrame.scaled(to: containingFrame)
            view.frame = frame
        }
    }
    
    private func updateItems()
    {
        itemViews.forEach { $0.removeFromSuperview() }
        
        var itemViews = [ItemView]()
        
        for item in (items ?? [])
        {
            let itemView = ItemView(item: item)
            self.addSubview(itemView)
            
            itemViews.append(itemView)
        }
        
        self.itemViews = itemViews
        
        setNeedsLayout()
    }
}

private class ItemView: UIView
{
    let item: ControllerSkin.Item
    
    private let label: UILabel
    
    init(item: ControllerSkin.Item)
    {
        self.item = item
        
        label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor.white
        label.font = UIFont.boldSystemFont(ofSize: 16)
        
        var text = ""
        
        for input in item.inputs.allInputs
        {
            if text.isEmpty
            {
                text = input.stringValue
            }
            else
            {
                text = text + "," + input.stringValue
            }
        }
        
        label.text = text
        
        label.sizeToFit()
        
        super.init(frame: CGRect.zero)
        
        self.addSubview(label)
        
        label.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        label.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        
        backgroundColor = UIColor.red.withAlphaComponent(0.75)
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError()
    }
}
