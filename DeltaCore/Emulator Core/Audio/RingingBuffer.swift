//
//  RingBuffer.swift
//  DeltaCore
//
//  Created by Riley Testut on 6/29/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//
//  Heavily based on Michael Tyson's TPCircularBuffer (https://github.com/michaeltyson/TPCircularBuffer)
//

import Foundation
import Darwin.Mach.machine.vm_types

private func trunc_page(_ x: vm_size_t) -> vm_size_t
{
    return x & ~(vm_page_size - 1)
}

private func round_page(_ x: vm_size_t) -> vm_size_t
{
    return trunc_page(x + (vm_size_t(vm_page_size) - 1))
}

@objc(MANCRingingBuffer) @objcMembers
public class RingingBuffer: NSObject {
    public var isEnabled: Bool = true
    
    public var enableBytesForWriting: Int {
        return Int(bufferLength - Int(usedBytesCount))
    }
    
    public var enableBytesForReading: Int {
        return Int(usedBytesCount)
    }
    
    private var head: UnsafeMutableRawPointer {
        let head = buffer.advanced(by: headOffset)
        return head
    }
    
    private var tail: UnsafeMutableRawPointer {
        let head = buffer.advanced(by: tailOffset)
        return head
    }
    
    private let buffer: UnsafeMutableRawPointer
    private var bufferLength = 0
    private var tailOffset = 0
    private var headOffset = 0
    private var usedBytesCount: Int32 = 0
    
    public init?(preferredBufferSize: Int) {
        assert(preferredBufferSize > 0)
        
        // To handle race conditions, repeat initialization process up to 3 times before failing.
        for _ in 1...3 {
            let length = round_page(vm_size_t(preferredBufferSize))
            bufferLength = Int(length)
            
            var bufferAddress: vm_address_t = 0
            guard vm_allocate(mach_task_self_, &bufferAddress, vm_size_t(length * 2), VM_FLAGS_ANYWHERE) == ERR_SUCCESS else { continue }
            
            guard vm_deallocate(mach_task_self_, bufferAddress + length, length) == ERR_SUCCESS else {
                vm_deallocate(mach_task_self_, bufferAddress, length)
                continue
            }
            
            var virtualAddress: vm_address_t = bufferAddress + length
            var current_protection: vm_prot_t = 0
            var max_protection: vm_prot_t = 0
            
            guard vm_remap(mach_task_self_, &virtualAddress, length, 0, 0, mach_task_self_, bufferAddress, 0, &current_protection, &max_protection, VM_INHERIT_DEFAULT) == ERR_SUCCESS else {
                vm_deallocate(mach_task_self_, bufferAddress, length)
                continue
            }
            
            guard virtualAddress == bufferAddress + length else {
                vm_deallocate(mach_task_self_, virtualAddress, length)
                vm_deallocate(mach_task_self_, bufferAddress, length)
                
                continue
            }
            
            buffer = UnsafeMutableRawPointer(bitPattern: UInt(bufferAddress))!
            
            return
        }
        
        return nil
    }
    
    deinit {
        let address = UInt(bitPattern: self.buffer)
        vm_deallocate(mach_task_self_, vm_address_t(address), vm_size_t(self.bufferLength * 2))
    }
    
    func incrementEnableBytes(by size: Int) {
        tailOffset = (tailOffset + size) % bufferLength
        OSAtomicAdd32(-Int32(size), &usedBytesCount)
    }
    
    func decrementEnableBytes(by size: Int) {
        headOffset = (headOffset + size) % bufferLength
        OSAtomicAdd32(Int32(size), &usedBytesCount)
    }
    
    /// Writes `size` bytes from `buffer` to ring buffer if possible. Otherwise, writes as many as possible.
    @objc(writeBuffer:size:)
    @discardableResult public func write(_ buffer: UnsafeRawPointer, size: Int) -> Int {
        guard isEnabled else { return 0 }
        guard enableBytesForWriting > 0 else { return 0 }
        
        if size > enableBytesForWriting {
            print("Ring Buffer Capacity reached. Available: \(enableBytesForWriting). Requested: \(size) Max: \(self.bufferLength). Filled: \(self.usedBytesCount).")
            
            reset()
        }
        
        let size = min(size, enableBytesForWriting)
        memcpy(head, buffer, size)
        
        decrementEnableBytes(by: size)
        
        return size
    }
    
    /// Copies `size` bytes from ring buffer to `buffer` if possible. Otherwise, copies as many as possible.
    @objc(readIntoBuffer:preferredSize:)
    @discardableResult public func read(into buffer: UnsafeMutableRawPointer, preferredSize: Int) -> Int {
        guard isEnabled else { return 0 }
        guard enableBytesForReading > 0 else { return 0 }
        
        if preferredSize > enableBytesForReading {
            print("Ring Buffer Empty. Available: \(enableBytesForReading). Requested: \(preferredSize) Max: \(bufferLength). Filled: \(usedBytesCount).")
            
            reset()
        }
        
        let size = min(preferredSize, enableBytesForReading)
        memcpy(buffer, tail, size)
        
        incrementEnableBytes(by: size)
        
        return size
    }
    
    public func reset() {
        let size = enableBytesForReading
        incrementEnableBytes(by: size)
    }
}
