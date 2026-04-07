import AppKit
import QuartzCore

// MARK: - PetViewDelegate
protocol PetViewDelegate: AnyObject {
    func petDidStartDrag()
    func petDidEndDrag()
    func petDidHover(_ hovering: Bool)
}

// MARK: - PetView
class PetView: NSView {
    var facingLeft = false
    var isDragging = false
    var dragOffset = NSPoint.zero
    var isHovering = false
    var petLayer: CALayer!
    var animationManager: AnimationManager!
    private var trackingArea: NSTrackingArea?
    weak var delegate: PetViewDelegate?

    // 双击检测
    private var lastClickTime: Date?
    private let doubleClickInterval: TimeInterval = 0.3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        petLayer = CALayer()
        petLayer.contentsGravity = .resizeAspect
        petLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        petLayer.magnificationFilter = .nearest  // 像素画默认锐利缩放
        layer?.addSublayer(petLayer)
        // 初始状态用 idle 尺寸，居中在窗口底部
        setLayerSize(PetConfig.size)

        animationManager = AnimationManager()
        animationManager.start { [weak self] image, needsFlip in
            self?.updateImage(image, needsFlip: needsFlip)
        }

        setupTrackingArea()
    }

    func setLayerSize(_ size: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = (bounds.width - size) / 2
        petLayer.frame = NSRect(x: x, y: 0, width: size, height: size)
        CATransaction.commit()
    }

    func switchState(_ state: PetState, layerSize: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x = (bounds.width - layerSize) / 2
        petLayer.frame = NSRect(x: x, y: 0, width: layerSize, height: layerSize)
        setState(state)
        CATransaction.commit()
    }

    private func setupTrackingArea() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        setupTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        window?.makeKey()  // 激活窗口，确保点击能立即响应
        delegate?.petDidHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isDragging {
            delegate?.petDidHover(false)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateImage(_ image: CGImage, needsFlip: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        petLayer.contents = image
        if needsFlip {
            petLayer.transform = facingLeft ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        }
        CATransaction.commit()
    }

    func setFacingLeft(_ left: Bool) {
        facingLeft = left
        petLayer.transform = left ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    var isCustomMode = false {
        didSet {
            // 像素画用锐利缩放，自定义高清图用平滑缩放
            petLayer.magnificationFilter = isCustomMode ? .trilinear : .nearest
        }
    }

    func setState(_ state: PetState) {
        let oldState = animationManager.currentState
        animationManager.setState(state)
        if isCustomMode && state != oldState {
            applyCustomAnimation(for: state)
        }
    }

    func applyCustomAnimation(for state: PetState) {
        petLayer.removeAnimation(forKey: "customIdle")
        petLayer.removeAnimation(forKey: "customWalkBounce")
        petLayer.removeAnimation(forKey: "customWalkRock")
        petLayer.removeAnimation(forKey: "customWorking")
        petLayer.removeAnimation(forKey: "customWorkingPulse")

        switch state {
        case .idle:
            // 呼吸浮动
            let anim = CABasicAnimation(keyPath: "transform.translation.y")
            anim.fromValue = -2
            anim.toValue = 2
            anim.duration = 1.5
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petLayer.add(anim, forKey: "customIdle")

        case .walk:
            // 上下颠簸
            let bounce = CABasicAnimation(keyPath: "transform.translation.y")
            bounce.fromValue = -2
            bounce.toValue = 2
            bounce.duration = 0.25
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petLayer.add(bounce, forKey: "customWalkBounce")
            // 左右摇晃
            let rock = CABasicAnimation(keyPath: "transform.rotation.z")
            rock.fromValue = -0.08  // ~5°
            rock.toValue = 0.08
            rock.duration = 0.5
            rock.autoreverses = true
            rock.repeatCount = .infinity
            rock.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petLayer.add(rock, forKey: "customWalkRock")

        case .working:
            if SettingsManager.shared.workingEffect == 1 {
                // 转圈圈（绕 Y 轴里外翻转）
                var perspective = CATransform3DIdentity
                perspective.m34 = -1.0 / 300.0
                petLayer.sublayerTransform = perspective
                let spin = CABasicAnimation(keyPath: "transform.rotation.y")
                spin.fromValue = 0
                spin.toValue = CGFloat.pi * 2
                spin.duration = 0.8
                spin.repeatCount = .infinity
                spin.timingFunction = CAMediaTimingFunction(name: .linear)
                petLayer.add(spin, forKey: "customWorking")
            } else {
                // 快速摇晃
                let rock = CABasicAnimation(keyPath: "transform.rotation.z")
                rock.fromValue = -0.08
                rock.toValue = 0.08
                rock.duration = 0.125
                rock.autoreverses = true
                rock.repeatCount = .infinity
                rock.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                petLayer.add(rock, forKey: "customWorking")
            }

        case .visiting:
            // 串门中：缓慢呼吸（半透明状态，暗示出门了）
            let anim = CABasicAnimation(keyPath: "transform.translation.y")
            anim.fromValue = -1
            anim.toValue = 1
            anim.duration = 2.0
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petLayer.add(anim, forKey: "customIdle")

        default:
            break
        }
    }

    func stopCustomAnimations() {
        petLayer.removeAnimation(forKey: "customIdle")
        petLayer.removeAnimation(forKey: "customWalkBounce")
        petLayer.removeAnimation(forKey: "customWalkRock")
        petLayer.removeAnimation(forKey: "customWorking")
        petLayer.removeAnimation(forKey: "customWorkingPulse")
    }

    override func mouseDown(with event: NSEvent) {
        // 检测双击
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < doubleClickInterval {
            // 双击：新建终端窗口
            lastClickTime = nil
            TerminalManager.shared.newWindow()
            return
        }
        lastClickTime = now

        isDragging = true
        dragOffset = event.locationInWindow
        if animationManager.currentState != .working {
            setState(.drag)
        }
        delegate?.petDidStartDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = window else { return }
        let screen = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: screen.x - dragOffset.x, y: screen.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        delegate?.petDidEndDrag()
        startFalling()
    }

    // 右键菜单（双指点击 / Ctrl+点击）
    override func rightMouseDown(with event: NSEvent) {
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return buildContextMenu()
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "DesktopPet")

        let chatItem = NSMenuItem(title: "对话", action: #selector(openChat), keyEquivalent: "")
        chatItem.target = self
        menu.addItem(chatItem)

        menu.addItem(NSMenuItem.separator())

        let friendItem = NSMenuItem(title: "好友...", action: #selector(openFriendPanel), keyEquivalent: "")
        friendItem.target = self
        menu.addItem(friendItem)

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 DesktopPet", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openChat() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openChat()
        }
    }

    @objc private func openFriendPanel() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openFriendPanel()
        }
    }

    @objc private func openSettings() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.settingsController.showSettings()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func startFalling() {
        guard let window = window, let screen = NSScreen.main else { return }
        let ground = screen.visibleFrame.minY
        if window.frame.minY <= ground {
            setState(.idle)
            return
        }

        setState(.fall)
        var velocity: CGFloat = 0
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] timer in
            velocity += 0.8
            var frame = window.frame
            frame.origin.y -= velocity
            if frame.origin.y <= ground {
                frame.origin.y = ground
                timer.invalidate()
                self?.setState(.idle)
            }
            window.setFrameOrigin(frame.origin)
        }
    }
}
