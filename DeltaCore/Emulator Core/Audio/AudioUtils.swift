//
//  AudioManager.swift
//  DeltaCore
//
//  Created by Riley Testut on 1/12/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import AVFoundation

internal extension AVAudioFormat {
    var frameSize: Int {
        return Int(streamDescription.pointee.mBytesPerFrame)
    }
}

private extension AVAudioSession {
    func setManicEmuCategory() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                        options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
    }
}

private extension AVAudioSessionRouteDescription {
    var isHeadset: Bool {
        let isHeadsetPluggedIn = outputs.contains { $0.portType == .headphones || $0.portType == .bluetoothA2DP }
        return isHeadsetPluggedIn
    }
    
    var isOutToReceiver: Bool {
        let isOutputtingToReceiver = outputs.contains { $0.portType == .builtInReceiver }
        return isOutputtingToReceiver
    }
    
    var isOutToExternalDevice: Bool {
        let isOutputtingToExternalDevice = outputs.contains { $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver }
        return isOutputtingToExternalDevice
    }
}

public class AudioUtils: NSObject, AudioRenderProtocol {
    /// Currently only supports 16-bit interleaved Linear PCM.
    public internal(set) var audioFormat: AVAudioFormat {
        didSet {
            resetAudioEngine()
        }
    }
    
    public var isEnabled = true {
        didSet {
            audioBuffer.isEnabled = isEnabled
            
            updateVolume()
            
            do {
                if isEnabled
                {
                    try audioEngine.start()
                }
                else
                {
                    audioEngine.pause()
                }
            }
            catch {
                print(error)
            }
            
            audioBuffer.reset()
        }
    }
    
    public var followSilentMode: Bool = true {
        didSet {
            updateVolume()
        }
    }
    
    public private(set) var audioBuffer: RingingBuffer
    
    public internal(set) var rate = 1.0 {
        didSet {
            timePitchEffect.rate = Float(self.rate)
        }
    }
    
    var frameDuration: Double = (1.0 / 60.0) {
        didSet {
            guard audioEngine.isRunning else { return }
            resetAudioEngine()
        }
    }
    
    private let audioEngine: AVAudioEngine
    private let audioPlayerNode: AVAudioPlayerNode
    private let timePitchEffect: AVAudioUnitTimePitch
    
    private var sourceNode: AVAudioSourceNode {
        get {
            if _sourceNode == nil {
                _sourceNode = makeSourceNode()
            }
            
            return _sourceNode as! AVAudioSourceNode
        }
        set {
            _sourceNode = newValue
        }
    }
    private var _sourceNode: Any! = nil
    
    private var audioConverter: AVAudioConverter?
    private var audioConverterNeedCount: AVAudioFrameCount?
    
    private let audioBufferCount = 3
    
    // Used to synchronize access to self.audioPlayerNode without causing deadlocks.
    private let renderingQueue = DispatchQueue(label: "com.aoshuang.EmulatorCore.AudioManager.renderingQueue")
    
    private var isMuted: Bool = false {
        didSet {
            self.updateVolume()
        }
    }
    
    private let muteMonitor = DLTAMuteSwitchMonitor()
        
    public init(audioFormat: AVAudioFormat) {
        self.audioFormat = audioFormat
        
        // Temporary. Will be replaced with more accurate RingBuffer in resetAudioEngine().
        self.audioBuffer = RingingBuffer(preferredBufferSize: 4096)!
        
        do {
            // Set category before configuring AVAudioEngine to prevent pausing any currently playing audio from another app.
            try AVAudioSession.sharedInstance().setManicEmuCategory()
        }
        catch {
            print(error)
        }
        
        self.audioEngine = AVAudioEngine()
        
        self.audioPlayerNode = AVAudioPlayerNode()
        self.audioEngine.attach(self.audioPlayerNode)
        
        self.timePitchEffect = AVAudioUnitTimePitch()
        self.audioEngine.attach(self.timePitchEffect)
        
        super.init()
        
        self.audioEngine.attach(self.sourceNode)
        
        self.updateVolume()
        
        NotificationCenter.default.addObserver(self, selector: #selector(AudioUtils.resetAudioEngine), name: .AVAudioEngineConfigurationChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AudioUtils.resetAudioEngine), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    func render(_ inputBuffer: AVAudioPCMBuffer, into outputBuffer: AVAudioPCMBuffer) {
        guard let buffer = inputBuffer.int16ChannelData, let audioConverter = audioConverter else { return }
        
        // Ensure any buffers from previous audio route configurations are no longer processed.
        guard inputBuffer.format == audioConverter.inputFormat && outputBuffer.format == audioConverter.outputFormat else { return }
        
        if audioConverterNeedCount == nil {
            // Determine the minimum number of input frames needed to perform a conversion.
            audioConverter.convert(to: outputBuffer, error: nil) { [weak self] (requiredPacketCount, outStatus) -> AVAudioBuffer? in
                guard let self = self else { return nil }
                // In Linear PCM, one packet = one frame.
                self.audioConverterNeedCount = requiredPacketCount
                
                // Setting to ".noDataNow" sometimes results in crash, so we set to ".endOfStream" and reset audioConverter afterwards.
                outStatus.pointee = .endOfStream
                return nil
            }
            
            audioConverter.reset()
        }
        
        guard let audioConverterRequiredFrameCount = audioConverterNeedCount else { return }
        
        let availableFrameCount = AVAudioFrameCount(audioBuffer.enableBytesForReading / self.audioFormat.frameSize)
        if self.audioEngine.isRunning && availableFrameCount >= audioConverterRequiredFrameCount {
            var conversionError: NSError?
            let status = audioConverter.convert(to: outputBuffer, error: &conversionError) { [weak self] (requiredPacketCount, outStatus) -> AVAudioBuffer? in
                guard let self = self else { return nil }
                
                // Copy requiredPacketCount frames into inputBuffer's first channel (since audio is interleaved, no need to modify other channels).
                let preferredSize = min(Int(requiredPacketCount) * self.audioFormat.frameSize, Int(inputBuffer.frameCapacity) * self.audioFormat.frameSize)
                buffer[0].withMemoryRebound(to: UInt8.self, capacity: preferredSize) { (uint8Buffer) in
                    let readBytes = self.audioBuffer.read(into: uint8Buffer, preferredSize: preferredSize)
                    
                    let frameLength = AVAudioFrameCount(readBytes / self.audioFormat.frameSize)
                    inputBuffer.frameLength = frameLength
                }
                
                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .noDataNow
                    return nil
                } else {
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
            }
            
            if status == .error {
                if let error = conversionError {
                    print(error, error.userInfo)
                }
            }
        } else {
            // If not running or not enough input frames, set frameLength to 0 to minimize time until we check again.
            inputBuffer.frameLength = 0
        }
        
        audioPlayerNode.scheduleBuffer(outputBuffer) { [weak self, weak node = audioPlayerNode] in
            guard let self = self else { return }
            
            self.renderingQueue.async {
                if node?.isPlaying == true
                {
                    self.render(inputBuffer, into: outputBuffer)
                }
            }
        }
    }
    
    @objc func resetAudioEngine() {
        renderingQueue.sync { [weak self] in
            guard let self = self else { return }
            self.audioPlayerNode.reset()
            
            guard let outputAudioFormat = AVAudioFormat(standardFormatWithSampleRate: AVAudioSession.sharedInstance().sampleRate, channels: self.audioFormat.channelCount) else { return }
            
            let inputAudioBufferFrameCount = Int(self.audioFormat.sampleRate * self.frameDuration)
            let outputAudioBufferFrameCount = Int(outputAudioFormat.sampleRate * self.frameDuration)
            
            // Allocate enough space to prevent us from overwriting data before we've used it.
            let ringBufferAudioBufferCount = Int((self.audioFormat.sampleRate / outputAudioFormat.sampleRate).rounded(.up) + 10.0)
            
            let preferredBufferSize = inputAudioBufferFrameCount * self.audioFormat.frameSize * ringBufferAudioBufferCount
            guard let ringBuffer = RingingBuffer(preferredBufferSize: preferredBufferSize) else {
                fatalError("Cannot initialize RingBuffer with preferredBufferSize of \(preferredBufferSize)")
            }
            self.audioBuffer = ringBuffer
            
            let audioConverter = AVAudioConverter(from: self.audioFormat, to: outputAudioFormat)
            self.audioConverter = audioConverter
            
            self.audioConverterNeedCount = nil
            
            self.audioEngine.disconnectNodeOutput(self.timePitchEffect)
            self.audioEngine.connect(self.timePitchEffect, to: self.audioEngine.mainMixerNode, format: outputAudioFormat)

            self.audioEngine.detach(self.sourceNode)
            
            self.sourceNode = self.makeSourceNode()
            self.audioEngine.attach(self.sourceNode)
            
            self.audioEngine.connect(self.sourceNode, to: self.timePitchEffect, format: outputAudioFormat)
            
            do {
                // Explicitly set output port since .defaultToSpeaker option pauses external audio.
                if AVAudioSession.sharedInstance().currentRoute.isOutToReceiver {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                }
                
                try self.audioEngine.start()
                
            } catch {
                print(error)
            }
        }
    }
    
    @objc func updateVolume() {
        if !isEnabled {
            audioEngine.mainMixerNode.outputVolume = 0.0
        } else {
            let route = AVAudioSession.sharedInstance().currentRoute
            
            if AVAudioSession.sharedInstance().isOtherAudioPlaying {
                // Always mute if another app is playing audio.
                audioEngine.mainMixerNode.outputVolume = 0.0
            } else if followSilentMode {
                if isMuted && (route.isHeadset || !route.isOutToExternalDevice) {
                    // Respect mute switch IFF playing through speaker or headphones.
                    audioEngine.mainMixerNode.outputVolume = 0.0
                } else {
                    // Ignore mute switch for other audio routes (e.g. AirPlay).
                    self.audioEngine.mainMixerNode.outputVolume = 1.0
                }
            } else {
                // Ignore silent mode and always play game audio (unless another app is playing audio).
                audioEngine.mainMixerNode.outputVolume = 1.0
            }
        }
    }
    
    func makeSourceNode() -> AVAudioSourceNode {
        var isPrimed = false
        var previousSampleCount: Int?
        
        // Accessing AVAudioSession.sharedInstance() from render block may cause audio glitches,
        // so calculate sampleRateRatio now rather than later when needed 🤷‍♂️
        let sampleRateRatio = (audioFormat.sampleRate / AVAudioSession.sharedInstance().sampleRate).rounded(.up)
        
        let sourceNode = AVAudioSourceNode(format: audioFormat) { [audioFormat, audioBuffer] (_, _, frameCount, audioBufferList) -> OSStatus in
            defer { previousSampleCount = audioBuffer.enableBytesForReading }
            
            let unsafeAudioBufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buffer = unsafeAudioBufferList[0].mData else { return kAudioFileStreamError_UnspecifiedError }
            
            let requestedBytes = Int(frameCount) * audioFormat.frameSize
            
            if !isPrimed {
                // Make sure audio buffer has enough initial samples to prevent audio distortion.
                
                guard audioBuffer.enableBytesForReading >= requestedBytes * Int(sampleRateRatio) else { return kAudioFileStreamError_DataUnavailable }
                isPrimed = true
            }
            
            if let previousSampleCount = previousSampleCount, audioBuffer.enableBytesForReading < previousSampleCount {
                // Audio buffer has been reset, so we need to prime it again.
                
                isPrimed = false
                return kAudioFileStreamError_DataUnavailable
            }
            
            guard audioBuffer.enableBytesForReading >= requestedBytes else {
                isPrimed = false
                return kAudioFileStreamError_DataUnavailable
            }
                        
            let readBytes = audioBuffer.read(into: buffer, preferredSize: requestedBytes)
            unsafeAudioBufferList[0].mDataByteSize = UInt32(readBytes)
            
            return noErr
        }
        
        return sourceNode
    }
    
    public func start() {
        muteMonitor.startMonitoring { [weak self] (isMuted) in
            guard let self = self else { return }
            self.isMuted = isMuted
        }
        
        do {
            try AVAudioSession.sharedInstance().setManicEmuCategory()
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.005)
            
            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
            
            try AVAudioSession.sharedInstance().setActive(true)
        }
        catch {
            print(error)
        }
        
        resetAudioEngine()
    }
    
    public func stop() {
        muteMonitor.stopMonitoring()
        
        renderingQueue.sync { [weak self] in
            guard let self = self else { return }
            self.audioPlayerNode.stop()
            self.audioEngine.stop()
        }
        
        audioBuffer.isEnabled = false
    }
}
