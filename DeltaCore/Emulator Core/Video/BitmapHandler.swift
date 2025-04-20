//
//  BitmapProcessor.swift
//  DeltaCore
//
//  Created by Riley Testut on 4/8/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreImage
import Accelerate

fileprivate extension VideoFormat.PixelFormat {
    var nativeCIFormat: CIFormat? {
        switch self {
        case .rgb565: return nil
        case .bgra8: return .BGRA8
        case .rgba8: return .RGBA8
        }
    }
}

fileprivate extension VideoFormat {
    var pixelFormat: PixelFormat {
        switch format {
        case .bitmap(let format): return format
        case .openGLES2, .openGLES3: fatalError("Should not be using VideoFormat.Format.openGLES with BitmapProcessor.")
        }
    }
    
    var bufferSize: Int {
        let bufferSize = Int(dimensions.width * dimensions.height) * pixelFormat.bytesPerPixel
        return bufferSize
    }
}

class BitmapHandler: VideoHandler {
    let videoFormat: VideoFormat
    let videoBuffer: UnsafeMutablePointer<UInt8>?
    
    var viewport: CGRect = .zero
    
    private let outputVideoFormat: VideoFormat
    private let outputVideoBuffer: UnsafeMutablePointer<UInt8>
    
    init(videoFormat: VideoFormat) {
        self.videoFormat = videoFormat
        
        switch videoFormat.pixelFormat {
        case .rgb565: outputVideoFormat = VideoFormat(format: .bitmap(.bgra8), dimensions: videoFormat.dimensions)
        case .bgra8, .rgba8: outputVideoFormat = videoFormat
        }
        
        videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: videoFormat.bufferSize)
        outputVideoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputVideoFormat.bufferSize)
    }
    
    deinit {
        videoBuffer?.deallocate()
        outputVideoBuffer.deallocate()
    }
    
    func prepare() {}
    
    func processFrame() -> CIImage? {
        guard let ciFormat = outputVideoFormat.pixelFormat.nativeCIFormat else {
            print("VideoManager output format is not supported.")
            return nil
        }
        
        return autoreleasepool {
            var inputVImageBuffer = vImage_Buffer(data: videoBuffer, height: vImagePixelCount(videoFormat.dimensions.height), width: vImagePixelCount(videoFormat.dimensions.width), rowBytes: videoFormat.pixelFormat.bytesPerPixel * Int(videoFormat.dimensions.width))
            var outputVImageBuffer = vImage_Buffer(data: outputVideoBuffer, height: vImagePixelCount(outputVideoFormat.dimensions.height), width: vImagePixelCount(outputVideoFormat.dimensions.width), rowBytes: outputVideoFormat.pixelFormat.bytesPerPixel * Int(outputVideoFormat.dimensions.width))
            
            switch videoFormat.pixelFormat {
            case .rgb565: vImageConvert_RGB565toBGRA8888(255, &inputVImageBuffer, &outputVImageBuffer, 0)
            case .bgra8, .rgba8:
                // Ensure alpha value is 255, not 0.
                // 0x1 refers to the Blue channel in ARGB, which corresponds to the Alpha channel in BGRA and RGBA.
                vImageOverwriteChannelsWithScalar_ARGB8888(255, &inputVImageBuffer, &outputVImageBuffer, 0x1, vImage_Flags(kvImageNoFlags))
            }
            
            let bitmapData = Data(bytes: outputVideoBuffer, count: outputVideoFormat.bufferSize)
            
            var image = CIImage(bitmapData: bitmapData, bytesPerRow: outputVideoFormat.pixelFormat.bytesPerPixel * Int(outputVideoFormat.dimensions.width), size: outputVideoFormat.dimensions, format: ciFormat, colorSpace: nil)
            
            if let viewport = correctedViewport {
                image = image.cropped(to: viewport)
            }
            
            return image
        }
    }
}
