import AppKit
import QuartzCore

// MARK: - 来访宠物窗口
class VisitorPetWindow {
    private var window: PetWindow?
    private var petLayer: CALayer?
    private var bubbleWindow: BubbleWindow?
    private var walkTimer: Timer?
    private var idleTimer: Timer?
    private let petSize: CGFloat = 64

    private(set) var isActive = false

    /// 创建来访宠物，传入 64x64 缩略图数据
    func showVisitor(thumbnailData: Data?, near hostWindow: NSWindow) {
        guard !isActive else { return }
        isActive = true

        guard let screen = NSScreen.main else { return }
        let winSize: CGFloat = 80 // 窗口略大于宠物
        let startX = screen.frame.maxX + 20 // 从屏幕右侧外开始
        let y = hostWindow.frame.origin.y

        // 创建窗口
        let win = PetWindow(contentRect: NSRect(x: startX, y: y, width: winSize, height: winSize))
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: winSize, height: winSize))
        contentView.wantsLayer = true

        // 宠物图层
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer.magnificationFilter = .trilinear
        let x = (winSize - petSize) / 2
        layer.frame = NSRect(x: x, y: 0, width: petSize, height: petSize)

        // 加载缩略图
        if let data = thumbnailData, let image = NSImage(data: data),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            layer.contents = cgImage
        } else {
            // 使用默认来访宠物图像
            layer.contents = createDefaultVisitorImage()
        }

        contentView.layer?.addSublayer(layer)
        win.contentView = contentView
        // 面朝左（走向主人）
        layer.transform = CATransform3DMakeScale(-1, 1, 1)
        win.orderFrontRegardless()

        self.window = win
        self.petLayer = layer
        self.bubbleWindow = BubbleWindow()

        // 入场动画：走到主人宠物旁边
        let targetX = hostWindow.frame.maxX + 10
        walkIn(to: targetX)
    }

    /// 显示对话气泡
    func showBubble(text: String, isDelivery: Bool = false) {
        guard let win = window else { return }
        let duration: TimeInterval = isDelivery ? 8 : 4.5
        bubbleWindow?.show(text: text, above: win, duration: duration, isDelivery: isDelivery)
    }

    /// 离场动画，完成后移除
    func dismiss(completion: (() -> Void)? = nil) {
        guard isActive, let win = window else {
            completion?()
            return
        }

        // 翻转朝右（走出去）
        petLayer?.transform = CATransform3DIdentity

        // 添加走路动画
        applyWalkAnimation()

        guard let screen = NSScreen.main else {
            cleanup()
            completion?()
            return
        }

        let targetX = screen.frame.maxX + 20
        let startX = win.frame.origin.x
        let distance = targetX - startX
        let duration: TimeInterval = Double(distance) / 120.0 // 每秒120点

        let steps = Int(duration * 60)
        let stepX = distance / CGFloat(steps)
        var step = 0

        walkTimer?.invalidate()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] timer in
            guard let self = self, let win = self.window else {
                timer.invalidate()
                completion?()
                return
            }
            step += 1
            var frame = win.frame
            frame.origin.x += stepX
            win.setFrameOrigin(frame.origin)

            if step >= steps {
                timer.invalidate()
                self.cleanup()
                completion?()
            }
        }
    }

    func cleanup() {
        walkTimer?.invalidate()
        walkTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        bubbleWindow?.hideBubble()
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
        window?.orderOut(nil)
        window = nil
        petLayer = nil
        isActive = false
    }

    // MARK: - 动画

    private func walkIn(to targetX: CGFloat) {
        guard let win = window else { return }

        applyWalkAnimation()

        let startX = win.frame.origin.x
        let distance = startX - targetX
        let duration: TimeInterval = Double(distance) / 120.0
        let steps = max(1, Int(duration * 60))
        let stepX = distance / CGFloat(steps)
        var step = 0

        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] timer in
            guard let self = self, let win = self.window else {
                timer.invalidate()
                return
            }
            step += 1
            var frame = win.frame
            frame.origin.x -= stepX
            win.setFrameOrigin(frame.origin)

            if step >= steps {
                timer.invalidate()
                self.stopWalkAnimation()
                self.applyIdleAnimation()
            }
        }
    }

    private func applyWalkAnimation() {
        guard let layer = petLayer else { return }
        // 上下颠簸
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = -2
        bounce.toValue = 2
        bounce.duration = 0.25
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bounce, forKey: "visitorWalk")
    }

    private func stopWalkAnimation() {
        petLayer?.removeAnimation(forKey: "visitorWalk")
    }

    private func applyIdleAnimation() {
        guard let layer = petLayer else { return }
        // 呼吸浮动
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = -2
        anim.toValue = 2
        anim.duration = 1.5
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "visitorIdle")
    }

    /// 默认来访宠物图像（简单的圆形头像）
    private func createDefaultVisitorImage() -> CGImage? {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            // 蓝色圆形身体
            NSColor.systemBlue.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 4, width: 48, height: 40)).fill()

            // 眼睛
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18, y: 20, width: 10, height: 12)).fill()
            NSBezierPath(ovalIn: NSRect(x: 36, y: 20, width: 10, height: 12)).fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 21, y: 24, width: 5, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 39, y: 24, width: 5, height: 6)).fill()

            // 微笑
            NSColor.black.setStroke()
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 24, y: 14))
            mouth.curve(to: NSPoint(x: 40, y: 14),
                       controlPoint1: NSPoint(x: 28, y: 8),
                       controlPoint2: NSPoint(x: 36, y: 8))
            mouth.lineWidth = 1.5
            mouth.stroke()

            // 耳朵
            NSColor.systemBlue.withAlphaComponent(0.7).setFill()
            let leftEar = NSBezierPath()
            leftEar.move(to: NSPoint(x: 14, y: 38))
            leftEar.line(to: NSPoint(x: 8, y: 56))
            leftEar.line(to: NSPoint(x: 24, y: 42))
            leftEar.close()
            leftEar.fill()
            let rightEar = NSBezierPath()
            rightEar.move(to: NSPoint(x: 50, y: 38))
            rightEar.line(to: NSPoint(x: 56, y: 56))
            rightEar.line(to: NSPoint(x: 40, y: 42))
            rightEar.close()
            rightEar.fill()

            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
