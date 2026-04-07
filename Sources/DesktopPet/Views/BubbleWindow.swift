import AppKit
import QuartzCore

// MARK: - 气泡窗口（暖色调设计）
class BubbleWindow: NSWindow {
    private var textField: NSTextField!
    private var hideTimer: Timer?
    private weak var followingWindow: NSWindow?
    private var followTimer: Timer?

    // 阴影需要额外空间，窗口比气泡本体大一圈
    private let shadowPad: CGFloat = 14
    private let bubbleH: CGFloat = 32

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
        container.wantsLayer = true
        container.layer?.masksToBounds = false

        textField = NSTextField(labelWithString: "")
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textField.textColor = DT.textPrimary
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        textField.cell?.isScrollable = false
        textField.cell?.wraps = false
        container.addSubview(textField)

        contentView = container
    }

    func show(text: String, above petWindow: NSWindow) {
        followingWindow = petWindow
        textField.stringValue = text

        let font = textField.font ?? NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: 20),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )

        let bodyW = ceil(textSize.width) + 48
        let bodyH = bubbleH
        let pad = shadowPad
        // 窗口尺寸 = 气泡 + 四周阴影留白
        let winW = bodyW + pad * 2
        let winH = bodyH + pad * 2

        setContentSize(NSSize(width: winW, height: winH))

        if let container = contentView {
            container.frame = NSRect(x: 0, y: 0, width: winW, height: winH)
            container.layer?.masksToBounds = false

            // 移除旧背景
            container.layer?.sublayers?
                .filter { $0.name == "bubble" }
                .forEach { $0.removeFromSuperlayer() }

            let bg = CALayer()
            bg.name = "bubble"
            bg.frame = NSRect(x: pad, y: pad, width: bodyW, height: bodyH)
            bg.cornerRadius = bodyH / 2
            bg.masksToBounds = false
            bg.backgroundColor = NSColor(red: 0xFD/255, green: 0xFA/255, blue: 0xF6/255, alpha: 1).cgColor
            bg.borderWidth = 0.5
            bg.borderColor = DT.borderDefault.cgColor
            // 阴影：四周均匀扩散
            bg.shadowColor = NSColor(red: 0.25, green: 0.20, blue: 0.15, alpha: 1).cgColor
            bg.shadowOffset = .zero
            bg.shadowRadius = 8
            bg.shadowOpacity = 0.15
            container.layer?.insertSublayer(bg, at: 0)
        }

        // 文字居中于气泡本体
        let textH = ceil(textField.intrinsicContentSize.height)
        let textY = pad + (bodyH - textH) / 2
        textField.frame = NSRect(x: pad + 18, y: textY, width: bodyW - 36, height: textH)

        updatePosition()

        // 淡入
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 1
        }

        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            self?.hideBubble()
        }
    }

    private func updatePosition() {
        guard let petWindow = followingWindow,
              let screen = petWindow.screen ?? NSScreen.main else { return }
        let petFrame = petWindow.frame
        let visibleFrame = screen.visibleFrame
        let winW = frame.width
        let winH = frame.height
        let pad = shadowPad

        // 气泡本体中心对齐宠物中心，再减去左侧 padding
        var x = petFrame.midX - winW / 2
        // 气泡底边对齐宠物头顶（窗口上方约40%是透明区域）
        let petH = petFrame.height
        var y = petFrame.maxY - petH * 0.4 - pad

        x = max(visibleFrame.minX, min(x, visibleFrame.maxX - winW))
        if y + winH > visibleFrame.maxY {
            y = petFrame.minY - winH - 4 + pad
        }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hideBubble() {
        hideTimer?.invalidate()
        hideTimer = nil
        followTimer?.invalidate()
        followTimer = nil
        followingWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
