//
//  RenderThread.swift
//  DeltaCore
//
//  Created by Riley Testut on 1/12/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import Foundation

class RenderingThread: Thread {
    var action: () -> Void
    
    private let startSemaphore = DispatchSemaphore(value: 0)
    private let stopSemaphore = DispatchSemaphore(value: 0)
        
    init(action: @escaping () -> Void) {
        self.action = action
        self.stopSemaphore.signal()
        
        super.init()
        
        name = "ManicEmu - Rendering"
        qualityOfService = .userInitiated
    }
    
    override func main() {
        while !isCancelled {
            autoreleasepool { [weak self] in
                guard let self = self else { return }
                self.startSemaphore.wait()
                defer { self.stopSemaphore.signal() }
                
                guard !self.isCancelled else { return }
                
                self.action()
            }
        }
    }
    
    override func cancel() {
        super.cancel()
        
        // We're probably waiting on startRenderSemaphore in main(),
        // so explicitly signal it so thread can finish.
        startSemaphore.signal()
    }
    
    func run() {
        startSemaphore.signal()
    }
    
    @discardableResult
    func wait(timeout: DispatchTime = .distantFuture) -> DispatchTimeoutResult {
        return stopSemaphore.wait(timeout: timeout)
    }
}
