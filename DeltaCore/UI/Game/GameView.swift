//
//  GameView.swift
//  DeltaCore
//
//  Created by Riley Testut on 3/16/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import UIKit
import CoreImage
import GLKit
import MetalKit
import AVFoundation

// Create wrapper class to prevent exposing GLKView (and its annoying deprecation warnings) to clients.
private class GameViewGLKDelegate: NSObject, GLKViewDelegate
{
    weak var gameView: GameView?
    
    init(gameView: GameView)
    {
        self.gameView = gameView
    }
    
    func glkView(_ view: GLKView, drawIn rect: CGRect)
    {
        gameView?.glkView(view, drawIn: rect)
    }
}

public enum SamplerMode
{
    case linear
    case nearestNeighbor
}

public class GameView: UIView
{
    public var isEnabled: Bool = true
    
    // Set to limit rendering to just a specific VideoManager.
    public weak var specificVideoManager: VideoUtils?
    
    @NSCopying public var inputImage: CIImage? {
        didSet {
            if self.inputImage?.extent != oldValue?.extent
            {
                DispatchQueue.main.async {
                    self.setNeedsLayout()
                }
            }
            
            update()
        }
    }
    
    @NSCopying public var filter: CIFilter? {
        didSet {
            guard self.filter != oldValue else { return }
            update()
        }
    }
    
    public var samplerMode: SamplerMode = .nearestNeighbor {
        didSet {
            update()
        }
    }
    
    public var outputImage: CIImage? {
        guard let inputImage = self.inputImage else { return nil }
        
        var image: CIImage?
        
        switch samplerMode
        {
        case .linear: image = inputImage.samplingLinear()
        case .nearestNeighbor: image = inputImage.samplingNearest()
        }
                
        if let filter = self.filter
        {
            filter.setValue(image, forKey: kCIInputImageKey)
            image = filter.outputImage
        }
        
        return image
    }
    
    internal var eaglContext: EAGLContext? {
        didSet {
            os_unfair_lock_lock(&self.lock)
            defer { os_unfair_lock_unlock(&self.lock) }
            
            didLayoutSubviews = false
            
            // For some reason, if we don't explicitly set current EAGLContext to nil, assigning
            // to self.glkView may crash if we've already rendered to a game view.
            EAGLContext.setCurrent(nil)
            
            if let eaglContext
            {
                glkView.context = EAGLContext(api: eaglContext.api, sharegroup: eaglContext.sharegroup)!
                glesContext = makeGLESContext()
            }
            
            DispatchQueue.main.async {
                // layoutSubviews() must be called after setting self.eaglContext before we can display anything.
                self.setNeedsLayout()
            }
        }
    }
    private lazy var glesContext: CIContext = makeGLESContext()
    private lazy var metalContext: CIContext = makeMetalContext()
        
    private let glkView: GLKView
    private lazy var glkViewDelegate = GameViewGLKDelegate(gameView: self)
    
    public let mtkView: MTKView
    private let metalDevice = MTLCreateSystemDefaultDevice()
    private lazy var metalQueue = metalDevice?.makeCommandQueue()
    private weak var metalLayer: CAMetalLayer?
    
    private var lock = os_unfair_lock()
    private var didLayoutSubviews = false
    private var didUpdateInitialFrame = false
    private var isUpdatingInitialFrame = false
    
    private var isUsingMetal: Bool {
        let isUsingMetal = (eaglContext == nil)
        return isUsingMetal
    }
    
    public override init(frame: CGRect)
    {
        let eaglContext = EAGLContext(api: .openGLES2)!
        self.glkView = GLKView(frame: CGRect.zero, context: eaglContext)
        self.mtkView = MTKView(frame: .zero, device: metalDevice)
        
        super.init(frame: frame)
        
        self.initialize()
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        let eaglContext = EAGLContext(api: .openGLES2)!
        self.glkView = GLKView(frame: CGRect.zero, context: eaglContext)
        self.mtkView = MTKView(frame: .zero, device: self.metalDevice)
        
        super.init(coder: aDecoder)
        
        self.initialize()
    }
    
    private func initialize()
    {        
        glkView.frame = bounds
        glkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glkView.delegate = glkViewDelegate
        glkView.enableSetNeedsDisplay = false
        addSubview(glkView)
        
        mtkView.frame = bounds
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.delegate = self
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = false // Must be false to avoid "frameBufferOnly texture not supported for compute" assertion
        mtkView.isPaused = true
        addSubview(mtkView)
        
        if let metalLayer = mtkView.layer as? CAMetalLayer
        {
            self.metalLayer = metalLayer
        }
    }
    
    public override func didMoveToWindow()
    {
        if let window = self.window
        {
            glkView.contentScaleFactor = window.screen.scale
            update()
        }
    }
    
    public override func layoutSubviews()
    {
        super.layoutSubviews()
        
        if outputImage != nil
        {
            if isUsingMetal
            {
                mtkView.isHidden = false
                glkView.isHidden = true
            }
            else
            {
                mtkView.isHidden = true
                glkView.isHidden = false
            }
        }
        else
        {
            mtkView.isHidden = true
            glkView.isHidden = true
        }
                
        didLayoutSubviews = true
    }
    
    public func snapshot() -> UIImage?
    {
        // Unfortunately, rendering CIImages doesn't always work when backed by an OpenGLES texture.
        // As a workaround, we simply render the view itself into a graphics context the same size
        // as our output image.
        //
        // let cgImage = self.context.createCGImage(outputImage, from: outputImage.extent)
        
        guard let outputImage = outputImage else { return nil }

        let rect = CGRect(origin: .zero, size: outputImage.extent.size)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        
        let snapshot = renderer.image { (context) in
            if isUsingMetal
            {
                mtkView.drawHierarchy(in: rect, afterScreenUpdates: false)
            }
            else
            {
                glkView.drawHierarchy(in: rect, afterScreenUpdates: false)
            }
        }
        
        return snapshot
    }
    
    public func update(for screen: ControllerSkin.Screen)
    {
        var filters = [CIFilter]()
        
        if let inputFrame = screen.inputFrame
        {
            let cropFilter = CIFilter(name: "CICrop", parameters: ["inputRectangle": CIVector(cgRect: inputFrame)])!
            filters.append(cropFilter)
        }
        
        if let screenFilters = screen.filters
        {
            filters.append(contentsOf: screenFilters)
        }
        
        // Always use FilterChain since it has additional logic for chained filters.
        let filterChain = filters.isEmpty ? nil : FilterChain(filters: filters)
        filter = filterChain
    }
    
    func makeGLESContext() -> CIContext
    {
        let context = CIContext(eaglContext: glkView.context, options: [.workingColorSpace: NSNull()])
        return context
    }
    
    func makeMetalContext() -> CIContext
    {
        guard let metalQueue else {
            // This should never be called, but just in case we return dummy CIContext.
            return CIContext(options: [.workingColorSpace: NSNull()])
        }
        
        let options: [CIContextOption: Any] = [.workingColorSpace: NSNull(),
                                               .cacheIntermediates: true,
                                               .name: "GameView Context"]
                
        let context = CIContext(mtlCommandQueue: metalQueue, options: options)
        return context
    }
    
    func update()
    {
        // Calling display when outputImage is nil may crash for OpenGLES-based rendering.
        guard isEnabled && outputImage != nil else { return }
        
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        // layoutSubviews() must be called after setting self.eaglContext before we can display anything.
        // Otherwise, the app may crash due to race conditions when creating framebuffer from background thread.
        guard didLayoutSubviews else { return }

        if !didUpdateInitialFrame
        {
            if Thread.isMainThread
            {
                render()
                didUpdateInitialFrame = true
            }
            else if !isUpdatingInitialFrame
            {
                // Make sure we don't make multiple calls to glkView.display() before first call returns.
                isUpdatingInitialFrame = true
                
                DispatchQueue.main.async {
                    self.render()
                    self.didUpdateInitialFrame = true
                    self.isUpdatingInitialFrame = false
                }
            }
        }
        else
        {
            render()
        }
    }
    
    func render()
    {
        if isUsingMetal
        {
            mtkView.draw()
        }
        else
        {
            glkView.display()
        }
    }
}

extension GameView: MTKViewDelegate
{
    func glkView(_ view: GLKView, drawIn rect: CGRect)
    {
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(UInt32(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        
        if let outputImage = outputImage
        {
            let bounds = CGRect(x: 0, y: 0, width: glkView.drawableWidth, height: glkView.drawableHeight)
            glesContext.draw(outputImage, in: bounds, from: outputImage.extent)
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    {
    }
    
    public func draw(in view: MTKView)
    {
        autoreleasepool {
            guard let image = outputImage,
                  let commandBuffer = metalQueue?.makeCommandBuffer(),
                  let currentDrawable = metalLayer?.nextDrawable()
            else { return }
            
            let scaleX = view.drawableSize.width / image.extent.width
            let scaleY = view.drawableSize.height / image.extent.height
            let outputImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            do
            {
                let destination = CIRenderDestination(width: Int(view.drawableSize.width),
                                                      height: Int(view.drawableSize.height),
                                                      pixelFormat: view.colorPixelFormat,
                                                      commandBuffer: nil) { [unowned currentDrawable] () -> MTLTexture in
                    // Lazily return texture to prevent hangs due to waiting for previous command to finish.
                    let texture = currentDrawable.texture
                    return texture
                }
                
                try self.metalContext.startTask(toRender: outputImage, from: outputImage.extent, to: destination, at: .zero)
                
                commandBuffer.present(currentDrawable)
                commandBuffer.commit()
            }
            catch
            {
                print("Failed to render frame with Metal.", error)
            }
        }
    }
}
