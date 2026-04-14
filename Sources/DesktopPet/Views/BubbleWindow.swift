import AppKit
import QuartzCore

// MARK: - 气泡窗口（暖色调设计）
class BubbleWindow: NSWindow {
    private var textField: NSTextField!
    private var hideTimer: Timer?
    private weak var followingWindow: NSWindow?
    private(set) var isShowingDelivery = false  // 带话气泡期间不被普通气泡打断
    private var showGeneration: Int = 0  // 防止异步 hide 关掉新气泡

    // 阴影需要额外空间，窗口比气泡本体大一圈
    private let shadowPad: CGFloat = 14
    private let bubbleH: CGFloat = 32

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
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

    /// isDelivery: 带话样式（深暖棕背景、支持换行）
    func show(text: String, above petWindow: NSWindow, duration: TimeInterval = 4.5, isDelivery: Bool = false) {
        // 带话气泡期间，普通气泡不能打断
        if isShowingDelivery && !isDelivery { return }

        // 强制清理上一次状态（取消动画中的 hide）
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
        }
        if let oldParent = followingWindow {
            oldParent.removeChildWindow(self)
        }
        alphaValue = 0

        showGeneration += 1
        isShowingDelivery = isDelivery
        followingWindow = petWindow

        let font = textField.font ?? NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxTextW: CGFloat = isDelivery ? 220 : CGFloat.greatestFiniteMagnitude
        let maxLines = isDelivery ? 5 : 1

        // 带话模式：支持换行
        textField.maximumNumberOfLines = maxLines
        textField.lineBreakMode = isDelivery ? .byWordWrapping : .byClipping
        textField.cell?.wraps = isDelivery
        textField.textColor = isDelivery ? NSColor.white : DT.textPrimary
        textField.stringValue = text

        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: maxTextW, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )

        let bodyW = ceil(textSize.width) + 48
        let bodyH = isDelivery ? max(bubbleH, ceil(textSize.height) + 20) : bubbleH
        let cornerRadius = isDelivery ? min(bodyH / 2, 16) : bodyH / 2
        let pad = shadowPad
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
            bg.cornerRadius = cornerRadius
            bg.masksToBounds = false
            if isDelivery {
                // 深暖棕色背景
                bg.backgroundColor = NSColor(red: 0x8B/255, green: 0x6E/255, blue: 0x55/255, alpha: 1).cgColor
                bg.borderWidth = 0
            } else {
                bg.backgroundColor = NSColor(red: 0xFD/255, green: 0xFA/255, blue: 0xF6/255, alpha: 1).cgColor
                bg.borderWidth = 0.5
                bg.borderColor = DT.borderDefault.cgColor
            }
            bg.shadowColor = NSColor(red: 0.25, green: 0.20, blue: 0.15, alpha: 1).cgColor
            bg.shadowOffset = .zero
            bg.shadowRadius = 8
            bg.shadowOpacity = isDelivery ? 0.25 : 0.15
            container.layer?.insertSublayer(bg, at: 0)
        }

        // 文字居中于气泡本体
        let textH = ceil(textSize.height)
        let textY = pad + (bodyH - textH) / 2
        textField.frame = NSRect(x: pad + 18, y: textY, width: bodyW - 36, height: textH)

        updatePosition()

        if let parent = followingWindow {
            parent.addChildWindow(self, ordered: .above)
        }

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 1
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
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

        var x = petFrame.midX - winW / 2
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
        isShowingDelivery = false
        let gen = showGeneration
        let parent = followingWindow
        followingWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: {
            // 如果在动画期间又调了 show()，不要关掉新气泡
            guard gen == self.showGeneration else { return }
            parent?.removeChildWindow(self)
            self.orderOut(nil)
        })
    }
}
