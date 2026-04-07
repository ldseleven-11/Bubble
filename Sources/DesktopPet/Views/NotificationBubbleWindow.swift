import AppKit
import QuartzCore

// MARK: - 钉钉通知气泡窗口
class NotificationBubbleWindow: NSWindow {
    private var textField: NSTextField!
    private var sourceLabel: NSTextField!
    private var timeLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var accentBar: CALayer!
    private var hideTimer: Timer?
    private var followTimer: Timer?
    private weak var followingWindow: NSWindow?

    /// 点击回调（旧版，保留兼容）
    var onTap: ((String) -> Void)?
    /// 点击回调（带上下文：sessionKey, scene, originalMessage, isError）
    var onTapWithContext: ((String, ChatScene, String?, Bool) -> Void)?
    private var currentSessionKey: String = ""
    private var currentScene: ChatScene = .myDirectChat
    private var currentOriginalMessage: String?
    private var currentIsError: Bool = false
    private var tappedCurrent = false

    /// 气泡自然消失且队列空时回调（非点击触发）
    var onAutoHideComplete: (() -> Void)?

    /// 通知队列
    private var queue: [(summary: String, sessionKey: String, isError: Bool, scene: ChatScene, originalMessage: String?)] = []
    private let maxQueue = 5
    private var isShowing = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 68),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = false  // 可点击

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 68))
        container.wantsLayer = true

        // 来源标签（如 "钉钉 · 产品群"）
        sourceLabel = NSTextField(labelWithString: "")
        sourceLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        sourceLabel.textColor = DT.textSecondary
        container.addSubview(sourceLabel)

        // 时间标签
        timeLabel = NSTextField(labelWithString: "")
        timeLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = DT.textTertiary
        timeLabel.alignment = .right
        container.addSubview(timeLabel)

        // 消息内容
        textField = NSTextField(labelWithString: "")
        textField.alignment = .left
        textField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        textField.textColor = DT.textPrimary
        textField.maximumNumberOfLines = 2
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        container.addSubview(textField)

        // 底部提示（"点击回复"）
        hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = DT.textTertiary
        container.addSubview(hintLabel)

        contentView = container
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        tappedCurrent = true
        if onTapWithContext != nil {
            onTapWithContext?(currentSessionKey, currentScene, currentOriginalMessage, currentIsError)
        } else {
            onTap?(currentSessionKey)
        }
        hideBubble()
    }

    // 鼠标悬停变手型
    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        // 悬停时暂停自动隐藏
        hideTimer?.invalidate()
        hideTimer = nil
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        // 鼠标移出后重新开始计时
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.hideBubble()
        }
    }

    // MARK: - 显示通知

    func showNotification(summary: String, sessionKey: String, isError: Bool, above petWindow: NSWindow,
                          scene: ChatScene = .myDirectChat, originalMessage: String? = nil) {
        NSLog("[NotifBubble] showNotification called: isShowing=%@ queueCount=%d summary=%@", isShowing ? "true" : "false", queue.count, String(summary.prefix(30)))
        if isShowing {
            // 正在显示，排队
            if queue.count < maxQueue {
                queue.append((summary: summary, sessionKey: sessionKey, isError: isError, scene: scene, originalMessage: originalMessage))
            }
            NSLog("[NotifBubble] queued (isShowing=true)")
            return
        }

        followingWindow = petWindow
        currentSessionKey = sessionKey
        currentScene = scene
        currentOriginalMessage = originalMessage
        currentIsError = isError
        isShowing = true

        textField.stringValue = summary
        textField.textColor = isError ? DT.error : DT.textPrimary

        // 来源和时间
        if isError {
            sourceLabel.stringValue = "系统消息"
            hintLabel.stringValue = "● 点击前往设置"
        } else {
            sourceLabel.stringValue = "钉钉通知"
            hintLabel.stringValue = "● 点击回复"
        }
        hintLabel.textColor = isError ? DT.error.withAlphaComponent(0.6) : DT.textTertiary

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.stringValue = formatter.string(from: Date())

        // 计算气泡大小
        let font = textField.font ?? NSFont.systemFont(ofSize: 12)
        let maxWidth: CGFloat = 280
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (summary as NSString).boundingRect(
            with: NSSize(width: maxWidth - 28, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )

        let bubbleWidth: CGFloat = min(max(ceil(textSize.width) + 40, 140), 320)
        let lineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading)
        let lineCount = min(max(Int(ceil(textSize.height / lineHeight)), 1), 2)
        let textH = CGFloat(lineCount) * lineHeight
        // header(16) + gap(4) + text + gap(6) + hint(12) + bottom(8) + top(10)
        let bubbleHeight: CGFloat = 10 + 14 + 6 + textH + 6 + 14 + 8

        setContentSize(NSSize(width: bubbleWidth, height: bubbleHeight))
        if let container = contentView {
            container.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
            // 清除旧的绘制层
            container.layer?.sublayers?.filter({ $0 is CAShapeLayer || $0.name == "accent" }).forEach({ $0.removeFromSuperlayer() })

            // 气泡背景（圆角矩形）
            let bgLayer = CAShapeLayer()
            let bgRect = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
            bgLayer.path = CGPath(roundedRect: bgRect, cornerWidth: DT.radiusLg, cornerHeight: DT.radiusLg, transform: nil)
            bgLayer.fillColor = DT.bgSurface.cgColor
            DT.applyShadowLg(to: bgLayer)
            container.layer?.insertSublayer(bgLayer, at: 0)

            // 左侧渐变色竖条
            let barH = bubbleHeight - 8
            let barLayer = CAGradientLayer()
            barLayer.name = "accent"
            barLayer.frame = NSRect(x: 0, y: 4, width: 3.5, height: barH)
            if isError {
                barLayer.colors = [DT.error.cgColor, NSColor(red: 0xD6/255, green: 0x36/255, blue: 0x36/255, alpha: 1).cgColor]
            } else {
                barLayer.colors = [DT.secondary.cgColor, NSColor(red: 0x3D/255, green: 0x8A/255, blue: 0xE8/255, alpha: 1).cgColor]
            }
            barLayer.startPoint = CGPoint(x: 0.5, y: 1)
            barLayer.endPoint = CGPoint(x: 0.5, y: 0)
            barLayer.cornerRadius = 1.75
            // 右侧圆角，左侧直角
            barLayer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            container.layer?.addSublayer(barLayer)
        }

        // 布局子视图
        let leftPad: CGFloat = 14
        let rightPad: CGFloat = 12

        sourceLabel.frame = NSRect(x: leftPad, y: bubbleHeight - 10 - 14, width: bubbleWidth * 0.6, height: 14)
        timeLabel.frame = NSRect(x: bubbleWidth * 0.6, y: bubbleHeight - 10 - 14, width: bubbleWidth * 0.4 - rightPad, height: 14)
        textField.frame = NSRect(x: leftPad, y: 8 + 14 + 6, width: bubbleWidth - leftPad - rightPad, height: textH)
        hintLabel.frame = NSRect(x: leftPad, y: 8, width: bubbleWidth - leftPad - rightPad, height: 14)

        // 添加鼠标追踪区域
        if let container = contentView {
            container.trackingAreas.forEach { container.removeTrackingArea($0) }
            let trackingArea = NSTrackingArea(
                rect: container.bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                owner: self,
                userInfo: nil
            )
            container.addTrackingArea(trackingArea)
        }

        // 定位（在普通气泡上方）
        updatePosition()

        // 淡入
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 1
        }

        // 跟随宠物
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }

        // 8秒后自动隐藏
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.hideBubble()
        }
    }

    private func updatePosition() {
        guard let petWindow = followingWindow,
              let screen = petWindow.screen ?? NSScreen.main else { return }
        let petFrame = petWindow.frame
        let visibleFrame = screen.visibleFrame
        let bubbleW = frame.width
        let bubbleH = frame.height

        var x = petFrame.midX - bubbleW / 2
        var y = petFrame.maxY - 15

        // 左右边界（留 4pt 间距）
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - bubbleW - 4))
        // 上边界：超出则放到宠物下方
        if y + bubbleH > visibleFrame.maxY {
            y = petFrame.minY - bubbleH - 4
        }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hideBubble() {
        NSLog("[NotifBubble] hideBubble called, tappedCurrent=%@", tappedCurrent ? "true" : "false")
        let wasTapped = tappedCurrent
        tappedCurrent = false

        hideTimer?.invalidate()
        hideTimer = nil
        followTimer?.invalidate()
        followTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.orderOut(nil)
            self.isShowing = false
            self.followingWindow = nil

            // 处理队列中的下一条
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                // 延迟一小段时间再弹下一条，避免视觉闪烁
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let petWindow = (NSApp.delegate as? AppDelegate)?.window else { return }
                    self.showNotification(summary: next.summary, sessionKey: next.sessionKey, isError: next.isError, above: petWindow,
                                          scene: next.scene, originalMessage: next.originalMessage)
                }
            } else if !wasTapped {
                // 非点击消失 + 队列空 → 通知流程结束
                self.onAutoHideComplete?()
            }
        })
    }
}
