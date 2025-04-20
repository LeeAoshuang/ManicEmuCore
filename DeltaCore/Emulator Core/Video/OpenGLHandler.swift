//
//  OpenGLESProcessor.swift
//  DeltaCore
//
//  Created by Riley Testut on 4/8/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreImage
import GLKit

class OpenGLHandler: VideoHandler {
    var videoFormat: VideoFormat {
        didSet {
            resizeVideoBuffers()
        }
    }
    
    var viewport: CGRect = .zero {
        didSet {
            resizeVideoBuffers()
        }
    }
    
    private let context: EAGLContext
    
    private var framebuffer: GLuint = 0
    private var texture: GLuint = 0
    private var renderbuffer: GLuint = 0
    
    private var indexBuffer: GLuint = 0
    private var vertexBuffer: GLuint = 0
    
    init(videoFormat: VideoFormat, context: EAGLContext) {
        self.videoFormat = videoFormat
        
        switch videoFormat.format
        {
        case .openGLES2: self.context = EAGLContext(api: .openGLES2, sharegroup: context.sharegroup)!
        case .openGLES3: self.context = EAGLContext(api: .openGLES3, sharegroup: context.sharegroup)!
        case .bitmap: fatalError("VideoFormat.Format.bitmap is not supported with OpenGLESProcessor.")
        }
    }
    
    deinit {
        if renderbuffer > 0
        {
            glDeleteRenderbuffers(1, &renderbuffer)
        }
        
        if self.texture > 0 {
            glDeleteTextures(1, &texture)
        }
        
        if self.framebuffer > 0 {
            glDeleteFramebuffers(1, &framebuffer)
        }
        
        if self.indexBuffer > 0 {
            glDeleteBuffers(1, &indexBuffer)
        }
        
        if self.vertexBuffer > 0 {
            glDeleteBuffers(1, &vertexBuffer)
        }
    }
}

extension OpenGLHandler {
    var videoBuffer: UnsafeMutablePointer<UInt8>? {
        return nil
    }
    
    func prepare() {
        struct Vertex {
            var x: GLfloat
            var y: GLfloat
            var z: GLfloat
            
            var u: GLfloat
            var v: GLfloat
        }
        
        EAGLContext.setCurrent(context)
        
        // Vertex buffer
        let vertices = [Vertex(x: -1.0, y: -1.0, z: 1.0, u: 0.0, v: 0.0),
                        Vertex(x: 1.0, y: -1.0, z: 1.0, u: 1.0, v: 0.0),
                        Vertex(x: 1.0, y: 1.0, z: 1.0, u: 1.0, v: 1.0),
                        Vertex(x: -1.0, y: 1.0, z: 1.0, u: 0.0, v: 1.0)]
        glGenBuffers(1, &vertexBuffer)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout<Vertex>.size * vertices.count, vertices, GLenum(GL_DYNAMIC_DRAW))
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
        
        // Index buffer
        let indices: [GLushort] = [0, 1, 2, 0, 2, 3]
        glGenBuffers(1, &indexBuffer)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBuffer)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), MemoryLayout<GLushort>.size * indices.count, indices, GLenum(GL_STATIC_DRAW))
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), 0)
        
        // Framebuffer
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        
        // Texture
        glGenTextures(1, &texture)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GLint(GL_LINEAR))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GLint(GL_LINEAR))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLint(GL_CLAMP_TO_EDGE))
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLint(GL_CLAMP_TO_EDGE))
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
        
        // Renderbuffer
        glGenRenderbuffers(1, &renderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_RENDERBUFFER), renderbuffer)
        
        resizeVideoBuffers()
    }
    
    func processFrame() -> CIImage? {
        glFlush()
        
        var image = CIImage(texture: texture, size: videoFormat.dimensions, flipped: false, colorSpace: nil)
        
        if let viewport = correctedViewport {
            image = image.cropped(to: viewport)
        }
        
        return image
    }
    
    func resizeVideoBuffers() {
        guard texture > 0 && renderbuffer > 0 else { return }
        
        EAGLContext.setCurrent(context)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(videoFormat.dimensions.width), GLsizei(videoFormat.dimensions.height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), GLsizei(videoFormat.dimensions.width), GLsizei(videoFormat.dimensions.height))
        
        var viewport = CGRect(origin: .zero, size: videoFormat.dimensions)
        if let correctedViewport = correctedViewport {
            viewport = correctedViewport
        }
        
        glViewport(GLsizei(viewport.minX), GLsizei(viewport.minY), GLsizei(viewport.width), GLsizei(viewport.height))
    }
}
