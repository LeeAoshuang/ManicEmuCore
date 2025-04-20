//
//  ButtonsDynamicEffectView.swift
//  DeltaCore
//
//  Created by Aushuang Lee on 2025/2/11.
//

import UIKit
import ZIPFoundation

internal class ButtonsDynamicEffectView: UIView {
    var items: [ControllerSkin.Item]? {
        didSet {
            self.updateItems()
        }
    }
    
    var archive: Archive?
    
    weak var appPlacementLayoutGuide: UILayoutGuide?
    
    private var itemViews = [DynamicEffectView]()
    
    private var imageDatasCache = [String: (normalImageData: Data?, selectedlImageData: Data?)]()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialize()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }
    
    private func initialize() {
        self.backgroundColor = UIColor.clear
        self.isUserInteractionEnabled = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        for view in itemViews {
            var containingFrame = bounds
            if let layoutGuide = appPlacementLayoutGuide, view.item.placement == .app {
                containingFrame = layoutGuide.layoutFrame
            }
            
//            let extendedFrame = view.item.extendedFrame.scaled(to: containingFrame)
            let noExtendedFrame = view.item.frame.scaled(to: containingFrame)
//            view.extenedEdges = UIEdgeInsets(top: extendedFrame.origin.y - noExtendedFrame.origin.y, left: extendedFrame.origin.x - noExtendedFrame.origin.x, bottom: extendedFrame.maxY - noExtendedFrame.maxY, right: extendedFrame.maxX - noExtendedFrame.maxX)
            
            view.frame = noExtendedFrame
            
            //设置动效image
            if let archive = archive, let asset = view.item.asset {
                let targetSize = noExtendedFrame.size
                var normalImage: UIImage? = nil
                var selectedlImage: UIImage? = nil
                
                if let data = imageDatasCache[view.item.id] {
                    //缓存存在
                    if let normalImageData = data.normalImageData {
                        normalImage = UIImage.image(withPDFData: normalImageData, targetSize: targetSize)
                    }
                    if let selectedlImageData = data.selectedlImageData {
                        selectedlImage = UIImage.image(withPDFData: selectedlImageData, targetSize: targetSize)
                    }
                } else {
                    //缓存不存在 从文件中解压出来
                    var normalDataCache: Data? = nil
                    var selectedDataCache: Data? = nil
                    if view.item.kind == .button, case .button(let normal, let selected) = asset {
                        //按钮
                        if let normal = normal, let normalData = extractArchive(archive, with: normal) {
                            normalImage = UIImage.image(withPDFData: normalData, targetSize: targetSize)
                            normalDataCache = normalData
                        }
                        if let selected = selected, let selectedData = extractArchive(archive, with: selected) {
                            selectedlImage = UIImage.image(withPDFData: selectedData, targetSize: targetSize)
                            selectedDataCache = selectedData
                        }
                    } else if view.item.kind == .dPad, case .dpad(let normal) = asset {
                        //方向键
                        if let normal = normal, let normalData = extractArchive(archive, with: normal) {
                            normalImage = UIImage.image(withPDFData: normalData, targetSize: targetSize)
                            normalDataCache = normalData
                        }
                    }
                    if normalDataCache != nil || selectedDataCache != nil {
                        imageDatasCache[view.item.id] = (normalDataCache, selectedDataCache)
                    }
                }
                view.normalImageView?.image = normalImage
                view.selectedlImageView?.image = selectedlImage
                if normalImage == nil && selectedlImage != nil {
                    view.selectedlImageView?.alpha = 1
                }
            }
        }
    }
    
    //从archive解压name命名的文件
    private func extractArchive(_ archive: Archive, with name: String) -> Data? {
        if let entry = archive[name],
           let data = try? archive.extract(entry) {
            return data
        }
        return nil
    }
    
    private func updateItems() {
        itemViews.forEach { $0.removeFromSuperview() }
        imageDatasCache.removeAll()
        
        var itemViews = [DynamicEffectView]()
        
        func addItemView(_ item: ControllerSkin.Item) {
            let itemView = DynamicEffectView(item: item)
            addSubview(itemView)
            itemViews.append(itemView)
        }
        
        for item in (items ?? []) {
            if item.kind == .button, let asset = item.asset, case .button(let normal, let selected) = asset, (normal != nil || selected != nil) {
                addItemView(item)
            } else if item.kind == .dPad, let asset = item.asset, case .dpad(let normal) = asset, normal != nil {
                addItemView(item)
            }
        }
        
        self.itemViews = itemViews
        
        setNeedsLayout()
    }
    
    private var previousActivateDate = Date()
    func activateButtonEffect(input: SomeInput) {
        previousActivateDate = Date()
        findItemView(with: input)?.pressEffect(input)
    }
    
    func deactivateButtonEffect(input: SomeInput) {
        let elapsed = Date().timeIntervalSince1970 - previousActivateDate.timeIntervalSince1970
        if elapsed < 0.06 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                self.findItemView(with: input)?.releaseEffect(input)
            })
        } else {
            self.findItemView(with: input)?.releaseEffect(input)
        }
    }
    
    //通过input查找到对应的视图
    private func findItemView(with input: SomeInput) -> DynamicEffectView? {
        for itemView in itemViews {
            if case .standard(let inputs) = itemView.item.inputs, inputs.contains(where: { $0 == input }) {
                return itemView
            } else if case .directional(let up, let down, let left, let right) = itemView.item.inputs, ((up == input) || (down == input) || (left == input) || (right == input)) {
                return itemView
            }
        }
        return nil
    }
}

private class DynamicEffectView: UIView {
    let item: ControllerSkin.Item
    
    lazy var normalImageView: UIImageView? = {
        let imageView = UIImageView()
        imageView.alpha = 1
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        return imageView
    }()
    lazy var selectedlImageView: UIImageView? = {
        if item.kind == .button, let asset = item.asset, case .button(let _, let selected) = asset, selected != nil {
            let imageView = UIImageView()
            imageView.alpha = 0
            imageView.contentMode = .center
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            return imageView
        }
        return nil
    }()
    
    init(item: ControllerSkin.Item) {
        self.item = item
        super.init(frame: CGRect.zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    // 按压效果
    func pressEffect(_ input: SomeInput) {
        if item.kind == .button {
            performButtonTransformation(CGAffineTransform(scaleX: 0.9, y: 0.9), isSelected: false)
        } else if item.kind == .dPad {
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 500.0 // 透视效果
            switch StandardGameControllerInput(stringValue: input.stringValue) {
            case .up:
                transform =  CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, .pi / 10, 1, 0, 0), 0, -1.75, 0), 0.95, 1, 1) // 绕 X 轴旋转
            case .down:
                transform =  CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, -.pi / 10, 1, 0, 0), 0, 1.75, 0), 0.95, 1, 1) // 绕 X 轴旋转
            case .left:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, -.pi / 10, 0, 1, 0), -1.75, 0, 0), 1, 0.95, 1) // 绕 Y 轴旋转
            case .right:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, .pi / 10, 0, 1, 0), 1.75, 0, 0), 1, 0.95, 1) // 绕 Y 轴旋转
            default:
                break
            }
            // 添加平移效果，模拟按键按压
            performDPadTransformation(transform)
        }
    }
    
    // 释放效果
    func releaseEffect(_ input: SomeInput) {
        if item.kind == .button {
            performButtonTransformation(CGAffineTransform(scaleX: 1, y: 1), isSelected: true)
        } else if item.kind == .dPad {
            performDPadTransformation(CATransform3DIdentity)
        }
    }
    
    private func performButtonTransformation(_ transformation: CGAffineTransform, isSelected: Bool) {
        let timingParameters = UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: CGVector(dx: 0.2, dy: 0.2))
        let animator = UIViewPropertyAnimator(duration: 0.65, timingParameters: timingParameters)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }
            self.normalImageView?.transform = transformation
            if let selectedlImageView = self.selectedlImageView {
                self.normalImageView?.alpha = isSelected ? 1 : 0
                selectedlImageView.transform = transformation
                selectedlImageView.alpha = isSelected ? 0 : 1
            }
        }
        animator.isInterruptible = true
        animator.startAnimation()
    }
    
    private func performDPadTransformation(_ transformation: CATransform3D) {
        let timingParameters = UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: CGVector(dx: 0.2, dy: 0.2))
        let animator = UIViewPropertyAnimator(duration: 0.65, timingParameters: timingParameters)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }
            self.normalImageView?.transform3D = transformation
        }
        animator.isInterruptible = true
        animator.startAnimation()
    }
}
