//
//  VideoManager.swift
//  DeltaCore
//
//  Created by Riley Testut on 3/16/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import Foundation
import Accelerate
import CoreImage
import GLKit

protocol VideoHandler {
    var videoFormat: VideoFormat { get }
    var videoBuffer: UnsafeMutablePointer<UInt8>? { get }
    
    var viewport: CGRect { get set }
    
    func prepare()
    func processFrame() -> CIImage?
}

extension VideoHandler {
    var correctedViewport: CGRect? {
        guard viewport != .zero else { return nil }
        
        let viewport = CGRect(x: viewport.minX, y: videoFormat.dimensions.height - viewport.height,
                              width: viewport.width, height: viewport.height)
        return viewport
    }
}

public class VideoUtils: NSObject, VideoRenderProtocol {
    public internal(set) var videoFormat: VideoFormat {
        didSet {
            updateProcessor()
        }
    }
    
    public let options: [EmulatorCore.Option: Any]
    
    public var viewport: CGRect = .zero {
        didSet {
            processor.viewport = viewport
        }
    }
    
    public var gameViews: Set<GameView> {
        return _gameViews.setRepresentation as! Set<GameView>
    }
    private let _gameViews: NSHashTable = NSHashTable<GameView>.weakObjects()
    
    public var isEnabled = true
    
    private let eaglContext: EAGLContext?
    private let ciContext: CIContext
    
    private var processor: VideoHandler
    @NSCopying private var processedImage: CIImage?
    @NSCopying private var displayedImage: CIImage? // Can only accurately snapshot rendered images.
    
    private lazy var renderThread = RenderingThread(action: { [weak self] in
        self?._render()
    })
    
    public init(videoFormat: VideoFormat, options: [EmulatorCore.Option: Any] = [:]) {
        self.videoFormat = videoFormat
        self.options = options
        
        switch videoFormat.format {
        case .bitmap:
            processor = BitmapHandler(videoFormat: videoFormat)
            
            if let prefersMetal = options[.metal] as? Bool, prefersMetal {
                ciContext = CIContext(options: [.workingColorSpace: NSNull()])
                eaglContext = nil
            } else {
                let context = EAGLContext(api: .openGLES3)!
                ciContext = CIContext(eaglContext: context, options: [.workingColorSpace: NSNull()])
                eaglContext = context
            }
            
        case .openGLES2:
            let context = EAGLContext(api: .openGLES2)!
            ciContext = CIContext(eaglContext: context, options: [.workingColorSpace: NSNull()])
            processor = OpenGLHandler(videoFormat: videoFormat, context: context)
            eaglContext = context
            
        case .openGLES3:
            let context = EAGLContext(api: .openGLES3)!
            ciContext = CIContext(eaglContext: context, options: [.workingColorSpace: NSNull()])
            processor = OpenGLHandler(videoFormat: videoFormat, context: context)
            eaglContext = context
        }
        
        super.init()
        
        renderThread.start()
    }
    
    private func updateProcessor() {
        switch videoFormat.format {
        case .bitmap:
            processor = BitmapHandler(videoFormat: videoFormat)
            
        case .openGLES2, .openGLES3:
            guard let processor = processor as? OpenGLHandler else { return }
            processor.videoFormat = videoFormat
        }
        
        processor.viewport = viewport
    }
    
    deinit
    {
        renderThread.cancel()
    }
    
    public func add(_ gameView: GameView) {
        guard !gameViews.contains(gameView) else { return }
        
        gameView.eaglContext = eaglContext
        _gameViews.add(gameView)
    }
    
    func remove(_ gameView: GameView) {
        _gameViews.remove(gameView)
    }
    
    public var videoBuffer: UnsafeMutablePointer<UInt8>? {
        return processor.videoBuffer
    }
    
    public func prepare() {
        processor.prepare()
    }
    
    public func processFrame() {
        guard isEnabled else { return }
        
        autoreleasepool {
            processedImage = processor.processFrame()
        }
    }
    
    public func render() {
        guard isEnabled else { return }
        
        guard let image = processedImage else { return }
        
        // Skip frame if previous frame is not finished rendering.
        guard renderThread.wait(timeout: .now()) == .success else { return }
        
        displayedImage = image
        
        renderThread.run()
    }
    
    public func snapshot() -> UIImage? {
        guard let displayedImage = displayedImage else { return nil }
        
        let imageWidth = Int(displayedImage.extent.width)
        let imageHeight = Int(displayedImage.extent.height)
        let capacity = imageWidth * imageHeight * 4
        
        let imageBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: capacity, alignment: 1)
        defer { imageBuffer.deallocate() }
        
        guard let baseAddress = imageBuffer.baseAddress, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        
        // Must render to raw buffer first so we can set CGImageAlphaInfo.noneSkipLast flag when creating CGImage.
        // Otherwise, some parts of images may incorrectly be transparent.
        ciContext.render(displayedImage, toBitmap: baseAddress, rowBytes: imageWidth * 4, bounds: displayedImage.extent, format: .RGBA8, colorSpace: colorSpace)
        
        let data = Data(bytes: baseAddress, count: imageBuffer.count)
        let bitmapInfo: CGBitmapInfo = [CGBitmapInfo.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)]
        
        guard
            let dataProvider = CGDataProvider(data: data as CFData),
            let cgImage = CGImage(width: imageWidth, height: imageHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: imageWidth * 4, space: colorSpace, bitmapInfo: bitmapInfo, provider: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        
        let image = UIImage(cgImage: cgImage)
        return image
    }
    
    func _render() {
        for gameView in gameViews
        {
            if let exclusiveVideoManager = gameView.specificVideoManager
            {
                guard exclusiveVideoManager == self else { continue }
            }
            
            gameView.inputImage = displayedImage
        }
    }
}

