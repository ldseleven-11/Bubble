import AppKit
import QuartzCore

// MARK: - 可接收键盘输入的无边框面板
private class IMPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - 水平内边距 + 垂直居中的输入框 Cell
private class PaddedTextFieldCell: NSTextFieldCell {
    private let hPad: CGFloat = 10

    private func centeredRect(_ rect: NSRect) -> NSRect {
        let f = font ?? NSFont.systemFont(ofSize: 13)
        let textH = ceil(f.ascender - f.descender + f.leading) + 4
        var r = rect
        r.origin.x += hPad
        r.size.width -= hPad * 2
        if textH < r.height {
            r.origin.y += (r.height - textH) / 2
            r.size.height = textH
        }
        return r
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        return centeredRect(rect)
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centeredRect(cellFrame), in: controlView)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

// MARK: - IM 风格回复指令面板
class ReplyInputPanel: NSObject, NSTextFieldDelegate {
    static let shared = ReplyInputPanel()

    private var panel: IMPanel?
    private var closeButton: NSButton!
    private var headerTitleLabel: NSTextField!
    private var headerSubtitleLabel: NSTextField!
    private var bubbleLabel: NSTextField!
    private var inputField: NSTextField!
    private var confirmButton: NSButton!
    private var hintLabel: NSTextField!
    private var followTimer: Timer?

    private weak var petWindow: NSWindow?

    private var sessionKey: String = ""
    private var scene: ChatScene = .myDirectChat
    private var originalMessage: String?

    /// 发送消息回调（由 AppDelegate 注入具体实现）
    var onSendMessage: ((_ sessionKey: String, _ message: String,
                         _ completion: @escaping (Bool, String?) -> Void) -> Void)?

    /// 面板关闭且未发送时回调（用户 Esc / × 关闭）
    var onDismissWithoutSend: (() -> Void)?

    private var isSending = false

    /// 面板是否正在显示
    var isVisible: Bool { panel?.isVisible ?? false }

    // 布局常量
    private let panelWidth: CGFloat = 320
    private let panelPadding: CGFloat = 16
    private let bubbleInset: CGFloat = 12
    private let inputBarHeight: CGFloat = 44
    private let buttonWidth: CGFloat = 36
    private let elementSpacing: CGFloat = 8
    private let cardMargin: CGFloat = 8  // 白色卡片与窗口边缘的间距，给阴影留空间

    // MARK: - 显示面板

    func show(sessionKey: String, scene: ChatScene, originalMessage: String?, above petWindow: NSWindow) {
        self.sessionKey = sessionKey
        self.scene = scene
        self.originalMessage = originalMessage
        self.petWindow = petWindow

        if panel == nil {
            buildPanel()
        }

        // 更新头部副标题
        if let msg = originalMessage {
            headerSubtitleLabel.stringValue = "回复消息"
            let truncated = msg.count > 120 ? String(msg.prefix(120)) + "…" : msg
            bubbleLabel.stringValue = truncated
            bubbleLabel.maximumNumberOfLines = 4
        } else {
            // 无消息时显示最近对话历史
            headerSubtitleLabel.stringValue = "对话"
            let chats = DingTalkMonitor.shared.recentChats
            if chats.isEmpty {
                bubbleLabel.stringValue = "跟我说点什么吧~"
                bubbleLabel.maximumNumberOfLines = 4
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                var lines: [String] = []
                for chat in chats.reversed() {
                    let time = formatter.string(from: chat.timestamp)
                    let userText = chat.userMessage.count > 15
                        ? String(chat.userMessage.prefix(15)) + "…"
                        : chat.userMessage
                    let replyText = chat.agentReply.count > 25
                        ? String(chat.agentReply.prefix(25)) + "…"
                        : chat.agentReply
                    lines.append("[\(time)] 我：\(userText)")
                    lines.append("  → \(replyText)")
                }
                bubbleLabel.stringValue = lines.joined(separator: "\n")
                bubbleLabel.maximumNumberOfLines = 10
            }
        }

        // 重新布局（气泡高度自适应）
        layoutPanel()

        // 重置输入
        inputField.stringValue = ""
        updateConfirmButton(enabled: false)

        // 定位到宠物上方
        updatePosition()

        // 淡入
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.panel?.animator().alphaValue = 1
        }

        // 跟随宠物移动
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }

        // 聚焦输入框
        panel?.makeFirstResponder(inputField)
    }

    // MARK: - 构建 UI

    private func buildPanel() {
        let p = IMPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.onEscape = { [weak self] in self?.dismiss() }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 180))
        container.wantsLayer = true
        p.contentView = container

        // 头部标题
        headerTitleLabel = NSTextField(labelWithString: SettingsManager.shared.petName)
        headerTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        headerTitleLabel.textColor = DT.textPrimary
        headerTitleLabel.isEditable = false
        headerTitleLabel.isSelectable = false
        container.addSubview(headerTitleLabel)

        // 头部副标题
        headerSubtitleLabel = NSTextField(labelWithString: "对话")
        headerSubtitleLabel.font = NSFont.systemFont(ofSize: 11)
        headerSubtitleLabel.textColor = DT.textTertiary
        headerSubtitleLabel.isEditable = false
        headerSubtitleLabel.isSelectable = false
        container.addSubview(headerSubtitleLabel)

        // 关闭按钮（右上角 ×）
        closeButton = NSButton(frame: .zero)
        closeButton.isBordered = false
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: DT.textTertiary,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
        )
        closeButton.target = self
        closeButton.action = #selector(dismissClicked)
        container.addSubview(closeButton)

        // 气泡文字标签
        bubbleLabel = NSTextField(wrappingLabelWithString: "")
        bubbleLabel.font = NSFont.systemFont(ofSize: 12)
        bubbleLabel.textColor = DT.textPrimary
        bubbleLabel.maximumNumberOfLines = 4
        bubbleLabel.lineBreakMode = .byTruncatingTail
        bubbleLabel.backgroundColor = .clear
        bubbleLabel.isBezeled = false
        bubbleLabel.isEditable = false
        bubbleLabel.isSelectable = false
        container.addSubview(bubbleLabel)

        // 输入框（暖色调边框）
        inputField = NSTextField(frame: .zero)
        inputField.cell = PaddedTextFieldCell()
        inputField.isEditable = true
        inputField.isSelectable = true
        inputField.placeholderString = "输入消息..."
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.isBezeled = false
        inputField.isBordered = false
        inputField.focusRingType = .none
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = DT.radiusMd
        inputField.layer?.borderWidth = 1.5
        inputField.layer?.borderColor = DT.borderDefault.cgColor
        inputField.layer?.backgroundColor = DT.bgMuted.cgColor
        inputField.delegate = self
        container.addSubview(inputField)

        // 确认按钮（紧凑发送图标）
        confirmButton = NSButton(frame: .zero)
        confirmButton.isBordered = false
        confirmButton.wantsLayer = true
        confirmButton.layer?.cornerRadius = DT.radiusSm
        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked)
        updateConfirmButton(enabled: false)
        container.addSubview(confirmButton)

        // 底部提示
        hintLabel = NSTextField(labelWithString: "⏎ 发送  ·  Esc 关闭")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = DT.textTertiary
        hintLabel.alignment = .center
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        container.addSubview(hintLabel)

        self.panel = p
    }

    private func updateConfirmButton(enabled: Bool) {
        confirmButton.isEnabled = enabled
        confirmButton.layer?.backgroundColor = enabled
            ? DT.primary.cgColor
            : DT.borderDefault.cgColor

        let textColor: NSColor = enabled ? .white : DT.textTertiary
        confirmButton.attributedTitle = NSAttributedString(
            string: "↑",
            attributes: [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold)
            ]
        )
    }

    private func layoutPanel() {
        guard let container = panel?.contentView else { return }
        let m = cardMargin  // 卡片外边距

        // 计算气泡文字高度
        let bubbleTextWidth = panelWidth - panelPadding * 2 - bubbleInset * 2
        let font = bubbleLabel.font ?? NSFont.systemFont(ofSize: 12)
        let textSize = (bubbleLabel.stringValue as NSString).boundingRect(
            with: NSSize(width: bubbleTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxLines = CGFloat(bubbleLabel.maximumNumberOfLines)
        let maxTextHeight = lineHeight * maxLines
        let textHeight = min(ceil(textSize.height), maxTextHeight)
        let bubbleContentHeight = textHeight + bubbleInset * 2

        // header 高度
        let headerH: CGFloat = 40
        let hintH: CGFloat = 18

        // 卡片内容高度
        let cardHeight = headerH + bubbleContentHeight + 10 + inputBarHeight + 4 + hintH + 8
        // 窗口尺寸 = 卡片 + 外边距
        let windowW = panelWidth + m * 2
        let windowH = cardHeight + m * 2

        panel?.setContentSize(NSSize(width: windowW, height: windowH))
        container.frame = NSRect(x: 0, y: 0, width: windowW, height: windowH)

        // 清除旧层
        container.layer?.sublayers?.filter({ $0 is CAShapeLayer || $0.name == "bubbleBg" || $0.name == "headerSep" }).forEach({ $0.removeFromSuperlayer() })

        // 白色卡片背景（圆角 14px）
        let bgLayer = CAShapeLayer()
        bgLayer.path = CGPath(roundedRect: NSRect(x: m, y: m, width: panelWidth, height: cardHeight),
                              cornerWidth: DT.radiusLg, cornerHeight: DT.radiusLg, transform: nil)
        bgLayer.fillColor = DT.bgSurface.cgColor
        container.layer?.insertSublayer(bgLayer, at: 0)

        // 头部分隔线
        let sepLayer = CALayer()
        sepLayer.name = "headerSep"
        let sepY = m + cardHeight - headerH
        sepLayer.frame = NSRect(x: m, y: sepY, width: panelWidth, height: 1)
        sepLayer.backgroundColor = DT.borderLight.cgColor
        container.layer?.addSublayer(sepLayer)

        // 头部标题和副标题
        let headerTop = m + cardHeight - 8
        headerTitleLabel.stringValue = SettingsManager.shared.petName
        headerTitleLabel.frame = NSRect(
            x: m + panelPadding,
            y: headerTop - 18,
            width: panelWidth - panelPadding * 2 - 30,
            height: 18
        )
        headerSubtitleLabel.frame = NSRect(
            x: m + panelPadding,
            y: headerTop - 32,
            width: panelWidth - panelPadding * 2 - 30,
            height: 14
        )

        // 关闭按钮（卡片右上角）
        let closeBtnSize: CGFloat = 24
        closeButton.frame = NSRect(
            x: m + panelWidth - closeBtnSize - 10,
            y: headerTop - closeBtnSize + 2,
            width: closeBtnSize,
            height: closeBtnSize
        )

        // 气泡区域背景（暖灰色圆角）
        let bubbleY = sepY - 8 - bubbleContentHeight
        let bubbleW = panelWidth - panelPadding * 2

        let bubbleBgLayer = CAShapeLayer()
        bubbleBgLayer.name = "bubbleBg"
        bubbleBgLayer.path = CGPath(roundedRect: NSRect(x: m + panelPadding, y: bubbleY, width: bubbleW, height: bubbleContentHeight),
                                     cornerWidth: DT.radiusMd, cornerHeight: DT.radiusMd, transform: nil)
        bubbleBgLayer.fillColor = DT.bgMuted.cgColor
        container.layer?.addSublayer(bubbleBgLayer)

        // 气泡文字
        bubbleLabel.frame = NSRect(
            x: m + panelPadding + bubbleInset,
            y: bubbleY + bubbleInset,
            width: bubbleTextWidth,
            height: textHeight
        )

        // 输入栏（底部）
        let fieldHeight: CGFloat = 32
        let inputY = m + 8 + hintH + 4
        let inputWidth = panelWidth - panelPadding * 2 - buttonWidth - elementSpacing

        inputField.frame = NSRect(
            x: m + panelPadding,
            y: inputY + (inputBarHeight - fieldHeight) / 2,
            width: inputWidth,
            height: fieldHeight
        )

        confirmButton.frame = NSRect(
            x: m + panelWidth - panelPadding - buttonWidth,
            y: inputY + (inputBarHeight - fieldHeight) / 2,
            width: buttonWidth,
            height: fieldHeight
        )

        // 底部提示
        hintLabel.frame = NSRect(
            x: m + panelPadding,
            y: m + 6,
            width: panelWidth - panelPadding * 2,
            height: hintH
        )
    }

    // MARK: - 定位（跟随宠物）

    private func updatePosition() {
        guard let petWindow = petWindow, let panel = panel,
              let screen = petWindow.screen ?? NSScreen.main else { return }
        let petFrame = petWindow.frame
        let visibleFrame = screen.visibleFrame
        let panelW = panel.frame.width
        let panelH = panel.frame.height

        var x = petFrame.midX - panelW / 2
        var y = petFrame.maxY - 45

        // 左右边界
        x = max(visibleFrame.minX, min(x, visibleFrame.maxX - panelW))
        // 上边界：超出则放到宠物下方
        if y + panelH > visibleFrame.maxY {
            y = petFrame.minY - panelH - 4
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 关闭

    func dismiss() {
        let wasSending = isSending
        isSending = false

        followTimer?.invalidate()
        followTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.panel?.animator().alphaValue = 0
        }, completionHandler: {
            self.panel?.orderOut(nil)
            if !wasSending {
                self.onDismissWithoutSend?()
            }
        })
    }

    // MARK: - 按钮动作

    @objc private func dismissClicked() {
        dismiss()
    }

    @objc private func confirmClicked() {
        let message = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        // 标记正在发送，dismiss 时不触发 onDismissWithoutSend
        isSending = true

        // 禁用输入框和按钮，显示"✓ 已发送"
        inputField.isEnabled = false
        confirmButton.isEnabled = false
        confirmButton.layer?.backgroundColor = DT.success.cgColor
        confirmButton.attributedTitle = NSAttributedString(
            string: "✓",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 15, weight: .medium)
            ]
        )

        // 记录用户消息到聊天记录
        DingTalkMonitor.shared.recordUserMessage(sessionKey: sessionKey, message: message)

        // 异步发送（fire-and-forget）
        sendToAgent(message: message)

        // 0.8 秒后关闭面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.dismiss()
            // 恢复输入框状态（下次 show 时也会重置）
            self?.inputField.isEnabled = true
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateConfirmButton(enabled: !text.isEmpty)

        // 输入时切换边框颜色
        if !text.isEmpty {
            inputField.layer?.borderColor = DT.primary.cgColor
            inputField.layer?.backgroundColor = DT.bgSurface.cgColor
        } else {
            inputField.layer?.borderColor = DT.borderDefault.cgColor
            inputField.layer?.backgroundColor = DT.bgMuted.cgColor
        }
    }

    // Enter → 确认，Esc → 关闭
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmClicked()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        return false
    }

    // MARK: - 发送到网关

    private func sendToAgent(message: String) {
        let sessionKey = self.sessionKey
        NSLog("[ReplyPanel] Sending to agent: sessionKey=%@ message=%@", sessionKey, String(message.prefix(100)))

        onSendMessage?(sessionKey, message) { success, error in
            DispatchQueue.main.async {
                if success {
                    NSLog("[ReplyPanel] chat.send accepted")
                } else {
                    NSLog("[ReplyPanel] chat.send failed: %@", error ?? "unknown")
                    // 发送失败时通过通知气泡提示
                    let errorMsg = error ?? "发送失败"
                    let notification = DingTalkNotification(
                        summary: "没发出去…\(errorMsg)",
                        sessionKey: sessionKey,
                        isError: true,
                        timestamp: Date(),
                        originalMessage: nil,
                        scene: .myDirectChat
                    )
                    DingTalkMonitor.shared.onNotification?(notification)
                }
            }
        }
    }
}
