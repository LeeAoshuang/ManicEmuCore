//
//  ControllerView.swift
//  DeltaCore
//
//  Created by Riley Testut on 5/3/15.
//  Copyright (c) 2015 Riley Testut. All rights reserved.
//

import UIKit

private struct ControllerViewInputMapping: GameControllerInputMappingBase
{
    let controllerView: ControllerView
    
    var name: String {
        return self.controllerView.name
    }
    
    var gameControllerInputType: GameControllerInputType {
        return self.controllerView.inputType
    }
    
    func input(forControllerInput controllerInput: Input) -> Input?
    {
        guard let gameType = self.controllerView.controllerSkin?.gameType, let deltaCore = ManicEmu.core(for: gameType) else { return nil }
        
        if let gameInput = deltaCore.gameInputType.init(stringValue: controllerInput.stringValue)
        {
            return gameInput
        }
        
        if let standardInput = StandardGameControllerInput(stringValue: controllerInput.stringValue)
        {
            return standardInput
        }
        
        return nil
    }
}

extension ControllerView
{
    public static let controllerSkinDidChangeNotification = Notification.Name("controllerSkinDidChangeNotification")
    public static let didUpdateGameViewsNotification = Notification.Name("didUpdateGameViewsNotification")
    
    public enum NotificationKey: String
    {
        case addedGameViews
        case removedGameViews
    }
}

public class ControllerView: UIView, GameController
{
    //MARK: - Properties -
    /** Properties **/
    public var controllerSkin: ControllerSkinBase? {
        didSet {
            self.updateSkin()
            NotificationCenter.default.post(name: ControllerView.controllerSkinDidChangeNotification, object: self)
        }
    }
    
    public var controllerSkinTraits: ControllerSkin.Traits? {
        if let traits = self.customControllerSkinTraits
        {
            return traits
        }
        
        guard let window = self.window else { return nil }
        
        let traits = ControllerSkin.Traits.defaults(for: window)
        
        guard let controllerSkin = controllerSkin else { return traits }
        
        guard let supportedTraits = controllerSkin.supportedTraits(for: traits) else { return traits }
        return supportedTraits
    }

    public var controllerSkinSize: ControllerSkin.Size! {
        let size = customControllerSkinSize ?? UIScreen.main.defaultSkinSize
        return size
    }
    
    public var customControllerSkinTraits: ControllerSkin.Traits?
    public var customControllerSkinSize: ControllerSkin.Size?
    
    public var translucent: CGFloat = 0.7
    
    public var isButtonHaptic = true {
        didSet {
            buttonsView.isHapticEnabled = isButtonHaptic
        }
    }
    
    public var isThumbstickHaptic = true {
        didSet {
            thumbstickViews.values.forEach { $0.isHapticEnabled = isThumbstickHaptic }
        }
    }
    
    //添加震感的样式
    public var hapticFeedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = .soft {
        didSet {
            buttonsView.hapticFeedbackStyle = hapticFeedbackStyle
            thumbstickViews.values.forEach { $0.hapticFeedbackStyle = hapticFeedbackStyle }
        }
    }
    
    //MARK: - <GameControllerType>
    /// <GameControllerType>
    public var name: String {
        return controllerSkin?.name ?? NSLocalizedString("Game Controller", comment: "")
    }
    
    public var playerIndex: Int? {
        didSet {
            reloadInputViews()
        }
    }
    
    public let inputType: GameControllerInputType = .controllerSkin
    public lazy var defaultInputMapping: GameControllerInputMappingBase? = ControllerViewInputMapping(controllerView: self)
    
    internal weak var placementLayoutGuide: UILayoutGuide? {
        didSet {
            debugView.placementLayoutGuide = placementLayoutGuide
            buttonsDynamicEffectView.appPlacementLayoutGuide = placementLayoutGuide
        }
    }
    
    internal var isControllerInputView = false
    internal var gameViews: [GameView] {
        var sortedGameViews = gameViewsWithScreenID.lazy.sorted { $0.key < $1.key }.map { $0.value }
        
        if let controllerView = controllerInputView?.controllerView
        {
            // Include controllerInputView's gameViews, if there are any.
            let gameViews = controllerView.gameViews
            sortedGameViews.append(contentsOf: gameViews)
        }
        
        return sortedGameViews
    }
    private var gameViewsWithScreenID = [ControllerSkin.Screen.ID: GameView]()
    
    //MARK: - Private Properties
    private let contentView = UIView(frame: .zero)
    private var transitionSnapshot: UIView? = nil
    private let debugView = InputDebugView()
    private let buttonsDynamicEffectView = ButtonsDynamicEffectView()
    private let buttonsView = ButtonsInputView(frame: CGRect.zero)
    private var thumbstickViews = [ControllerSkin.Item.ID: ThumbstickInputView]()
    private var touchViews = [ControllerSkin.Item.ID: TouchInputView]()
    
    private var initialLayout = false
    private var delayedUpdatingSkin = false
    
    private var controllerInputView: ControllerInputView?
    
    private(set) var imageCache = NSCache<NSString, NSCache<NSString, UIImage>>()
    
    public override var intrinsicContentSize: CGSize {
        return buttonsView.intrinsicContentSize
    }
    
    private let keyboardResponder = KeyboardResponder(nextResponder: nil)
    
    //MARK: - Initializers -
    /** Initializers **/
    public override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        initialize()
    }
    
    private func initialize()
    {
        backgroundColor = UIColor.clear
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        buttonsView.activateHandler = { [weak self] (inputs) in
            guard let self = self else { return }
            self.activateButtonInputs(inputs)
        }
        buttonsView.deactivateHandler = { [weak self] (inputs) in
            guard let self = self else { return }
            self.deactivateInputs(inputs)
        }
        contentView.addSubview(buttonsView)
        
        buttonsDynamicEffectView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonsDynamicEffectView)
        
        debugView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(debugView)
        
        isMultipleTouchEnabled = true
        
        // Remove shortcuts from shortcuts bar so it doesn't appear when using external keyboard as input.
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        
        NotificationCenter.default.addObserver(self, selector: #selector(ControllerView.keyboardDidDisconnect(_:)), name: .externalKeyboardDidDisconnect, object: nil)
        
        setContraint()
    }
    
    func setContraint() {
        NSLayoutConstraint.activate([contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     contentView.topAnchor.constraint(equalTo: topAnchor),
                                     contentView.bottomAnchor.constraint(equalTo: bottomAnchor)])
        
        NSLayoutConstraint.activate([buttonsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                                     buttonsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                                     buttonsView.topAnchor.constraint(equalTo: contentView.topAnchor),
                                     buttonsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        
        NSLayoutConstraint.activate([buttonsDynamicEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                                     buttonsDynamicEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                                     buttonsDynamicEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                                     buttonsDynamicEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        
        NSLayoutConstraint.activate([debugView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                                     debugView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                                     debugView.topAnchor.constraint(equalTo: contentView.topAnchor),
                                     debugView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
    }
    
    //MARK: - UIView
    /// UIView
    public override func layoutSubviews()
    {
        debugView.setNeedsLayout()
        buttonsDynamicEffectView.setNeedsLayout()
        
        super.layoutSubviews()
        
        initialLayout = true
        
        guard !delayedUpdatingSkin else {
            delayedUpdatingSkin = false
            updateSkin()
            return
        }
        
        // updateControllerSkin() calls layoutSubviews(), so don't call again to avoid infinite loop.
        // self.updateControllerSkin()
        
        guard let traits = controllerSkinTraits, let controllerSkin = controllerSkin, let items = controllerSkin.items(for: traits) else { return }
        
        for item in items
        {
            var containingFrame = self.bounds
            if let layoutGuide = placementLayoutGuide, item.placement == .app
            {
                containingFrame = layoutGuide.layoutFrame
            }
            
            let frame = item.frame.scaled(to: containingFrame)
            
            switch item.kind
            {
            case .button, .dPad: break
            case .thumbstick:
                guard let thumbstickView = thumbstickViews[item.id] else { continue }
                thumbstickView.frame = frame
                
                if thumbstickView.thumbstickSize == nil, let (image, size) = controllerSkin.thumbstick(for: item, traits: traits, preferredSize: controllerSkinSize)
                {
                    // Update thumbstick in first layoutSubviews() post-updateControllerSkin() to ensure correct size.
                    
                    let size = CGSize(width: size.width * self.bounds.width, height: size.height * self.bounds.height)
                    thumbstickView.thumbstickImage = image
                    thumbstickView.thumbstickSize = size
                }
                
            case .touchScreen:
                guard let touchView = touchViews[item.id] else { continue }
                touchView.frame = frame
            }
        }
        
        if let screens = controllerSkin.screens(for: traits)
        {
            for screen in screens where screen.placement == .controller
            {
                guard let normalizedFrame = screen.outputFrame, let gameView = gameViewsWithScreenID[screen.id] else { continue }
                
                let frame = normalizedFrame.scaled(to: bounds)
                gameView.frame = frame
            }
        }
    }
    
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView?
    {
        if !isUserInteractionEnabled {
            return nil
        }
        guard bounds.contains(point) else { return super.hitTest(point, with: event) }
        
        for (_, thumbstickView) in thumbstickViews
        {
            guard thumbstickView.frame.contains(point) else { continue }
            return thumbstickView
        }

        for (_, touchView) in touchViews
        {
            guard touchView.frame.contains(point) else { continue }

            if let inputs = buttonsView.inputs(at: point)
            {
                // No other inputs at this position, so return touchView.
                if inputs.isEmpty
                {
                    return touchView
                }
            }
        }
        
        return buttonsView
    }
    
    //MARK: - <UITraitEnvironment>
    /// <UITraitEnvironment>
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        
        self.setNeedsLayout()
    }
    
    public override var canBecomeFirstResponder: Bool {
        // "canBecomeFirstResponder" = "should display keyboard controller view" OR "should receive hardware keyboard events"
        // In latter case, we return a nil inputView to prevent software keyboard from appearing.
        
        guard let controllerSkin = controllerSkin, let traits = controllerSkinTraits else { return false }
        
        if let keyboardController = ExternalGameControllerUtils.shared.keyboardController, keyboardController.playerIndex != nil
        {
            // Keyboard is connected and has non-nil player index, so return true to receive keyboard presses.
            return true
        }
        
        guard !(controllerSkin is TouchControllerSkin) else {
            // Unless keyboard is connected, we never want to become first responder with
            // TouchControllerSkin because that will make the software keyboard appear.
            return false
        }
        
        guard playerIndex != nil else {
            // Only show keyboard controller if we've been assigned a playerIndex.
            return false
        }
        
        // Finally, only show keyboard controller if we're in Split View and the controller skin supports it.
        let canBecomeFirstResponder = traits.displayType == .splitView && controllerSkin.supports(traits)
        return canBecomeFirstResponder
    }
    
    public override var next: UIResponder? {
        if #available(iOS 15, *)
        {
            return super.next
        }
        else
        {
            return KeyboardResponder(nextResponder: super.next)
        }
    }
    
    public override var inputView: UIView? {
        if let keyboardController = ExternalGameControllerUtils.shared.keyboardController, keyboardController.playerIndex != nil
        {
            // Don't display any inputView if keyboard is connected and has non-nil player index.
            return nil
        }
        
        return self.controllerInputView
    }
    
    @discardableResult public override func becomeFirstResponder() -> Bool
    {
        guard super.becomeFirstResponder() else { return false }
        
        self.reloadInputViews()
        
        return self.isFirstResponder
    }
    
    internal override func _keyCommand(for event: UIEvent, target: UnsafeMutablePointer<UIResponder>) -> UIKeyCommand?
    {
        let keyCommand = super._keyCommand(for: event, target: target)
        
        if #available(iOS 15, *)
        {
            _ = keyboardResponder._keyCommand(for: event, target: target)
        }
        
        return keyCommand
    }
    
    public func beginUpdateSkin()
    {
        guard self.transitionSnapshot == nil else { return }
        
        guard let transitionSnapshotView = self.contentView.snapshotView(afterScreenUpdates: false) else { return }
        transitionSnapshotView.frame = self.contentView.frame
        transitionSnapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        transitionSnapshotView.alpha = self.contentView.alpha
        self.addSubview(transitionSnapshotView)
        
        self.transitionSnapshot = transitionSnapshotView
        
        self.contentView.alpha = 0.0
    }
    
    public func updateSkin()
    {
        guard initialLayout else {
            delayedUpdatingSkin = true
            return
        }

        if let isDebugModeEnabled = controllerSkin?.isDebugMode
        {
            debugView.isHidden = !isDebugModeEnabled
        }
        
        var isTranslucent = false
        
        if let traits = controllerSkinTraits
        {
            var items = controllerSkin?.items(for: traits)
       
            if traits.displayType == .splitView
            {
                if isControllerInputView
                {
                    // Filter out all items without `controller` placement.
                    items = items?.filter { $0.placement == .controller }
                }
                else
                {
                    // Filter out all items without `app` placement.
                    items = items?.filter { $0.placement == .app }
                }
            }
            
            if traits.displayType == .splitView && !isControllerInputView
            {
                buttonsView.image = nil
            }
            else
            {
                let image: UIImage?
                
                if let controllerSkin = controllerSkin
                {
                    let cacheKey = String(describing: traits) + "-" + String(describing: controllerSkinSize)
                    
                    if
                        let cache = imageCache.object(forKey: controllerSkin.identifier as NSString),
                        let cachedImage = cache.object(forKey: cacheKey as NSString)
                    {
                        image = cachedImage
                    }
                    else
                    {
                        image = controllerSkin.image(for: traits, preferredSize: controllerSkinSize)
                    }
                    
                    if let image = image
                    {
                        let cache = imageCache.object(forKey: controllerSkin.identifier as NSString) ?? NSCache<NSString, UIImage>()
                        cache.setObject(image, forKey: cacheKey as NSString)
                        imageCache.setObject(cache, forKey: controllerSkin.identifier as NSString)
                    }
                }
                else
                {
                    image = nil
                }
                
                buttonsView.image = image
            }
            
            buttonsView.items = items
            debugView.items = items
            buttonsDynamicEffectView.items = items
            if let skin = controllerSkin as? ControllerSkin {
                buttonsDynamicEffectView.archive = skin.archive
            }
            
            isTranslucent = controllerSkin?.isTranslucent(for: traits) ?? false
            
            var thumbstickViews = [ControllerSkin.Item.ID: ThumbstickInputView]()
            var previousThumbstickViews = self.thumbstickViews
            
            var touchViews = [ControllerSkin.Item.ID: TouchInputView]()
            var previousTouchViews = self.touchViews
            
            for item in items ?? []
            {
                switch item.kind
                {
                case .button, .dPad: break
                case .thumbstick:
                    let thumbstickView: ThumbstickInputView
                    
                    if let previousThumbstickView = previousThumbstickViews[item.id]
                    {
                        thumbstickView = previousThumbstickView
                        previousThumbstickViews[item.id] = nil
                    }
                    else
                    {
                        thumbstickView = ThumbstickInputView(frame: .zero)
                        contentView.addSubview(thumbstickView)
                    }
                    
                    thumbstickView.valueChangedHandler = { [weak self] (xAxis, yAxis) in
                        guard let self = self else { return }
                        self.updateThumbstick(item: item, xAxis: xAxis, yAxis: yAxis)
                    }
                    
                    // Calculate correct `thumbstickSize` in layoutSubviews().
                    thumbstickView.thumbstickSize = nil
                    
                    thumbstickView.isHapticEnabled = isThumbstickHaptic
                    
                    thumbstickViews[item.id] = thumbstickView
                    
                case .touchScreen:
                    let touchView: TouchInputView
                    
                    if let previousTouchView = previousTouchViews[item.id]
                    {
                        touchView = previousTouchView
                        previousTouchViews[item.id] = nil
                    }
                    else
                    {
                        touchView = TouchInputView(frame: .zero)
                        contentView.addSubview(touchView)
                    }
                    
                    touchView.valueChangedHandler = { [weak self] (point) in
                        guard let self = self else { return }
                        self.updateTouch(item: item, point: point)
                    }
                    
                    touchViews[item.id] = touchView
                }
            }
            
            previousThumbstickViews.values.forEach { $0.removeFromSuperview() }
            self.thumbstickViews = thumbstickViews
            
            previousTouchViews.values.forEach { $0.removeFromSuperview() }
            self.touchViews = touchViews
        }
        else
        {
            buttonsView.items = nil
            debugView.items = nil
            
            thumbstickViews.values.forEach { $0.removeFromSuperview() }
            thumbstickViews = [:]
            
            touchViews.values.forEach { $0.removeFromSuperview() }
            touchViews = [:]
        }
        
        updateGameViews()
        
        if transitionSnapshot != nil
        {
            // Wrap in an animation closure to ensure it actually animates correctly
            // As of iOS 8.3, calling this within transition coordinator animation closure without wrapping
            // in this animation closure causes the change to be instantaneous
            UIView.animate(withDuration: 0.0) {
                self.contentView.alpha = isTranslucent ? self.translucent : 1.0
            }
        }
        else
        {
            contentView.alpha = isTranslucent ? translucent : 1.0
        }
        
        transitionSnapshot?.alpha = 0.0
        
        if controllerSkinTraits?.displayType == .splitView
        {
            presentInputView()
        }
        else
        {
            dismissInputView()
        }
        
        invalidateIntrinsicContentSize()
        setNeedsUpdateConstraints()
        setNeedsLayout()
        
        reloadInputViews()
    }
    
    public func updateGameViews()
    {
        guard isControllerInputView else { return }
        
        var previousGameViews = gameViewsWithScreenID
        var gameViews = [ControllerSkin.Screen.ID: GameView]()
        
        if let controllerSkin = controllerSkin,
           let traits = controllerSkinTraits,
           let screens = controllerSkin.screens(for: traits)
        {
            for screen in screens where screen.placement == .controller
            {
                // Only manage screens with explicit outputFrames.
                guard screen.outputFrame != nil else { continue }
                
                let gameView = previousGameViews[screen.id] ?? GameView(frame: .zero)
                gameView.update(for: screen)

                previousGameViews[screen.id] = nil
                gameViews[screen.id] = gameView
            }
        }
        else
        {
            for (_, gameView) in previousGameViews
            {
                gameView.filter = nil
            }
            
            gameViews = [:]
        }
        
        var addedGameViews = Set<GameView>()
        var removedGameViews = Set<GameView>()
        
        // Sort them in controller skin order, so that early screens can be covered by later ones.
        let sortedGameViews = gameViews.lazy.sorted { $0.key < $1.key }.map { $0.value }
        for gameView in sortedGameViews
        {
            guard !gameViewsWithScreenID.values.contains(gameView) else { continue }
            
            contentView.insertSubview(gameView, belowSubview: buttonsView)
            addedGameViews.insert(gameView)
        }
        
        for gameView in previousGameViews.values
        {
            gameView.removeFromSuperview()
            removedGameViews.insert(gameView)
        }
        
        gameViewsWithScreenID = gameViews
        
        // Use destination controllerView as Notification object, since that is what client expects.
        let controllerView = receivers.lazy.compactMap { $0 as? ControllerView }.first ?? self
        
        NotificationCenter.default.post(name: ControllerView.didUpdateGameViewsNotification, object: controllerView, userInfo: [
            ControllerView.NotificationKey.addedGameViews: addedGameViews,
            ControllerView.NotificationKey.removedGameViews: removedGameViews
        ])
    }
    
    public func finishUpdateSkin()
    {
        if let transitionImageView = transitionSnapshot
        {
            transitionImageView.removeFromSuperview()
            transitionSnapshot = nil
        }
        
        if let traits = controllerSkinTraits, let isTranslucent = controllerSkin?.isTranslucent(for: traits), isTranslucent
        {
            contentView.alpha = translucent
        }
        else
        {
            contentView.alpha = 1.0
        }
    }
    
    func presentInputView()
    {
        guard !isControllerInputView else { return }

        guard let controllerSkin = controllerSkin, let traits = controllerSkinTraits else { return }

        if self.controllerInputView == nil
        {
            let inputControllerView = ControllerInputView(frame: CGRect(x: 0, y: 0, width: 1024, height: 300))
            inputControllerView.controllerView.addReceiver(self, inputMapping: nil)
            controllerInputView = inputControllerView
        }

        if controllerSkin.supports(traits)
        {
            controllerInputView?.controllerView.controllerSkin = controllerSkin
        }
        else
        {
            controllerInputView?.controllerView.controllerSkin = ControllerSkin.standardControllerSkin(for: controllerSkin.gameType)
        }
    }
    
    func dismissInputView()
    {
        guard !isControllerInputView else { return }
        
        guard controllerInputView != nil else { return }
        
        controllerInputView = nil
    }
    
    func activateButtonInputs(_ inputs: Set<SomeInput>)
    {
        for input in inputs
        {
            activate(input)
            buttonsDynamicEffectView.activateButtonEffect(input: input)
        }
    }
    
    func deactivateInputs(_ inputs: Set<SomeInput>)
    {
        for input in inputs
        {
            deactivate(input)
            buttonsDynamicEffectView.deactivateButtonEffect(input: input)
        }
    }
    
    func updateThumbstick(item: ControllerSkin.Item, xAxis: Double, yAxis: Double)
    {
        guard case .directional(let up, let down, let left, let right) = item.inputs else { return }
        
        switch xAxis
        {
        case ..<0:
            activate(left, value: -xAxis)
            deactivate(right)
            
        case 0:
            deactivate(left)
            deactivate(right)
            
        default:
            deactivate(left)
            activate(right, value: xAxis)
        }
        
        switch yAxis
        {
        case ..<0:
            activate(down, value: -yAxis)
            deactivate(up)
            
        case 0:
            deactivate(down)
            deactivate(up)
            
        default:
            deactivate(down)
            activate(up, value: yAxis)
        }
    }
    
    func updateTouch(item: ControllerSkin.Item, point: CGPoint?)
    {
        guard case .touch(let x, let y) = item.inputs else { return }
        
        if let point = point
        {
            activate(x, value: Double(point.x))
            activate(y, value: Double(point.y))
        }
        else
        {
            deactivate(x)
            deactivate(y)
        }
    }
    
    @objc func keyboardDidDisconnect(_ notification: Notification)
    {
        guard self.isFirstResponder else { return }
        
        self.resignFirstResponder()
        
        if canBecomeFirstResponder
        {
            becomeFirstResponder()
        }
    }
}

//MARK: - GameControllerReceiver -
/// GameControllerReceiver
extension ControllerView: ControllerReceiverProtocol
{
    public func gameController(_ gameController: GameController, didActivate input: Input, value: Double)
    {
        guard gameController == controllerInputView?.controllerView else { return }
        
        activate(input, value: value)
    }
    
    public func gameController(_ gameController: GameController, didDeactivate input: Input)
    {
        guard gameController == controllerInputView?.controllerView else { return }
        
        deactivate(input)
    }
}

//MARK: - UIKeyInput
/// UIKeyInput
// Becoming first responder doesn't steal keyboard focus from other apps in split view unless the first responder conforms to UIKeyInput.
// So, we conform ControllerView to UIKeyInput and provide stub method implementations.
extension ControllerView: UIKeyInput
{
    public var hasText: Bool {
        return false
    }
    
    public func insertText(_ text: String)
    {
    }
    
    public func deleteBackward()
    {
    }
}
